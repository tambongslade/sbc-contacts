import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AiUnavailableError } from './ai-unavailable.error';

/**
 * DeepSeek occasionally load-sheds: a 429/5xx, or — in JSON mode — an empty
 * completion with finish_reason=stop. These are transient, so we retry; a fresh
 * sampling temperature each time also unsticks a deterministic empty answer.
 *
 * Retries are bounded by a total BUDGET, not a fixed count, because the Flutter
 * app aborts the request at 20s (api_client receiveTimeout). We must answer
 * well inside that: keep the whole retry loop under BUDGET_MS so a slow call is
 * never turned into a client-side timeout. Fast empties (~1s) still get several
 * tries; a single attempt can't hang longer than ATTEMPT_TIMEOUT_MS.
 */
const BUDGET_MS = 16_000;
const ATTEMPT_TIMEOUT_MS = 9_000;
const BACKOFF_MS = 400;

const delay = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const now = (): number => Date.now();

/**
 * Thin REST client for the one DeepSeek call SBC Data needs: JSON generation
 * guided by a response schema. DeepSeek speaks the OpenAI chat shape and has
 * a JSON mode, but no server-side schema enforcement like Gemini — so the
 * schema is injected into the prompt and every caller still coerces the
 * result. Embeddings run on Voyage (or Gemini): DeepSeek has no embeddings endpoint.
 *
 * Every caller must treat [AiUnavailableError] as "carry on without AI".
 */
@Injectable()
export class DeepseekClient {
  private readonly logger = new Logger(DeepseekClient.name);
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly model: string;

  constructor(config: ConfigService) {
    this.apiKey = config.get<string>('deepseek.apiKey') ?? '';
    this.baseUrl = config.get<string>('deepseek.baseUrl') ?? 'https://api.deepseek.com';
    this.model = config.get<string>('deepseek.model') ?? 'deepseek-chat';
  }

  /** The generation model in use, for logs and the health check. */
  get modelName(): string {
    return this.model;
  }

  get enabled(): boolean {
    return this.apiKey.length > 0;
  }

  /** Generate one JSON object that follows [schema] (OpenAPI subset). */
  generateJson<T>(system: string, prompt: string, schema: object): Promise<T> {
    return this.generateJsonChat<T>(system, [{ role: 'user', text: prompt }], schema);
  }

  /** Same, continuing a conversation: [turns] alternate user and model. */
  async generateJsonChat<T>(
    system: string,
    turns: Array<{ role: 'user' | 'model'; text: string }>,
    schema: object,
    temperature = 0.1,
  ): Promise<T> {
    const messages = [
      { role: 'system', content: `${system}${schemaInstruction(schema)}` },
      // DeepSeek uses "assistant" where Gemini uses "model".
      ...turns.map((t) => ({
        role: t.role === 'model' ? 'assistant' : 'user',
        content: t.text,
      })),
    ];
    const deadline = now() + BUDGET_MS;
    let lastError: AiUnavailableError = new AiUnavailableError('DeepSeek unavailable', true);
    let attempt = 0;
    while (now() < deadline) {
      attempt++;
      // Nudge the temperature up each retry: an identical request can hit the
      // same empty JSON-mode completion, but a different sampling temperature
      // changes the output and unsticks it.
      const temp = Math.min(1, temperature + 0.2 * (attempt - 1));
      // Never let one attempt run past the remaining budget (or its own cap).
      const timeout = Math.min(ATTEMPT_TIMEOUT_MS, deadline - now());
      if (timeout < 1_000) break; // too little left to be worth another call
      // Always keep JSON mode: without it DeepSeek sometimes answers the turn
      // in plain prose (e.g. the "other zones?" question after the city), which
      // is unparseable. JSON mode reliably returns structure; the empty-content
      // blips are handled by retrying with a fresh temperature.
      try {
        return await this.attempt<T>(
          { model: this.model, messages, temperature: temp, response_format: { type: 'json_object' } },
          timeout,
        );
      } catch (err) {
        if (!(err instanceof AiUnavailableError) || !err.retryable) throw err;
        lastError = err;
        const backoff = BACKOFF_MS * attempt;
        if (now() + backoff >= deadline) break; // no budget for another try
        this.logger.warn(
          `DeepSeek ${this.model} attempt ${attempt} failed (${err.message}); retrying`,
        );
        await delay(backoff);
      }
    }
    this.logger.warn(`DeepSeek ${this.model} gave up after ${attempt} attempt(s): ${lastError.message}`);
    throw lastError;
  }

  /** One completion attempt; transient failures are flagged retryable. */
  private async attempt<T>(body: unknown, timeoutMs: number): Promise<T> {
    const res = await this.post<{
      choices?: Array<{ finish_reason?: string; message?: { content?: string } }>;
    }>('/chat/completions', body, timeoutMs);

    const choice = res.choices?.[0];
    const text = choice?.message?.content?.trim() ?? '';
    if (!text) {
      // Empty answer in JSON mode is DeepSeek load-shedding, not a real "stop".
      throw new AiUnavailableError(
        `DeepSeek returned no content (finish_reason=${choice?.finish_reason ?? 'none'})`,
        true,
      );
    }
    const json = extractJson(text);
    try {
      return JSON.parse(json) as T;
    } catch {
      throw new AiUnavailableError(
        `DeepSeek returned malformed JSON: ${text.slice(0, 120)}`,
        true,
      );
    }
  }

  private async post<T>(path: string, body: unknown, timeoutMs: number): Promise<T> {
    if (!this.enabled) throw new AiUnavailableError('DEEPSEEK_API_KEY is not set');
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${this.apiKey}` },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      // A network drop or timeout is transient — let the caller retry.
      this.logger.warn(`DeepSeek ${path} unreachable: ${(err as Error).message}`);
      throw new AiUnavailableError(`DeepSeek unreachable: ${(err as Error).message}`, true);
    }
    if (!res.ok) {
      // The body names the problem (quota, bad model) but never echoes the key.
      const detail = (await res.text()).slice(0, 300);
      this.logger.warn(`DeepSeek ${path} → ${res.status}: ${detail}`);
      // 429 and 5xx are load/outage (retry); 4xx is our request (do not).
      const retryable = res.status === 429 || res.status >= 500;
      throw new AiUnavailableError(`DeepSeek answered ${res.status}`, retryable);
    }
    return (await res.json()) as T;
  }
}

/**
 * DeepSeek's JSON mode needs the word "json" in the prompt and no schema of
 * its own, so we spell out the shape and rely on the caller's coercion.
 */
/**
 * Without JSON mode DeepSeek may wrap the object in prose or a ```json fence.
 * Take the outermost {...} so the caller still gets clean JSON to parse.
 */
function extractJson(text: string): string {
  const first = text.indexOf('{');
  const last = text.lastIndexOf('}');
  return first >= 0 && last > first ? text.slice(first, last + 1) : text;
}

function schemaInstruction(schema: object): string {
  return `\n\nRéponds uniquement avec un objet json valide, sans aucun texte autour, conforme à ce schéma (type OpenAPI) :\n${JSON.stringify(schema)}`;
}

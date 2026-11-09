import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AiUnavailableError } from './ai-unavailable.error';

const TIMEOUT_MS = 25_000;
/** deepseek-chat's own ceiling; without it a long answer can be cut mid-JSON. */
const MAX_TOKENS = 8192;

export interface ChatOptions {
  temperature?: number;
  /** Per-call limit; the pro assistant writes long answers and needs more. */
  timeoutMs?: number;
}

/**
 * Thin REST client for the one DeepSeek call SBC Data needs: JSON generation
 * guided by a response schema. DeepSeek speaks the OpenAI chat shape and has
 * a JSON mode, but no server-side schema enforcement like Gemini — so the
 * schema is injected into the prompt and every caller still coerces the
 * result. Embeddings stay on Gemini: DeepSeek has no embeddings endpoint.
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
    options: ChatOptions = {},
  ): Promise<T> {
    const timeoutMs = options.timeoutMs ?? TIMEOUT_MS;
    const started = Date.now();
    try {
      return await this.chatOnce<T>(system, turns, schema, options.temperature ?? 0.1, timeoutMs);
    } catch (err) {
      // A cut or empty answer is usually a one-off: ask once more if there is time.
      const left = timeoutMs - (Date.now() - started);
      if (!(err instanceof AiUnavailableError) || !err.retryable || left < 10_000) throw err;
      this.logger.warn(`DeepSeek ${this.model}: retrying after "${err.message}"`);
      return this.chatOnce<T>(system, turns, schema, options.temperature ?? 0.1, left);
    }
  }

  private async chatOnce<T>(
    system: string,
    turns: Array<{ role: 'user' | 'model'; text: string }>,
    schema: object,
    temperature: number,
    timeoutMs: number,
  ): Promise<T> {
    const body = {
      model: this.model,
      messages: [
        { role: 'system', content: `${system}${schemaInstruction(schema)}` },
        // DeepSeek uses "assistant" where Gemini uses "model".
        ...turns.map((t) => ({
          role: t.role === 'model' ? 'assistant' : 'user',
          content: t.text,
        })),
      ],
      temperature,
      max_tokens: MAX_TOKENS,
      response_format: { type: 'json_object' },
    };
    const res = await this.post<{
      choices?: Array<{ finish_reason?: string; message?: { content?: string } }>;
    }>('/chat/completions', body, timeoutMs);

    const choice = res.choices?.[0];
    const text = choice?.message?.content?.trim() ?? '';
    if (!text) {
      this.logger.warn(
        `DeepSeek ${this.model} returned no content (finish_reason=${choice?.finish_reason ?? 'none'})`,
      );
      throw new AiUnavailableError('DeepSeek returned no content', true);
    }
    try {
      return JSON.parse(text) as T;
    } catch {
      this.logger.warn(
        `DeepSeek ${this.model} returned malformed JSON (finish_reason=${choice?.finish_reason ?? 'none'}, ` +
          `${text.length} chars): ${text.slice(0, 200)}`,
      );
      throw new AiUnavailableError('DeepSeek returned malformed JSON', true);
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
      this.logger.warn(`DeepSeek ${path} unreachable: ${(err as Error).message}`);
      throw new AiUnavailableError(`DeepSeek unreachable: ${(err as Error).message}`);
    }
    if (!res.ok) {
      // The body names the problem (quota, bad model) but never echoes the key.
      const detail = (await res.text()).slice(0, 300);
      this.logger.warn(`DeepSeek ${path} → ${res.status}: ${detail}`);
      throw new AiUnavailableError(`DeepSeek answered ${res.status}`);
    }
    return (await res.json()) as T;
  }
}

/**
 * DeepSeek's JSON mode needs the word "json" in the prompt and no schema of
 * its own, so we spell out the shape and rely on the caller's coercion.
 */
function schemaInstruction(schema: object): string {
  return `\n\nRéponds uniquement avec un objet json valide, sans aucun texte autour, conforme à ce schéma (type OpenAPI) :\n${JSON.stringify(schema)}`;
}

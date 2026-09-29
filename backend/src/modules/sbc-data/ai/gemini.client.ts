import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

const API = 'https://generativelanguage.googleapis.com/v1beta/models';
const TIMEOUT_MS = 25_000;
/** 768 separates services as well as 1536 did on our samples, at half the storage. */
export const EMBEDDING_DIMENSIONS = 768;

export type EmbeddingTask = 'RETRIEVAL_QUERY' | 'RETRIEVAL_DOCUMENT';

/** Thrown when Gemini is not configured or does not answer usably. */
export class GeminiUnavailableError extends Error {}

/**
 * Thin REST client for the two Gemini calls SBC Data needs: JSON generation
 * against a response schema, and batch embeddings.
 *
 * REST rather than the SDK: two endpoints do not justify a dependency, and the
 * request shapes are stable. Every caller must treat [GeminiUnavailableError]
 * as "carry on without AI" — a missing key or a Google outage degrades SBC Data
 * to keyword matching, it never blocks a request.
 */
@Injectable()
export class GeminiClient {
  private readonly logger = new Logger(GeminiClient.name);
  private readonly apiKey: string;
  private readonly model: string;
  private readonly embeddingModel: string;

  constructor(config: ConfigService) {
    this.apiKey = config.get<string>('gemini.apiKey') ?? '';
    this.model = config.get<string>('gemini.model') ?? 'gemini-flash-latest';
    this.embeddingModel = config.get<string>('gemini.embeddingModel') ?? 'gemini-embedding-001';
  }

  get enabled(): boolean {
    return this.apiKey.length > 0;
  }

  /** Generate one JSON object that conforms to [schema] (OpenAPI subset). */
  async generateJson<T>(system: string, prompt: string, schema: object): Promise<T> {
    const body = {
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: schema,
        temperature: 0.1,
      },
    };
    const res = await this.post<{
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    }>(`${this.model}:generateContent`, body);

    const text = res.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) throw new GeminiUnavailableError('Gemini returned no content');
    try {
      return JSON.parse(text) as T;
    } catch {
      throw new GeminiUnavailableError('Gemini returned malformed JSON');
    }
  }

  /** Embed [texts] in one call; the result is index-aligned with the input. */
  async embed(texts: string[], task: EmbeddingTask): Promise<number[][]> {
    if (texts.length === 0) return [];
    const model = `models/${this.embeddingModel}`;
    const res = await this.post<{ embeddings?: Array<{ values: number[] }> }>(
      `${this.embeddingModel}:batchEmbedContents`,
      {
        requests: texts.map((text) => ({
          model,
          content: { parts: [{ text }] },
          taskType: task,
          outputDimensionality: EMBEDDING_DIMENSIONS,
        })),
      },
    );
    const vectors = res.embeddings?.map((e) => e.values) ?? [];
    if (vectors.length !== texts.length) {
      throw new GeminiUnavailableError('Gemini returned the wrong number of embeddings');
    }
    return vectors;
  }

  private async post<T>(path: string, body: unknown): Promise<T> {
    if (!this.enabled) throw new GeminiUnavailableError('GEMINI_API_KEY is not set');
    let res: Response;
    try {
      res = await fetch(`${API}/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': this.apiKey },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (err) {
      throw new GeminiUnavailableError(`Gemini unreachable: ${(err as Error).message}`);
    }
    if (!res.ok) {
      // The body names the problem (quota, bad model) but never echoes the key.
      const detail = (await res.text()).slice(0, 300);
      this.logger.warn(`Gemini ${path} → ${res.status}: ${detail}`);
      throw new GeminiUnavailableError(`Gemini answered ${res.status}`);
    }
    return (await res.json()) as T;
  }
}

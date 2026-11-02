import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AiUnavailableError } from './ai-unavailable.error';

const API = 'https://generativelanguage.googleapis.com/v1beta/models';
const TIMEOUT_MS = 25_000;
/** 768 separates services as well as 1536 did on our samples, at half the storage. */
export const EMBEDDING_DIMENSIONS = 768;

export type EmbeddingTask = 'RETRIEVAL_QUERY' | 'RETRIEVAL_DOCUMENT';

/**
 * Thin REST client for the one Gemini call SBC Data still needs: batch
 * embeddings. Text generation (structuring, analysis, matching) runs on
 * DeepSeek now; Gemini stays only for embeddings, which DeepSeek cannot do.
 *
 * REST rather than the SDK: one endpoint does not justify a dependency, and
 * the request shape is stable. Every caller must treat [AiUnavailableError]
 * as "carry on without AI" — a missing key or a Google outage degrades SBC
 * Data to keyword matching, it never blocks a request.
 */
@Injectable()
export class GeminiClient {
  private readonly logger = new Logger(GeminiClient.name);
  private readonly apiKey: string;
  private readonly embeddingModel: string;

  constructor(config: ConfigService) {
    this.apiKey = config.get<string>('gemini.apiKey') ?? '';
    this.embeddingModel = config.get<string>('gemini.embeddingModel') ?? 'gemini-embedding-001';
  }

  get enabled(): boolean {
    return this.apiKey.length > 0;
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
      throw new AiUnavailableError('Gemini returned the wrong number of embeddings');
    }
    return vectors;
  }

  private async post<T>(path: string, body: unknown): Promise<T> {
    if (!this.enabled) throw new AiUnavailableError('GEMINI_API_KEY is not set');
    let res: Response;
    try {
      res = await fetch(`${API}/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': this.apiKey },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (err) {
      this.logger.warn(`Gemini ${path} unreachable: ${(err as Error).message}`);
      throw new AiUnavailableError(`Gemini unreachable: ${(err as Error).message}`);
    }
    if (!res.ok) {
      // The body names the problem (quota, bad model) but never echoes the key.
      const detail = (await res.text()).slice(0, 300);
      this.logger.warn(`Gemini ${path} → ${res.status}: ${detail}`);
      throw new AiUnavailableError(`Gemini answered ${res.status}`);
    }
    return (await res.json()) as T;
  }
}

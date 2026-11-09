import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AiUnavailableError } from './ai-unavailable.error';
import type { EmbeddingTask } from './gemini.client';

const API = 'https://api.voyageai.com/v1/embeddings';
const TIMEOUT_MS = 25_000;
/** Voyage supports 256/512/1024/2048; 1024 is the default and matches storage. */
export const VOYAGE_DIMENSIONS = 1024;

/** Our two retrieval tasks mapped to Voyage's input_type values. */
const INPUT_TYPE: Record<EmbeddingTask, 'query' | 'document'> = {
  RETRIEVAL_QUERY: 'query',
  RETRIEVAL_DOCUMENT: 'document',
};

/**
 * Thin REST client for Voyage AI embeddings — the alternative embedder to
 * Gemini. Anthropic has no embeddings model of its own and points to Voyage;
 * this lets SBC Data embed without a Google dependency. Text generation stays
 * on DeepSeek.
 *
 * REST rather than an SDK: one endpoint, a stable shape. Like Gemini, every
 * caller must treat [AiUnavailableError] as "carry on without AI" — a missing
 * key or a Voyage outage degrades matching to keywords, it never blocks a
 * request.
 */
@Injectable()
export class VoyageClient {
  private readonly logger = new Logger(VoyageClient.name);
  private readonly apiKey: string;
  private readonly embeddingModel: string;
  private readonly embeddingsEnabled: boolean;

  constructor(config: ConfigService) {
    this.apiKey = config.get<string>('voyage.apiKey') ?? '';
    this.embeddingModel = config.get<string>('voyage.embeddingModel') ?? 'voyage-3.5';
    this.embeddingsEnabled = config.get<boolean>('voyage.embeddingsEnabled') ?? false;
  }

  /** Ready to embed: the feature is switched on and a key is configured. */
  get enabled(): boolean {
    return this.embeddingsEnabled && this.apiKey.length > 0;
  }

  /** Embed [texts] in one call; the result is index-aligned with the input. */
  async embed(texts: string[], task: EmbeddingTask): Promise<number[][]> {
    if (texts.length === 0) return [];
    if (!this.enabled) {
      throw new AiUnavailableError('embeddings are off (VOYAGE_EMBEDDINGS_ENABLED=false)');
    }
    const res = await this.post<{ data?: Array<{ embedding: number[]; index: number }> }>({
      input: texts,
      model: this.embeddingModel,
      input_type: INPUT_TYPE[task],
      output_dimension: VOYAGE_DIMENSIONS,
    });
    const data = res.data ?? [];
    if (data.length !== texts.length) {
      throw new AiUnavailableError('Voyage returned the wrong number of embeddings');
    }
    // Voyage returns each vector with its input index; order by it so the
    // result stays aligned with [texts] even if the API reorders.
    const vectors: number[][] = new Array(texts.length);
    for (const item of data) vectors[item.index] = item.embedding;
    return vectors;
  }

  private async post<T>(body: unknown): Promise<T> {
    if (!this.enabled) throw new AiUnavailableError('VOYAGE_API_KEY is not set');
    let res: Response;
    try {
      res = await fetch(API, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (err) {
      this.logger.warn(`Voyage unreachable: ${(err as Error).message}`);
      throw new AiUnavailableError(`Voyage unreachable: ${(err as Error).message}`);
    }
    if (!res.ok) {
      // The body names the problem (quota, bad model) but never echoes the key.
      const detail = (await res.text()).slice(0, 300);
      this.logger.warn(`Voyage → ${res.status}: ${detail}`);
      throw new AiUnavailableError(`Voyage answered ${res.status}`);
    }
    return (await res.json()) as T;
  }
}

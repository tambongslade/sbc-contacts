/**
 * Thrown when an AI provider is not configured or does not answer usably.
 * Every caller must treat it as "carry on without AI": a missing key, an
 * outage or malformed output degrades SBC Data to keyword matching, it never
 * blocks a request. DeepSeek (text) and Voyage/Gemini (embeddings) both raise it.
 *
 * [retryable] marks a transient failure (a 429/5xx, a timeout, or an empty or
 * malformed answer) that a caller may retry before giving up; a missing key or
 * a 4xx is not retryable.
 */
export class AiUnavailableError extends Error {
  constructor(
    message: string,
    readonly retryable = false,
  ) {
    super(message);
  }
}

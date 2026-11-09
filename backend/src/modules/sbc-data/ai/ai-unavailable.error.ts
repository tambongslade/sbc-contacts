/**
 * Thrown when an AI provider is not configured or does not answer usably.
 * Every caller must treat it as "carry on without AI": a missing key, an
 * outage or malformed output degrades SBC Data to keyword matching, it never
 * blocks a request. DeepSeek (text) and Gemini (embeddings) both raise it.
 */
export class AiUnavailableError extends Error {
  /** True when asking again may well work (an empty or cut answer). */
  constructor(
    message?: string,
    readonly retryable = false,
  ) {
    super(message);
  }
}

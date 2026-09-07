/** Consistent success envelope (brief §8, §17). */
export interface ApiSuccessResponse<T> {
  success: true;
  statusCode: number;
  data: T;
  meta?: Record<string, unknown>;
}

/** Consistent error envelope (brief §8). Never leaks internals. */
export interface ApiErrorResponse {
  success: false;
  statusCode: number;
  message: string;
  errors?: unknown[];
  code?: string;
  path?: string;
  timestamp: string;
}

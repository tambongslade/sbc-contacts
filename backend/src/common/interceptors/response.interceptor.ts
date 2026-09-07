import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Response } from 'express';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { ApiSuccessResponse } from '../interfaces/api-response.interface';

/** Opt-out marker for endpoints that must return raw payloads (files, health). */
export const RAW_RESPONSE = 'RAW_RESPONSE';

/**
 * Wraps every successful controller return value in the standard success
 * envelope, unless the handler is marked @Raw() (e.g. VCF export, health).
 */
@Injectable()
export class ResponseInterceptor<T> implements NestInterceptor<T, ApiSuccessResponse<T> | T> {
  constructor(private readonly reflector: Reflector) {}

  intercept(context: ExecutionContext, next: CallHandler<T>): Observable<ApiSuccessResponse<T> | T> {
    const isRaw = this.reflector.getAllAndOverride<boolean>(RAW_RESPONSE, [
      context.getHandler(),
      context.getClass(),
    ]);

    const response = context.switchToHttp().getResponse<Response>();

    return next.handle().pipe(
      map((data) => {
        if (isRaw) return data;
        return {
          success: true as const,
          statusCode: response.statusCode,
          data,
        };
      }),
    );
  }
}

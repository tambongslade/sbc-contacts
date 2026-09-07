import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Request, Response } from 'express';
import { ApiErrorResponse } from '../interfaces/api-response.interface';

/**
 * Single, centralised exception filter (brief §8).
 * - Normalises everything to the standard error envelope.
 * - Maps known Prisma errors to clean HTTP statuses.
 * - NEVER leaks stack traces, SQL, or internals to the client.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const { status, message, errors, code } = this.resolve(exception);

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(
        `${request.method} ${request.url} -> ${status} ${message}`,
        exception instanceof Error ? exception.stack : undefined,
      );
    } else {
      this.logger.warn(`${request.method} ${request.url} -> ${status} ${message}`);
    }

    const body: ApiErrorResponse = {
      success: false,
      statusCode: status,
      message,
      ...(errors ? { errors } : {}),
      ...(code ? { code } : {}),
      path: request.url,
      timestamp: new Date().toISOString(),
    };

    response.status(status).json(body);
  }

  private resolve(exception: unknown): {
    status: number;
    message: string;
    errors?: unknown[];
    code?: string;
  } {
    if (exception instanceof HttpException) {
      const res = exception.getResponse();
      if (typeof res === 'object' && res !== null) {
        const r = res as Record<string, unknown>;
        const rawMessage = r.message;
        const message = Array.isArray(rawMessage)
          ? 'Validation failed'
          : (rawMessage as string) ?? exception.message;
        return {
          status: exception.getStatus(),
          message,
          errors: Array.isArray(rawMessage) ? rawMessage : undefined,
          code: typeof r.code === 'string' ? r.code : undefined,
        };
      }
      return { status: exception.getStatus(), message: exception.message };
    }

    if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      return this.mapPrismaError(exception);
    }

    if (exception instanceof Prisma.PrismaClientValidationError) {
      return { status: HttpStatus.BAD_REQUEST, message: 'Invalid database query' };
    }

    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      message: 'Internal server error',
    };
  }

  private mapPrismaError(e: Prisma.PrismaClientKnownRequestError): {
    status: number;
    message: string;
    code: string;
  } {
    switch (e.code) {
      case 'P2002':
        return { status: HttpStatus.CONFLICT, message: 'Resource already exists', code: e.code };
      case 'P2025':
        return { status: HttpStatus.NOT_FOUND, message: 'Resource not found', code: e.code };
      case 'P2003':
        return {
          status: HttpStatus.BAD_REQUEST,
          message: 'Related resource constraint failed',
          code: e.code,
        };
      default:
        return {
          status: HttpStatus.INTERNAL_SERVER_ERROR,
          message: 'Database error',
          code: e.code,
        };
    }
  }
}

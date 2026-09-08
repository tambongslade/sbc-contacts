import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { LoggerModule } from 'nestjs-pino';

import { configuration } from './config/configuration';
import { validateEnv } from './config/env.validation';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { CryptoModule } from './common/crypto/crypto.module';
import { PrismaModule } from './infrastructure/prisma/prisma.module';
import { RedisModule } from './infrastructure/cache/redis.module';
import { QueueModule } from './infrastructure/queue/queue.module';
import { SbcClientModule } from './modules/sbc-client/sbc-client.module';
import { AuthModule } from './modules/auth/auth.module';
import { SsoBridgeModule } from './modules/sso-bridge/sso-bridge.module';
import { AuditModule } from './modules/audit/audit.module';
import { MembersModule } from './modules/members/members.module';
import { DirectoryModule } from './modules/directory/directory.module';
import { FavoritesModule } from './modules/favorites/favorites.module';
import { ReviewsModule } from './modules/reviews/reviews.module';
import { SyncModule } from './modules/sync/sync.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { MatchingModule } from './modules/matching/matching.module';
import { WebhooksModule } from './modules/webhooks/webhooks.module';
import { HealthModule } from './modules/health/health.module';

const nodeEnv = process.env.NODE_ENV ?? 'development';

@Module({
  imports: [
    // Centralised, validated, namespaced configuration (brief §4).
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      // env-specific file listed last so it overrides the base `.env`.
      // (On the deployed server, `.env` holds the active production config.)
      envFilePath: ['.env', `.env.${nodeEnv}`],
      validate: validateEnv,
      load: [() => configuration(validateEnv(process.env))],
    }),

    // Structured logging (brief §10) — pino, request-scoped, secrets redacted.
    LoggerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        pinoHttp: {
          level: config.get<string>('app.logLevel') ?? 'info',
          transport:
            config.get('app.env') === 'production'
              ? undefined
              : { target: 'pino-pretty', options: { singleLine: true } },
          redact: {
            paths: [
              'req.headers.authorization',
              'req.headers.cookie',
              'req.body.client_secret',
              'req.body.password',
              'req.body.refresh_token',
            ],
            remove: true,
          },
          autoLogging: true,
          customProps: () => ({ context: 'HTTP' }),
        },
      }),
    }),

    // Rate limiting (brief §9). Per-route overrides tighten auth/sync later.
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        throttlers: [
          {
            ttl: (config.get<number>('throttle.ttl') ?? 60) * 1000,
            limit: config.get<number>('throttle.limit') ?? 120,
          },
        ],
      }),
    }),

    // Infrastructure
    PrismaModule,
    RedisModule,
    QueueModule,
    CryptoModule,

    // Feature modules
    AuditModule,
    SbcClientModule,
    AuthModule,
    SsoBridgeModule,
    MembersModule,
    DirectoryModule,
    FavoritesModule,
    ReviewsModule,
    SyncModule,
    NotificationsModule,
    MatchingModule,
    WebhooksModule,
    HealthModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
  ],
})
export class AppModule {}

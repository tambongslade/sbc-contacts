import { ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { Logger as PinoLogger } from 'nestjs-pino';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  // rawBody: true captures the unparsed body for webhook HMAC verification.
  const app = await NestFactory.create(AppModule, { bufferLogs: true, rawBody: true });

  // Use pino as the app logger.
  app.useLogger(app.get(PinoLogger));

  const config = app.get(ConfigService);
  const apiPrefix = config.get<string>('app.apiPrefix') ?? 'api';
  const port = config.get<number>('app.port') ?? 3001;
  const corsOrigins = config.get<string[]>('app.corsOrigins') ?? [];
  const swaggerEnabled = config.get<boolean>('app.swaggerEnabled');
  const isProd = config.get('app.env') === 'production';

  // Security headers (brief §9).
  app.use(helmet());

  // CORS — explicit allow-list, credentials for cookie/session support.
  app.enableCors({
    origin: corsOrigins.length > 0 ? corsOrigins : false,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  });

  // URI versioning: /api/v1/... (brief §17).
  app.setGlobalPrefix(apiPrefix);
  app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });

  // Global validation: whitelist + reject unknown props + transform (brief §7).
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
      forbidUnknownValues: true,
    }),
  );

  // Graceful shutdown (closes Prisma/Redis/BullMQ cleanly).
  app.enableShutdownHooks();

  // Swagger / OpenAPI (brief §18) — never exposed in prod unless explicitly on.
  if (swaggerEnabled && !isProd) {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('SBC Contacts API')
      .setDescription('SSO-delegated backend for the SBC Contacts mobile app')
      .setVersion('1.0')
      .addBearerAuth()
      .build();
    const document = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup(`${apiPrefix}/docs`, app, document, {
      swaggerOptions: { persistAuthorization: true },
    });
  }

  await app.listen(port, '0.0.0.0');
  const logger = app.get(PinoLogger);
  logger.log(`🚀 SBC Contacts API on http://localhost:${port}/${apiPrefix}/v1`);
  if (swaggerEnabled && !isProd) {
    logger.log(`📚 Swagger docs on http://localhost:${port}/${apiPrefix}/docs`);
  }
}

void bootstrap();

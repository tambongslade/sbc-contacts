import { EnvironmentVariables } from './env.validation';

/**
 * Namespaced, typed config object built from the already-validated env.
 * Consume via ConfigService.get('app'|'redis'|'jwt'|'sbc'...).
 * Nothing else in the app should read process.env directly.
 */
export const configuration = (env: EnvironmentVariables) => ({
  app: {
    env: env.NODE_ENV,
    port: env.PORT,
    apiPrefix: env.API_PREFIX,
    corsOrigins: env.CORS_ORIGINS.split(',')
      .map((o) => o.trim())
      .filter(Boolean),
    swaggerEnabled: env.SWAGGER_ENABLED,
    logLevel: env.LOG_LEVEL,
  },
  database: {
    url: env.DATABASE_URL,
  },
  redis: {
    host: env.REDIS_HOST,
    port: env.REDIS_PORT,
    password: env.REDIS_PASSWORD || undefined,
    db: env.REDIS_DB,
  },
  jwt: {
    accessSecret: env.JWT_ACCESS_SECRET,
    accessTtl: env.JWT_ACCESS_TTL,
    refreshSecret: env.JWT_REFRESH_SECRET,
    refreshTtl: env.JWT_REFRESH_TTL,
  },
  security: {
    tokenEncryptionKey: env.TOKEN_ENCRYPTION_KEY,
  },
  sbc: {
    baseUrl: env.SBC_BASE_URL,
    clientId: env.SBC_SSO_CLIENT_ID,
    clientSecret: env.SBC_SSO_CLIENT_SECRET,
    redirectUri: env.SBC_SSO_REDIRECT_URI,
    // Other redirect_uris registered for this client (comma separated), e.g.
    // the mobile custom scheme. Clients may request one of these.
    extraRedirectUris: process.env.SBC_SSO_EXTRA_REDIRECT_URIS ?? 'sbccontacts://auth/callback',
    scopes: env.SBC_SSO_SCOPES.split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    webhookSecret: env.SBC_WEBHOOK_SECRET,
  },
  throttle: {
    ttl: env.THROTTLE_TTL,
    limit: env.THROTTLE_LIMIT,
  },
});

export type AppConfiguration = ReturnType<typeof configuration>;

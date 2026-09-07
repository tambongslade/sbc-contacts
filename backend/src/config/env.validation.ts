import { plainToInstance, Transform } from 'class-transformer';
import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
  MinLength,
  validateSync,
} from 'class-validator';

export enum NodeEnv {
  Development = 'development',
  Production = 'production',
  Test = 'test',
}

const toBool = ({ value }: { value: unknown }) =>
  value === true || value === 'true' || value === '1';

/**
 * Strongly-typed, validated view of process.env.
 * The app REFUSES TO BOOT if any of these are missing or malformed —
 * fail fast, fail clearly (requirement §4).
 */
export class EnvironmentVariables {
  @IsEnum(NodeEnv)
  NODE_ENV: NodeEnv = NodeEnv.Development;

  @IsInt()
  @Min(0)
  @Max(65535)
  @Transform(({ value }) => parseInt(value as string, 10))
  PORT = 3000;

  @IsString()
  @IsNotEmpty()
  API_PREFIX = 'api';

  @IsString()
  @IsOptional()
  CORS_ORIGINS = '';

  @IsBoolean()
  @Transform(toBool)
  SWAGGER_ENABLED = true;

  // --- Database ---
  @IsString()
  @IsNotEmpty()
  DATABASE_URL!: string;

  // --- Redis ---
  @IsString()
  @IsNotEmpty()
  REDIS_HOST!: string;

  @IsInt()
  @Transform(({ value }) => parseInt(value as string, 10))
  REDIS_PORT = 6379;

  @IsString()
  @IsOptional()
  REDIS_PASSWORD = '';

  @IsInt()
  @IsOptional()
  @Transform(({ value }) => parseInt(value as string, 10))
  REDIS_DB = 0;

  // --- App JWT ---
  @IsString()
  @MinLength(32)
  JWT_ACCESS_SECRET!: string;

  @IsInt()
  @Transform(({ value }) => parseInt(value as string, 10))
  JWT_ACCESS_TTL = 900;

  @IsString()
  @MinLength(32)
  JWT_REFRESH_SECRET!: string;

  @IsInt()
  @Transform(({ value }) => parseInt(value as string, 10))
  JWT_REFRESH_TTL = 2592000;

  // --- SBC token encryption (AES-256-GCM → 32 bytes → 64 hex chars) ---
  @IsString()
  @Length(64, 64, { message: 'TOKEN_ENCRYPTION_KEY must be 64 hex chars (32 bytes)' })
  TOKEN_ENCRYPTION_KEY!: string;

  // --- SBC SSO client ---
  @IsString()
  @IsNotEmpty()
  SBC_BASE_URL!: string;

  @IsString()
  @IsNotEmpty()
  SBC_SSO_CLIENT_ID!: string;

  @IsString()
  @IsNotEmpty()
  SBC_SSO_CLIENT_SECRET!: string;

  @IsString()
  @IsNotEmpty()
  SBC_SSO_REDIRECT_URI!: string;

  @IsString()
  @IsNotEmpty()
  SBC_SSO_SCOPES = 'profile.read,contacts.read';

  @IsString()
  @IsOptional()
  SBC_WEBHOOK_SECRET = '';

  // --- Throttling ---
  @IsInt()
  @Transform(({ value }) => parseInt(value as string, 10))
  THROTTLE_TTL = 60;

  @IsInt()
  @Transform(({ value }) => parseInt(value as string, 10))
  THROTTLE_LIMIT = 120;

  @IsString()
  @IsOptional()
  LOG_LEVEL = 'info';
}

export function validateEnv(config: Record<string, unknown>): EnvironmentVariables {
  const validated = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: false,
  });

  const errors = validateSync(validated, {
    skipMissingProperties: false,
    whitelist: false,
  });

  if (errors.length > 0) {
    const details = errors
      .map((e) => `  - ${e.property}: ${Object.values(e.constraints ?? {}).join(', ')}`)
      .join('\n');
    throw new Error(`❌ Invalid environment configuration:\n${details}`);
  }

  return validated;
}

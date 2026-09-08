import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class SsoCallbackDto {
  @ApiProperty({ description: 'One-shot SBC authorization code from /auth/callback' })
  @IsString()
  @MinLength(8)
  @MaxLength(512)
  code!: string;

  @ApiPropertyOptional({ description: 'Client-generated stable device id (for session binding)' })
  @IsOptional()
  @IsString()
  @MaxLength(128)
  deviceId?: string;

  /**
   * The redirect_uri the client actually used on /sso/authorize. SBC requires
   * the exchange to repeat it verbatim, so a mobile client authorizing with
   * the custom scheme cannot be exchanged against the web bridge URI — that
   * mismatch surfaces as SBC's generic 400 "invalid authorization code".
   * Validated against the configured allowlist before use.
   */
  @ApiPropertyOptional({ description: 'redirect_uri used on /sso/authorize' })
  @IsOptional()
  @IsString()
  @MaxLength(512)
  redirectUri?: string;
}

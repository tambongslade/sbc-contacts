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
}

import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { DIAL_CODES } from '../../../common/utils/phone';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
const upper = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim().toUpperCase() : value;

/**
 * An SBC Network account of its own: created in the app, with no SBC account
 * behind it. Someone who wants an SBC account creates it on SBC instead.
 */
export class RegisterDto {
  @ApiProperty({ example: 'Jean Paul Mbarga' })
  @Transform(trim)
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @ApiProperty({ example: 'CM', description: 'ISO alpha-2 code' })
  @Transform(upper)
  @IsIn(Object.keys(DIAL_CODES))
  country!: string;

  @ApiProperty({
    example: '670000000',
    description: 'WhatsApp number, with or without its country code',
  })
  @IsString()
  @MinLength(6)
  @MaxLength(30)
  phoneNumber!: string;

  @ApiProperty({ minLength: 8 })
  @IsString()
  @MinLength(8)
  @MaxLength(200)
  password!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  deviceId?: string;
}

/** Sign in to an SBC Network account: its WhatsApp number and password. */
export class PhoneLoginDto {
  @ApiPropertyOptional({
    example: 'CM',
    description: 'Completes a number typed without its country code',
  })
  @IsOptional()
  @Transform(upper)
  @IsIn(Object.keys(DIAL_CODES))
  country?: string;

  @ApiProperty({ example: '+237670000000' })
  @IsString()
  @MinLength(6)
  @MaxLength(30)
  phoneNumber!: string;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  password!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  deviceId?: string;
}

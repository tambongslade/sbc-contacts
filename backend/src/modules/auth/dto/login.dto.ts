import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * Email + password login for the admin back-office. SSO stays the default way
 * in; this exists so an admin can sign in without the SBC round-trip (and so
 * admin access works off the main host). Only accounts explicitly provisioned
 * with a password hash can use it.
 */
export class LoginDto {
  @ApiProperty({ example: 'admin@example.com' })
  @IsEmail()
  @MaxLength(254)
  email!: string;

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

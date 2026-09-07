import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { Platform } from '@prisma/client';
import { PaginationQueryDto } from '../../../common/dto/pagination.dto';

export class NotificationsQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ description: 'Only unread notifications' })
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true' || value === '1')
  @IsBoolean()
  unreadOnly?: boolean;
}

export class RegisterDeviceDto {
  @ApiProperty({ enum: Platform })
  @IsEnum(Platform)
  platform!: Platform;

  @ApiPropertyOptional({ description: 'FCM/APNs push token' })
  @IsOptional()
  @IsString()
  @MaxLength(512)
  pushToken?: string;
}

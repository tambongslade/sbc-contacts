import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';
import { PaginationQueryDto } from '../../../common/dto/pagination.dto';

/**
 * Start a sync run. Either resolve targets from a saved criteria, or pass an
 * explicit selection of member SBC ids (cahier §10 "tous ou une sélection").
 */
export class StartSyncDto {
  @ApiPropertyOptional({ description: 'Saved criteria to resolve matches from' })
  @IsOptional()
  @IsString()
  criteriaId?: string;

  @ApiPropertyOptional({ type: [String], description: 'Explicit selection of member SBC ids' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(500)
  @IsString({ each: true })
  memberSbcIds?: string[];

  @ApiPropertyOptional({ description: 'Client device id (contacts are device-scoped)' })
  @IsOptional()
  @IsString()
  @MaxLength(128)
  deviceId?: string;
}

export enum ReportedStatus {
  SYNCED = 'SYNCED',
  FAILED = 'FAILED',
}

export class SyncResultItemDto {
  @ApiProperty()
  @IsString()
  memberSbcId!: string;

  @ApiPropertyOptional({ description: 'Native contact id created on the device' })
  @IsOptional()
  @IsString()
  @MaxLength(256)
  deviceContactId?: string;

  @ApiProperty({ enum: ReportedStatus })
  @IsEnum(ReportedStatus)
  status!: ReportedStatus;
}

/** Client reports the outcome of writing contacts to the phone. */
export class ReportSyncDto {
  @ApiProperty({ type: [SyncResultItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => SyncResultItemDto)
  results!: SyncResultItemDto[];
}

export class SyncContactsQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: ['PENDING', 'SYNCED', 'FAILED', 'STALE'] })
  @IsOptional()
  @IsString()
  status?: string;
}

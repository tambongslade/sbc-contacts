import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

/** Repeatable query param: ?countries=CM&countries=CI. */
const toArray = ({ value }: { value: unknown }) => (Array.isArray(value) ? value : [value]);
import { PaginationQueryDto } from '../../common/dto/pagination.dto';

export class StatusBoostQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ description: 'Only members with this SBC subscription (e.g. CIBLE)' })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  subscription?: string;

  // The criteria filters, applied to the list. Ciblé may use them all; anyone
  // else the country only (see status-boost.filters.ts).

  @ApiPropertyOptional({ type: [String], description: 'Repeatable: ?countries=CM' })
  @IsOptional()
  @Transform(toArray)
  @IsArray()
  @ArrayMaxSize(50)
  @IsString({ each: true })
  countries?: string[];

  @ApiPropertyOptional({ type: [String], description: 'Régions. Ciblé only' })
  @IsOptional()
  @Transform(toArray)
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  cities?: string[];

  @ApiPropertyOptional({ type: [String], description: 'Ciblé only' })
  @IsOptional()
  @Transform(toArray)
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  professions?: string[];

  @ApiPropertyOptional({ type: [String], description: 'Ciblé only' })
  @IsOptional()
  @Transform(toArray)
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  interests?: string[];

  @ApiPropertyOptional({ description: 'Ciblé only' })
  @IsOptional()
  @IsString()
  @MaxLength(16)
  sex?: string;

  @ApiPropertyOptional({ minimum: 0, maximum: 120, description: 'Ciblé only' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  ageMin?: number;

  @ApiPropertyOptional({ minimum: 0, maximum: 120, description: 'Ciblé only' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  ageMax?: number;
}

export class StatusBoostOptInDto {
  @ApiProperty({ description: 'Join (true) or leave (false) the list' })
  @IsBoolean()
  optIn!: boolean;
}

import { ApiProperty, ApiPropertyOptional, OmitType, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
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
  MinLength,
} from 'class-validator';

/** Saved sync criteria (cahier §10). All filter arrays are combinable. */
export class CreateCriteriaDto {
  @ApiProperty({ example: 'Designers Douala' })
  @IsString()
  @MinLength(1)
  @MaxLength(80)
  label!: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(50)
  @IsString({ each: true })
  countries?: string[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  cities?: string[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  professions?: string[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  interests?: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(16)
  sex?: string;

  @ApiPropertyOptional({ minimum: 0, maximum: 120 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  ageMin?: number;

  @ApiPropertyOptional({ minimum: 0, maximum: 120 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(120)
  ageMax?: number;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional({
    default: false,
    description:
      'Target the members of "Augmenter mes vues WhatsApp", narrowed by the ' +
      'filters (Ciblé: all of them; otherwise the country only). Only for a ' +
      'member in the list, one per member.',
  })
  @IsOptional()
  @IsBoolean()
  statusBoost?: boolean;
}

/** What a criteria targets is fixed at creation. */
export class UpdateCriteriaDto extends PartialType(OmitType(CreateCriteriaDto, ['statusBoost'])) {}

/** Ad-hoc criteria for the live match-count preview on the create screen. */
export class PreviewCriteriaDto extends PartialType(CreateCriteriaDto) {}

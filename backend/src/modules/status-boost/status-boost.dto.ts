import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';
import { PaginationQueryDto } from '../../common/dto/pagination.dto';

export class StatusBoostQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ description: 'Only members with this SBC subscription (e.g. CIBLE)' })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  subscription?: string;
}

export class StatusBoostOptInDto {
  @ApiProperty({ description: 'Join (true) or leave (false) the list' })
  @IsBoolean()
  optIn!: boolean;
}

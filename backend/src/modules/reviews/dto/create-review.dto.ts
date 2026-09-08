import { ApiProperty } from '@nestjs/swagger';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';

/** Create or update the caller's review for a member (upsert). */
export class CreateReviewDto {
  @ApiProperty({ description: 'SBC id of the member being reviewed' })
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  memberSbcId!: string;

  @ApiProperty({ minimum: 1, maximum: 5, description: 'Star rating 1-5' })
  @IsInt()
  @Min(1)
  @Max(5)
  stars!: number;

  @ApiProperty({ required: false, description: 'Optional written opinion' })
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  comment?: string;
}

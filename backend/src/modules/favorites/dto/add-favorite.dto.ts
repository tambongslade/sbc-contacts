import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

export class AddFavoriteDto {
  @ApiProperty({ description: 'SBC id of the member to favorite' })
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  memberSbcId!: string;
}

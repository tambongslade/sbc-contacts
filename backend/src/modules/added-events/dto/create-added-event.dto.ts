import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * Record a direct "Ajouter au téléphone" add (§21). The app calls this after a
 * successful native add so the addition shows in "Mes contacts SBC" and the
 * target learns who added them.
 */
export class CreateAddedEventDto {
  @ApiProperty({ description: 'SBC id of the member that was added' })
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  memberSbcId!: string;

  @ApiProperty({ required: false, description: 'Native contact id returned by the phone' })
  @IsOptional()
  @IsString()
  @MaxLength(256)
  deviceContactId?: string;
}

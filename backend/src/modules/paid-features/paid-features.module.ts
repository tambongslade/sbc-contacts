import { Module } from '@nestjs/common';
import { PaidFeaturesService } from './paid-features.service';

/** What a member paid on SBC (Pro, mise en avant), applied to the app's fields. */
@Module({
  providers: [PaidFeaturesService],
  exports: [PaidFeaturesService],
})
export class PaidFeaturesModule {}

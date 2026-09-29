import { Module } from '@nestjs/common';
import { ReviewsController } from './reviews.controller';
import { ReviewsService } from './reviews.service';

@Module({
  controllers: [ReviewsController],
  providers: [ReviewsService],
  // SBC Data rates the chosen pro through the same reviews (Data §15).
  exports: [ReviewsService],
})
export class ReviewsModule {}

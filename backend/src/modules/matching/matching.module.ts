import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { MatchingProcessor } from './matching.processor';
import { MatchingService } from './matching.service';

@Module({
  imports: [NotificationsModule], // for NotificationsService
  providers: [MatchingService, MatchingProcessor],
  exports: [MatchingService],
})
export class MatchingModule {}

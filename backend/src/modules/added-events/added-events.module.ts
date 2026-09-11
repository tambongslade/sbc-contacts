import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { AddedEventsController } from './added-events.controller';
import { AddedEventsService } from './added-events.service';

/**
 * "Qui m'a ajouté ?" (§21) + the direct-add hook that keeps "Mes contacts SBC"
 * populated. MembersModule is @Global; NotificationsModule is imported for its
 * exported NotificationsService.
 */
@Module({
  imports: [NotificationsModule],
  controllers: [AddedEventsController],
  providers: [AddedEventsService],
})
export class AddedEventsModule {}

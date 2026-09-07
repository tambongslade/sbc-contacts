import { Module } from '@nestjs/common';
import { DevicesService } from './devices.service';
import { NotificationsController } from './notifications.controller';
import { NotificationsProcessor } from './notifications.processor';
import { NotificationsService } from './notifications.service';
import { NOTIFICATION_PROVIDERS } from './providers/notification-provider.interface';
import { PushProvider } from './providers/push.provider';

/**
 * Notification system (cahier §19 / brief §15). Providers are collected behind
 * the NOTIFICATION_PROVIDERS token so channels can be added without touching
 * callers. NotificationsService is exported for the matching worker.
 */
@Module({
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    DevicesService,
    NotificationsProcessor,
    PushProvider,
    {
      provide: NOTIFICATION_PROVIDERS,
      useFactory: (push: PushProvider) => [push],
      inject: [PushProvider],
    },
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}

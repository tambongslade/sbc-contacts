import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Inject, Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';
import { DevicesService } from './devices.service';
import { notificationLink } from './routing/notification-link';
import {
  NOTIFICATION_PROVIDERS,
  NotificationProvider,
} from './providers/notification-provider.interface';

/**
 * Delivers a persisted notification across all configured channels (brief §13).
 * Idempotent by notification id; provider failures are isolated per-provider so
 * one bad channel can't fail the job (retries are configured on the queue).
 */
@Processor(QUEUE_NAMES.NOTIFICATIONS)
export class NotificationsProcessor extends WorkerHost {
  private readonly logger = new Logger(NotificationsProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly devices: DevicesService,
    @Inject(NOTIFICATION_PROVIDERS) private readonly providers: NotificationProvider[],
  ) {
    super();
  }

  async process(job: Job<{ notificationId: string }>): Promise<void> {
    const notification = await this.prisma.notification.findUnique({
      where: { id: job.data.notificationId },
    });
    if (!notification) return;

    const [targets, badge] = await Promise.all([
      this.devices.pushTargets(notification.userId),
      this.prisma.notification.count({ where: { userId: notification.userId, readAt: null } }),
    ]);
    const data = (notification.data as Record<string, unknown>) ?? undefined;
    const payload = {
      userId: notification.userId,
      notificationId: notification.id,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      data,
      link: notificationLink(notification.type, data),
      badge,
      deviceTokens: targets.fcm,
      apnsTokens: targets.apns,
    };

    await Promise.all(
      this.providers.map((p) =>
        p.send(payload).catch((err) =>
          this.logger.error(`provider ${p.channel} failed: ${(err as Error).message}`),
        ),
      ),
    );
  }
}

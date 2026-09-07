import { InjectQueue } from '@nestjs/bullmq';
import { Injectable } from '@nestjs/common';
import { Member, Notification, NotificationType, Prisma, SyncCriteria } from '@prisma/client';
import { Queue } from 'bullmq';
import { PaginatedResult, PaginationQueryDto, paginate } from '../../common/dto/pagination.dto';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';

export interface CreateNotificationInput {
  userId: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

/**
 * In-app notification store (cahier §19) + fan-out to delivery channels via the
 * NOTIFICATIONS queue (push/SMS/email are dispatched asynchronously by the
 * processor, so a slow provider never blocks the request that raised the event).
 */
@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    @InjectQueue(QUEUE_NAMES.NOTIFICATIONS) private readonly queue: Queue,
  ) {}

  /** Persist an in-app notification and enqueue channel delivery. */
  async create(input: CreateNotificationInput): Promise<Notification> {
    const notification = await this.prisma.notification.create({
      data: {
        userId: input.userId,
        type: input.type,
        title: input.title,
        body: input.body,
        data: input.data ? (input.data as Prisma.InputJsonValue) : undefined,
      },
    });
    await this.queue.add('dispatch', { notificationId: notification.id }, { jobId: notification.id });
    return notification;
  }

  /**
   * Raise a NEW_MATCH (cahier §11), deduped per (user, member) so a member that
   * matches several of a user's criteria only notifies once.
   */
  async notifyNewMatch(userId: string, member: Member, criteria: SyncCriteria): Promise<boolean> {
    const already = await this.prisma.notification.findFirst({
      where: {
        userId,
        type: NotificationType.NEW_MATCH,
        data: { path: ['memberSbcId'], equals: member.sbcId },
      },
      select: { id: true },
    });
    if (already) return false;

    const label = [member.firstName, member.name].filter(Boolean).join(' ') || 'Un membre';
    const where = [member.profession, member.city, member.country].filter(Boolean).join(' — ');
    await this.create({
      userId,
      type: NotificationType.NEW_MATCH,
      title: 'Nouveau membre correspondant à vos critères',
      body: `${label}${where ? ' — ' + where : ''} (${criteria.label})`,
      data: { memberSbcId: member.sbcId, criteriaId: criteria.id },
    });
    return true;
  }

  list(
    userId: string,
    pagination: PaginationQueryDto,
    unreadOnly = false,
  ): Promise<PaginatedResult<Notification>> {
    const where = { userId, ...(unreadOnly ? { readAt: null } : {}) };
    return this.prisma
      .$transaction([
        this.prisma.notification.findMany({
          where,
          orderBy: { createdAt: 'desc' },
          skip: pagination.skip,
          take: pagination.limit,
        }),
        this.prisma.notification.count({ where }),
      ])
      .then(([items, total]) => paginate(items, total, pagination.page, pagination.limit));
  }

  unreadCount(userId: string): Promise<number> {
    return this.prisma.notification.count({ where: { userId, readAt: null } });
  }

  async markRead(userId: string, id: string): Promise<void> {
    await this.prisma.notification.updateMany({
      where: { id, userId, readAt: null },
      data: { readAt: new Date() },
    });
  }

  async markAllRead(userId: string): Promise<void> {
    await this.prisma.notification.updateMany({
      where: { userId, readAt: null },
      data: { readAt: new Date() },
    });
  }
}

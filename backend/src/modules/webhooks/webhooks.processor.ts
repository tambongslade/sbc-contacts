import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Job, Queue } from 'bullmq';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';
import { MembersService } from '../members/members.service';
import { PaidFeaturesService } from '../paid-features/paid-features.service';
import { SbcSubscription } from '../sbc-client/interfaces/sbc.interface';
import { SbcClientService } from '../sbc-client/sbc-client.service';

const MEMBER_EVENTS = ['member.created', 'member.updated'];

/**
 * A member's subscriptions changed on SBC: paid, renewed, expired or
 * cancelled (docs/paiements-sbc.md). The payload carries the member's whole
 * current state, so every one of them is handled the same way.
 */
const SUBSCRIPTION_EVENTS = [
  'subscription.activated',
  'subscription.renewed',
  'subscription.updated',
  'subscription.expired',
  'subscription.cancelled',
];

interface SubscriptionEventData {
  user?: { id?: string; subscriptionTypes?: string[]; subscriptions?: SbcSubscription[] };
}

/**
 * Processes a stored webhook event: for member events it hydrates the mirror and
 * enqueues a MATCHING job. Throwing lets BullMQ retry (backoff/DLQ configured);
 * the error is persisted on the event row for inspection.
 */
@Processor(QUEUE_NAMES.WEBHOOKS)
export class WebhooksProcessor extends WorkerHost {
  constructor(
    private readonly prisma: PrismaService,
    private readonly members: MembersService,
    private readonly sbc: SbcClientService,
    @InjectQueue(QUEUE_NAMES.MATCHING) private readonly matchingQueue: Queue,
    private readonly paid: PaidFeaturesService,
  ) {
    super();
  }

  async process(job: Job<{ webhookEventId: string }>): Promise<void> {
    const event = await this.prisma.webhookEvent.findUnique({
      where: { id: job.data.webhookEventId },
    });
    if (!event || event.processedAt) return; // idempotent

    try {
      if (MEMBER_EVENTS.includes(event.type)) {
        const payload = event.payload as { data?: { member?: Record<string, unknown> } };
        const raw = payload.data?.member;
        // Normalise fr/en aliases exactly like the search path before mirroring.
        const contact = raw ? this.sbc.normalizeContact(raw) : undefined;
        if (contact?.id) {
          const member = await this.members.upsertFromSbc(contact);
          // No custom jobId: every member event re-matches; duplicate notifications
          // are prevented at the notification layer (notifyNewMatch dedup).
          await this.matchingQueue.add('match', { memberId: member.id });
        }
      }
      if (SUBSCRIPTION_EVENTS.includes(event.type)) {
        await this.applySubscriptions((event.payload as { data?: SubscriptionEventData }).data);
      }
      await this.prisma.webhookEvent.update({
        where: { id: event.id },
        data: { processedAt: new Date(), error: null },
      });
    } catch (err) {
      await this.prisma.webhookEvent.update({
        where: { id: event.id },
        data: { error: (err as Error).message },
      });
      throw err; // let BullMQ retry
    }
  }

  /**
   * Takes the member's subscriptions from the event right away, instead of
   * waiting for their next app open. A member who never logged in to the app
   * is skipped: their first login reads the same state from SBC.
   */
  private async applySubscriptions(data: SubscriptionEventData | undefined): Promise<void> {
    const sbcUser = data?.user;
    if (!sbcUser?.id) return;
    const user = await this.prisma.user.findUnique({
      where: { sbcUserId: sbcUser.id },
      select: { id: true },
    });
    if (!user) return;
    if (Array.isArray(sbcUser.subscriptionTypes)) {
      await this.prisma.user.update({
        where: { id: user.id },
        data: { subscriptionTypes: sbcUser.subscriptionTypes },
      });
    }
    await this.paid.applyFromSbc(user.id, sbcUser);
  }
}

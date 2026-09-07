import { InjectQueue } from '@nestjs/bullmq';
import { BadRequestException, Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { Queue } from 'bullmq';
import { createHmac, timingSafeEqual } from 'crypto';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';

interface SbcWebhookPayload {
  id: string; // provider event id (idempotency key)
  type: string; // e.g. member.created | member.updated
  data: unknown;
}

/**
 * Inbound SBC webhooks (brief §20 / cahier §11). Every request is:
 *  - authenticated by HMAC signature over the RAW body (not the parsed JSON),
 *  - deduplicated by event id (idempotency), and
 *  - processed asynchronously via the WEBHOOKS queue (retry-safe).
 *
 * READY now; inert until SBC actually emits member events (see project notes).
 */
@Injectable()
export class WebhooksService {
  private readonly logger = new Logger(WebhooksService.name);
  private readonly secret: string;

  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
    @InjectQueue(QUEUE_NAMES.WEBHOOKS) private readonly queue: Queue,
  ) {
    this.secret = config.get<string>('sbc.webhookSecret') ?? '';
  }

  async ingest(
    rawBody: Buffer | undefined,
    signature?: string,
  ): Promise<{ received: boolean; duplicate: boolean; id?: string }> {
    if (!rawBody || rawBody.length === 0) throw new BadRequestException('Empty webhook body');
    if (!this.verifySignature(rawBody, signature)) {
      throw new UnauthorizedException('Invalid webhook signature');
    }

    let payload: SbcWebhookPayload;
    try {
      payload = JSON.parse(rawBody.toString('utf8'));
    } catch {
      throw new BadRequestException('Malformed webhook JSON');
    }
    if (!payload.id || !payload.type) {
      throw new BadRequestException('Webhook must include id and type');
    }

    // Idempotency: same event id is accepted once.
    const existing = await this.prisma.webhookEvent.findUnique({
      where: { externalId: payload.id },
      select: { id: true },
    });
    if (existing) return { received: true, duplicate: true, id: existing.id };

    const event = await this.prisma.webhookEvent.create({
      data: {
        externalId: payload.id,
        type: payload.type,
        payload: payload as unknown as Prisma.InputJsonValue,
        signature,
      },
    });
    await this.queue.add('process', { webhookEventId: event.id }, { jobId: event.id });
    return { received: true, duplicate: false, id: event.id };
  }

  private verifySignature(rawBody: Buffer, signature?: string): boolean {
    if (!this.secret) {
      // No secret configured → refuse rather than accept blindly (brief §20).
      this.logger.error('SBC_WEBHOOK_SECRET is not set; rejecting webhook');
      return false;
    }
    if (!signature) return false;
    const expected = createHmac('sha256', this.secret).update(rawBody).digest('hex');
    const a = Buffer.from(signature, 'utf8');
    const b = Buffer.from(expected, 'utf8');
    return a.length === b.length && timingSafeEqual(a, b);
  }
}

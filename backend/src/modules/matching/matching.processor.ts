import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';
import { MatchingService } from './matching.service';

/** Consumes MATCHING jobs enqueued after a member is mirrored (cahier §11). */
@Processor(QUEUE_NAMES.MATCHING)
export class MatchingProcessor extends WorkerHost {
  private readonly logger = new Logger(MatchingProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly matching: MatchingService,
  ) {
    super();
  }

  async process(job: Job<{ memberId: string }>): Promise<void> {
    const member = await this.prisma.member.findUnique({ where: { id: job.data.memberId } });
    if (!member) {
      this.logger.warn(`MATCHING job for unknown member ${job.data.memberId}`);
      return;
    }
    await this.matching.onMember(member);
  }
}

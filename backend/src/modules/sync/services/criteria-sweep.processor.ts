import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger, OnModuleInit } from '@nestjs/common';
import { Queue } from 'bullmq';
import { QUEUE_NAMES } from '../../../infrastructure/queue/queue.module';
import { CriteriaSweepService } from './criteria-sweep.service';

/** How often every active criteria is re-checked against SBC. */
const SWEEP_EVERY_MS = 15 * 60 * 1000; // 15 min

/**
 * Drives [CriteriaSweepService] on a repeatable BullMQ job.
 *
 * A repeatable job rather than `@nestjs/schedule`: the queue infrastructure,
 * its Redis connection and its retry/retention policy already exist, and a
 * repeatable job survives a pm2 restart without every instance firing its own
 * timer. `jobId` is fixed so re-registering on each boot replaces the schedule
 * instead of stacking another one on top of it.
 */
@Processor(QUEUE_NAMES.CRITERIA_SWEEP)
export class CriteriaSweepProcessor extends WorkerHost implements OnModuleInit {
  private readonly logger = new Logger(CriteriaSweepProcessor.name);

  constructor(
    private readonly sweep: CriteriaSweepService,
    @InjectQueue(QUEUE_NAMES.CRITERIA_SWEEP) private readonly queue: Queue,
  ) {
    super();
  }

  async onModuleInit(): Promise<void> {
    await this.queue.add(
      'sweep',
      {},
      {
        jobId: 'criteria-sweep',
        repeat: { every: SWEEP_EVERY_MS },
        // A sweep that failed is re-run by the next tick; retrying a stale one
        // would only re-ask SBC for members the next pass covers anyway.
        attempts: 1,
        removeOnComplete: { count: 50 },
      },
    );
    this.logger.log(`Criteria sweep scheduled every ${SWEEP_EVERY_MS / 60000} min`);
  }

  async process(): Promise<void> {
    await this.sweep.sweep();
  }
}

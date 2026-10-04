import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger, OnModuleInit } from '@nestjs/common';
import { Job, Queue } from 'bullmq';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';
import { RequestsService } from './services/requests.service';

/** How often routed-but-unanswered requests are swept and closed (Data §16). */
const SWEEP_EVERY_MS = 30 * 60 * 1000; // 30 min

/**
 * Matches a sent request and routes it to pros off the request path: embedding
 * and the AI judge take seconds, and a Gemini hiccup should be retried by the
 * queue, not surface as an error on "Envoyer ma demande".
 *
 * Also drives the stale-request sweep on a repeatable job — a fixed jobId so
 * re-registering on each boot replaces the schedule instead of stacking one
 * (same pattern as the criteria sweep), surviving a pm2 restart.
 */
@Processor(QUEUE_NAMES.SBC_DATA)
export class SbcDataProcessor extends WorkerHost implements OnModuleInit {
  private readonly logger = new Logger(SbcDataProcessor.name);

  constructor(
    private readonly requests: RequestsService,
    @InjectQueue(QUEUE_NAMES.SBC_DATA) private readonly queue: Queue,
  ) {
    super();
  }

  async onModuleInit(): Promise<void> {
    await this.queue.add(
      'sweep-stale',
      {},
      {
        jobId: 'sbc-data-sweep-stale',
        repeat: { every: SWEEP_EVERY_MS },
        attempts: 1,
        removeOnComplete: { count: 50 },
      },
    );
    this.logger.log(`Stale-request sweep scheduled every ${SWEEP_EVERY_MS / 60000} min`);
  }

  async process(job: Job<{ requestId: string }>): Promise<void> {
    if (job.name === 'match') await this.requests.runMatching(job.data.requestId);
    else if (job.name === 'sweep-stale') await this.requests.closeStale();
  }
}

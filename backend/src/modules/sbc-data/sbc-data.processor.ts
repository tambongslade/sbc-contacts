import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger, OnModuleInit } from '@nestjs/common';
import { Job, Queue } from 'bullmq';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';
import { ProfessionalService } from './services/professional.service';
import { RequestsService } from './services/requests.service';

/** How often routed-but-unanswered requests are swept and closed (Data §16). */
const SWEEP_EVERY_MS = 30 * 60 * 1000; // 30 min
/** How often services left without an embedding (a Gemini outage) are retried. */
const REEMBED_EVERY_MS = 15 * 60 * 1000; // 15 min

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
    private readonly professionals: ProfessionalService,
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
    await this.queue.add(
      'reembed-services',
      {},
      {
        jobId: 'sbc-data-reembed-services',
        repeat: { every: REEMBED_EVERY_MS },
        attempts: 1,
        removeOnComplete: { count: 50 },
      },
    );
    this.logger.log(
      `Stale-request sweep every ${SWEEP_EVERY_MS / 60000} min, ` +
        `embedding retry every ${REEMBED_EVERY_MS / 60000} min`,
    );
  }

  async process(job: Job<{ requestId: string }>): Promise<void> {
    if (job.name === 'match') await this.requests.runMatching(job.data.requestId);
    else if (job.name === 'sweep-stale') await this.requests.closeStale();
    else if (job.name === 'reembed-services') {
      const healed = await this.professionals.reembedMissing();
      if (healed) this.logger.log(`Re-embedded ${healed} service(s) that had no vector`);
    }
  }
}

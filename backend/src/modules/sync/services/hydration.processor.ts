import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { QUEUE_NAMES } from '../../../infrastructure/queue/queue.module';
import { CriteriaHydrationService, HydrationJob } from './criteria-hydration.service';

/**
 * Runs the deep hydration walk off the member's screen (§10). A criteria preview
 * enqueues one of these; here it pages the whole criteria into the mirror so the
 * matches list can be paged and saved through to the end. Throwing lets BullMQ
 * retry (backoff/DLQ configured) — [CriteriaHydrationService.hydrateFull] throws
 * only when SBC failed every query, i.e. a real outage worth retrying.
 */
@Processor(QUEUE_NAMES.HYDRATION)
export class HydrationProcessor extends WorkerHost {
  constructor(private readonly hydration: CriteriaHydrationService) {
    super();
  }

  async process(job: Job<HydrationJob>): Promise<void> {
    await this.hydration.hydrateFull(job.data);
  }
}

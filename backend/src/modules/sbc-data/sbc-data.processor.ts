import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { QUEUE_NAMES } from '../../infrastructure/queue/queue.module';
import { RequestsService } from './services/requests.service';

/**
 * Matches a sent request and routes it to pros off the request path: embedding
 * and the AI judge take seconds, and a Gemini hiccup should be retried by the
 * queue, not surface as an error on "Envoyer ma demande".
 */
@Processor(QUEUE_NAMES.SBC_DATA)
export class SbcDataProcessor extends WorkerHost {
  constructor(private readonly requests: RequestsService) {
    super();
  }

  async process(job: Job<{ requestId: string }>): Promise<void> {
    if (job.name === 'match') await this.requests.runMatching(job.data.requestId);
  }
}

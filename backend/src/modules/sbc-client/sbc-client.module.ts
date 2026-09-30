import { Global, Module } from '@nestjs/common';
import { SbcClientService } from './sbc-client.service';
import { SbcRateLimiterService } from './sbc-rate-limiter.service';

/**
 * Global so any module (directory, sync, matching) can obtain SBC data through
 * the one typed client — no module reimplements SBC calls. The rate limiter is
 * exported too so background callers can check its pause state before a walk.
 */
@Global()
@Module({
  providers: [SbcClientService, SbcRateLimiterService],
  exports: [SbcClientService, SbcRateLimiterService],
})
export class SbcClientModule {}

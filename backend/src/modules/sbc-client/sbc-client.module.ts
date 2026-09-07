import { Global, Module } from '@nestjs/common';
import { SbcClientService } from './sbc-client.service';

/**
 * Global so any module (directory, sync, matching) can obtain SBC data through
 * the one typed client — no module reimplements SBC calls.
 */
@Global()
@Module({
  providers: [SbcClientService],
  exports: [SbcClientService],
})
export class SbcClientModule {}

import { Module } from '@nestjs/common';
import { SpotlightController } from './spotlight.controller';
import { SpotlightService } from './spotlight.service';
import { StatusBoostController } from './status-boost.controller';
import { StatusBoostService } from './status-boost.service';

@Module({
  controllers: [StatusBoostController, SpotlightController],
  providers: [StatusBoostService, SpotlightService],
  // Sync: a criteria can target the list.
  exports: [StatusBoostService],
})
export class StatusBoostModule {}

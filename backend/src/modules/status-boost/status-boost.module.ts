import { Module } from '@nestjs/common';
import { StatusBoostController } from './status-boost.controller';
import { StatusBoostService } from './status-boost.service';

@Module({
  controllers: [StatusBoostController],
  providers: [StatusBoostService],
})
export class StatusBoostModule {}

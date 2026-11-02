import { Module } from '@nestjs/common';
import { TerminusModule } from '@nestjs/terminus';
import { SbcDataModule } from '../sbc-data/sbc-data.module';
import { HealthController } from './health.controller';

@Module({
  imports: [TerminusModule, SbcDataModule],
  controllers: [HealthController],
})
export class HealthModule {}

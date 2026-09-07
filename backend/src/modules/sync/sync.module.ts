import { Module } from '@nestjs/common';
import { CriteriaController } from './controllers/criteria.controller';
import { SyncController } from './controllers/sync.controller';
import { CriteriaService } from './services/criteria.service';
import { SyncService } from './services/sync.service';

/**
 * Sync = the "intelligent synchronisation" core (cahier §10–§17). Criteria are
 * evaluated against the Member mirror; runs track per-device contact state.
 * CriteriaService is exported for Phase 5's matching worker.
 */
@Module({
  controllers: [CriteriaController, SyncController],
  providers: [CriteriaService, SyncService],
  exports: [CriteriaService],
})
export class SyncModule {}

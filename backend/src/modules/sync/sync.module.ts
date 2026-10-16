import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { StatusBoostModule } from '../status-boost/status-boost.module';
import { CriteriaController } from './controllers/criteria.controller';
import { SyncController } from './controllers/sync.controller';
import { CriteriaHydrationService } from './services/criteria-hydration.service';
import { CriteriaMatchResolver } from './services/criteria-match.resolver';
import { CriteriaSweepProcessor } from './services/criteria-sweep.processor';
import { CriteriaSweepService } from './services/criteria-sweep.service';
import { CriteriaService } from './services/criteria.service';
import { HydrationProcessor } from './services/hydration.processor';
import { SyncService } from './services/sync.service';

/**
 * Sync = the "intelligent synchronisation" core (cahier §10–§17). Criteria are
 * evaluated against the Member mirror; runs track per-device contact state.
 * CriteriaService is exported for Phase 5's matching worker.
 */
@Module({
  // Notifications: reporting a sync now tells the person who was saved (§21).
  // AuthModule: SbcTokenService, to hydrate criteria straight from SBC.
  // StatusBoostModule: a criteria can target "Augmenter mes vues WhatsApp".
  imports: [NotificationsModule, AuthModule, StatusBoostModule],
  controllers: [CriteriaController, SyncController],
  providers: [
    CriteriaHydrationService,
    CriteriaMatchResolver,
    CriteriaService,
    CriteriaSweepService,
    CriteriaSweepProcessor,
    SyncService,
    HydrationProcessor,
  ],
  exports: [CriteriaService],
})
export class SyncModule {}

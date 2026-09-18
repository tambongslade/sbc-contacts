import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { CriteriaController } from './controllers/criteria.controller';
import { SyncController } from './controllers/sync.controller';
import { CriteriaHydrationService } from './services/criteria-hydration.service';
import { CriteriaService } from './services/criteria.service';
import { SyncService } from './services/sync.service';

/**
 * Sync = the "intelligent synchronisation" core (cahier §10–§17). Criteria are
 * evaluated against the Member mirror; runs track per-device contact state.
 * CriteriaService is exported for Phase 5's matching worker.
 */
@Module({
  // Notifications: reporting a sync now tells the person who was saved (§21).
  // AuthModule: SbcTokenService, to hydrate criteria straight from SBC.
  imports: [NotificationsModule, AuthModule],
  controllers: [CriteriaController, SyncController],
  providers: [CriteriaHydrationService, CriteriaService, SyncService],
  exports: [CriteriaService],
})
export class SyncModule {}

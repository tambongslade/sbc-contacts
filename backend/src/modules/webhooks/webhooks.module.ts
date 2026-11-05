import { Module } from '@nestjs/common';
import { MatchingModule } from '../matching/matching.module';
import { PaidFeaturesModule } from '../paid-features/paid-features.module';
import { WebhooksController } from './webhooks.controller';
import { WebhooksProcessor } from './webhooks.processor';
import { WebhooksService } from './webhooks.service';

/**
 * Inbound SBC webhooks → mirror hydration → MATCHING queue. Imports MatchingModule
 * so the matching worker (and its NotificationsService dependency) is wired.
 */
@Module({
  imports: [MatchingModule, PaidFeaturesModule],
  controllers: [WebhooksController],
  providers: [WebhooksService, WebhooksProcessor],
})
export class WebhooksModule {}

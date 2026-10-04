import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { ReviewsModule } from '../reviews/reviews.module';
import { GeminiClient } from './ai/gemini.client';
import { ProSetupAssistant } from './ai/pro-setup-assistant';
import { SbcDataAiService } from './ai/sbc-data-ai.service';
import { SbcDataAdminController } from './controllers/admin.controller';
import { ProController } from './controllers/pro.controller';
import { RequestsController } from './controllers/requests.controller';
import { RequestMatchingService } from './matching/request-matching.service';
import { SbcDataProcessor } from './sbc-data.processor';
import { SbcDataAdminService } from './services/admin.service';
import { ProfessionalService } from './services/professional.service';
import { RequestsService } from './services/requests.service';

/**
 * SBC Data (cahier "SBC Data"): a requester describes a need, the AI reads it,
 * matching routes it to the pros whose services fit, they answer, the
 * requester chooses. Reception is the paid part (2 000 FCFA/mois).
 */
@Module({
  imports: [NotificationsModule, ReviewsModule],
  controllers: [ProController, RequestsController, SbcDataAdminController],
  providers: [
    GeminiClient,
    ProSetupAssistant,
    SbcDataAiService,
    RequestMatchingService,
    ProfessionalService,
    RequestsService,
    SbcDataAdminService,
    SbcDataProcessor,
  ],
})
export class SbcDataModule {}

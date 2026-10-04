import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthenticatedUser, CurrentUser } from '../../../common/decorators/current-user.decorator';
import { PaginatedResult } from '../../../common/dto/pagination.dto';
import { AssistantTurn } from '../ai/pro-setup-assistant';
import { StructuredServices } from '../ai/sbc-data-ai.service';
import {
  AddServicesDto,
  AssistantTurnDto,
  InboxQueryDto,
  RespondDto,
  StructureServicesDto,
  UpdateServiceDto,
  UpsertProProfileDto,
} from '../dto/sbc-data.dto';
import { InboxItemView, ProProfileView } from '../sbc-data.views';
import { ProfessionalService, ProStats } from '../services/professional.service';

/** SBC Data, professional side (Data §3, §4, §10, §18). */
@ApiTags('sbc-data: pro')
@ApiBearerAuth()
@Controller({ path: 'data/pro', version: '1' })
export class ProController {
  constructor(private readonly pros: ProfessionalService) {}

  @Get('profile')
  @ApiOperation({ summary: 'My professional profile, services and reception status' })
  profile(@CurrentUser() user: AuthenticatedUser): Promise<ProProfileView> {
    return this.pros.getProfile(user.userId);
  }

  @Put('profile')
  @ApiOperation({ summary: 'Create or update my professional profile' })
  upsertProfile(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpsertProProfileDto,
  ): Promise<ProProfileView> {
    return this.pros.upsertProfile(user.userId, dto);
  }

  @Post('assistant')
  @ApiOperation({ summary: 'One turn of the AI setup conversation — nothing is saved' })
  assistant(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: AssistantTurnDto,
  ): Promise<AssistantTurn> {
    return this.pros.assistantTurn(user.userId, dto);
  }

  @Post('services/structure')
  @ApiOperation({ summary: 'AI proposals from free text — nothing is saved' })
  structure(@Body() dto: StructureServicesDto): Promise<StructuredServices> {
    return this.pros.structure(dto.text);
  }

  @Post('services')
  @ApiOperation({ summary: 'Save the services I validated' })
  addServices(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: AddServicesDto,
  ): Promise<ProProfileView> {
    return this.pros.addServices(user.userId, dto);
  }

  @Patch('services/:id')
  updateService(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateServiceDto,
  ): Promise<ProProfileView> {
    return this.pros.updateService(user.userId, id, dto);
  }

  @Delete('services/:id')
  deleteService(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<ProProfileView> {
    return this.pros.deleteService(user.userId, id);
  }

  @Get('inbox')
  @ApiOperation({ summary: '"Mes demandes reçues"' })
  inbox(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: InboxQueryDto,
  ): Promise<PaginatedResult<InboxItemView>> {
    return this.pros.inbox(user.userId, query);
  }

  @Get('inbox/:requestId')
  @ApiOperation({ summary: 'Open a received request (marks it seen)' })
  inboxItem(
    @CurrentUser() user: AuthenticatedUser,
    @Param('requestId', ParseUUIDPipe) requestId: string,
  ): Promise<InboxItemView> {
    return this.pros.inboxItem(user.userId, requestId);
  }

  @Post('inbox/:requestId/respond')
  @ApiOperation({ summary: 'Interested / question / unavailable / cannot do it' })
  respond(
    @CurrentUser() user: AuthenticatedUser,
    @Param('requestId', ParseUUIDPipe) requestId: string,
    @Body() dto: RespondDto,
  ): Promise<InboxItemView> {
    return this.pros.respond(user.userId, requestId, dto);
  }

  @Get('stats')
  @ApiOperation({ summary: '"Mes statistiques"' })
  stats(@CurrentUser() user: AuthenticatedUser): Promise<ProStats> {
    return this.pros.stats(user.userId);
  }
}

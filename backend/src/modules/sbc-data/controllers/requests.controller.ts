import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthenticatedUser, CurrentUser } from '../../../common/decorators/current-user.decorator';
import { PaginatedResult } from '../../../common/dto/pagination.dto';
import {
  CompleteRequestDto,
  CreateRequestDto,
  RequestsQueryDto,
  SelectProDto,
  UpdateRequestDto,
} from '../dto/sbc-data.dto';
import { RequestView } from '../sbc-data.views';
import { RequestsService } from '../services/requests.service';

/** SBC Data, requester side (Data §6–§16, §19). */
@ApiTags('sbc-data: requests')
@ApiBearerAuth()
@Controller({ path: 'data/requests', version: '1' })
export class RequestsController {
  constructor(private readonly requests: RequestsService) {}

  @Post()
  @ApiOperation({ summary: 'Describe a need; returns the AI reading as a draft' })
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateRequestDto,
  ): Promise<RequestView> {
    return this.requests.create(user.userId, dto);
  }

  @Get()
  @ApiOperation({ summary: '"Mes demandes"' })
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: RequestsQueryDto,
  ): Promise<PaginatedResult<RequestView>> {
    return this.requests.list(user.userId, query);
  }

  @Get(':id')
  get(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<RequestView> {
    return this.requests.get(user.userId, id);
  }

  @Patch(':id')
  @ApiOperation({ summary: "Correct the draft, or answer the AI's question" })
  update(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateRequestDto,
  ): Promise<RequestView> {
    return this.requests.update(user.userId, id, dto);
  }

  @Post(':id/send')
  @ApiOperation({ summary: '"Envoyer ma demande"' })
  send(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<RequestView> {
    return this.requests.send(user.userId, id);
  }

  @Post(':id/select')
  @ApiOperation({ summary: '"Retenir ce professionnel"' })
  select(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SelectProDto,
  ): Promise<RequestView> {
    return this.requests.select(user.userId, id, dto.dispatchId);
  }

  @Post(':id/complete')
  @ApiOperation({ summary: 'Confirm the job and rate, or report it as not done' })
  complete(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CompleteRequestDto,
  ): Promise<RequestView> {
    return this.requests.complete(user.userId, user.sbcUserId, id, dto);
  }

  @Post(':id/cancel')
  cancel(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<RequestView> {
    return this.requests.cancel(user.userId, id);
  }
}

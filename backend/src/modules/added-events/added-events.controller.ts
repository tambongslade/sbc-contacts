import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../common/decorators/current-user.decorator';
import { PaginatedResult, PaginationQueryDto } from '../../common/dto/pagination.dto';
import {
  AddedByUserView,
  AddedEventsService,
  RecordAddResult,
} from './added-events.service';
import { CreateAddedEventDto } from './dto/create-added-event.dto';

@ApiTags('added-events')
@ApiBearerAuth()
@Controller({ path: 'added-events', version: '1' })
export class AddedEventsController {
  constructor(private readonly addedEvents: AddedEventsService) {}

  @Post()
  @ApiOperation({
    summary: 'Record a direct add (§21) — feeds "Mes contacts SBC" and notifies the target',
  })
  record(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateAddedEventDto,
  ): Promise<RecordAddResult> {
    return this.addedEvents.record(user.userId, dto);
  }

  @Get('who-added-me')
  @ApiOperation({ summary: 'People who added the caller to their contacts (§21)' })
  whoAddedMe(
    @CurrentUser() user: AuthenticatedUser,
    @Query() pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<AddedByUserView>> {
    return this.addedEvents.whoAddedMe(user.sbcUserId, pagination);
  }
}

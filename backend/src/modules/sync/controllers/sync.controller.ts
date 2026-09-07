import { Body, Controller, Get, Param, Post, Query, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../../common/decorators/current-user.decorator';
import { PaginatedResult, PaginationQueryDto } from '../../../common/dto/pagination.dto';
import { ReportSyncDto, StartSyncDto, SyncContactsQueryDto } from '../dto/sync.dto';
import { StartSyncResult, SyncService } from '../services/sync.service';

@ApiTags('sync')
@ApiBearerAuth()
@Controller({ path: 'sync', version: '1' })
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post('runs')
  @ApiOperation({ summary: 'Start a sync run; returns targets + dedup hints (§10/§15)' })
  start(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: StartSyncDto,
    @Req() req: Request,
  ): Promise<StartSyncResult> {
    return this.sync.start(user.userId, dto, req.ip);
  }

  @Post('runs/:id/report')
  @ApiOperation({ summary: 'Report device write outcomes; finalizes the run' })
  report(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() dto: ReportSyncDto,
    @Req() req: Request,
  ) {
    return this.sync.report(user.userId, id, dto, req.ip);
  }

  @Get('history')
  @ApiOperation({ summary: 'Synchronisation history (§17)' })
  history(
    @CurrentUser() user: AuthenticatedUser,
    @Query() pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<unknown>> {
    return this.sync.history(user.userId, pagination.page, pagination.limit);
  }

  @Get('summary')
  @ApiOperation({ summary: '"Mes contacts SBC" dashboard counts (§16)' })
  summary(@CurrentUser() user: AuthenticatedUser) {
    return this.sync.summary(user.userId);
  }

  @Get('contacts')
  @ApiOperation({ summary: 'Synced contacts with status (§16)' })
  contacts(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: SyncContactsQueryDto,
  ): Promise<PaginatedResult<unknown>> {
    return this.sync.contacts(user.userId, query);
  }
}

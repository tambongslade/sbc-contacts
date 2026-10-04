import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Role } from '@prisma/client';
import { AuthenticatedUser, CurrentUser } from '../../../common/decorators/current-user.decorator';
import { Roles } from '../../../common/decorators/roles.decorator';
import {
  AdminListQueryDto,
  AdminProsQueryDto,
  AdminRequestsQueryDto,
  AdminServiceUpdateDto,
  MergeServiceDto,
  SetReceivingDto,
  UnfulfilledAnalyticsQueryDto,
} from '../dto/sbc-data.dto';
import { SbcDataAdminService } from '../services/admin.service';

/** The SBC back-office API (Data §21). Admins only; every write is audited. */
@ApiTags('sbc-data: admin')
@ApiBearerAuth()
@Roles(Role.ADMIN, Role.SUPER_ADMIN)
@Controller({ path: 'data/admin', version: '1' })
export class SbcDataAdminController {
  constructor(private readonly admin: SbcDataAdminService) {}

  @Get('stats')
  @ApiOperation({ summary: 'Dashboard: requests, pros, responses, conversions' })
  stats() {
    return this.admin.stats();
  }

  @Get('requests')
  requests(@Query() q: AdminRequestsQueryDto) {
    return this.admin.requests(q);
  }

  @Get('requests/:id')
  @ApiOperation({ summary: 'One request with its matching log and reports' })
  request(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.request(id);
  }

  /** Kept for callers of the first admin version. */
  @Get('requests/:id/matching')
  matchingLog(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.request(id);
  }

  @Post('requests/:id/suspend')
  @ApiOperation({ summary: 'Take a request off the market' })
  suspend(@CurrentUser() admin: AuthenticatedUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.suspendRequest(admin.userId, id);
  }

  @Get('pros')
  pros(@Query() q: AdminProsQueryDto) {
    return this.admin.pros(q);
  }

  @Get('pros/:userId')
  pro(@Param('userId', ParseUUIDPipe) userId: string) {
    return this.admin.pro(userId);
  }

  @Patch('pros/:userId/receiving')
  @ApiOperation({ summary: "Switch a pro's request reception on or off (Data §17)" })
  setReceiving(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('userId', ParseUUIDPipe) userId: string,
    @Body() dto: SetReceivingDto,
  ) {
    return this.admin.setReceiving(admin.userId, userId, dto);
  }

  @Get('services')
  services(@Query() q: AdminListQueryDto) {
    return this.admin.services(q);
  }

  @Patch('services/:id')
  @ApiOperation({ summary: 'Correct a service, its synonyms, or switch it off' })
  updateService(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdminServiceUpdateDto,
  ) {
    return this.admin.updateService(admin.userId, id, dto);
  }

  @Post('services/:id/merge')
  @ApiOperation({ summary: 'Merge this service into another of the same pro' })
  mergeService(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MergeServiceDto,
  ) {
    return this.admin.mergeService(admin.userId, id, dto.intoId);
  }

  @Delete('services/:id')
  @HttpCode(204)
  async deleteService(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<void> {
    await this.admin.deleteService(admin.userId, id);
  }

  @Get('analytics/unfulfilled')
  @ApiOperation({
    summary: 'Unfulfilled demands, grouped by term, to target recruitment (Data §E)',
  })
  unfulfilled(@Query() query: UnfulfilledAnalyticsQueryDto) {
    return this.admin.unfulfilled(query);
  }

  @Get('reports')
  @ApiOperation({ summary: '"Prestation non réalisée" reports' })
  reports(@Query() q: AdminListQueryDto) {
    return this.admin.reports(q);
  }
}

import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Device, Notification } from '@prisma/client';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../common/decorators/current-user.decorator';
import { PaginatedResult } from '../../common/dto/pagination.dto';
import { DevicesService } from './devices.service';
import { NotificationsQueryDto, RegisterDeviceDto } from './dto/notifications.dto';
import { NotificationsService } from './notifications.service';

@ApiTags('notifications')
@ApiBearerAuth()
@Controller({ path: 'notifications', version: '1' })
export class NotificationsController {
  constructor(
    private readonly notifications: NotificationsService,
    private readonly devices: DevicesService,
  ) {}

  @Get()
  @ApiOperation({ summary: 'List notifications (cahier §19)' })
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: NotificationsQueryDto,
  ): Promise<PaginatedResult<Notification>> {
    return this.notifications.list(user.userId, query, query.unreadOnly ?? false);
  }

  @Get('unread-count')
  @ApiOperation({ summary: 'Unread notification count (badge)' })
  async unreadCount(@CurrentUser() user: AuthenticatedUser): Promise<{ count: number }> {
    return { count: await this.notifications.unreadCount(user.userId) };
  }

  @Post(':id/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Mark one notification read' })
  async markRead(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<void> {
    await this.notifications.markRead(user.userId, id);
  }

  @Post('read-all')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Mark all notifications read' })
  async markAllRead(@CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.notifications.markAllRead(user.userId);
  }

  // ── device registration (push targets) ──
  @Post('devices')
  @ApiOperation({ summary: 'Register a device for push notifications' })
  registerDevice(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterDeviceDto,
  ): Promise<Device> {
    return this.devices.register(user.userId, dto.platform, dto.pushToken);
  }

  @Get('devices')
  @ApiOperation({ summary: "List the caller's registered devices" })
  listDevices(@CurrentUser() user: AuthenticatedUser): Promise<Device[]> {
    return this.devices.list(user.userId);
  }

  @Delete('devices/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Unregister a device' })
  async removeDevice(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<void> {
    await this.devices.remove(user.userId, id);
  }
}

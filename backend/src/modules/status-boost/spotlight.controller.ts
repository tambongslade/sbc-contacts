import { Body, Controller, Get, Param, ParseUUIDPipe, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Role } from '@prisma/client';
import { AuthenticatedUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { SetSpotlightDto } from './status-boost.dto';
import { SpotlightEntry, SpotlightService, SpotlightStatus } from './spotlight.service';

/** "Mise en avant": featured members in "Qui m'a enregistré" and "Augmenter mes vues WhatsApp". */
@ApiTags('spotlight')
@ApiBearerAuth()
@Controller({ path: 'spotlight', version: '1' })
export class SpotlightController {
  constructor(private readonly spotlight: SpotlightService) {}

  @Get('featured')
  @ApiOperation({ summary: 'Featured members the caller has not saved yet' })
  featured(@CurrentUser() user: AuthenticatedUser): Promise<SpotlightEntry[]> {
    return this.spotlight.featured(user.userId);
  }

  @Get('me')
  @ApiOperation({ summary: "Whether the caller's own profile is featured" })
  me(@CurrentUser() user: AuthenticatedUser): Promise<SpotlightStatus> {
    return this.spotlight.me(user.userId);
  }

  @Put('admin/:userId')
  @Roles(Role.ADMIN, Role.SUPER_ADMIN)
  @ApiOperation({ summary: 'Back-office: feature a member until a date, or stop (until: null)' })
  set(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('userId', ParseUUIDPipe) userId: string,
    @Body() dto: SetSpotlightDto,
  ) {
    return this.spotlight.setUntil(admin.userId, userId, dto.until ? new Date(dto.until) : null);
  }
}

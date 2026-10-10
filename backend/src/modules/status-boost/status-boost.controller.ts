import { Body, Controller, Get, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthenticatedUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { StatusBoostOptInDto, StatusBoostQueryDto } from './status-boost.dto';
import { StatusBoostPage, StatusBoostService } from './status-boost.service';

/** "Je veux augmenter mon nombre de vues en statut WhatsApp". */
@ApiTags('status-boost')
@ApiBearerAuth()
@Controller({ path: 'status-boost', version: '1' })
export class StatusBoostController {
  constructor(private readonly boost: StatusBoostService) {}

  @Get()
  @ApiOperation({ summary: 'Members who opted in, to save on the phone' })
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Query() q: StatusBoostQueryDto,
  ): Promise<StatusBoostPage> {
    return this.boost.list(user.userId, q);
  }

  @Get('me')
  me(@CurrentUser() user: AuthenticatedUser) {
    return this.boost.me(user.userId);
  }

  @Put('me')
  @ApiOperation({ summary: 'Join or leave the list' })
  setOptIn(@CurrentUser() user: AuthenticatedUser, @Body() dto: StatusBoostOptInDto) {
    return this.boost.setOptIn(user.userId, dto.optIn);
  }
}

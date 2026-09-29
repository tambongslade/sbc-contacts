import {
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Patch,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Role } from '@prisma/client';
import { AuthenticatedUser, CurrentUser } from '../../../common/decorators/current-user.decorator';
import { Roles } from '../../../common/decorators/roles.decorator';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { SetReceivingDto } from '../dto/sbc-data.dto';

/**
 * The slice of the SBC Data back-office (Data §21) the MVP cannot run without:
 * switching a pro's reception on while payments do not exist yet, and reading
 * why a request went to whom.
 */
@ApiTags('sbc-data: admin')
@ApiBearerAuth()
@Roles(Role.ADMIN, Role.SUPER_ADMIN)
@Controller({ path: 'data/admin', version: '1' })
export class SbcDataAdminController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  @Patch('pros/:userId/receiving')
  @ApiOperation({ summary: "Switch a pro's request reception on or off (Data §17)" })
  async setReceiving(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('userId', ParseUUIDPipe) userId: string,
    @Body() dto: SetReceivingDto,
  ) {
    const before = await this.prisma.proProfile.findUnique({ where: { userId } });
    if (!before) throw new NotFoundException('Ce membre n’a pas de profil professionnel');
    const after = await this.prisma.proProfile.update({
      where: { userId },
      data: {
        receivingEnabled: dto.enabled,
        receivingUntil: dto.until ? new Date(dto.until) : null,
      },
      select: { userId: true, receivingEnabled: true, receivingUntil: true },
    });
    await this.audit.record({
      actorId: admin.userId,
      action: 'sbc-data.pro.receiving',
      resource: `ProProfile:${before.id}`,
      before: { receivingEnabled: before.receivingEnabled, receivingUntil: before.receivingUntil },
      after,
    });
    return after;
  }

  @Get('requests/:id/matching')
  @ApiOperation({ summary: 'Matching log: who received a request, and why (Data §21)' })
  async matchingLog(@Param('id', ParseUUIDPipe) id: string) {
    const found = await this.prisma.serviceRequest.findUnique({ where: { id } });
    if (!found) throw new NotFoundException('Demande introuvable');
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { embedding, ...request } = found;
    const dispatches = await this.prisma.requestDispatch.findMany({
      where: { requestId: id },
      orderBy: { score: 'desc' },
      include: {
        service: { select: { name: true, category: true } },
        pro: { select: { profession: true, city: true, user: { select: { name: true } } } },
      },
    });
    return { request, dispatches };
  }
}

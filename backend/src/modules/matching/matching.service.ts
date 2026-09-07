import { Injectable, Logger } from '@nestjs/common';
import { Member } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { MemberMatchService } from '../members/member-match.service';
import { toMatchCriteria } from '../members/member.view';
import { NotificationsService } from '../notifications/notifications.service';

/**
 * New-member matching (cahier §11). When a member is created/updated (via the
 * SBC webhook → mirror), test it against every active saved criteria and raise a
 * deduped NEW_MATCH notification for each affected user.
 *
 * v1 loads active criteria and tests in-memory — simple and correct. If the
 * criteria table grows large this is the natural place to add pre-filtering.
 */
@Injectable()
export class MatchingService {
  private readonly logger = new Logger(MatchingService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly matcher: MemberMatchService,
    private readonly notifications: NotificationsService,
  ) {}

  async onMember(member: Member): Promise<{ notified: number }> {
    const activeCriteria = await this.prisma.syncCriteria.findMany({ where: { isActive: true } });

    let notified = 0;
    for (const criteria of activeCriteria) {
      if (!this.matcher.matchesMember(member, toMatchCriteria(criteria))) continue;
      // notifyNewMatch dedupes per (user, member): a member matching several of a
      // user's criteria yields a single notification.
      const created = await this.notifications.notifyNewMatch(criteria.userId, member, criteria);
      if (created) notified++;
    }

    if (notified > 0) {
      this.logger.log(`member ${member.sbcId} matched → ${notified} user(s) notified`);
    }
    return { notified };
  }
}

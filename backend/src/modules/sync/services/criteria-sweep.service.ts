import { Injectable, Logger } from '@nestjs/common';
import { SyncCriteria } from '@prisma/client';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { MemberMatchService } from '../../members/member-match.service';
import { toMatchCriteria } from '../../members/member.view';
import { NotificationsService } from '../../notifications/notifications.service';
import { CriteriaHydrationService } from './criteria-hydration.service';

/**
 * Periodic re-check of every active criteria (cahier §11).
 *
 * The matching worker only ever ran from an SBC webhook, and SBC does not call
 * us — so "tell me when somebody new matches" never fired once. This sweep is
 * the trigger that was missing: it pulls fresh members out of SBC for each
 * criteria, notices the ones that arrived since the last pass, and notifies the
 * criteria's owner.
 *
 * SBC's contacts payload carries no registration date, so "new" can only mean
 * "new to our mirror" (`Member.createdAt`). That makes the first pass over a
 * criteria dangerous: hydration mirrors members who have been on SBC for years
 * but are new to us, and notifying on those would dump thousands of alerts.
 * Hence [baseline]: a criteria whose `lastCheckedAt` is null is only stamped,
 * never notified on, and [MAX_NOTIFICATIONS_PER_SWEEP] caps the blast radius if
 * a baseline is ever missed.
 */
@Injectable()
export class CriteriaSweepService {
  private readonly logger = new Logger(CriteriaSweepService.name);

  /**
   * Most a single criteria may notify in one pass.
   *
   * Not a performance guard — a correctness one. Anything above this means the
   * mirror just learned about a batch of members wholesale rather than a person
   * genuinely registering, and the member would rather see ten alerts than two
   * thousand.
   */
  private static readonly MAX_NOTIFICATIONS_PER_SWEEP = 10;

  /** Criteria handled per pass, oldest-checked first, so one sweep is bounded. */
  private static readonly MAX_CRITERIA_PER_SWEEP = 50;

  constructor(
    private readonly prisma: PrismaService,
    private readonly matcher: MemberMatchService,
    private readonly hydration: CriteriaHydrationService,
    private readonly notifications: NotificationsService,
  ) {}

  /** One pass over the active criteria that went longest without a check. */
  async sweep(): Promise<{ checked: number; notified: number }> {
    const criteria = await this.prisma.syncCriteria.findMany({
      where: { isActive: true },
      orderBy: { lastCheckedAt: { sort: 'asc', nulls: 'first' } },
      take: CriteriaSweepService.MAX_CRITERIA_PER_SWEEP,
    });

    let notified = 0;
    for (const c of criteria) {
      try {
        notified += await this.sweepOne(c);
      } catch (err) {
        // One criteria's owner having a lapsed SBC session must not stop the
        // rest of the sweep — the same reasoning as hydration's per-query catch.
        this.logger.warn(`Sweep skipped criteria ${c.id}: ${(err as Error).message}`);
      }
    }

    if (criteria.length) {
      this.logger.log(`Swept ${criteria.length} criteria → ${notified} notification(s)`);
    }
    return { checked: criteria.length, notified };
  }

  private async sweepOne(criteria: SyncCriteria): Promise<number> {
    const matchCriteria = toMatchCriteria(criteria);

    // Pull whatever SBC has for this criteria into the mirror first; without it
    // the sweep can only ever see members somebody happened to search for. Run
    // the walk inline (not the queued enqueueDeepWalk) so matching below sees a
    // filled mirror rather than racing a background job.
    await this.hydration.hydrateFull({ userId: criteria.userId, criteria: matchCriteria });

    const sinceBaseline = criteria.lastCheckedAt;
    const checkedAt = new Date();

    let notified = 0;
    if (sinceBaseline) {
      const fresh = await this.matcher.findNewSince(
        matchCriteria,
        sinceBaseline,
        CriteriaSweepService.MAX_NOTIFICATIONS_PER_SWEEP,
      );
      for (const member of fresh) {
        // Deduped per (user, member) inside notifyNewMatch, so a member matching
        // several of this user's criteria still yields one alert.
        if (await this.notifications.notifyNewMatch(criteria.userId, member, criteria)) {
          notified++;
        }
      }
    } else {
      this.logger.log(`Criteria ${criteria.id} baselined; first pass notifies nobody`);
    }

    await this.prisma.syncCriteria.update({
      where: { id: criteria.id },
      data: {
        lastCheckedAt: checkedAt,
        lastMatchCount: await this.matcher.count(matchCriteria),
      },
    });
    return notified;
  }
}

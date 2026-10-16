import { Injectable } from '@nestjs/common';
import { SyncCriteria } from '@prisma/client';
import { MatchCriteria, toMatchCriteria } from '../../members/member.view';
import { StatusBoostService } from '../../status-boost/status-boost.service';

/**
 * A saved criteria as the matcher evaluates it. Most are filters and map
 * straight across; a "Augmenter mes vues WhatsApp" criteria is the list of
 * members in it, resolved here — and mirrored, so the sync can save them.
 */
@Injectable()
export class CriteriaMatchResolver {
  constructor(private readonly statusBoost: StatusBoostService) {}

  async resolve(c: SyncCriteria): Promise<MatchCriteria> {
    const match = toMatchCriteria(c);
    if (!c.statusBoost) return match;
    const members = await this.statusBoost.participants(c.userId);
    return { ...match, sbcIds: members.map((m) => m.sbcId) };
  }
}

import { Injectable } from '@nestjs/common';
import { Member, Prisma } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { countryAliases } from '../../common/utils/country';
import { MatchCriteria } from './member.view';

/**
 * Evaluates saved criteria against the local Member MIRROR (cahier §10/§11).
 * Multi-value criteria (countries/cities/professions/interests) map cleanly to
 * SQL `IN`/`hasSome`, which SBC's single-value search can't express — this is a
 * core reason the mirror exists. Completeness tracks mirror hydration
 * (search cache-through today; webhook/bulk import in Phase 5).
 *
 * Phase 5's matching worker reuses buildWhere()/find() verbatim.
 */
@Injectable()
export class MemberMatchService {
  constructor(private readonly prisma: PrismaService) {}

  buildWhere(c: MatchCriteria): Prisma.MemberWhereInput {
    const where: Prisma.MemberWhereInput = {};
    // Matched against every spelling of each country, not just the ISO code:
    // rows mirrored before ingest normalised still hold "Cameroun", and a
    // criteria asking for CM must still find them.
    if (c.countries?.length) {
      where.country = { in: c.countries.flatMap((code) => countryAliases(code)) };
    }
    if (c.cities?.length) where.city = { in: c.cities };
    if (c.professions?.length) where.profession = { in: c.professions };
    if (c.interests?.length) where.interests = { hasSome: c.interests };
    if (c.sex) where.sex = c.sex;
    if (c.ageMin != null || c.ageMax != null) {
      where.age = {
        ...(c.ageMin != null ? { gte: c.ageMin } : {}),
        ...(c.ageMax != null ? { lte: c.ageMax } : {}),
      };
    }
    return where;
  }

  count(c: MatchCriteria): Promise<number> {
    return this.prisma.member.count({ where: this.buildWhere(c) });
  }

  find(c: MatchCriteria, opts: { skip?: number; take?: number } = {}): Promise<Member[]> {
    return this.prisma.member.findMany({
      where: this.buildWhere(c),
      orderBy: { lastSeenAt: 'desc' },
      skip: opts.skip,
      take: opts.take,
    });
  }

  /**
   * In-memory predicate: does a single member satisfy the criteria? Used by the
   * matching worker to test one new member against many active criteria without
   * a DB round-trip per criteria. Mirrors buildWhere() exactly.
   */
  matchesMember(member: Member, c: MatchCriteria): boolean {
    if (
      c.countries?.length &&
      (!member.country ||
        !c.countries.some((code) => countryAliases(code).includes(member.country as string)))
    )
      return false;
    if (c.cities?.length && (!member.city || !c.cities.includes(member.city))) return false;
    if (c.professions?.length && (!member.profession || !c.professions.includes(member.profession)))
      return false;
    if (c.interests?.length && !member.interests.some((i) => c.interests.includes(i))) return false;
    if (c.sex && member.sex !== c.sex) return false;
    if (c.ageMin != null && (member.age == null || member.age < c.ageMin)) return false;
    if (c.ageMax != null && (member.age == null || member.age > c.ageMax)) return false;
    return true;
  }

  /** Members matching the criteria that were first mirrored after `since`. */
  findNewSince(c: MatchCriteria, since: Date, take = 100): Promise<Member[]> {
    return this.prisma.member.findMany({
      where: { AND: [this.buildWhere(c), { createdAt: { gt: since } }] },
      orderBy: { createdAt: 'desc' },
      take,
    });
  }
}

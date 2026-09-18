import { Injectable } from '@nestjs/common';
import { Member, Prisma } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { countryAliases } from '../../common/utils/country';
import { regionsForCountry } from '../../common/utils/region-country';
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

    // The mirror stores country, région and profession exactly as SBC sent
    // them, and SBC sends them as they were typed — "Cameroun", "cameroun" and
    // "CAMEROUN" all sit in the same column. Every one of these is therefore
    // matched case-insensitively; an exact IN silently dropped every spelling
    // but the one the alias table happened to list.
    //
    // Each field is its own OR group and the groups are ANDed, so a criteria
    // naming a country AND a région means both, not either.
    const groups: Prisma.MemberWhereInput[] = [];
    if (c.countries?.length) {
      groups.push({ OR: this.countryClauses(c.countries) });
    }
    if (c.cities?.length) groups.push({ OR: this.anyOfInsensitive('city', c.cities) });
    if (c.professions?.length) {
      groups.push({ OR: this.anyOfInsensitive('profession', c.professions) });
    }
    if (groups.length) where.AND = groups;

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

  /**
   * Members of any of these countries.
   *
   * Two ways in. The country column, matched across every spelling the alias
   * table knows and ignoring case — and, for rows that have no country at all,
   * the région.
   *
   * The second is not a nicety. SBC's search sends no country, so the column is
   * only ever filled by the ingest fallback, which refuses to resolve a région
   * shared between countries — and "Littoral" and "Centre", the two it refuses
   * for Cameroon, are where most Cameroonian members live. Without this a
   * criteria asking for Cameroon misses Douala entirely.
   *
   * Scoped to `country: null`, so an inferred match can never overrule a
   * country the member actually has.
   */
  private countryClauses(codes: string[]): Prisma.MemberWhereInput[] {
    const spellings = Array.from(
      new Set(codes.flatMap((code) => countryAliases(code)).map((s) => s.toLowerCase())),
    );
    const clauses = this.anyOfInsensitive('country', spellings);

    const regions = Array.from(new Set(codes.flatMap((code) => regionsForCountry(code))));
    if (regions.length) {
      clauses.push({
        AND: [{ country: null }, { OR: this.anyOfInsensitive('city', regions) }],
      });
    }
    return clauses;
  }

  /** `field` equals any of `values`, ignoring case. */
  private anyOfInsensitive(
    field: 'country' | 'city' | 'profession',
    values: string[],
  ): Prisma.MemberWhereInput[] {
    return values.map((value) => ({
      [field]: { equals: value, mode: 'insensitive' as const },
    }));
  }

  /** Same folding the SQL above applies, for the in-memory predicate. */
  private static eq(a: string | null, values: string[]): boolean {
    if (!a) return false;
    const folded = a.trim().toLowerCase();
    return values.some((v) => v.trim().toLowerCase() === folded);
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
    if (c.countries?.length) {
      const byCountry = MemberMatchService.eq(
        member.country,
        c.countries.flatMap((code) => countryAliases(code)),
      );
      // Same two ways in as countryClauses(), and the same scoping: the région
      // only stands in for a country the member does not have.
      const byRegion =
        !member.country &&
        MemberMatchService.eq(
          member.city,
          c.countries.flatMap((code) => regionsForCountry(code)),
        );
      if (!byCountry && !byRegion) return false;
    }
    if (c.cities?.length && !MemberMatchService.eq(member.city, c.cities)) return false;
    if (c.professions?.length && !MemberMatchService.eq(member.profession, c.professions))
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

import { Injectable } from '@nestjs/common';
import { Member } from '@prisma/client';
import { createHash } from 'crypto';
import { PaginatedResult, paginate } from '../../common/dto/pagination.dto';
import { toIsoCountry } from '../../common/utils/country';
import { RegionEntry, aggregateRegions } from '../../common/utils/regions';
import { RedisService } from '../../infrastructure/cache/redis.service';
import { SbcExportResult } from '../sbc-client/interfaces/sbc.interface';
import { SbcClientService } from '../sbc-client/sbc-client.service';
import { SbcTokenService } from '../auth/services/sbc-token.service';
import { MembersService } from '../members/members.service';
import { MemberView } from '../members/member.view';
import { SearchQueryDto } from './dto/search-query.dto';

/**
 * Directory = read-through proxy over SBC's per-member contacts search. Results
 * are cached briefly in Redis, hydrated into the Member mirror, and annotated
 * with the caller's favorite/sync state. Entitlement (subscription/scope) is
 * enforced by SBC on every call and surfaces as 403 (cahier §20 in the guide).
 */
interface HydratedPage {
  rows: Member[];
  total: number;
  page: number;
  limit: number;
}

@Injectable()
export class DirectoryService {
  // Directory pages don't change second-to-second; cache generously so repeated
  // searches, pagination and back-navigation are instant (avoids the ~1-2s SBC
  // round-trip AND the mirror-hydration DB writes on a hit).
  private static readonly SEARCH_TTL = 600; // seconds (10 min)

  // The région list only moves as the mirror grows; an hour keeps the
  // group-by off the hot path without hiding new places for long.
  private static readonly REGIONS_TTL = 3600;

  constructor(
    private readonly sbcTokens: SbcTokenService,
    private readonly sbc: SbcClientService,
    private readonly members: MembersService,
    private readonly cache: RedisService,
  ) {}

  async search(userId: string, query: SearchQueryDto): Promise<PaginatedResult<MemberView>> {
    const accessToken = await this.sbcTokens.getValidAccessToken(userId);
    const page = await this.getHydratedPage(userId, accessToken, query);

    // Warm the NEXT page's cache in the background so scrolling doesn't wait on
    // SBC. Fire-and-forget — never blocks or fails this response.
    this.prefetchNextPage(userId, accessToken, query, page);

    // Annotate fresh on every call (favorite/sync state changes; it's a cheap
    // indexed read) — but the expensive SBC call + upsert are cache-served.
    const annotated = await this.members.annotate(userId, page.rows);
    return paginate(this.sortRows(annotated, query.sort), page.total, page.page, page.limit);
  }

  /**
   * Reputation-first ordering, applied to the page in hand rather than to the
   * whole result set.
   *
   * `confidenceScore` is derived from OUR reviews; SBC owns the paging and
   * knows nothing about it, so there is no way to ask upstream for a globally
   * ranked page. Ordering what the member is looking at is the honest version
   * of this feature — a page is 20 rows, which is the scope of one screen.
   * Unrated members all sit at the neutral 50, so the tie-breaks (more reviews
   * first, then better average) are what actually separate them, and anything
   * still tied keeps SBC's own order: Array.prototype.sort is stable.
   */
  private sortRows(rows: MemberView[], sort?: string): MemberView[] {
    if (sort !== 'confidence') return rows;
    return [...rows].sort(
      (a, b) =>
        b.confidenceScore - a.confidenceScore ||
        b.reviewCount - a.reviewCount ||
        (b.averageRating ?? 0) - (a.averageRating ?? 0),
    );
  }

  /** Resolve one page (handling the name+profession merge), cache-served. */
  private async getHydratedPage(
    userId: string,
    accessToken: string,
    query: SearchQueryDto,
  ): Promise<HydratedPage> {
    const term = query.search?.trim();
    if (term && !query.profession) {
      // A free-text term should match NAME or PROFESSION. SBC can't OR the two
      // params in one call, so we query both and merge (profession first — far
      // more useful for a directory: "designer" -> 235, not just 4 name hits).
      // The two calls are INDEPENDENT: SBC intermittently 500s the profession
      // filter under load, so we must not let that failure sink the (usually
      // successful) name results — settle both and return whatever we got.
      const [byProfession, byName] = await Promise.allSettled([
        this.fetchHydrated(userId, accessToken, { ...query, search: undefined, profession: term }),
        this.fetchHydrated(userId, accessToken, query),
      ]);
      const profPage = byProfession.status === 'fulfilled' ? byProfession.value : null;
      const namePage = byName.status === 'fulfilled' ? byName.value : null;
      if (profPage && namePage) return this.mergeHydrated(profPage, namePage);
      if (profPage ?? namePage) return (profPage ?? namePage)!;
      // Both failed — surface a real error rather than a silent empty page.
      throw byName.status === 'rejected'
        ? byName.reason
        : (byProfession as PromiseRejectedResult).reason;
    }
    return this.fetchHydrated(userId, accessToken, query);
  }

  private prefetchNextPage(
    userId: string,
    accessToken: string,
    query: SearchQueryDto,
    current: HydratedPage,
  ): void {
    const totalPages = current.limit > 0 ? Math.ceil(current.total / current.limit) : 0;
    if (current.page >= totalPages) return; // already the last page
    const next = { ...query, page: current.page + 1 } as SearchQueryDto;
    // Fire-and-forget: populate the next page's cache, swallow any error.
    void this.getHydratedPage(userId, accessToken, next).catch(() => undefined);
  }

  /**
   * Cache-served hydrated page: on a miss, hit SBC and upsert into the mirror;
   * on a hit, return instantly with no SBC call and no DB writes.
   */
  private fetchHydrated(
    userId: string,
    accessToken: string,
    query: SearchQueryDto,
  ): Promise<HydratedPage> {
    const cacheKey = `dir:search:v2:${userId}:${this.hashQuery(query)}`;
    return this.cache.getOrSet<HydratedPage>(cacheKey, DirectoryService.SEARCH_TTL, async () => {
      const data = await this.sbc.searchContacts(accessToken, query);
      const rows = await this.members.upsertMany(data.items);
      const bySbcId = new Map(rows.map((r) => [r.sbcId, r]));
      const ordered = data.items
        .map((i) => bySbcId.get(i.id))
        .filter((m): m is Member => Boolean(m));
      return { rows: ordered, total: data.total, page: data.page, limit: data.limit };
    });
  }

  /** Merge two hydrated pages, de-duping by member id (profession first). */
  private mergeHydrated(a: HydratedPage, b: HydratedPage): HydratedPage {
    const seen = new Set<string>();
    const rows = [...a.rows, ...b.rows].filter((r) => {
      if (seen.has(r.sbcId)) return false;
      seen.add(r.sbcId);
      return true;
    });
    return { rows, total: a.total + b.total, page: a.page, limit: a.limit };
  }

  async getProfile(userId: string, sbcId: string): Promise<MemberView> {
    // Served from the mirror (no SBC get-by-id endpoint exists); populated by search.
    const member = await this.members.getBySbcIdOrThrow(sbcId);
    const [annotated] = await this.members.annotate(userId, [member]);
    return annotated;
  }

  /**
   * Régions per country, built from the member mirror (SBC exposes no such
   * list). Only places where mirrored members actually live are returned, so a
   * région picked from this list can always match someone; the list grows as
   * searches hydrate more members. `country` (any spelling) narrows it to one.
   */
  async regions(country?: string): Promise<{ regions: RegionEntry[] }> {
    const all = await this.cache.getOrSet<RegionEntry[]>(
      'dir:regions:v1',
      DirectoryService.REGIONS_TTL,
      async () => aggregateRegions(await this.members.regionGroups()),
    );
    const iso = country ? toIsoCountry(country)?.toUpperCase() : undefined;
    return { regions: iso ? all.filter((r) => r.country === iso) : all };
  }

  async export(userId: string, query: SearchQueryDto): Promise<SbcExportResult> {
    const accessToken = await this.sbcTokens.getValidAccessToken(userId);
    return this.sbc.exportContacts(accessToken, query);
  }

  private hashQuery(query: SearchQueryDto): string {
    const normalized = {
      search: query.search ?? '',
      country: query.country ?? '',
      region: query.region ?? '',
      city: query.city ?? '',
      profession: query.profession ?? '',
      sex: query.sex ?? '',
      ageMin: query.ageMin ?? '',
      ageMax: query.ageMax ?? '',
      interests: [...(query.interests ?? [])].sort(),
      page: query.page,
      limit: query.limit,
    };
    return createHash('sha1').update(JSON.stringify(normalized)).digest('hex');
  }
}

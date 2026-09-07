import { Injectable } from '@nestjs/common';
import { Member } from '@prisma/client';
import { createHash } from 'crypto';
import { PaginatedResult, paginate } from '../../common/dto/pagination.dto';
import { RedisService } from '../../infrastructure/cache/redis.service';
import { SbcExportResult, SbcSearchData } from '../sbc-client/interfaces/sbc.interface';
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
@Injectable()
export class DirectoryService {
  private static readonly SEARCH_TTL = 60; // seconds

  constructor(
    private readonly sbcTokens: SbcTokenService,
    private readonly sbc: SbcClientService,
    private readonly members: MembersService,
    private readonly cache: RedisService,
  ) {}

  async search(userId: string, query: SearchQueryDto): Promise<PaginatedResult<MemberView>> {
    const accessToken = await this.sbcTokens.getValidAccessToken(userId);
    const term = query.search?.trim();

    let data: SbcSearchData;
    if (term && !query.profession) {
      // A free-text term should match NAME or PROFESSION. SBC can't OR the two
      // params in one call, so we query both and merge (profession first — far
      // more useful for a directory: "designer" -> 235, not just 4 name hits).
      const [byProfession, byName] = await Promise.all([
        this.fetchContacts(userId, accessToken, { ...query, search: undefined, profession: term }),
        this.fetchContacts(userId, accessToken, query),
      ]);
      data = this.mergeSearch(byProfession, byName);
    } else {
      data = await this.fetchContacts(userId, accessToken, query);
    }

    // Hydrate the mirror and map SBC ids -> our member rows (order preserved).
    const rows = await this.members.upsertMany(data.items);
    const bySbcId = new Map(rows.map((r) => [r.sbcId, r]));
    const ordered = data.items.map((i) => bySbcId.get(i.id)).filter((m): m is Member => Boolean(m));

    const annotated = await this.members.annotate(userId, ordered);
    return paginate(annotated, data.total, data.page, data.limit);
  }

  private fetchContacts(
    userId: string,
    accessToken: string,
    query: SearchQueryDto,
  ): Promise<SbcSearchData> {
    const cacheKey = `dir:search:${userId}:${this.hashQuery(query)}`;
    return this.cache.getOrSet<SbcSearchData>(cacheKey, DirectoryService.SEARCH_TTL, () =>
      this.sbc.searchContacts(accessToken, query),
    );
  }

  /** Merge two result sets, de-duping by member id (profession matches first). */
  private mergeSearch(a: SbcSearchData, b: SbcSearchData): SbcSearchData {
    const seen = new Set<string>();
    const items = [...a.items, ...b.items].filter((it) => {
      if (!it.id || seen.has(it.id)) return false;
      seen.add(it.id);
      return true;
    });
    return {
      items,
      total: a.total + b.total, // approximate (upper bound; overlap is small)
      page: a.page,
      limit: a.limit,
      totalPages: Math.max(a.totalPages, b.totalPages),
      hasMore: a.hasMore || b.hasMore,
    };
  }

  async getProfile(userId: string, sbcId: string): Promise<MemberView> {
    // Served from the mirror (no SBC get-by-id endpoint exists); populated by search.
    const member = await this.members.getBySbcIdOrThrow(sbcId);
    const [annotated] = await this.members.annotate(userId, [member]);
    return annotated;
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

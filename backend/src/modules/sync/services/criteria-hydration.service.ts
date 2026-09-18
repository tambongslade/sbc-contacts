import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'crypto';
import { RedisService } from '../../../infrastructure/cache/redis.service';
import { SbcTokenService } from '../../auth/services/sbc-token.service';
import { SbcClientService } from '../../sbc-client/sbc-client.service';
import { SbcContactQuery } from '../../sbc-client/interfaces/sbc.interface';
import { MembersService } from '../../members/members.service';
import { MatchCriteria } from '../../members/member.view';

/**
 * Pulls the members a criteria selects out of SBC and into the mirror, before
 * the criteria is evaluated against that mirror.
 *
 * Without this step a criteria could only ever match members the caller had
 * already stumbled across in the annuaire — the mirror is filled by directory
 * searches and nothing else. A member who wrote "Maçons de Douala" and never
 * happened to search for exactly that saw "0 membre(s) correspondent" and a
 * synchronisation that saved nobody, which is the single reason criteria felt
 * broken. Hydrating first means a criteria is evaluated against SBC's base,
 * not against the caller's browsing history.
 *
 * SBC's search takes ONE value per field, so a criteria listing three
 * professions in two countries is six searches; the combinations are capped and
 * the whole result is cached, because this runs on a screen the member is
 * waiting on.
 */
@Injectable()
export class CriteriaHydrationService {
  private readonly logger = new Logger(CriteriaHydrationService.name);

  /** Hydration is a cache warm-up, not a read: the same criteria re-previewed
   *  a minute later matches the same members. */
  private static readonly TTL = 600; // seconds (10 min)

  /** SBC calls per hydration. A criteria with many values is sampled, not
   *  enumerated — the member is waiting on this. */
  private static readonly MAX_COMBINATIONS = 12;

  /** Pages per combination, at [PAGE_SIZE] each. */
  private static readonly MAX_PAGES = 3;
  private static readonly PAGE_SIZE = 100;

  constructor(
    private readonly sbcTokens: SbcTokenService,
    private readonly sbc: SbcClientService,
    private readonly members: MembersService,
    private readonly cache: RedisService,
  ) {}

  /**
   * Best-effort. A criteria preview must still answer when SBC is down or the
   * caller's SBC session has lapsed — it then falls back to whatever the mirror
   * already holds, which is exactly the old behaviour.
   */
  async hydrate(userId: string, criteria: MatchCriteria): Promise<void> {
    const key = `sync:hydrate:v1:${userId}:${this.hash(criteria)}`;
    if (await this.cache.get<number>(key)) return;

    try {
      const accessToken = await this.sbcTokens.getValidAccessToken(userId);
      const mirrored = await this.fetchAll(accessToken, criteria);
      await this.cache.set(key, mirrored, CriteriaHydrationService.TTL);
    } catch (err) {
      // Never fails the caller: the criteria is still answered from the mirror.
      this.logger.warn(`Criteria hydration skipped: ${(err as Error).message}`);
    }
  }

  private async fetchAll(accessToken: string, criteria: MatchCriteria): Promise<number> {
    const combinations = this.combinations(criteria);
    let mirrored = 0;
    let failed = 0;

    for (const combination of combinations) {
      try {
        mirrored += await this.fetchCombination(accessToken, combination);
      } catch (err) {
        // Each combination stands alone. SBC intermittently 500s the profession
        // filter under load, and one such query must not sink the other eleven
        // — a criteria naming three professions would otherwise hydrate nothing
        // because one of them was unlucky.
        failed++;
        this.logger.warn(
          `Criteria hydration: one query failed (${String((err as Error).message)})`,
        );
      }
    }

    // Every query failing is not partial success, it is the outage the caller's
    // cache must not hold onto — see hydrate().
    if (failed === combinations.length && combinations.length > 0) {
      throw new Error(`all ${failed} SBC quer(ies) failed`);
    }

    this.logger.log(
      `Criteria hydration mirrored ${mirrored} member(s)` +
        (failed ? ` (${failed}/${combinations.length} quer(ies) failed)` : ''),
    );
    return mirrored;
  }

  /** One combination, paged. Throws if SBC does — the caller decides. */
  private async fetchCombination(
    accessToken: string,
    combination: SbcContactQuery,
  ): Promise<number> {
    let mirrored = 0;
    for (let page = 1; page <= CriteriaHydrationService.MAX_PAGES; page++) {
      const data = await this.sbc.searchContacts(accessToken, {
        ...combination,
        page,
        limit: CriteriaHydrationService.PAGE_SIZE,
      });
      if (data.items.length === 0) break;
      await this.members.upsertMany(data.items);
      mirrored += data.items.length;
      if (!data.hasMore) break;
    }
    return mirrored;
  }

  /**
   * One SBC query per (country, région, profession) triple, since SBC takes a
   * single value per field. Interests, sexe and âge ride along on every query —
   * SBC accepts those as-is.
   *
   * A field the criteria leaves empty contributes `undefined`, i.e. "any", so a
   * criteria filtering on nothing but a profession is one query, not one per
   * country.
   */
  private combinations(c: MatchCriteria): SbcContactQuery[] {
    const anyOf = (values?: string[] | null): (string | undefined)[] =>
      values?.length ? values : [undefined];

    const base: SbcContactQuery = {
      sex: c.sex ?? undefined,
      ageMin: c.ageMin ?? undefined,
      ageMax: c.ageMax ?? undefined,
      interests: c.interests?.length ? c.interests : undefined,
    };

    const out: SbcContactQuery[] = [];
    for (const country of anyOf(c.countries)) {
      for (const region of anyOf(c.cities)) {
        for (const profession of anyOf(c.professions)) {
          if (out.length >= CriteriaHydrationService.MAX_COMBINATIONS) return out;
          out.push({ ...base, country, region, profession });
        }
      }
    }
    return out;
  }

  private hash(c: MatchCriteria): string {
    const normalized = {
      countries: [...(c.countries ?? [])].sort(),
      cities: [...(c.cities ?? [])].sort(),
      professions: [...(c.professions ?? [])].sort(),
      interests: [...(c.interests ?? [])].sort(),
      sex: c.sex ?? '',
      ageMin: c.ageMin ?? '',
      ageMax: c.ageMax ?? '',
    };
    return createHash('sha1').update(JSON.stringify(normalized)).digest('hex');
  }
}

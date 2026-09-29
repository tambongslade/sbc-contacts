import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import { Queue } from 'bullmq';
import { createHash } from 'crypto';
import { RedisService } from '../../../infrastructure/cache/redis.service';
import { QUEUE_NAMES } from '../../../infrastructure/queue/queue.module';
import { SbcTokenService } from '../../auth/services/sbc-token.service';
import { SbcClientService } from '../../sbc-client/sbc-client.service';
import { SbcContactQuery } from '../../sbc-client/interfaces/sbc.interface';
import { MembersService } from '../../members/members.service';
import { MatchCriteria } from '../../members/member.view';

/** A criteria to hydrate, plus the caller whose SBC session pulls its members. */
export interface HydrationJob {
  userId: string;
  criteria: MatchCriteria;
}

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
 * professions in two countries is six searches; the combinations are capped.
 *
 * Two speeds, because the member's screen and the whole country want opposite
 * things. [previewTotal] answers the count SBC reports — one page per
 * combination, read for its `total` — fast enough to block "Calculer" on, and
 * enqueues the rest. [hydrateFull] then walks every page into the mirror off a
 * queue, so the list the member pages and saves through grows to the whole
 * country without anyone waiting on it. Earlier this walk ran on the screen and
 * was capped at 1200, so a Cameroon of 13 826 previewed as ~2300 — the bug this
 * split fixes.
 */
@Injectable()
export class CriteriaHydrationService {
  private readonly logger = new Logger(CriteriaHydrationService.name);

  /** How long a computed SBC total is trusted before it's recomputed — the same
   *  criteria re-previewed a minute later is the same size. */
  private static readonly TTL = 600; // seconds (10 min)

  /** SBC calls per hydration. A criteria with many values is sampled, not
   *  enumerated. */
  private static readonly MAX_COMBINATIONS = 12;

  private static readonly PAGE_SIZE = 100;

  /**
   * Pages the BACKGROUND walk may pull per combination, at [PAGE_SIZE] each.
   *
   * Generous, because it runs off a queue and not on the member's screen: 200 ×
   * 100 = 20 000 per combination, past SBC's largest single country, and
   * [DEEP_BUDGET_MS] stops a pathological criteria before it walks forever.
   */
  private static readonly DEEP_MAX_PAGES = 200;

  /**
   * How long the background walk may spend before it stops asking for more
   * pages. It stops between pages, never mid-flight, and whatever it mirrored by
   * then counts. Off-screen, so the ceiling is minutes, not the few seconds a
   * member will sit through.
   */
  private static readonly DEEP_BUDGET_MS = 5 * 60_000;

  /** Don't re-enqueue a deep walk we already ran for this criteria this recently. */
  private static readonly DEEP_TTL = 600; // seconds

  constructor(
    private readonly sbcTokens: SbcTokenService,
    private readonly sbc: SbcClientService,
    private readonly members: MembersService,
    private readonly cache: RedisService,
    @InjectQueue(QUEUE_NAMES.HYDRATION) private readonly queue: Queue,
  ) {}

  /**
   * The headline count for a criteria, as SBC sees it — the number the member is
   * really asking for when they tap "Calculer".
   *
   * Cheap: one page per combination, read only for its `total`. SBC reports the
   * full count on page 1, so a country of 13 826 costs a single request, not
   * 138. The members on those first pages are mirrored in passing (a free
   * warm-up), and the deep walk that fills the rest of the mirror is enqueued to
   * run off the screen — see [hydrateFull].
   *
   * Best-effort: if SBC is down or the caller's session has lapsed it returns
   * null, and the caller falls back to the mirror count — the old behaviour.
   *
   * For a multi-value criteria the total is the sum of its combinations' totals,
   * an upper bound when they overlap; the mirror count, once the deep walk
   * lands, is the exact figure.
   */
  async previewTotal(userId: string, criteria: MatchCriteria): Promise<number | null> {
    const key = `sync:total:v1:${this.hash(criteria)}`;
    const cached = await this.cache.get<number>(key);
    if (cached !== null) {
      // Count already known, but the deep walk may still be worth (re)running.
      await this.enqueueDeepWalk(userId, criteria);
      return cached;
    }

    try {
      const accessToken = await this.sbcTokens.getValidAccessToken(userId);
      const combinations = this.combinations(criteria);
      let total = 0;
      let failed = 0;

      for (const combination of combinations) {
        try {
          const data = await this.sbc.searchContacts(accessToken, {
            ...combination,
            page: 1,
            limit: CriteriaHydrationService.PAGE_SIZE,
          });
          total += data.total;
          // Page one is already fetched, so mirror it — a free head-start on the
          // deep walk.
          if (data.items.length) await this.members.upsertMany(data.items);
        } catch (err) {
          failed++;
          this.logger.warn(`Criteria total: one query failed (${String((err as Error).message)})`);
        }
      }

      // Every query failing is the outage the cache must not hold onto.
      if (failed === combinations.length && combinations.length > 0) {
        throw new Error(`all ${failed} SBC quer(ies) failed`);
      }

      await this.cache.set(key, total, CriteriaHydrationService.TTL);
      await this.enqueueDeepWalk(userId, criteria);
      this.logger.log(`Criteria total ${total} member(s) across ${combinations.length} quer(ies)`);
      return total;
    } catch (err) {
      this.logger.warn(`Criteria total unavailable: ${(err as Error).message}`);
      return null;
    }
  }

  /**
   * Enqueue the deep walk that fills the mirror with the whole criteria, unless
   * one ran for it recently. Deduped by criteria hash so re-tapping "Calculer"
   * or paging the matches list never piles up walks of the same country.
   */
  async enqueueDeepWalk(userId: string, criteria: MatchCriteria): Promise<void> {
    const hash = this.hash(criteria);
    const guard = `sync:deepwalk:v1:${hash}`;
    // Set-if-absent: the first caller within the window wins the walk.
    const won = await this.cache.client.set(
      guard,
      '1',
      'EX',
      CriteriaHydrationService.DEEP_TTL,
      'NX',
    );
    if (!won) return;
    try {
      await this.queue.add('hydrate', { userId, criteria } satisfies HydrationJob, {
        jobId: `hydrate:${userId}:${hash}`,
      });
    } catch (err) {
      // Losing the walk is not fatal: the count is already answered and the
      // mirror holds the warm-up. Free the guard so a later tap can retry.
      await this.cache.del(guard);
      this.logger.warn(`Could not enqueue deep hydration: ${(err as Error).message}`);
    }
  }

  /**
   * The deep walk itself, run from the queue: every page of every combination
   * into the mirror, the on-screen page cap lifted. Off the member's screen, so
   * it can take the minutes a whole country needs. Throws (letting BullMQ retry)
   * only when every query failed.
   */
  async hydrateFull(job: HydrationJob): Promise<number> {
    const accessToken = await this.sbcTokens.getValidAccessToken(job.userId);
    const combinations = this.combinations(job.criteria);
    const deadline = Date.now() + CriteriaHydrationService.DEEP_BUDGET_MS;
    let mirrored = 0;
    let failed = 0;

    for (const combination of combinations) {
      if (Date.now() > deadline) {
        this.logger.warn('Deep hydration hit its time budget; mirrored what it had');
        break;
      }
      try {
        mirrored += await this.fetchCombination(accessToken, combination, deadline);
      } catch (err) {
        // Each combination stands alone. SBC intermittently 500s the profession
        // filter under load, and one such query must not sink the others.
        failed++;
        this.logger.warn(`Deep hydration: one query failed (${String((err as Error).message)})`);
      }
    }

    if (failed === combinations.length && combinations.length > 0) {
      throw new Error(`all ${failed} SBC quer(ies) failed`);
    }

    this.logger.log(
      `Deep hydration mirrored ${mirrored} member(s)` +
        (failed ? ` (${failed}/${combinations.length} quer(ies) failed)` : ''),
    );
    return mirrored;
  }

  /** One combination, walked to its end (or the deep budget). Throws if SBC does. */
  private async fetchCombination(
    accessToken: string,
    combination: SbcContactQuery,
    deadline: number,
  ): Promise<number> {
    let mirrored = 0;
    for (let page = 1; page <= CriteriaHydrationService.DEEP_MAX_PAGES; page++) {
      if (page > 1 && Date.now() > deadline) break;
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

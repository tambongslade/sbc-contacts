import { ServiceMode } from '@prisma/client';
import { coverage, tokens } from '../text';
import {
  MatchCandidate,
  applyVerdicts,
  bestPerPro,
  budgetScore,
  PRO_LOCATION_TTL_MS,
  proximityScore,
  scoreService,
} from './request-matching.service';

/**
 * Matching decides who is asked to work, so the cases that matter are the
 * ones where a wrong answer costs somebody: a pro spammed with jobs they cannot
 * reach, or a request that reaches nobody because it was phrased differently.
 */
describe('SBC Data matching', () => {
  const request = (over: Record<string, unknown> = {}) => ({
    userId: 'requester',
    rawText: 'Je cherche quelqu’un pour réparer mes locks à domicile samedi à Yaoundé',
    profession: 'Coiffeur',
    service: 'Réparation de locks',
    specialties: [] as string[],
    city: 'Yaoundé',
    district: null,
    mode: ServiceMode.HOME as ServiceMode | null,
    budget: 20000 as number | null,
    embedding: [] as number[],
    latitude: null as number | null,
    longitude: null as number | null,
    ...over,
  });

  const service = (over: Record<string, unknown> = {}, pro: Record<string, unknown> = {}) =>
    ({
      id: 's1',
      proId: 'p1',
      name: 'Réparation de locks',
      category: 'Locks',
      profession: 'Coiffeuse',
      synonyms: ['dreads', 'dreadlocks'],
      specialties: [],
      modes: [],
      zones: [],
      priceMin: null,
      embedding: [],
      pro: {
        id: 'p1',
        profession: 'Coiffeuse',
        city: 'yaounde',
        zones: [],
        modes: [ServiceMode.HOME],
        priceMin: null,
        latitude: null,
        longitude: null,
        locatedAt: null,
        ...pro,
      },
      ...over,
    }) as never;

  it('folds accents, case, plurals and feminine forms so phrasing does not matter', () => {
    expect(coverage(tokens('réparer mes Locks'), tokens('Réparation de locks'))).toBe(1);
    expect(coverage(tokens('Coiffeuse'), tokens('coiffeur'))).toBe(1);
  });

  it('keeps a pro in the same city who comes to the client', () => {
    const c = scoreService(request(), service());
    expect(c).not.toBeNull();
    expect(c!.reasons.keyword).toBe(1);
    expect(c!.reasons.profession).toBe(true);
    expect(c!.reasons.location).toBe('yaounde');
  });

  it('drops a pro in another city for an in-person job', () => {
    expect(scoreService(request(), service({}, { city: 'Douala' }))).toBeNull();
  });

  it('widens to a pro in another city when relaxed (the town has nobody)', () => {
    const c = scoreService(request(), service({}, { city: 'Douala' }), undefined, true);
    expect(c).not.toBeNull();
    expect(c!.reasons.location).toBe('autre zone');
  });

  it('keeps a pro in another city when one of their zones covers the request', () => {
    expect(
      scoreService(request(), service({}, { city: 'Douala', zones: ['Yaoundé'] })),
    ).not.toBeNull();
  });

  it('ignores location for online work', () => {
    const online = request({ mode: ServiceMode.ONLINE });
    expect(
      scoreService(online, service({ modes: [ServiceMode.ONLINE] }, { city: 'Douala' })),
    ).not.toBeNull();
  });

  it('drops a pro who never works at the client’s home for a home job', () => {
    expect(scoreService(request(), service({}, { modes: [ServiceMode.ON_SITE] }))).toBeNull();
  });

  it('does not hold unstated delivery modes against a pro', () => {
    expect(scoreService(request(), service({}, { modes: [] }))).not.toBeNull();
  });

  it('prefers the service-level modes over the profile ones', () => {
    const s = service({ modes: [ServiceMode.ON_SITE] }, { modes: [ServiceMode.HOME] });
    expect(scoreService(request(), s)).toBeNull();
  });

  describe('near the requester', () => {
    const now = new Date('2026-10-26T12:00:00Z');
    // Akwa, Douala; Bonapriso is ~3 km away, Yaoundé ~200 km.
    const here = { latitude: 4.0511, longitude: 9.7679 };
    const bonapriso = { latitude: 4.0275, longitude: 9.6943, locatedAt: now };
    const yaounde = { latitude: 3.848, longitude: 11.5021, locatedAt: now };

    it('takes a pro close by even when their zones name another town', () => {
      const c = scoreService(request(here), service({}, { city: 'Bafoussam', ...bonapriso }), now);
      expect(c!.reasons.location).toBe('près de toi');
      expect(c!.reasons.distanceKm).toBeGreaterThan(2);
      expect(c!.reasons.distanceKm).toBeLessThan(10);
    });

    it('still takes a far pro whose zones cover the named city', () => {
      const c = scoreService(request(here), service({}, yaounde), now);
      expect(c!.reasons.location).toBe('yaounde');
    });

    it('ranks the pro close by above the same pro far away', () => {
      const near = scoreService(request(here), service({}, bonapriso), now)!;
      const far = scoreService(request(here), service({}, yaounde), now)!;
      expect(near.score).toBeGreaterThan(far.score);
    });

    it('with no city named, leaves out a pro in another town', () => {
      const c = scoreService(request({ ...here, city: null }), service({}, yaounde), now);
      expect(c).toBeNull();
    });

    it('with no city named, widens to the far pro when relaxed', () => {
      const r = request({ ...here, city: null });
      expect(scoreService(r, service({}, yaounde), now)).toBeNull();
      const relaxed = scoreService(r, service({}, yaounde), now, true)!;
      expect(relaxed).not.toBeNull();
      expect(relaxed.reasons.location).toBe('autre zone');
      expect(relaxed.reasons.distanceKm).toBeGreaterThan(50);
    });

    it('ignores a position the pro has not refreshed in days', () => {
      const stale = { ...bonapriso, city: 'Bafoussam' };
      stale.locatedAt = new Date(now.getTime() - PRO_LOCATION_TTL_MS - 1);
      expect(scoreService(request(here), service({}, stale), now)).toBeNull();
    });

    it('ranks the pro close by above an equal pro with no position', () => {
      const near = scoreService(request(here), service({}, bonapriso), now)!;
      const unknown = scoreService(request(here), service(), now)!;
      expect(near.score).toBeGreaterThan(unknown.score);
    });

    it('lifts only a pro known to be close', () => {
      expect(proximityScore(null)).toBe(0);
      expect(proximityScore(0)).toBe(1);
      expect(proximityScore(30)).toBe(0);
    });
  });

  it('matches on the raw text when the AI could not name the service', () => {
    const c = scoreService(request({ service: null, profession: null }), service());
    expect(c!.reasons.keyword).toBeGreaterThan(0);
  });

  it('scores a plumber far below the locks specialist', () => {
    const locks = scoreService(request(), service())!;
    const plumber = scoreService(
      request(),
      service(
        {
          name: 'Réparation de fuites',
          category: 'Plomberie',
          profession: 'Plombier',
          synonyms: [],
        },
        { profession: 'Plombier' },
      ),
    )!;
    expect(locks.score).toBeGreaterThan(plumber.score + 0.3);
  });

  it('lowers the budget fit as the price moves above the budget', () => {
    expect(budgetScore(20000, 15000)).toBe(1);
    expect(budgetScore(20000, 30000)).toBe(0.5);
    expect(budgetScore(20000, 50000)).toBe(0);
    expect(budgetScore(null, 50000)).toBe(1);
  });

  const cand = (proId: string, serviceId: string, score: number, keyword = 1): MatchCandidate => ({
    proId,
    serviceId,
    score,
    reasons: {
      keyword,
      semantic: 0,
      profession: true,
      budgetFit: 1,
      retrieval: score,
      relevance: null,
      location: 'x',
      distanceKm: null,
    },
  });

  it('sends a request once per pro, for their best service', () => {
    const kept = bestPerPro([cand('p1', 'a', 0.4), cand('p1', 'b', 0.8), cand('p2', 'c', 0.5)]);
    expect(kept.map((c) => c.serviceId).sort()).toEqual(['b', 'c']);
  });

  it('lets the AI verdict drop weak matches and rerank the rest', () => {
    const out = applyVerdicts(
      [cand('p1', 'a', 0.9), cand('p2', 'b', 0.5), cand('p3', 'c', 0.7)],
      new Map([
        ['a', 0.2],
        ['b', 1],
        ['c', 0.6],
      ]),
    );
    expect(out.map((c) => c.serviceId)).toEqual(['b', 'c']);
    expect(out[0].reasons.relevance).toBe(1);
  });

  it('without the AI, keeps only services whose words meet the request', () => {
    const out = applyVerdicts([cand('p1', 'a', 0.5, 0.5), cand('p2', 'b', 0.4, 0)], null);
    expect(out.map((c) => c.serviceId)).toEqual(['a']);
  });
});

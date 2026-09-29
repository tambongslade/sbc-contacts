import { ServiceMode } from '@prisma/client';
import { coverage, tokens } from '../text';
import {
  MatchCandidate,
  applyVerdicts,
  bestPerPro,
  budgetScore,
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

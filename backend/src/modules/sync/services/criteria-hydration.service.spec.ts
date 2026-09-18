import { CriteriaHydrationService } from './criteria-hydration.service';
import { MatchCriteria } from '../../members/member.view';

/**
 * Criteria used to be evaluated against whatever the caller had already
 * searched for, so a brand-new criterion matched nobody. These cover the
 * queries that now go out to SBC first.
 */
describe('CriteriaHydrationService', () => {
  const base: MatchCriteria = { countries: [], cities: [], professions: [], interests: [] };

  function build(searchContacts = jest.fn()) {
    const cache = {
      get: jest.fn().mockResolvedValue(null),
      set: jest.fn().mockResolvedValue(undefined),
    };
    const members = { upsertMany: jest.fn().mockResolvedValue([]) };
    const tokens = { getValidAccessToken: jest.fn().mockResolvedValue('token') };
    const service = new CriteriaHydrationService(
      tokens as never,
      { searchContacts } as never,
      members as never,
      cache as never,
    );
    return { service, cache, members, tokens, searchContacts };
  }

  /** One page of `n` members, with nothing after it. */
  const page = (n: number) => ({
    items: Array.from({ length: n }, (_, i) => ({ id: `m${i}` })),
    total: n,
    page: 1,
    limit: 100,
    totalPages: 1,
    hasMore: false,
  });

  it('asks SBC once per (country, région, profession) triple', async () => {
    const searchContacts = jest.fn().mockResolvedValue(page(2));
    const { service } = build(searchContacts);

    await service.hydrate('user-1', {
      ...base,
      countries: ['CM', 'FR'],
      professions: ['Macon', 'Plombier'],
    });

    // 2 countries x 1 (any région) x 2 professions.
    expect(searchContacts).toHaveBeenCalledTimes(4);
    const queried = searchContacts.mock.calls.map(([, q]) => [q.country, q.profession]);
    expect(queried).toEqual([
      ['CM', 'Macon'],
      ['CM', 'Plombier'],
      ['FR', 'Macon'],
      ['FR', 'Plombier'],
    ]);
  });

  it('leaves an unset field out of the query instead of enumerating it', async () => {
    const searchContacts = jest.fn().mockResolvedValue(page(1));
    const { service } = build(searchContacts);

    await service.hydrate('user-1', { ...base, professions: ['Macon'] });

    expect(searchContacts).toHaveBeenCalledTimes(1);
    const [, query] = searchContacts.mock.calls[0];
    expect(query.country).toBeUndefined();
    expect(query.region).toBeUndefined();
    expect(query.profession).toBe('Macon');
  });

  it("carries sexe, âge and centres d'intérêt on every query", async () => {
    const searchContacts = jest.fn().mockResolvedValue(page(1));
    const { service } = build(searchContacts);

    await service.hydrate('user-1', {
      ...base,
      countries: ['CM', 'FR'],
      interests: ['business'],
      sex: 'female',
      ageMin: 25,
      ageMax: 40,
    });

    for (const [, query] of searchContacts.mock.calls) {
      expect(query).toMatchObject({
        sex: 'female',
        ageMin: 25,
        ageMax: 40,
        interests: ['business'],
      });
    }
  });

  it('caps the fan-out — the member is waiting on this', async () => {
    const searchContacts = jest.fn().mockResolvedValue(page(1));
    const { service } = build(searchContacts);

    await service.hydrate('user-1', {
      ...base,
      countries: ['CM', 'FR', 'SN', 'TG'],
      cities: ['Centre', 'Littoral'],
      professions: ['Macon', 'Plombier', 'Medecin'],
    });

    expect(searchContacts.mock.calls.length).toBeLessThanOrEqual(12);
  });

  it('mirrors everything it fetched', async () => {
    const searchContacts = jest.fn().mockResolvedValue(page(3));
    const { service, members } = build(searchContacts);

    await service.hydrate('user-1', { ...base, professions: ['Macon'] });

    expect(members.upsertMany).toHaveBeenCalledWith([{ id: 'm0' }, { id: 'm1' }, { id: 'm2' }]);
  });

  it('does nothing when the same criteria was hydrated a moment ago', async () => {
    const searchContacts = jest.fn();
    const { service, cache } = build(searchContacts);
    cache.get.mockResolvedValue(12);

    await service.hydrate('user-1', { ...base, professions: ['Macon'] });

    expect(searchContacts).not.toHaveBeenCalled();
  });

  it('keeps the other queries when SBC fails one of them', async () => {
    // SBC intermittently 500s the profession filter under load. A criteria
    // naming three professions must still hydrate on the two that answered.
    const searchContacts = jest
      .fn()
      .mockResolvedValueOnce(page(2))
      .mockRejectedValueOnce(new Error('SBC 500'))
      .mockResolvedValueOnce(page(3));
    const { service, members, cache } = build(searchContacts);

    await service.hydrate('user-1', {
      ...base,
      professions: ['Macon', 'Plombier', 'Medecin'],
    });

    expect(searchContacts).toHaveBeenCalledTimes(3);
    expect(members.upsertMany).toHaveBeenCalledTimes(2);
    // Partial success still counts as hydrated: the mirror did grow.
    expect(cache.set).toHaveBeenCalled();
  });

  it('does not cache an outage where every query failed', async () => {
    const searchContacts = jest.fn().mockRejectedValue(new Error('SBC 500'));
    const { service, cache } = build(searchContacts);

    await service.hydrate('user-1', { ...base, professions: ['Macon', 'Plombier'] });

    // Nothing reached the mirror, so the next preview must try again rather
    // than read a cache entry that says "already hydrated".
    expect(cache.set).not.toHaveBeenCalled();
  });

  it('never fails the caller when SBC is unreachable', async () => {
    const searchContacts = jest.fn().mockRejectedValue(new Error('SBC is down'));
    const { service, cache } = build(searchContacts);

    // The preview still answers — from the mirror, as it always did.
    await expect(
      service.hydrate('user-1', { ...base, professions: ['Macon'] }),
    ).resolves.toBeUndefined();
    // And nothing is cached, so the next attempt tries again.
    expect(cache.set).not.toHaveBeenCalled();
  });
});

import { CriteriaHydrationService } from './criteria-hydration.service';
import { MatchCriteria } from '../../members/member.view';

/**
 * A criteria preview now answers SBC's own total for the criteria (one page per
 * combination, read for its `total`) and enqueues a background walk that fills
 * the mirror with the rest. These cover both halves.
 */
describe('CriteriaHydrationService', () => {
  const base: MatchCriteria = { countries: [], cities: [], professions: [], interests: [] };

  // The deep walk ships gated off in production (SYNC_DEEP_WALK_ENABLED) until
  // the shared SBC rate limiter lands; these tests exercise its enabled logic.
  const prevDeepWalk = process.env.SYNC_DEEP_WALK_ENABLED;
  beforeAll(() => {
    process.env.SYNC_DEEP_WALK_ENABLED = 'true';
  });
  afterAll(() => {
    process.env.SYNC_DEEP_WALK_ENABLED = prevDeepWalk;
  });

  function build(searchContacts = jest.fn()) {
    const cache = {
      get: jest.fn().mockResolvedValue(null),
      set: jest.fn().mockResolvedValue(undefined),
      del: jest.fn().mockResolvedValue(undefined),
      // The deep-walk guard is a raw SET ... NX; 'OK' means this caller won it.
      client: { set: jest.fn().mockResolvedValue('OK') },
    };
    const members = { upsertMany: jest.fn().mockResolvedValue([]) };
    const tokens = { getValidAccessToken: jest.fn().mockResolvedValue('token') };
    const queue = { add: jest.fn().mockResolvedValue(undefined) };
    const service = new CriteriaHydrationService(
      tokens as never,
      { searchContacts } as never,
      members as never,
      cache as never,
      queue as never,
    );
    return { service, cache, members, tokens, queue, searchContacts };
  }

  /** One page of `n` members, reporting `total` as the criteria's SBC total. */
  const page = (n: number, total = n, hasMore = false) => ({
    items: Array.from({ length: n }, (_, i) => ({ id: `m${i}` })),
    total,
    page: 1,
    limit: 100,
    totalPages: 1,
    hasMore,
  });

  describe('previewTotal', () => {
    it('asks SBC once per (country, région, profession) triple', async () => {
      const searchContacts = jest.fn().mockResolvedValue(page(2));
      const { service } = build(searchContacts);

      await service.previewTotal('user-1', {
        ...base,
        countries: ['CM', 'FR'],
        professions: ['Macon', 'Plombier'],
      });

      // 2 countries x 1 (any région) x 2 professions, one page each.
      expect(searchContacts).toHaveBeenCalledTimes(4);
      const queried = searchContacts.mock.calls.map(([, q]) => [q.country, q.profession]);
      expect(queried).toEqual([
        ['CM', 'Macon'],
        ['CM', 'Plombier'],
        ['FR', 'Macon'],
        ['FR', 'Plombier'],
      ]);
    });

    it("returns SBC's total, not the count of members it mirrored", async () => {
      // One page of 100 fetched, but SBC says the country holds 13 826.
      const searchContacts = jest.fn().mockResolvedValue(page(100, 13826));
      const { service } = build(searchContacts);

      const total = await service.previewTotal('user-1', { ...base, countries: ['CM'] });

      expect(total).toBe(13826);
    });

    it('sums the totals across a multi-value criteria', async () => {
      const searchContacts = jest
        .fn()
        .mockResolvedValueOnce(page(100, 1000))
        .mockResolvedValueOnce(page(100, 500));
      const { service } = build(searchContacts);

      const total = await service.previewTotal('user-1', {
        ...base,
        professions: ['Macon', 'Plombier'],
      });

      expect(total).toBe(1500);
    });

    it('leaves an unset field out of the query instead of enumerating it', async () => {
      const searchContacts = jest.fn().mockResolvedValue(page(1));
      const { service } = build(searchContacts);

      await service.previewTotal('user-1', { ...base, professions: ['Macon'] });

      expect(searchContacts).toHaveBeenCalledTimes(1);
      const [, query] = searchContacts.mock.calls[0];
      expect(query.country).toBeUndefined();
      expect(query.region).toBeUndefined();
      expect(query.profession).toBe('Macon');
    });

    it("carries sexe, âge and centres d'intérêt on every query", async () => {
      const searchContacts = jest.fn().mockResolvedValue(page(1));
      const { service } = build(searchContacts);

      await service.previewTotal('user-1', {
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

      await service.previewTotal('user-1', {
        ...base,
        countries: ['CM', 'FR', 'SN', 'TG'],
        cities: ['Centre', 'Littoral'],
        professions: ['Macon', 'Plombier', 'Medecin'],
      });

      expect(searchContacts.mock.calls.length).toBeLessThanOrEqual(12);
    });

    it('mirrors page one in passing — a free head-start on the deep walk', async () => {
      const searchContacts = jest.fn().mockResolvedValue(page(3));
      const { service, members } = build(searchContacts);

      await service.previewTotal('user-1', { ...base, professions: ['Macon'] });

      expect(members.upsertMany).toHaveBeenCalledWith([{ id: 'm0' }, { id: 'm1' }, { id: 'm2' }]);
    });

    it('reads the cached total instead of asking SBC again', async () => {
      const searchContacts = jest.fn();
      const { service, cache, queue } = build(searchContacts);
      cache.get.mockResolvedValue(13826);

      const total = await service.previewTotal('user-1', { ...base, professions: ['Macon'] });

      expect(total).toBe(13826);
      expect(searchContacts).not.toHaveBeenCalled();
      // The count is cached, but the deep walk may still be worth (re)running.
      expect(queue.add).toHaveBeenCalled();
    });

    it('enqueues the deep walk after answering', async () => {
      const searchContacts = jest.fn().mockResolvedValue(page(2));
      const { service, queue } = build(searchContacts);

      await service.previewTotal('user-1', { ...base, professions: ['Macon'] });

      expect(queue.add).toHaveBeenCalledTimes(1);
      const [, jobData] = queue.add.mock.calls[0];
      expect(jobData).toMatchObject({ userId: 'user-1' });
    });

    it('keeps the other queries when SBC fails one of them', async () => {
      const searchContacts = jest
        .fn()
        .mockResolvedValueOnce(page(100, 200))
        .mockRejectedValueOnce(new Error('SBC 500'))
        .mockResolvedValueOnce(page(100, 300));
      const { service, cache } = build(searchContacts);

      const total = await service.previewTotal('user-1', {
        ...base,
        professions: ['Macon', 'Plombier', 'Medecin'],
      });

      expect(searchContacts).toHaveBeenCalledTimes(3);
      // The two that answered still give a total, and it is cached.
      expect(total).toBe(500);
      expect(cache.set).toHaveBeenCalled();
    });

    it('returns null and caches nothing when every query failed', async () => {
      const searchContacts = jest.fn().mockRejectedValue(new Error('SBC 500'));
      const { service, cache } = build(searchContacts);

      const total = await service.previewTotal('user-1', {
        ...base,
        professions: ['Macon', 'Plombier'],
      });

      // The caller falls back to the mirror count; the next preview retries.
      expect(total).toBeNull();
      expect(cache.set).not.toHaveBeenCalled();
    });

    it('never throws when SBC is unreachable', async () => {
      const searchContacts = jest.fn().mockRejectedValue(new Error('SBC is down'));
      const { service } = build(searchContacts);

      await expect(
        service.previewTotal('user-1', { ...base, professions: ['Macon'] }),
      ).resolves.toBeNull();
    });
  });

  describe('enqueueDeepWalk', () => {
    it('enqueues one walk keyed on the criteria', async () => {
      const { service, queue } = build();

      await service.enqueueDeepWalk('user-1', { ...base, countries: ['CM'] });

      expect(queue.add).toHaveBeenCalledTimes(1);
      const [name, data, opts] = queue.add.mock.calls[0];
      expect(name).toBe('hydrate');
      expect(data).toMatchObject({ userId: 'user-1' });
      expect(opts.jobId).toContain('user-1');
    });

    it('does not enqueue when another walk already holds the guard', async () => {
      const { service, cache, queue } = build();
      cache.client.set.mockResolvedValue(null); // SET ... NX lost

      await service.enqueueDeepWalk('user-1', { ...base, countries: ['CM'] });

      expect(queue.add).not.toHaveBeenCalled();
    });

    it('frees the guard if the enqueue itself fails', async () => {
      const { service, cache, queue } = build();
      queue.add.mockRejectedValue(new Error('queue down'));

      await expect(
        service.enqueueDeepWalk('user-1', { ...base, countries: ['CM'] }),
      ).resolves.toBeUndefined();
      expect(cache.del).toHaveBeenCalled();
    });
  });

  describe('hydrateFull', () => {
    it('walks every page of the combination into the mirror', async () => {
      const searchContacts = jest
        .fn()
        .mockResolvedValueOnce(page(100, 250, true))
        .mockResolvedValueOnce(page(100, 250, true))
        .mockResolvedValueOnce(page(50, 250, false));
      const { service, members } = build(searchContacts);

      const mirrored = await service.hydrateFull({
        userId: 'user-1',
        criteria: { ...base, countries: ['CM'] },
      });

      expect(searchContacts).toHaveBeenCalledTimes(3);
      expect(members.upsertMany).toHaveBeenCalledTimes(3);
      expect(mirrored).toBe(250);
    });

    it('throws when every query failed, so BullMQ retries', async () => {
      const searchContacts = jest.fn().mockRejectedValue(new Error('SBC 500'));
      const { service } = build(searchContacts);

      await expect(
        service.hydrateFull({ userId: 'user-1', criteria: { ...base, professions: ['Macon'] } }),
      ).rejects.toThrow();
    });
  });
});

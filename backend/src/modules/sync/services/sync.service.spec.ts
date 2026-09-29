import { SyncService } from './sync.service';

/**
 * The queue leak (§16 dashboard): a run that is started and never reported
 * used to leave its targets PENDING forever, so "en attente" counted work
 * nobody was waiting on. These cover the reclaim that takes that queue back.
 */
describe('SyncService — abandoned runs', () => {
  const openRuns = [{ id: 'run-1' }, { id: 'run-2' }];

  function build(runs: { id: string }[] = openRuns) {
    const deleteMany = jest.fn().mockResolvedValue({ count: 7 });
    const updateMany = jest.fn().mockResolvedValue({ count: runs.length });
    const findMany = jest.fn().mockResolvedValue(runs);

    const prisma = {
      syncRun: {
        findMany,
        updateMany,
        findFirst: jest.fn().mockResolvedValue(null),
      },
      syncedContact: {
        deleteMany,
        groupBy: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
      },
      syncCriteria: {
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
      },
      favorite: { count: jest.fn().mockResolvedValue(0) },
      addedEvent: { count: jest.fn().mockResolvedValue(0) },
      // The reclaim batches its two writes; run them and hand back the results.
      $transaction: jest.fn((ops: Promise<unknown>[]) => Promise.all(ops)),
    };

    const service = new SyncService(
      prisma as never,
      {} as never,
      {} as never,
      { record: jest.fn() } as never,
      {} as never,
      { hydrate: jest.fn() } as never,
    );
    return { service, prisma, findMany, deleteMany, updateMany };
  }

  it('releases only the PENDING rows stamped with the reclaimed runs', async () => {
    const { service, deleteMany, updateMany } = build();
    await service.summary('user-1');

    expect(deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', status: 'PENDING', syncRunId: { in: ['run-1', 'run-2'] } },
    });
    // A contact that was actually written is never touched.
    const [{ where }] = deleteMany.mock.calls[0] as [{ where: { status: string } }];
    expect(where.status).toBe('PENDING');

    expect(updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: { in: ['run-1', 'run-2'] } },
        data: expect.objectContaining({ status: 'ABANDONED' }),
      }),
    );
  });

  it('only reclaims runs old enough to be given up on, from the dashboard', async () => {
    const { service, findMany } = build();
    await service.summary('user-1');

    const [{ where }] = findMany.mock.calls[0] as [{ where: { startedAt?: { lt: Date } } }];
    expect(where.startedAt?.lt).toBeInstanceOf(Date);
    expect(where.startedAt!.lt.getTime()).toBeLessThan(Date.now());
  });

  it('does nothing, and writes nothing, when no run is open', async () => {
    const { service, deleteMany, updateMany } = build([]);
    const result = await service.summary('user-1');

    expect(deleteMany).not.toHaveBeenCalled();
    expect(updateMany).not.toHaveBeenCalled();
    expect(result.pendingCount).toBe(0);
  });
});

/**
 * A run that names only a criteria never passed through the preview or the
 * matches list, so nothing had pulled SBC's members into the mirror for it. It
 * used to expand the criteria against whatever the mirror happened to hold and
 * sync a fraction of what the member was shown — or nobody at all.
 */
describe('SyncService — a run started from a criteria alone', () => {
  const criteria = {
    id: 'crit-1',
    countries: ['CM'],
    cities: ['Littoral'],
    professions: [],
    interests: [],
    sex: null,
    ageMin: null,
    ageMax: null,
  };

  function build() {
    const enqueueDeepWalk = jest.fn().mockResolvedValue(undefined);
    const find = jest.fn().mockResolvedValue([]);
    const prisma = {
      syncCriteria: { findFirst: jest.fn().mockResolvedValue(criteria) },
      syncedContact: { findMany: jest.fn().mockResolvedValue([]), upsert: jest.fn() },
      syncRun: {
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn().mockResolvedValue({ id: 'run-1' }),
      },
    };
    const service = new SyncService(
      prisma as never,
      {} as never,
      { find } as never,
      { record: jest.fn() } as never,
      {} as never,
      { enqueueDeepWalk } as never,
    );
    return { service, enqueueDeepWalk, find };
  }

  it('kicks off the background hydration before expanding the criteria', async () => {
    const { service, enqueueDeepWalk, find } = build();
    await service.start('user-1', { criteriaId: 'crit-1' } as never);

    expect(enqueueDeepWalk).toHaveBeenCalledWith(
      'user-1',
      expect.objectContaining({ countries: ['CM'], cities: ['Littoral'] }),
    );
    // Order matters: kicking the mirror fill before reading it is the whole bug.
    expect(enqueueDeepWalk.mock.invocationCallOrder[0]).toBeLessThan(
      find.mock.invocationCallOrder[0],
    );
  });

  it('matches on the same criteria it enqueued', async () => {
    const { service, enqueueDeepWalk, find } = build();
    await service.start('user-1', { criteriaId: 'crit-1' } as never);

    const [, enqueued] = enqueueDeepWalk.mock.calls[0] as [string, unknown];
    const [matched] = find.mock.calls[0] as [unknown];
    expect(matched).toEqual(enqueued);
  });
});

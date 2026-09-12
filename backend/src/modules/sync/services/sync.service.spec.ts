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
      syncCriteria: { findMany: jest.fn().mockResolvedValue([]) },
      // The reclaim batches its two writes; run them and hand back the results.
      $transaction: jest.fn((ops: Promise<unknown>[]) => Promise.all(ops)),
    };

    const service = new SyncService(
      prisma as never,
      {} as never,
      {} as never,
      { record: jest.fn() } as never,
      {} as never,
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

    const [{ where }] = findMany.mock.calls[0] as [
      { where: { startedAt?: { lt: Date } } },
    ];
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

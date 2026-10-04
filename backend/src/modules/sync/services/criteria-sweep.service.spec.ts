import { CriteriaSweepService } from './criteria-sweep.service';

/**
 * The sweep is the trigger §11 never had: without it "notify me when somebody
 * new matches" only fired from an SBC webhook that never arrives.
 *
 * The cases that matter are about restraint, not delivery. "New" can only mean
 * "new to our mirror", so a criteria meeting the mirror for the first time must
 * stay silent, and no single pass may ever turn a bulk hydration into a wall of
 * alerts.
 */
describe('CriteriaSweepService', () => {
  const member = (sbcId: string) => ({ sbcId, firstName: 'A', name: 'B' });

  function build(criteria: Record<string, unknown>[], fresh = [member('m1')]) {
    const update = jest.fn().mockResolvedValue({});
    const prisma = {
      syncCriteria: { findMany: jest.fn().mockResolvedValue(criteria), update },
    };
    const matcher = {
      findNewSince: jest.fn().mockResolvedValue(fresh),
      count: jest.fn().mockResolvedValue(42),
    };
    const hydration = { hydrateFull: jest.fn().mockResolvedValue(0) };
    const notifications = { notifyNewMatch: jest.fn().mockResolvedValue(true) };

    const service = new CriteriaSweepService(
      prisma as never,
      matcher as never,
      hydration as never,
      notifications as never,
    );
    return { service, prisma, matcher, hydration, notifications, update };
  }

  const active = (over: Record<string, unknown> = {}) => ({
    id: 'c1',
    userId: 'u1',
    label: 'Designers de Douala',
    countries: ['CM'],
    cities: [],
    professions: [],
    interests: [],
    sex: null,
    ageMin: null,
    ageMax: null,
    lastCheckedAt: new Date('2026-09-01'),
    ...over,
  });

  it('notifies the criteria owner about members mirrored since the last pass', async () => {
    const { service, notifications, matcher } = build([active()]);

    const result = await service.sweep();

    expect(matcher.findNewSince).toHaveBeenCalledWith(
      expect.anything(),
      new Date('2026-09-01'),
      expect.any(Number),
    );
    expect(notifications.notifyNewMatch).toHaveBeenCalledTimes(1);
    expect(notifications.notifyNewMatch.mock.calls[0][0]).toBe('u1');
    expect(result).toEqual({ checked: 1, notified: 1 });
  });

  it('hydrates from SBC before matching, or it only ever sees what was searched', async () => {
    const { service, hydration, matcher } = build([active()]);

    await service.sweep();

    expect(hydration.hydrateFull).toHaveBeenCalledWith({
      userId: 'u1',
      criteria: expect.anything(),
    });
    expect(hydration.hydrateFull.mock.invocationCallOrder[0]).toBeLessThan(
      matcher.findNewSince.mock.invocationCallOrder[0],
    );
  });

  it('stays silent on a criteria it has never checked, and stamps it instead', async () => {
    // Everything already in the mirror is older than this criteria's interest in
    // it; notifying here would alert on the entire back catalogue.
    const { service, notifications, matcher, update } = build([active({ lastCheckedAt: null })]);

    const result = await service.sweep();

    expect(notifications.notifyNewMatch).not.toHaveBeenCalled();
    expect(matcher.findNewSince).not.toHaveBeenCalled();
    expect(update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ lastCheckedAt: expect.any(Date) }),
      }),
    );
    expect(result.notified).toBe(0);
  });

  it('caps how many members one pass may announce', async () => {
    const { service, matcher } = build([active()]);

    await service.sweep();

    const take = matcher.findNewSince.mock.calls[0][2];
    expect(take).toBeLessThanOrEqual(10);
  });

  it('one owner with a lapsed SBC session does not sink the rest of the sweep', async () => {
    const { service, hydration, notifications } = build([
      active({ id: 'c1', userId: 'u1' }),
      active({ id: 'c2', userId: 'u2' }),
    ]);
    hydration.hydrateFull.mockRejectedValueOnce(new Error('no SBC token'));

    const result = await service.sweep();

    expect(result.checked).toBe(2);
    expect(notifications.notifyNewMatch).toHaveBeenCalledTimes(1);
    expect(notifications.notifyNewMatch.mock.calls[0][0]).toBe('u2');
  });

  it('records the refreshed match count so the dashboard stops lying', async () => {
    const { service, update } = build([active()]);

    await service.sweep();

    expect(update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'c1' },
        data: expect.objectContaining({ lastMatchCount: 42 }),
      }),
    );
  });
});

import { StatusBoostService } from './status-boost.service';

/**
 * The list is only worth something if everyone on it can actually be saved:
 * never yourself, never someone without a number, and always someone the
 * contact recording can find in the member mirror.
 */
describe('StatusBoostService', () => {
  function build(users: Array<Record<string, unknown>>) {
    const prisma = {
      user: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({
          sbcUserId: 'me-sbc',
          statusBoostOptIn: true,
          phoneNumber: '237600',
        }),
        findMany: jest.fn().mockReturnValue('rows'),
        count: jest.fn().mockReturnValue('count'),
        update: jest.fn().mockResolvedValue({
          sbcUserId: 'me-sbc',
          name: 'Moi',
          phoneNumber: '237600',
          country: 'Cameroun',
          avatarUrl: null,
        }),
      },
      syncCriteria: {
        findFirst: jest.fn().mockReturnValue(null),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      member: {
        findMany: jest.fn().mockResolvedValue([]),
        upsert: jest.fn(
          ({ where }: { where: { sbcId: string }; update?: unknown; create?: unknown }) =>
            Promise.resolve({ id: `m-${where.sbcId}`, sbcId: where.sbcId }),
        ),
      },
      syncedContact: { findMany: jest.fn().mockResolvedValue([]) },
      addedEvent: { findMany: jest.fn().mockResolvedValue([]) },
      $transaction: jest.fn().mockResolvedValue([users, users.length, users]),
    };
    return { svc: new StatusBoostService(prisma as never), prisma };
  }

  const user = (id: string, types: string[]) => ({
    id,
    sbcUserId: `${id}-sbc`,
    name: id,
    phoneNumber: '237699',
    avatarUrl: null,
    country: 'CM',
    subscriptionTypes: types,
    statusBoostSince: new Date(),
  });

  it('asks only for other opted-in members with a number, filtered by subscription', async () => {
    const { svc, prisma } = build([user('a', ['CIBLE'])]);
    await svc.list('me', { page: 1, limit: 30, skip: 0, subscription: 'CIBLE' } as never);
    const where = prisma.user.findMany.mock.calls[0][0].where;
    expect(where).toEqual(
      expect.objectContaining({
        statusBoostOptIn: true,
        deletedAt: null,
        id: { not: 'me' },
        phoneNumber: { not: null },
        subscriptionTypes: { has: 'CIBLE' },
      }),
    );
  });

  it('makes sure every listed member exists in the mirror, without overwriting SBC data', async () => {
    const { svc, prisma } = build([user('a', ['CIBLE']), user('b', ['CLASSIQUE'])]);
    const page = await svc.list('me', { page: 1, limit: 30, skip: 0 } as never);
    expect(prisma.member.upsert).toHaveBeenCalledTimes(2);
    expect(prisma.member.upsert.mock.calls[0][0].update).toEqual({});
    expect(page.subscriptionTypes).toEqual(['CIBLE', 'CLASSIQUE']);
  });

  it('puts a member who joins in the mirror straight away', async () => {
    const { svc, prisma } = build([]);
    prisma.$transaction.mockResolvedValueOnce([
      { statusBoostOptIn: true, statusBoostSince: new Date(), phoneNumber: '237600' },
      1,
    ]);
    await svc.setOptIn('me', true);
    expect(prisma.member.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { sbcId: 'me-sbc' },
        create: expect.objectContaining({ country: 'CM' }),
      }),
    );
  });

  it('stops the member saving the list when they leave it', async () => {
    const { svc, prisma } = build([]);
    prisma.$transaction.mockResolvedValueOnce([
      { statusBoostOptIn: false, statusBoostSince: null, phoneNumber: '237600' },
      0,
      { id: 'c1', isActive: false },
    ]);
    await svc.setOptIn('me', false);
    expect(prisma.syncCriteria.updateMany).toHaveBeenCalledWith({
      where: { userId: 'me', statusBoost: true, isActive: true },
      data: { isActive: false },
    });
  });

  it('resolves the participants to mirror rows, creating only the missing ones', async () => {
    const { svc, prisma } = build([]);
    prisma.user.findMany.mockResolvedValueOnce([user('a', []), user('b', [])]);
    prisma.member.findMany.mockResolvedValueOnce([{ id: 'm-a-sbc', sbcId: 'a-sbc' }]);

    const members = await svc.participants('me', { since: new Date('2026-10-01') });

    expect(prisma.user.findMany.mock.calls[0][0].where).toEqual(
      expect.objectContaining({
        id: { not: 'me' },
        statusBoostSince: { gt: new Date('2026-10-01') },
      }),
    );
    expect(prisma.member.upsert).toHaveBeenCalledTimes(1);
    expect(prisma.member.upsert.mock.calls[0][0].where).toEqual({ sbcId: 'b-sbc' });
    expect(members.map((m) => m.sbcId).sort()).toEqual(['a-sbc', 'b-sbc']);
  });
});

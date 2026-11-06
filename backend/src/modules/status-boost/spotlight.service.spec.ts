import { SpotlightService, spotlightSource } from './spotlight.service';

/**
 * A featured member is shown to whoever has not saved them yet, and to nobody
 * once they have: the contact is won, the place goes to the next one.
 */
describe('SpotlightService', () => {
  const now = new Date('2026-11-05T12:00:00Z');
  const later = new Date('2026-12-05T12:00:00Z');
  const earlier = new Date('2026-10-05T12:00:00Z');

  const user = (id: string) => ({
    id,
    sbcUserId: `${id}-sbc`,
    name: id,
    phoneNumber: '237699',
    avatarUrl: null,
    country: 'CM',
    subscriptionTypes: ['CLASSIQUE', 'MISE_EN_AVANT'],
    spotlightUntil: null as Date | null,
  });

  function build(opts: {
    candidates: Array<ReturnType<typeof user>>;
    synced?: string[];
    added?: string[];
    savers?: string[];
  }) {
    const prisma = {
      user: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({ sbcUserId: 'me-sbc' }),
        findMany: jest.fn().mockResolvedValue(opts.candidates),
      },
      syncedContact: {
        findMany: jest.fn().mockResolvedValue((opts.synced ?? []).map((m) => ({ memberId: m }))),
      },
      addedEvent: {
        findMany: jest
          .fn()
          .mockResolvedValueOnce((opts.added ?? []).map((t) => ({ targetMemberSbcId: t })))
          .mockResolvedValueOnce((opts.savers ?? []).map((a) => ({ actorId: a }))),
      },
    };
    const boost = {
      mirror: jest.fn((users: Array<{ sbcUserId: string }>) =>
        Promise.resolve(users.map((u) => ({ id: `m-${u.sbcUserId}`, sbcId: u.sbcUserId }))),
      ),
    };
    const svc = new SpotlightService(
      prisma as never,
      boost as never,
      { record: jest.fn() } as never,
    );
    return { svc, prisma };
  }

  it('comes from the SBC subscription or an admin date still to come', () => {
    expect(
      spotlightSource({ subscriptionTypes: ['mise_en_avant'], spotlightUntil: null }, now),
    ).toBe('sbc');
    expect(spotlightSource({ subscriptionTypes: ['CIBLE'], spotlightUntil: later }, now)).toBe(
      'admin',
    );
    expect(
      spotlightSource({ subscriptionTypes: ['CIBLE'], spotlightUntil: earlier }, now),
    ).toBeNull();
    expect(spotlightSource({ subscriptionTypes: [], spotlightUntil: null }, now)).toBeNull();
  });

  it('asks only for other members with a number who are featured', async () => {
    const { svc, prisma } = build({ candidates: [] });
    await svc.featured('me', now);
    const where = prisma.user.findMany.mock.calls[0][0].where;
    expect(where.id).toEqual({ not: 'me' });
    expect(where.phoneNumber).toEqual({ not: null });
    expect(where.OR).toEqual(expect.arrayContaining([{ spotlightUntil: { gt: now } }]));
  });

  it('drops a featured member as soon as the viewer has saved them', async () => {
    const { svc } = build({
      candidates: [user('a'), user('b'), user('c')],
      synced: ['m-b-sbc'], // saved through a sync
      added: ['c-sbc'], // saved from the app
    });
    const featured = await svc.featured('me', now);
    expect(featured.map((f) => f.sbcId)).toEqual(['a-sbc']);
  });

  it('says when the featured member already saved the viewer', async () => {
    const { svc } = build({ candidates: [user('a')], savers: ['a'] });
    const [entry] = await svc.featured('me', now);
    expect(entry.savedMe).toBe(true);
  });

  it('shows at most five at a time', async () => {
    const { svc } = build({ candidates: 'abcdefgh'.split('').map(user) });
    expect(await svc.featured('me', now)).toHaveLength(5);
  });

  it('lists members for the back-office with where their spotlight comes from', async () => {
    const admin = { ...user('a'), subscriptionTypes: ['CLASSIQUE'], spotlightUntil: later, email: null };
    const none = { ...user('b'), subscriptionTypes: [], spotlightUntil: earlier, email: null };
    const { svc, prisma } = build({ candidates: [admin, none] });
    Object.assign(prisma.user, { count: jest.fn().mockResolvedValue(2) });
    const page = await svc.adminList({ search: 'a', featured: undefined, page: 1, limit: 20 }, now);
    expect(page.total).toBe(2);
    expect(page.items.map((r) => [r.userId, r.active, r.source])).toEqual([
      ['a', true, 'admin'],
      ['b', false, null],
    ]);
  });
});

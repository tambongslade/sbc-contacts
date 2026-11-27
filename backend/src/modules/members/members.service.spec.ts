import { MembersService } from './members.service';

/**
 * Saving back someone from "Qui m'a enregistré" needs a directory row for them.
 * App accounts that never showed up in a search had none, so the add-back was
 * silently dropped and they stayed in the list.
 */
describe('MembersService.findOrMirrorBySbcIds', () => {
  function build(existing: { id: string; sbcId: string }[]) {
    const prisma = {
      member: {
        findMany: jest.fn().mockResolvedValue(existing),
        upsert: jest.fn(({ create }: { create: { sbcId: string } }) =>
          Promise.resolve({ id: `m-${create.sbcId}`, ...create }),
        ),
      },
      user: {
        findMany: jest.fn().mockResolvedValue([
          { sbcUserId: 'sbc-new', name: 'Nadia', phoneNumber: '+237600000000', country: 'Cameroun', avatarUrl: null },
        ]),
      },
    };
    return { service: new MembersService(prisma as never), prisma };
  }

  it('creates a row from the app account when the directory has none', async () => {
    const { service, prisma } = build([{ id: 'm-old', sbcId: 'sbc-old' }]);
    const members = await service.findOrMirrorBySbcIds(['sbc-old', 'sbc-new']);

    expect(members.map((m) => m.sbcId).sort()).toEqual(['sbc-new', 'sbc-old']);
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { sbcUserId: { in: ['sbc-new'] }, deletedAt: null } }),
    );
    // An existing directory row is never overwritten.
    expect(prisma.member.upsert).toHaveBeenCalledTimes(1);
    expect(prisma.member.upsert.mock.calls[0][0]).toMatchObject({
      where: { sbcId: 'sbc-new' },
      update: {},
      create: { sbcId: 'sbc-new', name: 'Nadia', phoneNumber: '+237600000000' },
    });
  });

  it('touches nothing when every id is already in the directory', async () => {
    const { service, prisma } = build([{ id: 'm-old', sbcId: 'sbc-old' }]);
    await service.findOrMirrorBySbcIds(['sbc-old']);
    expect(prisma.user.findMany).not.toHaveBeenCalled();
    expect(prisma.member.upsert).not.toHaveBeenCalled();
  });
});

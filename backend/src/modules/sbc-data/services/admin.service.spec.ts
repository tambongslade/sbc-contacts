import { BadRequestException } from '@nestjs/common';
import { RequestStatus } from '@prisma/client';
import { SbcDataAdminService } from './admin.service';

/**
 * Back-office writes touch other people's work: a merge rewrites a pro's
 * services, a suspension closes a request pros may be answering. The rules
 * worth pinning are the ones that stop an admin from doing damage by mistake.
 */
describe('SbcDataAdminService', () => {
  const service = (over: Record<string, unknown>) => ({
    id: 's1',
    proId: 'p1',
    name: 'Réparation de locks',
    category: 'Locks',
    profession: 'Coiffeur',
    synonyms: ['rattrapage'],
    specialties: [],
    isActive: true,
    ...over,
  });

  function build(rows: Record<string, unknown>) {
    const prisma = {
      proService: {
        findUnique: jest.fn(({ where }: { where: { id: string } }) =>
          Promise.resolve(rows[where.id] ?? null),
        ),
        update: jest.fn().mockReturnValue('update-op'),
        delete: jest.fn().mockReturnValue('delete-op'),
      },
      requestDispatch: { updateMany: jest.fn().mockReturnValue('move-op') },
      serviceRequest: {
        findUnique: jest.fn(() => Promise.resolve(rows.request ?? null)),
        update: jest.fn().mockReturnValue('close-op'),
      },
      $transaction: jest.fn().mockResolvedValue([]),
    };
    const audit = { record: jest.fn() };
    const ai = { embed: jest.fn().mockResolvedValue([[0.1, 0.2]]) };
    return {
      svc: new SbcDataAdminService(prisma as never, audit as never, ai as never),
      prisma,
      audit,
    };
  }

  it('merges two services of the same pro: synonyms join, history moves, source goes', async () => {
    const { svc, prisma, audit } = build({
      s1: service({}),
      s2: service({ id: 's2', name: 'Entretien de locks', synonyms: ['retwist'] }),
    });
    await svc.mergeService('admin', 's1', 's2');
    expect(prisma.requestDispatch.updateMany).toHaveBeenCalledWith({
      where: { serviceId: 's1' },
      data: { serviceId: 's2' },
    });
    expect(prisma.proService.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 's2' },
        data: expect.objectContaining({
          synonyms: ['retwist', 'rattrapage', 'Réparation de locks'],
        }),
      }),
    );
    expect(prisma.proService.delete).toHaveBeenCalledWith({ where: { id: 's1' } });
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'sbc-data.admin.service.merge' }),
    );
  });

  it('refuses to merge services of two different pros', async () => {
    const { svc, prisma } = build({ s1: service({}), s2: service({ id: 's2', proId: 'p2' }) });
    await expect(svc.mergeService('admin', 's1', 's2')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('refuses to merge a service into itself', async () => {
    const { svc } = build({ s1: service({}) });
    await expect(svc.mergeService('admin', 's1', 's1')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('will not suspend a request that is already closed', async () => {
    const { svc, prisma } = build({ request: { id: 'r1', status: RequestStatus.COMPLETED } });
    await expect(svc.suspendRequest('admin', 'r1')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
});

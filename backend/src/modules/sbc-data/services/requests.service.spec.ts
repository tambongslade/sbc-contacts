import { ConflictException, NotFoundException } from '@nestjs/common';
import { DispatchStatus, RequestStatus } from '@prisma/client';
import { RequestsService } from './requests.service';

/**
 * Deleting a request is the requester tidying their list, so the cases that
 * matter are the people on the other side: pros who answered must keep their
 * history, and a pro already chosen must not see their job vanish.
 */
describe('RequestsService.remove', () => {
  function build(request: Record<string, unknown> | null) {
    const tx = {
      requestDispatch: { updateMany: jest.fn().mockResolvedValue({ count: 2 }) },
      serviceRequest: { update: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      serviceRequest: {
        findUnique: jest.fn().mockResolvedValue(request),
        delete: jest.fn().mockResolvedValue({}),
      },
      $transaction: jest.fn((fn: (t: typeof tx) => Promise<unknown>) => fn(tx)),
    };
    const service = new RequestsService(
      prisma as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    );
    return { service, prisma, tx };
  }

  const req = (status: RequestStatus, over: Record<string, unknown> = {}) => ({
    id: 'r1',
    userId: 'u1',
    status,
    hiddenAt: null,
    ...over,
  });

  it('erases a draft, which never reached anyone', async () => {
    const { service, prisma, tx } = build(req(RequestStatus.DRAFT));
    await service.remove('u1', 'r1');
    expect(prisma.serviceRequest.delete).toHaveBeenCalledWith({ where: { id: 'r1' } });
    expect(tx.serviceRequest.update).not.toHaveBeenCalled();
  });

  it('cancels an open request before hiding it, so pros see it close', async () => {
    const { service, prisma, tx } = build(req(RequestStatus.RESPONDED));
    await service.remove('u1', 'r1');
    expect(prisma.serviceRequest.delete).not.toHaveBeenCalled();
    expect(tx.requestDispatch.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: { status: DispatchStatus.LOST } }),
    );
    expect(tx.serviceRequest.update).toHaveBeenCalledWith({
      where: { id: 'r1' },
      data: { hiddenAt: expect.any(Date), status: RequestStatus.CANCELLED },
    });
  });

  it('only hides a finished request, keeping it in the pros’ history', async () => {
    const { service, prisma, tx } = build(req(RequestStatus.COMPLETED));
    await service.remove('u1', 'r1');
    expect(prisma.serviceRequest.delete).not.toHaveBeenCalled();
    expect(tx.requestDispatch.updateMany).not.toHaveBeenCalled();
    expect(tx.serviceRequest.update).toHaveBeenCalledWith({
      where: { id: 'r1' },
      data: { hiddenAt: expect.any(Date) },
    });
  });

  it('refuses while a chosen pro is waiting to do the job', async () => {
    const { service } = build(req(RequestStatus.SELECTED));
    await expect(service.remove('u1', 'r1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('treats someone else’s request, or an already deleted one, as not found', async () => {
    await expect(
      build(req(RequestStatus.DRAFT, { userId: 'other' })).service.remove('u1', 'r1'),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      build(req(RequestStatus.COMPLETED, { hiddenAt: new Date() })).service.remove('u1', 'r1'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});

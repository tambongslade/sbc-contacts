import { extendUntil, paidUntil } from './paid-features';
import { PaidFeaturesService } from './paid-features.service';

/**
 * What SBC says was paid becomes "paid until" dates on the app's side, and a
 * longer period (or an open-ended one, like the free iOS reception) is never
 * shortened by it.
 */
describe('paid features', () => {
  const now = new Date('2026-11-05T12:00:00Z');
  const inMonth = '2026-12-05T12:00:00.000Z';
  const lastMonth = '2026-10-05T12:00:00.000Z';
  const grace = new Date('2026-11-08T12:00:00Z');

  describe('paidUntil', () => {
    it('takes the end date of an active dated subscription', () => {
      const sbc = { subscriptions: [{ type: 'PRO', status: 'active', expiresAt: inMonth }] };
      expect(paidUntil(sbc, 'PRO', now)).toEqual(new Date(inMonth));
      expect(paidUntil(sbc, 'SPOTLIGHT', now)).toBeNull();
    });

    it('ignores expired, cancelled and past subscriptions', () => {
      const sbc = {
        subscriptions: [
          { type: 'MISE_EN_AVANT', status: 'expired', expiresAt: inMonth },
          { type: 'mise_en_avant', status: 'cancelled', expiresAt: inMonth },
          { type: 'MISE_EN_AVANT', status: 'active', expiresAt: lastMonth },
        ],
        subscriptionTypes: ['MISE_EN_AVANT'],
      };
      expect(paidUntil(sbc, 'SPOTLIGHT', now)).toBeNull();
    });

    it('falls back on subscriptionTypes, for a few days, when SBC sends no dates', () => {
      expect(paidUntil({ subscriptionTypes: ['CIBLE', 'pro'] }, 'PRO', now)).toEqual(grace);
      expect(paidUntil({ subscriptionTypes: ['CIBLE'] }, 'PRO', now)).toBeNull();
    });
  });

  describe('extendUntil', () => {
    it('keeps the later date and never shortens an open-ended period', () => {
      const paid = new Date(inMonth);
      expect(extendUntil(null, paid, false)).toEqual(paid);
      expect(extendUntil(new Date('2027-01-01'), paid, false)).toEqual(new Date('2027-01-01'));
      expect(extendUntil(null, paid, true)).toBeNull();
    });
  });

  describe('PaidFeaturesService', () => {
    function build(profile: { receivingEnabled: boolean; receivingUntil: Date | null } | null) {
      const prisma = {
        user: {
          findUnique: jest.fn().mockResolvedValue({ spotlightUntil: null }),
          update: jest.fn().mockResolvedValue({}),
        },
        proProfile: {
          findUnique: jest.fn().mockResolvedValue(profile),
          update: jest.fn().mockResolvedValue({}),
        },
      };
      return { svc: new PaidFeaturesService(prisma as never), prisma };
    }

    it('switches the reception on until the paid date', async () => {
      const { svc, prisma } = build({ receivingEnabled: false, receivingUntil: null });
      await svc.applyFromSbc(
        'u1',
        { subscriptions: [{ type: 'PRO', status: 'active', expiresAt: inMonth }] },
        now,
      );
      expect(prisma.proProfile.update).toHaveBeenCalledWith({
        where: { userId: 'u1' },
        data: { receivingEnabled: true, receivingUntil: new Date(inMonth) },
      });
    });

    it('leaves a free iOS reception open-ended', async () => {
      const { svc, prisma } = build({ receivingEnabled: true, receivingUntil: null });
      await svc.applyFromSbc('u1', { subscriptionTypes: ['PRO'] }, now);
      expect(prisma.proProfile.update).not.toHaveBeenCalled();
    });

    it('features the member until the paid date', async () => {
      const { svc, prisma } = build(null);
      await svc.applyFromSbc(
        'u1',
        { subscriptions: [{ type: 'MISE_EN_AVANT', status: 'active', expiresAt: inMonth }] },
        now,
      );
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: 'u1' },
        data: { spotlightUntil: new Date(inMonth) },
      });
    });

    it('does nothing for a member who paid for neither', async () => {
      const { svc, prisma } = build(null);
      await svc.applyFromSbc('u1', { subscriptionTypes: ['CIBLE'] }, now);
      expect(prisma.user.findUnique).not.toHaveBeenCalled();
      expect(prisma.proProfile.findUnique).not.toHaveBeenCalled();
    });
  });
});

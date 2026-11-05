import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { extendUntil, paidUntil, SbcPaidState } from './paid-features';

/**
 * Writes what a member paid on SBC into the fields the app already runs on:
 * ProProfile.receivingUntil for the Pro, User.spotlightUntil for the mise en
 * avant. Called with every fresh SBC snapshot — at login, each time the app
 * opens (auth/me) and on each SBC subscription webhook.
 *
 * It only ever extends: a period already longer (or open-ended, like the free
 * iOS reception) is kept. An unpaid feature simply runs out at its date.
 */
@Injectable()
export class PaidFeaturesService {
  private readonly logger = new Logger(PaidFeaturesService.name);

  constructor(private readonly prisma: PrismaService) {}

  async applyFromSbc(userId: string, sbc: SbcPaidState, now = new Date()): Promise<void> {
    const spotlight = paidUntil(sbc, 'SPOTLIGHT', now);
    const pro = paidUntil(sbc, 'PRO', now);
    if (!spotlight && !pro) return;

    try {
      if (spotlight) {
        const user = await this.prisma.user.findUnique({
          where: { id: userId },
          select: { spotlightUntil: true },
        });
        const until = extendUntil(user?.spotlightUntil, spotlight, false);
        if (until?.getTime() !== user?.spotlightUntil?.getTime()) {
          await this.prisma.user.update({ where: { id: userId }, data: { spotlightUntil: until } });
        }
      }

      if (pro) {
        const profile = await this.prisma.proProfile.findUnique({
          where: { userId },
          select: { receivingEnabled: true, receivingUntil: true },
        });
        // No pro profile yet: the next snapshot after it is created applies it.
        if (profile) {
          const openEnded = profile.receivingEnabled && profile.receivingUntil === null;
          const current = profile.receivingEnabled ? profile.receivingUntil : null;
          const until = extendUntil(current, pro, openEnded);
          if (!profile.receivingEnabled || until?.getTime() !== profile.receivingUntil?.getTime()) {
            await this.prisma.proProfile.update({
              where: { userId },
              data: { receivingEnabled: true, receivingUntil: until },
            });
          }
        }
      }
    } catch (err) {
      // Never break a login over this: the next snapshot tries again.
      this.logger.warn(`Paid features not applied for ${userId}: ${(err as Error).message}`);
    }
  }
}

import { Injectable } from '@nestjs/common';
import { Device, Platform } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';

/** Push-token registry per user (targets for the push providers). */
@Injectable()
export class DevicesService {
  constructor(private readonly prisma: PrismaService) {}

  async register(
    userId: string,
    platform: Platform,
    pushToken?: string,
  ): Promise<Device> {
    if (pushToken) {
      // A token belongs to one phone. When someone signs in on a phone another
      // account used, that account must stop receiving its pushes.
      await this.prisma.device.deleteMany({ where: { pushToken, userId: { not: userId } } });
      return this.prisma.device.upsert({
        where: { userId_pushToken: { userId, pushToken } },
        create: { userId, platform, pushToken },
        update: { platform, lastSeenAt: new Date() },
      });
    }
    return this.prisma.device.create({ data: { userId, platform } });
  }

  list(userId: string): Promise<Device[]> {
    return this.prisma.device.findMany({ where: { userId }, orderBy: { lastSeenAt: 'desc' } });
  }

  async remove(userId: string, id: string): Promise<void> {
    await this.prisma.device.deleteMany({ where: { id, userId } });
  }

  /** Push tokens for a user, split by the service that delivers to them. */
  async pushTargets(userId: string): Promise<{ fcm: string[]; apns: string[] }> {
    const devices = await this.prisma.device.findMany({
      where: { userId, pushToken: { not: null } },
      select: { pushToken: true, platform: true },
    });
    const fcm: string[] = [];
    const apns: string[] = [];
    for (const d of devices) {
      if (!d.pushToken) continue;
      (d.platform === Platform.IOS ? apns : fcm).push(d.pushToken);
    }
    return { fcm, apns };
  }

  /** Forgets tokens a push service reported as dead (app removed, token rotated). */
  async forgetTokens(tokens: string[]): Promise<void> {
    if (tokens.length === 0) return;
    await this.prisma.device.deleteMany({ where: { pushToken: { in: tokens } } });
  }
}

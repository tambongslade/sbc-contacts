import { Injectable } from '@nestjs/common';
import { Device, Platform } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';

/** Push-token registry per user (targets for the push provider). */
@Injectable()
export class DevicesService {
  constructor(private readonly prisma: PrismaService) {}

  async register(
    userId: string,
    platform: Platform,
    pushToken?: string,
  ): Promise<Device> {
    if (pushToken) {
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

  /** Push tokens for a user (used by the notifications processor). */
  async pushTokens(userId: string): Promise<string[]> {
    const devices = await this.prisma.device.findMany({
      where: { userId, pushToken: { not: null } },
      select: { pushToken: true },
    });
    return devices.map((d) => d.pushToken!).filter(Boolean);
  }
}

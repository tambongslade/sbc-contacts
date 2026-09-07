import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import { randomUUID } from 'crypto';
import { EncryptionService } from '../../../common/crypto/encryption.service';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { TokenService } from './token.service';

interface Row {
  id: string;
  userId: string;
  refreshTokenHash: string;
  familyId: string;
  expiresAt: Date;
  revokedAt: Date | null;
  replacedById: string | null;
  createdAt: Date;
}

/** Minimal in-memory stand-in for the AppSession table + $transaction. */
function makePrisma(user: { id: string; sbcUserId: string; role: string; deletedAt: Date | null }) {
  const rows: Row[] = [];
  let seq = 0;

  const appSession = {
    create: async ({ data }: { data: Partial<Row> }) => {
      const row: Row = {
        id: randomUUID(),
        userId: data.userId!,
        refreshTokenHash: data.refreshTokenHash!,
        familyId: data.familyId!,
        expiresAt: data.expiresAt!,
        revokedAt: null,
        replacedById: null,
        createdAt: new Date(Date.now() + seq++), // strictly increasing
      };
      rows.push(row);
      return row;
    },
    findUnique: async ({ where }: { where: { refreshTokenHash: string } }) => {
      const row = rows.find((r) => r.refreshTokenHash === where.refreshTokenHash) ?? null;
      return row ? { ...row, user } : null;
    },
    findFirst: async ({ where }: { where: { familyId: string } }) =>
      [...rows]
        .filter((r) => r.familyId === where.familyId)
        .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0] ?? null,
    update: async ({ where, data }: { where: { id: string }; data: Partial<Row> }) => {
      const row = rows.find((r) => r.id === where.id)!;
      Object.assign(row, data);
      return row;
    },
    updateMany: async ({
      where,
      data,
    }: {
      where: { familyId: string; revokedAt: null };
      data: Partial<Row>;
    }) => {
      let count = 0;
      rows
        .filter((r) => r.familyId === where.familyId && r.revokedAt === null)
        .forEach((r) => {
          Object.assign(r, data);
          count++;
        });
      return { count };
    },
  };

  const prisma = {
    appSession,
    // Faithful transaction: roll back row mutations if the callback throws,
    // so a "revoke-then-throw" inside a tx cannot silently persist (the bug
    // the live Postgres test caught).
    $transaction: async (fn: (tx: unknown) => Promise<unknown>) => {
      const snapshot = rows.map((r) => ({ ...r }));
      try {
        return await fn(prisma);
      } catch (e) {
        rows.splice(0, rows.length, ...snapshot);
        throw e;
      }
    },
  };
  return { prisma: prisma as unknown as PrismaService, rows };
}

describe('TokenService (refresh rotation)', () => {
  const user = { id: randomUUID(), sbcUserId: 'sbc-123', role: Role.USER, deletedAt: null };
  const config = {
    get: (k: string) =>
      ({
        'jwt.accessSecret': 'access-secret-at-least-32-chars-long!!',
        'jwt.accessTtl': 900,
        'jwt.refreshTtl': 2592000,
        'jwt.refreshSecret': 'refresh-secret-at-least-32-chars-long!!',
        'security.tokenEncryptionKey':
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      })[k],
  } as unknown as ConfigService;

  const build = () => {
    const { prisma, rows } = makePrisma({ ...user });
    const enc = new EncryptionService(config);
    const svc = new TokenService(new JwtService({}), prisma, enc, config);
    return { svc, rows };
  };

  it('issues an access + refresh token on login', async () => {
    const { svc } = build();
    const tokens = await svc.issueForUser(user);
    expect(tokens.accessToken.split('.')).toHaveLength(3); // JWT
    expect(tokens.refreshToken).toBeTruthy();
    expect(tokens.expiresIn).toBe(900);
  });

  it('rotates: old token invalidated, new token works', async () => {
    const { svc } = build();
    const first = await svc.issueForUser(user);
    const second = await svc.rotate(first.refreshToken);

    expect(second.refreshToken).not.toBe(first.refreshToken);
    // reusing the first (now-rotated) token must fail
    await expect(svc.rotate(first.refreshToken)).rejects.toThrow(/reuse/i);
  });

  it('reuse detection revokes the whole family', async () => {
    const { svc, rows } = build();
    const first = await svc.issueForUser(user);
    const second = await svc.rotate(first.refreshToken);

    // Attacker replays the old token → family compromised.
    await expect(svc.rotate(first.refreshToken)).rejects.toThrow(/reuse/i);

    // The legitimate (second) token is now also revoked.
    await expect(svc.rotate(second.refreshToken)).rejects.toThrow();
    expect(rows.every((r) => r.revokedAt !== null)).toBe(true);
  });

  it('rejects an unknown refresh token', async () => {
    const { svc } = build();
    await expect(svc.rotate('not-a-real-token')).rejects.toThrow(/invalid/i);
  });
});

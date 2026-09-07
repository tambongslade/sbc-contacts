import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import { randomUUID } from 'crypto';
import { EncryptionService } from '../../../common/crypto/encryption.service';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';

export interface IssuedTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number; // access-token lifetime (seconds)
  tokenType: 'Bearer';
}

export interface SessionMeta {
  deviceId?: string;
  userAgent?: string;
  ip?: string;
}

/**
 * Our own app-session layer on top of SBC SSO. Access tokens are stateless JWTs;
 * refresh tokens are opaque, HMAC-fingerprinted, and rotated on every use with
 * reuse detection (a replayed old token revokes the whole family) — brief §5, §9.
 */
@Injectable()
export class TokenService {
  private readonly logger = new Logger(TokenService.name);
  private readonly accessSecret: string;
  private readonly accessTtl: number;
  private readonly refreshTtl: number;

  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
    private readonly enc: EncryptionService,
    config: ConfigService,
  ) {
    this.accessSecret = config.get<string>('jwt.accessSecret')!;
    this.accessTtl = config.get<number>('jwt.accessTtl')!;
    this.refreshTtl = config.get<number>('jwt.refreshTtl')!;
  }

  /** Issue a brand-new session family (login). */
  async issueForUser(
    user: { id: string; sbcUserId: string; role: Role },
    meta: SessionMeta = {},
  ): Promise<IssuedTokens> {
    const { tokens } = await this.mint(user, randomUUID(), meta);
    return tokens;
  }

  /** Rotate: validate the presented refresh token and issue a fresh pair. */
  async rotate(refreshToken: string, meta: SessionMeta = {}): Promise<IssuedTokens> {
    const hash = this.enc.hmac(refreshToken);

    const session = await this.prisma.appSession.findUnique({
      where: { refreshTokenHash: hash },
      include: { user: true },
    });

    if (!session) throw new UnauthorizedException('Invalid refresh token');

    // Reuse of an already-rotated/revoked token → compromise. Nuke the family.
    // NOTE: this revocation MUST be committed on its own — doing it inside the
    // rotation transaction (which then throws) would roll the revocation back.
    if (session.revokedAt || session.replacedById) {
      await this.prisma.appSession.updateMany({
        where: { familyId: session.familyId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      this.logger.warn(`Refresh reuse detected; revoked family ${session.familyId}`);
      throw new UnauthorizedException('Refresh token reuse detected');
    }

    if (session.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException('Refresh token expired');
    }
    if (session.user.deletedAt) {
      throw new UnauthorizedException('Account is no longer active');
    }

    // Mint the new session and revoke the old one atomically.
    return this.prisma.$transaction(async (tx) => {
      const txClient = tx as unknown as PrismaService;
      const { tokens, sessionId } = await this.mint(
        { id: session.user.id, sbcUserId: session.user.sbcUserId, role: session.user.role },
        session.familyId,
        meta,
        txClient,
      );
      await txClient.appSession.update({
        where: { id: session.id },
        data: { revokedAt: new Date(), replacedById: sessionId },
      });
      return tokens;
    });
  }

  /** Logout: revoke the presented refresh token's session (and its family). */
  async revoke(refreshToken: string): Promise<void> {
    const hash = this.enc.hmac(refreshToken);
    const session = await this.prisma.appSession.findUnique({ where: { refreshTokenHash: hash } });
    if (!session) return; // idempotent logout
    await this.prisma.appSession.updateMany({
      where: { familyId: session.familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  /** Revoke every active session for a user (global logout / account action). */
  async revokeAllForUser(userId: string): Promise<void> {
    await this.prisma.appSession.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  private async mint(
    user: { id: string; sbcUserId: string; role: Role },
    familyId: string,
    meta: SessionMeta,
    prisma: PrismaService = this.prisma,
  ): Promise<{ tokens: IssuedTokens; sessionId: string }> {
    const refreshToken = this.enc.randomToken();
    const refreshTokenHash = this.enc.hmac(refreshToken);
    const expiresAt = new Date(Date.now() + this.refreshTtl * 1000);

    const session = await prisma.appSession.create({
      data: {
        userId: user.id,
        refreshTokenHash,
        familyId,
        deviceId: meta.deviceId,
        userAgent: meta.userAgent,
        ip: meta.ip,
        expiresAt,
      },
    });

    const accessToken = await this.jwt.signAsync(
      { sub: user.id, sbcUserId: user.sbcUserId, role: user.role, type: 'access' },
      { secret: this.accessSecret, expiresIn: this.accessTtl },
    );

    return {
      tokens: { accessToken, refreshToken, expiresIn: this.accessTtl, tokenType: 'Bearer' },
      sessionId: session.id,
    };
  }
}

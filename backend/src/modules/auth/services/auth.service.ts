import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { User } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { SbcClientService } from '../../sbc-client/sbc-client.service';
import { SbcUser } from '../../sbc-client/interfaces/sbc.interface';
import { IssuedTokens, SessionMeta, TokenService } from './token.service';
import { SbcTokenService } from './sbc-token.service';

export interface PublicUser {
  id: string;
  sbcUserId: string;
  name: string | null;
  email: string | null;
  phoneNumber: string | null;
  country: string | null;
  avatarUrl: string | null;
  subscriptionTypes: string[];
  isActivated: boolean;
  role: User['role'];
}

export interface AuthResult {
  user: PublicUser;
  tokens: IssuedTokens;
}

/**
 * A valid bcrypt hash compared against when no matching user is found, so a
 * wrong email costs the same time as a wrong password — no user enumeration.
 */
const DUMMY_HASH = bcrypt.hashSync('unused-placeholder-for-constant-time', 10);

/**
 * Orchestrates the SSO login lifecycle: exchange code → upsert local user from
 * the SBC profile snapshot → persist encrypted SBC tokens → issue our own
 * session. Auth is fully delegated to SBC (cahier §4) — no local passwords.
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly sbc: SbcClientService,
    private readonly sbcTokens: SbcTokenService,
    private readonly tokens: TokenService,
  ) {}

  async ssoCallback(
    code: string,
    meta: SessionMeta,
    redirectUri?: string,
  ): Promise<AuthResult> {
    const exchange = await this.sbc.exchangeCode(code, redirectUri);
    const user = await this.upsertFromSbc(exchange.user);
    await this.sbcTokens.storeFromExchange(user.id, exchange);

    const tokens = await this.tokens.issueForUser(
      { id: user.id, sbcUserId: user.sbcUserId, role: user.role },
      meta,
    );
    this.logger.log(`SSO login for sbcUserId=${user.sbcUserId}`);
    return { user: this.toPublic(user), tokens };
  }

  /**
   * Email + password login (admin back-office). Only accounts with a stored
   * passwordHash can use it; everyone else stays SSO-only. Errors are generic
   * and a bcrypt compare always runs, so a bad email and a bad password are
   * indistinguishable (no enumeration, no timing signal).
   */
  async loginWithPassword(
    email: string,
    password: string,
    meta: SessionMeta,
  ): Promise<AuthResult> {
    const normalized = email.trim().toLowerCase();
    const user = await this.prisma.user.findFirst({
      where: {
        email: { equals: normalized, mode: 'insensitive' },
        passwordHash: { not: null },
        deletedAt: null,
      },
    });
    const ok = await bcrypt.compare(password, user?.passwordHash ?? DUMMY_HASH);
    if (!user || !ok) {
      throw new UnauthorizedException('Email ou mot de passe incorrect');
    }
    await this.prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });
    const tokens = await this.tokens.issueForUser(
      { id: user.id, sbcUserId: user.sbcUserId, role: user.role },
      meta,
    );
    this.logger.log(`Password login for ${normalized} (role=${user.role})`);
    return { user: this.toPublic(user), tokens };
  }

  refresh(refreshToken: string, meta: SessionMeta): Promise<IssuedTokens> {
    return this.tokens.rotate(refreshToken, meta);
  }

  logout(refreshToken: string): Promise<void> {
    return this.tokens.revoke(refreshToken);
  }

  async me(userId: string): Promise<PublicUser> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    return this.toPublic(user);
  }

  /**
   * Pull a fresh profile from SBC /userinfo and update the local snapshot.
   * Subscription state changes, so callers that need current entitlement use this.
   */
  async refreshProfile(userId: string): Promise<PublicUser> {
    const accessToken = await this.sbcTokens.getValidAccessToken(userId);
    const sbcUser = await this.sbc.getUserInfo(accessToken);
    const user = await this.upsertFromSbc(sbcUser);
    return this.toPublic(user);
  }

  private async upsertFromSbc(sbcUser: SbcUser): Promise<User> {
    const snapshot = {
      name: sbcUser.name,
      email: sbcUser.email,
      phoneNumber: sbcUser.phoneNumber,
      country: sbcUser.country,
      avatarUrl: sbcUser.avatarUrl,
      subscriptionTypes: sbcUser.subscriptionTypes ?? [],
      isActivated: sbcUser.isActivated,
      lastLoginAt: new Date(),
    };
    return this.prisma.user.upsert({
      where: { sbcUserId: sbcUser.id },
      create: { sbcUserId: sbcUser.id, ...snapshot },
      update: snapshot,
    });
  }

  private toPublic(user: User): PublicUser {
    return {
      id: user.id,
      sbcUserId: user.sbcUserId,
      name: user.name,
      email: user.email,
      phoneNumber: user.phoneNumber,
      country: user.country,
      avatarUrl: user.avatarUrl,
      subscriptionTypes: user.subscriptionTypes,
      isActivated: user.isActivated,
      role: user.role,
    };
  }
}

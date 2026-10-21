import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { MemberSource, User } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { SbcClientService } from '../../sbc-client/sbc-client.service';
import { SbcUser } from '../../sbc-client/interfaces/sbc.interface';
import { toInternationalPhone } from '../../../common/utils/phone';
import { PhoneLoginDto, RegisterDto } from '../dto/network-account.dto';
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
  /** SBC: signed in through SBC. NETWORK: an SBC Network account of its own. */
  origin: User['origin'];
}

export interface AuthResult {
  user: PublicUser;
  tokens: IssuedTokens;
}

/**
 * A valid bcrypt hash compared against when no matching user is found, so a
 * wrong email costs the same time as a wrong password — no user enumeration.
 */
/** Whole years from `birthDate` to today. */
function ageOn(birthDate: Date, today = new Date()): number {
  const years = today.getUTCFullYear() - birthDate.getUTCFullYear();
  const beforeBirthday =
    today.getUTCMonth() < birthDate.getUTCMonth() ||
    (today.getUTCMonth() === birthDate.getUTCMonth() &&
      today.getUTCDate() < birthDate.getUTCDate());
  return beforeBirthday ? years - 1 : years;
}

const DUMMY_HASH = bcrypt.hashSync('unused-placeholder-for-constant-time', 10);

/**
 * Orchestrates the SSO login lifecycle: exchange code → upsert local user from
 * the SBC profile snapshot → persist encrypted SBC tokens → issue our own
 * session. SBC members sign in through SBC (cahier §4); SBC Network accounts,
 * which have no SBC account, sign in with their WhatsApp number and password.
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly sbc: SbcClientService,
    private readonly sbcTokens: SbcTokenService,
    private readonly tokens: TokenService,
    private readonly config: ConfigService,
  ) {}

  async ssoCallback(code: string, meta: SessionMeta, redirectUri?: string): Promise<AuthResult> {
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
  async loginWithPassword(email: string, password: string, meta: SessionMeta): Promise<AuthResult> {
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

  /**
   * Create an SBC Network account: it lives in SBC Network only, with no SBC
   * account behind it. Its profile is mirrored as a member at once, so it can
   * join "Augmenter mes vues WhatsApp" and be saved like anyone else.
   */
  async register(dto: RegisterDto, meta: SessionMeta): Promise<AuthResult> {
    const phoneNumber = this.phone(dto.phoneNumber, dto.country);
    const birthDate = new Date(`${dto.birthDate.slice(0, 10)}T00:00:00Z`);
    const age = ageOn(birthDate);
    if (age < 13 || age > 110) throw new BadRequestException('Date de naissance invalide');
    const interests = [...new Set(dto.interests.map((i) => i.trim()).filter(Boolean))];
    const taken = await this.prisma.user.findFirst({
      where: { origin: 'NETWORK', phoneNumber, deletedAt: null },
      select: { id: true },
    });
    if (taken) {
      throw new ConflictException(
        'Un compte SBC Network existe déjà avec ce numéro : connecte-toi',
      );
    }

    const sbcUserId = `net_${randomUUID()}`;
    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = await this.prisma.$transaction(async (tx) => {
      const created = await tx.user.create({
        data: {
          sbcUserId,
          origin: 'NETWORK',
          name: dto.name,
          phoneNumber,
          country: dto.country,
          birthDate,
          passwordHash,
          isActivated: true,
          lastLoginAt: new Date(),
        },
      });
      await tx.member.create({
        data: {
          sbcId: sbcUserId,
          name: dto.name,
          phoneNumber,
          country: dto.country,
          city: dto.region,
          profession: dto.profession,
          sex: dto.sex,
          age,
          interests,
          source: MemberSource.NETWORK,
        },
      });
      return created;
    });

    const tokens = await this.tokens.issueForUser(
      { id: user.id, sbcUserId: user.sbcUserId, role: user.role },
      meta,
    );
    this.logger.log(`SBC Network account created (${user.id})`);
    return { user: this.toPublic(user), tokens };
  }

  /**
   * Sign in to an SBC Network account with its WhatsApp number. Same rules as
   * the password login: a generic error and a bcrypt compare every time.
   */
  async loginWithPhone(dto: PhoneLoginDto, meta: SessionMeta): Promise<AuthResult> {
    const phoneNumber = toInternationalPhone(dto.phoneNumber, dto.country);
    const user = phoneNumber ? await this.phoneAccount(phoneNumber) : null;
    const ok = await bcrypt.compare(dto.password, user?.passwordHash ?? DUMMY_HASH);
    if (!user || !ok) {
      throw new UnauthorizedException('Numéro ou mot de passe incorrect');
    }
    await this.prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
    // Keeps the age criteria match on current; SBC does this for its members.
    if (user.birthDate) {
      await this.prisma.member.updateMany({
        where: { sbcId: user.sbcUserId },
        data: { age: ageOn(user.birthDate) },
      });
    }
    const tokens = await this.tokens.issueForUser(
      { id: user.id, sbcUserId: user.sbcUserId, role: user.role },
      meta,
    );
    return { user: this.toPublic(user), tokens };
  }

  /**
   * The account a WhatsApp number signs in to: an SBC Network account, or the
   * one SBC account set aside for App Review. That one is matched on the
   * number configured for it, not its stored one, which SBC rewrites at every
   * profile refresh. Its SBC session was opened once through SSO and is kept
   * alive by SbcTokenService, so it has the whole directory.
   */
  private phoneAccount(phoneNumber: string): Promise<User | null> {
    const review = this.config.get<{ sbcUserId: string; phone: string }>('appReview');
    if (review?.sbcUserId && review.phone && toInternationalPhone(review.phone) === phoneNumber) {
      return this.prisma.user.findFirst({
        where: { sbcUserId: review.sbcUserId, passwordHash: { not: null }, deletedAt: null },
      });
    }
    return this.prisma.user.findFirst({
      where: { origin: 'NETWORK', phoneNumber, passwordHash: { not: null }, deletedAt: null },
    });
  }

  private phone(raw: string, country: string): string {
    const phone = toInternationalPhone(raw, country);
    if (!phone) throw new BadRequestException('Numéro WhatsApp invalide');
    return phone;
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
    // An SBC Network account has no SBC profile to pull: its own is current.
    const local = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (local.origin === 'NETWORK') return this.toPublic(local);
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
      origin: user.origin,
    };
  }
}

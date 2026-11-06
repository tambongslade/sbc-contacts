import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SyncStatus, User } from '@prisma/client';
import { paginate, PaginatedResult } from '../../common/dto/pagination.dto';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { StatusBoostService } from './status-boost.service';

/**
 * SBC subscription types that mean "Mise en avant". SBC sells it next to
 * CLASSIQUE and CIBLE and reports it in the member's subscription types;
 * whichever name SBC settles on goes here.
 */
export const SPOTLIGHT_SUBSCRIPTION_TYPES = ['MISE_EN_AVANT', 'SPOTLIGHT'];

/** Price shown where the store rules allow it (not on iOS). */
export const SPOTLIGHT_PRICE_FCFA = 3000;

/** How many featured members a section shows at once. */
export const SPOTLIGHT_TAKE = 5;

/** One featured member, shaped like a "Augmenter mes vues" entry so the apps reuse its row. */
export interface SpotlightEntry {
  sbcId: string;
  name: string | null;
  phoneNumber: string;
  avatarUrl: string | null;
  country: string | null;
  subscriptionTypes: string[];
  /** This member already saved the caller: saving back completes the pair. */
  savedMe: boolean;
}

export type SpotlightSource = 'sbc' | 'admin';

export interface SpotlightStatus {
  active: boolean;
  /** End of an admin activation; null when it comes from the SBC subscription. */
  until: Date | null;
  source: SpotlightSource | null;
  priceFcfa: number;
}

export function spotlightSource(
  user: Pick<User, 'subscriptionTypes' | 'spotlightUntil'>,
  now = new Date(),
): SpotlightSource | null {
  const types = user.subscriptionTypes.map((t) => t.toUpperCase());
  if (SPOTLIGHT_SUBSCRIPTION_TYPES.some((t) => types.includes(t))) return 'sbc';
  if (user.spotlightUntil && user.spotlightUntil > now) return 'admin';
  return null;
}

/**
 * "Mise en avant": a member who pays for it is shown first in "Qui m'a
 * enregistré" and "Augmenter mes vues WhatsApp", so the people browsing them
 * save their number. Each viewer stops seeing a featured member once they
 * have saved them: that contact is won.
 */
@Injectable()
export class SpotlightService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly boost: StatusBoostService,
    private readonly audit: AuditService,
  ) {}

  async me(userId: string, now = new Date()): Promise<SpotlightStatus> {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { subscriptionTypes: true, spotlightUntil: true },
    });
    const source = spotlightSource(user, now);
    return {
      active: source !== null,
      until: source === 'admin' ? user.spotlightUntil : null,
      source,
      priceFcfa: SPOTLIGHT_PRICE_FCFA,
    };
  }

  /**
   * Featured members this viewer has not saved yet, in random order so every
   * paying member gets their turn at the top.
   */
  async featured(userId: string, now = new Date()): Promise<SpotlightEntry[]> {
    const me = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { sbcUserId: true },
    });
    const candidates = await this.prisma.user.findMany({
      where: {
        id: { not: userId },
        deletedAt: null,
        // Nobody can save a member without a number.
        phoneNumber: { not: null },
        OR: [
          { subscriptionTypes: { hasSome: spotlightTypeVariants() } },
          { spotlightUntil: { gt: now } },
        ],
      } satisfies Prisma.UserWhereInput,
    });
    if (!candidates.length) return [];

    // Saving records against the member mirror; make sure it knows them.
    const members = await this.boost.mirror(candidates);
    const memberBySbc = new Map(members.map((m) => [m.sbcId, m.id]));
    const [synced, added, savers] = await Promise.all([
      this.prisma.syncedContact.findMany({
        where: { userId, memberId: { in: members.map((m) => m.id) }, status: SyncStatus.SYNCED },
        select: { memberId: true },
      }),
      this.prisma.addedEvent.findMany({
        where: { actorId: userId, targetMemberSbcId: { in: candidates.map((c) => c.sbcUserId) } },
        select: { targetMemberSbcId: true },
      }),
      this.prisma.addedEvent.findMany({
        where: { targetMemberSbcId: me.sbcUserId, actorId: { in: candidates.map((c) => c.id) } },
        select: { actorId: true },
      }),
    ]);
    const syncedIds = new Set(synced.map((s) => s.memberId));
    const addedSbc = new Set(added.map((a) => a.targetMemberSbcId));
    const saverIds = new Set(savers.map((s) => s.actorId));

    const unsaved = candidates.filter(
      (c) => !addedSbc.has(c.sbcUserId) && !syncedIds.has(memberBySbc.get(c.sbcUserId) ?? ''),
    );
    return shuffle(unsaved)
      .slice(0, SPOTLIGHT_TAKE)
      .map((u) => ({
        sbcId: u.sbcUserId,
        name: u.name,
        phoneNumber: u.phoneNumber!,
        avatarUrl: u.avatarUrl,
        country: u.country,
        subscriptionTypes: u.subscriptionTypes,
        savedMe: saverIds.has(u.id),
      }));
  }

  /** Back-office: members to feature, searchable, featured ones first. */
  async adminList(
    query: { search?: string; featured?: 'on' | 'off'; page: number; limit: number },
    now = new Date(),
  ): Promise<PaginatedResult<SpotlightAdminRow>> {
    const featured: Prisma.UserWhereInput = {
      OR: [
        { subscriptionTypes: { hasSome: spotlightTypeVariants() } },
        { spotlightUntil: { gt: now } },
      ],
    };
    const search = query.search?.trim();
    const where: Prisma.UserWhereInput = {
      deletedAt: null,
      AND: [
        search
          ? {
              OR: [
                { name: { contains: search, mode: 'insensitive' } },
                { email: { contains: search, mode: 'insensitive' } },
                { phoneNumber: { contains: search.replace(/\s+/g, '') } },
              ],
            }
          : {},
        query.featured === 'on' ? featured : query.featured === 'off' ? { NOT: featured } : {},
      ],
    };
    const [users, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        orderBy: [{ spotlightUntil: { sort: 'desc', nulls: 'last' } }, { name: 'asc' }],
        skip: (query.page - 1) * query.limit,
        take: query.limit,
      }),
      this.prisma.user.count({ where }),
    ]);
    const items = users.map((u) => {
      const source = spotlightSource(u, now);
      return {
        userId: u.id,
        name: u.name,
        phoneNumber: u.phoneNumber,
        email: u.email,
        country: u.country,
        avatarUrl: u.avatarUrl,
        spotlightUntil: u.spotlightUntil,
        active: source !== null,
        source,
      };
    });
    return paginate(items, total, query.page, query.limit);
  }

  /** Back-office: switch a member's spotlight on until a date, or off (null). */
  async setUntil(adminId: string, userId: string, until: Date | null) {
    const before = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { spotlightUntil: true },
    });
    if (!before) throw new NotFoundException('Membre introuvable');
    const after = await this.prisma.user.update({
      where: { id: userId },
      data: { spotlightUntil: until },
      select: { id: true, spotlightUntil: true },
    });
    await this.audit.record({
      actorId: adminId,
      action: 'spotlight.set',
      resource: `User:${userId}`,
      before,
      after,
    });
    return after;
  }
}

/** One member as the back-office's "Mise en avant" page lists them. */
export interface SpotlightAdminRow {
  userId: string;
  name: string | null;
  phoneNumber: string | null;
  email: string | null;
  country: string | null;
  avatarUrl: string | null;
  spotlightUntil: Date | null;
  active: boolean;
  source: SpotlightSource | null;
}

/** `hasSome` is case-sensitive; SBC has sent both cases before. */
function spotlightTypeVariants(): string[] {
  return SPOTLIGHT_SUBSCRIPTION_TYPES.flatMap((t) => [t, t.toLowerCase()]);
}

function shuffle<T>(items: T[]): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

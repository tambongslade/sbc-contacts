import { ForbiddenException, Injectable } from '@nestjs/common';
import { Member, Prisma, SyncStatus } from '@prisma/client';
import { PaginatedResult, paginate } from '../../common/dto/pagination.dto';
import { toIsoCountry } from '../../common/utils/country';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { MemberMatchService } from '../members/member-match.service';
import { StatusBoostQueryDto } from './status-boost.dto';
import {
  ADVANCED_FILTERS_MESSAGE,
  BoostFilters,
  FilterAccess,
  filterAccessFor,
  hasAdvancedFilters,
  hasFilters,
} from './status-boost.filters';

/** One member in "Je veux augmenter mon nombre de vues en statut WhatsApp". */
export interface StatusBoostEntry {
  sbcId: string;
  name: string | null;
  phoneNumber: string;
  avatarUrl: string | null;
  country: string | null;
  subscriptionTypes: string[];
  since: Date | null;
  /** Already in the caller's phone, as far as the app recorded. */
  savedByMe: boolean;
  /** This member already saved the caller — the one to save back first. */
  savedMe: boolean;
}

export interface StatusBoostPage extends PaginatedResult<StatusBoostEntry> {
  /** Subscription types present among participants, for the filter chips. */
  subscriptionTypes: string[];
}

/**
 * WhatsApp only shows a status to people who saved each other's number, so
 * members who want more views opt in here and save one another. The section
 * lists everyone who opted in; saving goes through the usual contact recording
 * (it lands in "Mes contacts SBC" and tells the other side "Quelqu'un t'a
 * enregistré"), which is what nudges them to save back.
 */
@Injectable()
export class StatusBoostService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly match: MemberMatchService,
  ) {}

  async me(userId: string) {
    const [user, participants, criteria] = await this.prisma.$transaction([
      this.prisma.user.findUniqueOrThrow({
        where: { id: userId },
        select: {
          statusBoostOptIn: true,
          statusBoostSince: true,
          phoneNumber: true,
          subscriptionTypes: true,
        },
      }),
      this.prisma.user.count({ where: { statusBoostOptIn: true, deletedAt: null } }),
      this.prisma.syncCriteria.findFirst({
        where: { userId, statusBoost: true },
        select: { id: true, isActive: true },
      }),
    ]);
    return {
      optIn: user.statusBoostOptIn,
      since: user.statusBoostSince,
      participants,
      // Without a number on the SBC account nobody can save you.
      hasPhone: Boolean(user.phoneNumber?.trim()),
      // The member's "save everyone in the list" criteria, once created.
      criteria,
      // Which filters the member's subscription opens on the list.
      filterAccess: filterAccessFor(user.subscriptionTypes),
    };
  }

  async filterAccess(userId: string): Promise<FilterAccess> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { subscriptionTypes: true },
    });
    return filterAccessFor(user?.subscriptionTypes ?? []);
  }

  /** Ciblé filters by everything; anyone else by country only. */
  async assertFiltersAllowed(userId: string, f: BoostFilters): Promise<void> {
    if (hasAdvancedFilters(f) && (await this.filterAccess(userId)) !== 'all') {
      throw new ForbiddenException(ADVANCED_FILTERS_MESSAGE);
    }
  }

  async setOptIn(userId: string, optIn: boolean) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: { statusBoostOptIn: optIn, statusBoostSince: optIn ? new Date() : null },
    });
    if (optIn) {
      await this.mirror([user]);
    } else {
      // Someone who left no longer expects to be saved by the list, and must
      // not go on saving the people still in it.
      await this.prisma.syncCriteria.updateMany({
        where: { userId, statusBoost: true, isActive: true },
        data: { isActive: false },
      });
    }
    return this.me(userId);
  }

  async isOptedIn(userId: string): Promise<boolean> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { statusBoostOptIn: true },
    });
    return Boolean(user?.statusBoostOptIn);
  }

  /**
   * Member mirror rows for everyone else in the list: what a "Augmenter mes
   * vues WhatsApp" criteria matches. `since` keeps only those who joined after
   * it, which is what "new" means for this list.
   */
  async participants(
    userId: string,
    opts: { since?: Date; take?: number } = {},
  ): Promise<Member[]> {
    const users = await this.prisma.user.findMany({
      where: {
        ...this.othersWhere(userId),
        ...(opts.since ? { statusBoostSince: { gt: opts.since } } : {}),
      },
      orderBy: [{ statusBoostSince: 'desc' }, { id: 'asc' }],
      take: opts.take,
    });
    if (!users.length) return [];
    // Joining mirrors the member already; only someone who joined before that
    // existed can be missing, so upsert just those.
    const mirrored = await this.prisma.member.findMany({
      where: { sbcId: { in: users.map((u) => u.sbcUserId) } },
    });
    const known = new Set(mirrored.map((m) => m.sbcId));
    const missing = users.filter((u) => !known.has(u.sbcUserId));
    return [...mirrored, ...(missing.length ? await this.mirror(missing) : [])];
  }

  /** Everyone in the list the caller could save: not themselves, and with a number. */
  private othersWhere(userId: string): Prisma.UserWhereInput {
    return {
      statusBoostOptIn: true,
      deletedAt: null,
      id: { not: userId },
      phoneNumber: { not: null },
    };
  }

  async list(userId: string, q: StatusBoostQueryDto): Promise<StatusBoostPage> {
    const me = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { sbcUserId: true },
    });
    const term = q.search?.trim();
    const where: Prisma.UserWhereInput = {
      ...this.othersWhere(userId),
      ...(hasFilters(q) ? { sbcUserId: { in: await this.matching(userId, q) } } : {}),
      ...(q.subscription ? { subscriptionTypes: { has: q.subscription } } : {}),
      ...(term
        ? {
            OR: [
              { name: { contains: term, mode: 'insensitive' } },
              { phoneNumber: { contains: term.replace(/\D/g, '') || term } },
            ],
          }
        : {}),
    };
    const [rows, total, all] = await this.prisma.$transaction([
      this.prisma.user.findMany({
        where,
        // Newest first: a member who just joined is the one nobody saved yet.
        orderBy: [{ statusBoostSince: 'desc' }, { id: 'asc' }],
        skip: q.skip,
        take: q.limit,
      }),
      this.prisma.user.count({ where }),
      this.prisma.user.findMany({
        where: { statusBoostOptIn: true, deletedAt: null },
        select: { subscriptionTypes: true },
      }),
    ]);

    // Saving records against the member mirror, which may not know a member
    // who has only logged in to the app; make sure it does.
    const members = await this.mirror(rows);
    const memberIds = members.map((m) => m.id);
    const [saved, savers] = await Promise.all([
      this.prisma.syncedContact.findMany({
        where: { userId, memberId: { in: memberIds }, status: SyncStatus.SYNCED },
        select: { memberId: true },
      }),
      this.prisma.addedEvent.findMany({
        where: { targetMemberSbcId: me.sbcUserId, actorId: { in: rows.map((r) => r.id) } },
        select: { actorId: true },
      }),
    ]);
    const savedIds = new Set(saved.map((s) => s.memberId));
    const memberBySbc = new Map(members.map((m) => [m.sbcId, m.id]));
    const saverIds = new Set(savers.map((s) => s.actorId));

    const items: StatusBoostEntry[] = rows.map((u) => ({
      sbcId: u.sbcUserId,
      name: u.name,
      phoneNumber: u.phoneNumber!,
      avatarUrl: u.avatarUrl,
      country: u.country,
      subscriptionTypes: u.subscriptionTypes,
      since: u.statusBoostSince,
      savedByMe: savedIds.has(memberBySbc.get(u.sbcUserId) ?? ''),
      savedMe: saverIds.has(u.id),
    }));
    const types = [...new Set(all.flatMap((u) => u.subscriptionTypes))].sort();
    return { ...paginate(items, total, q.page, q.limit), subscriptionTypes: types };
  }

  /**
   * SBC ids of the participants whose profile matches the filters. Profession,
   * interests, age… live on the member mirror, not the account, so the filters
   * run there, against the participants only.
   */
  private async matching(userId: string, f: BoostFilters): Promise<string[]> {
    await this.assertFiltersAllowed(userId, f);
    const participants = await this.participants(userId);
    if (!participants.length) return [];
    const rows = await this.prisma.member.findMany({
      where: this.match.buildWhere({
        countries: f.countries ?? [],
        cities: f.cities ?? [],
        professions: f.professions ?? [],
        interests: f.interests ?? [],
        sex: f.sex,
        ageMin: f.ageMin,
        ageMax: f.ageMax,
        sbcIds: participants.map((m) => m.sbcId),
      }),
      select: { sbcId: true },
    });
    return rows.map((r) => r.sbcId);
  }

  /** Member mirror rows for these users, created from their SBC snapshot when missing. */
  private async mirror(
    users: Array<{
      sbcUserId: string;
      name: string | null;
      phoneNumber: string | null;
      country: string | null;
      avatarUrl: string | null;
    }>,
  ) {
    return Promise.all(
      users.map((u) =>
        this.prisma.member.upsert({
          where: { sbcId: u.sbcUserId },
          // An existing mirror row is SBC's directory data; leave it alone.
          update: {},
          create: {
            sbcId: u.sbcUserId,
            name: u.name,
            phoneNumber: u.phoneNumber,
            country: toIsoCountry(u.country) ?? u.country,
            avatarUrl: u.avatarUrl,
          },
        }),
      ),
    );
  }
}

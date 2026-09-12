import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Member, SyncCriteria } from '@prisma/client';
import { Logger } from '@nestjs/common';
import {
  PaginatedResult,
  PaginationQueryDto,
  paginate,
} from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { MemberMatchService } from '../../members/member-match.service';
import { MembersService } from '../../members/members.service';
import { NotificationsService } from '../../notifications/notifications.service';
import { MatchCriteria } from '../../members/member.view';
import {
  ReportSyncDto,
  ReportedStatus,
  StartSyncDto,
  SyncContactsQueryDto,
} from '../dto/sync.dto';

/** One person who saved you (cahier §21). */
export interface SavedMeEntry {
  actorSbcId: string;
  name: string | null;
  profession: string | null;
  city: string | null;
  country: string | null;
  avatarUrl: string | null;
  phoneNumber: string | null;
  savedAt: Date;
}

export interface SyncTargetItem {
  memberSbcId: string;
  name: string | null;
  firstName: string | null;
  profession: string | null;
  city: string | null;
  country: string | null;
  avatarUrl: string | null;
  phoneNumber: string | null;
  alreadySynced: boolean; // dedup hint (cahier §15); client still checks the phone
}

export interface StartSyncResult {
  syncRunId: string;
  deviceId: string;
  matchCount: number;
  pendingCount: number;
  items: SyncTargetItem[];
}

const DEFAULT_DEVICE = 'default';
const MAX_TARGETS = 500;

/**
 * Orchestrates a sync run (cahier §10–§17). The backend resolves the target
 * members and tracks their per-device sync state; the actual write to the phone
 * book happens client-side via native APIs, then the client reports outcomes.
 */
@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);

  /// A run still open this long after it started is not coming back.
  private static readonly ABANDONED_AFTER_MS = 30 * 60 * 1000;

  constructor(
    private readonly prisma: PrismaService,
    private readonly members: MembersService,
    private readonly match: MemberMatchService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
  ) {}

  async start(userId: string, dto: StartSyncDto, ip?: string): Promise<StartSyncResult> {
    const deviceId = dto.deviceId ?? DEFAULT_DEVICE;
    const { members, criteriaId } = await this.resolveTargets(userId, dto);

    // Existing per-device state for dedup.
    const existing = await this.prisma.syncedContact.findMany({
      where: { userId, deviceId, memberId: { in: members.map((m) => m.id) } },
      select: { memberId: true, status: true },
    });
    const statusByMember = new Map(existing.map((e) => [e.memberId, e.status]));

    // Any run of this user's still open when a new one starts was abandoned:
    // the client runs one at a time, and a run only leaves RUNNING by
    // reporting. Reclaiming here is what stops the queue growing forever.
    await this.reclaimAbandonedRuns(userId, { all: true });

    const run = await this.prisma.syncRun.create({
      data: { userId, criteriaId, deviceId, status: 'RUNNING', matchCount: members.length },
    });

    // Mark not-yet-synced members PENDING (idempotent upsert per device), and
    // stamp them with this run so they can be taken back if it never reports.
    let pendingCount = 0;
    for (const m of members) {
      const alreadySynced = statusByMember.get(m.id) === 'SYNCED';
      if (!alreadySynced) pendingCount++;
      await this.prisma.syncedContact.upsert({
        where: { userId_memberId_deviceId: { userId, memberId: m.id, deviceId } },
        create: {
          userId,
          memberId: m.id,
          deviceId,
          status: 'PENDING',
          syncRunId: run.id,
        },
        update: alreadySynced ? {} : { status: 'PENDING', syncRunId: run.id },
      });
    }

    await this.audit.record({
      actorId: userId,
      action: 'sync.start',
      resource: `SyncRun:${run.id}`,
      metadata: { criteriaId, deviceId, matchCount: members.length, pendingCount },
      ip,
    });

    return {
      syncRunId: run.id,
      deviceId,
      matchCount: members.length,
      pendingCount,
      items: members.map((m) => ({
        memberSbcId: m.sbcId,
        name: m.name,
        firstName: m.firstName,
        profession: m.profession,
        city: m.city,
        country: m.country,
        avatarUrl: m.avatarUrl,
        phoneNumber: m.phoneNumber,
        alreadySynced: statusByMember.get(m.id) === 'SYNCED',
      })),
    };
  }

  async report(userId: string, runId: string, dto: ReportSyncDto, ip?: string) {
    const run = await this.prisma.syncRun.findFirst({ where: { id: runId, userId } });
    if (!run) throw new NotFoundException('Sync run not found');
    if (run.status === 'COMPLETED') throw new ConflictException('Sync run already finalized');

    const deviceId = run.deviceId ?? DEFAULT_DEVICE;
    const sbcIds = dto.results.map((r) => r.memberSbcId);
    const members = await this.members.findManyBySbcIds(sbcIds);
    const memberBySbcId = new Map(members.map((m) => [m.sbcId, m]));

    let syncedCount = 0;
    let failedCount = 0;

    for (const result of dto.results) {
      const member = memberBySbcId.get(result.memberSbcId);
      if (!member) continue;
      const isSynced = result.status === ReportedStatus.SYNCED;
      isSynced ? syncedCount++ : failedCount++;

      // Upsert, not update: a report that arrives after its run was reclaimed
      // still describes a contact that is on the phone, and dropping it would
      // hide a contact the member can see in their own address book.
      const outcome = {
        status: isSynced ? ('SYNCED' as const) : ('FAILED' as const),
        deviceContactId: result.deviceContactId,
        syncedAt: isSynced ? new Date() : null,
        // The run is done with this row either way; only PENDING rows are
        // owned by a run.
        syncRunId: null,
      };
      await this.prisma.syncedContact.upsert({
        where: { userId_memberId_deviceId: { userId, memberId: member.id, deviceId } },
        create: { userId, memberId: member.id, deviceId, ...outcome },
        update: outcome,
      });

      // "Qui m'a ajouté ?" — record only technically-confirmed additions (§21).
      if (isSynced) {
        await this.prisma.addedEvent.create({
          data: { actorId: userId, targetMemberSbcId: member.sbcId },
        });
        // ...and tell the person who was saved. The event alone was write-only:
        // nothing read it, so being added to someone's phone stayed invisible
        // to the one being added, which is the whole point of §21.
        await this.notifySaved(userId, member.sbcId);
      }
    }

    const updated = await this.prisma.syncRun.update({
      where: { id: run.id },
      data: { status: 'COMPLETED', syncedCount, failedCount, finishedAt: new Date() },
    });

    await this.audit.record({
      actorId: userId,
      action: 'sync.report',
      resource: `SyncRun:${run.id}`,
      metadata: { syncedCount, failedCount },
      ip,
    });

    return {
      syncRunId: updated.id,
      status: updated.status,
      syncedCount: updated.syncedCount,
      failedCount: updated.failedCount,
      finishedAt: updated.finishedAt,
    };
  }

  /**
   * Close runs that were started and never reported, and take their queue back.
   *
   * A run leaves RUNNING only by reporting, so one that is still open is one
   * the client abandoned — the member backed out of the review screen, refused
   * the contacts permission, or the app was killed mid-write. Its targets were
   * already marked PENDING, and nothing ever cleared them: that is how a
   * dashboard came to read "156 en attente" for work nobody was waiting on.
   *
   * Only rows still PENDING *and* stamped with the reclaimed run are removed,
   * so a contact that was actually written is never touched.
   *
   * With `all`, every open run of this user is reclaimed — used when a new run
   * starts, since the client runs one at a time. Otherwise only runs older
   * than [ABANDONED_AFTER_MS] are, which lets the dashboard heal itself for a
   * member who simply never syncs again.
   */
  private async reclaimAbandonedRuns(
    userId: string,
    { all = false }: { all?: boolean } = {},
  ): Promise<number> {
    const open = await this.prisma.syncRun.findMany({
      where: {
        userId,
        status: { in: ['RUNNING', 'PENDING'] },
        ...(all
          ? {}
          : { startedAt: { lt: new Date(Date.now() - SyncService.ABANDONED_AFTER_MS) } }),
      },
      select: { id: true },
    });
    if (open.length === 0) return 0;

    const ids = open.map((r) => r.id);
    const [removed] = await this.prisma.$transaction([
      this.prisma.syncedContact.deleteMany({
        where: { userId, status: 'PENDING', syncRunId: { in: ids } },
      }),
      this.prisma.syncRun.updateMany({
        where: { id: { in: ids } },
        data: { status: 'ABANDONED', finishedAt: new Date() },
      }),
    ]);
    this.logger.log(
      `Reclaimed ${open.length} abandoned run(s) for ${userId}, ` +
        `${removed.count} queued contact(s) released`,
    );
    return removed.count;
  }

  /**
   * Notify the saved member, when that member is also an app user.
   *
   * A member is only reachable if they have signed in here — SBC ids and our
   * user ids share a namespace (`User.sbcUserId`), so the lookup is direct.
   * Never notifies you about your own sync, and never fails the report: the
   * contacts are already on the device, and a notification is not worth
   * losing that bookkeeping over.
   */
  private async notifySaved(actorUserId: string, targetMemberSbcId: string): Promise<void> {
    try {
      const [target, actor] = await Promise.all([
        this.prisma.user.findUnique({
          where: { sbcUserId: targetMemberSbcId },
          select: { id: true },
        }),
        this.prisma.user.findUnique({
          where: { id: actorUserId },
          select: { id: true, name: true },
        }),
      ]);
      if (!target || !actor || target.id === actorUserId) return;
      await this.notifications.notifyContactSaved(target.id, actor);
    } catch (error) {
      this.logger.warn(
        `notifyContactSaved failed for ${targetMemberSbcId}: ${String(error)}`,
      );
    }
  }

  /**
   * "Qui m'a enregistré ?" (§21) — the people who have saved YOU.
   *
   * Keyed on the caller's own SBC id, because that is what an AddedEvent
   * records as its target. Only confirmed additions are in the table, so this
   * never claims someone saved you when they merely looked at your profile.
   */
  async savedMe(
    userSbcId: string,
    pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<SavedMeEntry>> {
    const [events, total] = await this.prisma.$transaction([
      this.prisma.addedEvent.findMany({
        where: { targetMemberSbcId: userSbcId },
        orderBy: { confirmedAt: 'desc' },
        skip: pagination.skip,
        take: pagination.limit,
        include: {
          actor: { select: { id: true, sbcUserId: true, name: true, phoneNumber: true } },
        },
      }),
      this.prisma.addedEvent.count({ where: { targetMemberSbcId: userSbcId } }),
    ]);

    // The actor's directory profile, when we have mirrored it, adds the
    // profession/location that make a name recognisable.
    const sbcIds = events.map((e) => e.actor.sbcUserId);
    const profiles = sbcIds.length
      ? await this.prisma.member.findMany({ where: { sbcId: { in: sbcIds } } })
      : [];
    const bySbcId = new Map(profiles.map((m) => [m.sbcId, m]));

    const items = events.map((e) => {
      const profile = bySbcId.get(e.actor.sbcUserId);
      return {
        actorSbcId: e.actor.sbcUserId,
        name: e.actor.name ?? ([profile?.firstName, profile?.name].filter(Boolean).join(' ') || null),
        profession: profile?.profession ?? null,
        city: profile?.city ?? null,
        country: profile?.country ?? null,
        avatarUrl: profile?.avatarUrl ?? null,
        phoneNumber: e.actor.phoneNumber ?? profile?.phoneNumber ?? null,
        savedAt: e.confirmedAt,
      };
    });
    return paginate(items, total, pagination.page, pagination.limit);
  }

  history(userId: string, page: number, limit: number) {
    return this.prisma
      .$transaction([
        this.prisma.syncRun.findMany({
          where: { userId },
          orderBy: { startedAt: 'desc' },
          skip: (page - 1) * limit,
          take: limit,
        }),
        this.prisma.syncRun.count({ where: { userId } }),
      ])
      .then(([items, total]) => paginate(items, total, page, limit));
  }

  /** "Mes contacts SBC" dashboard counts (cahier §16). */
  async summary(userId: string) {
    // Self-healing: the dashboard is where a stale queue is seen, so it is
    // also where it gets cleared. A member who abandons one sync and never
    // starts another would otherwise keep reading a count of nothing.
    // Bounded and idempotent — it finds no open runs and returns immediately
    // in the normal case.
    await this.reclaimAbandonedRuns(userId);

    const [syncedGroups, pending, failed, activeCriteria, lastRun] = await Promise.all([
      this.prisma.syncedContact.groupBy({
        by: ['memberId'],
        where: { userId, status: 'SYNCED' },
      }),
      this.prisma.syncedContact.count({ where: { userId, status: 'PENDING' } }),
      this.prisma.syncedContact.count({ where: { userId, status: 'FAILED' } }),
      this.prisma.syncCriteria.findMany({
        where: { userId, isActive: true },
        select: { lastMatchCount: true },
      }),
      this.prisma.syncRun.findFirst({
        where: { userId, status: 'COMPLETED' },
        orderBy: { finishedAt: 'desc' },
        select: { finishedAt: true },
      }),
    ]);

    return {
      syncedCount: syncedGroups.length,
      pendingCount: pending,
      failedCount: failed,
      activeCriteria: activeCriteria.length,
      currentMatches: activeCriteria.reduce((sum, c) => sum + c.lastMatchCount, 0),
      lastSyncAt: lastRun?.finishedAt ?? null,
    };
  }

  async contacts(userId: string, query: SyncContactsQueryDto): Promise<PaginatedResult<unknown>> {
    const where = {
      userId,
      ...(query.status ? { status: query.status as never } : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.syncedContact.findMany({
        where,
        include: { member: true },
        orderBy: { updatedAt: 'desc' },
        skip: query.skip,
        take: query.limit,
      }),
      this.prisma.syncedContact.count({ where }),
    ]);
    const items = rows.map((r) => ({
      memberSbcId: r.member.sbcId,
      name: r.member.name,
      firstName: r.member.firstName,
      profession: r.member.profession,
      city: r.member.city,
      country: r.member.country,
      avatarUrl: r.member.avatarUrl,
      phoneNumber: r.member.phoneNumber,
      status: r.status,
      deviceId: r.deviceId,
      syncedAt: r.syncedAt,
    }));
    return paginate(items, total, query.page, query.limit);
  }

  private async resolveTargets(
    userId: string,
    dto: StartSyncDto,
  ): Promise<{ members: Member[]; criteriaId: string | null }> {
    // An explicit selection wins over the criteria it came from. The review
    // screen sends BOTH — the criteria for attribution, and the members the
    // user actually ticked. Expanding the criteria here instead would mark
    // every match PENDING while the device only ever writes, and reports on,
    // the chosen few: the remainder is then stranded "En attente" forever,
    // because nothing ever reports a status for it.
    if (dto.memberSbcIds?.length) {
      const criteriaId = dto.criteriaId
        ? (
            await this.prisma.syncCriteria.findFirst({
              where: { id: dto.criteriaId, userId },
              select: { id: true },
            })
          )?.id ?? null
        : null;
      if (dto.criteriaId && !criteriaId) throw new NotFoundException('Criteria not found');
      const members = await this.members.findManyBySbcIds(dto.memberSbcIds);
      return { members, criteriaId };
    }
    if (dto.criteriaId) {
      const criteria = await this.prisma.syncCriteria.findFirst({
        where: { id: dto.criteriaId, userId },
      });
      if (!criteria) throw new NotFoundException('Criteria not found');
      const members = await this.match.find(this.toMatch(criteria), { take: MAX_TARGETS });
      return { members, criteriaId: criteria.id };
    }
    throw new BadRequestException('Provide either criteriaId or memberSbcIds');
  }

  private toMatch(c: SyncCriteria): MatchCriteria {
    return {
      countries: c.countries,
      cities: c.cities,
      professions: c.professions,
      interests: c.interests,
      sex: c.sex,
      ageMin: c.ageMin,
      ageMax: c.ageMax,
    };
  }
}

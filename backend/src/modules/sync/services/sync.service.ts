import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Member, SyncCriteria } from '@prisma/client';
import { PaginatedResult, paginate } from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { MemberMatchService } from '../../members/member-match.service';
import { MembersService } from '../../members/members.service';
import { MatchCriteria } from '../../members/member.view';
import {
  ReportSyncDto,
  ReportedStatus,
  StartSyncDto,
  SyncContactsQueryDto,
} from '../dto/sync.dto';

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
  constructor(
    private readonly prisma: PrismaService,
    private readonly members: MembersService,
    private readonly match: MemberMatchService,
    private readonly audit: AuditService,
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

    const run = await this.prisma.syncRun.create({
      data: { userId, criteriaId, deviceId, status: 'RUNNING', matchCount: members.length },
    });

    // Mark not-yet-synced members PENDING (idempotent upsert per device).
    let pendingCount = 0;
    for (const m of members) {
      const alreadySynced = statusByMember.get(m.id) === 'SYNCED';
      if (!alreadySynced) pendingCount++;
      await this.prisma.syncedContact.upsert({
        where: { userId_memberId_deviceId: { userId, memberId: m.id, deviceId } },
        create: { userId, memberId: m.id, deviceId, status: 'PENDING' },
        update: alreadySynced ? {} : { status: 'PENDING' },
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

      await this.prisma.syncedContact.updateMany({
        where: { userId, memberId: member.id, deviceId },
        data: {
          status: isSynced ? 'SYNCED' : 'FAILED',
          deviceContactId: result.deviceContactId,
          syncedAt: isSynced ? new Date() : null,
        },
      });

      // "Qui m'a ajouté ?" — record only technically-confirmed additions (§21).
      if (isSynced) {
        await this.prisma.addedEvent.create({
          data: { actorId: userId, targetMemberSbcId: member.sbcId },
        });
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
    if (dto.criteriaId) {
      const criteria = await this.prisma.syncCriteria.findFirst({
        where: { id: dto.criteriaId, userId },
      });
      if (!criteria) throw new NotFoundException('Criteria not found');
      const members = await this.match.find(this.toMatch(criteria), { take: MAX_TARGETS });
      return { members, criteriaId: criteria.id };
    }
    if (dto.memberSbcIds?.length) {
      const members = await this.members.findManyBySbcIds(dto.memberSbcIds);
      return { members, criteriaId: null };
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

import { Injectable, NotFoundException } from '@nestjs/common';
import { SyncCriteria } from '@prisma/client';
import { PaginatedResult, PaginationQueryDto, paginate } from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { MemberMatchService } from '../../members/member-match.service';
import { MembersService } from '../../members/members.service';
import { MatchCriteria, MemberView } from '../../members/member.view';
import { CreateCriteriaDto, PreviewCriteriaDto, UpdateCriteriaDto } from '../dto/criteria.dto';
import { CriteriaHydrationService } from './criteria-hydration.service';

/** Saved sync criteria (cahier §10): CRUD + live match-count preview + matches. */
@Injectable()
export class CriteriaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly match: MemberMatchService,
    private readonly members: MembersService,
    private readonly audit: AuditService,
    private readonly hydration: CriteriaHydrationService,
  ) {}

  async create(userId: string, dto: CreateCriteriaDto, ip?: string): Promise<SyncCriteria> {
    const created = await this.prisma.syncCriteria.create({
      data: {
        userId,
        label: dto.label,
        countries: dto.countries ?? [],
        cities: dto.cities ?? [],
        professions: dto.professions ?? [],
        interests: dto.interests ?? [],
        sex: dto.sex ?? null,
        ageMin: dto.ageMin ?? null,
        ageMax: dto.ageMax ?? null,
        isActive: dto.isActive ?? true,
        // Baseline for the sweep (§11). Everything already mirrored — and
        // everything the first hydration is about to mirror — predates this
        // criteria, so only members that turn up later count as "new". Without
        // the stamp the first sweep would treat the whole mirror as new and
        // notify on every one of them.
        lastCheckedAt: new Date(),
      },
    });
    await this.audit.record({
      actorId: userId,
      action: 'criteria.create',
      resource: `SyncCriteria:${created.id}`,
      after: created,
      ip,
    });
    return created;
  }

  list(userId: string): Promise<SyncCriteria[]> {
    return this.prisma.syncCriteria.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async get(userId: string, id: string): Promise<SyncCriteria> {
    const criteria = await this.prisma.syncCriteria.findFirst({ where: { id, userId } });
    if (!criteria) throw new NotFoundException('Criteria not found');
    return criteria;
  }

  async update(
    userId: string,
    id: string,
    dto: UpdateCriteriaDto,
    ip?: string,
  ): Promise<SyncCriteria> {
    const before = await this.get(userId, id);
    const updated = await this.prisma.syncCriteria.update({
      where: { id },
      data: {
        label: dto.label,
        countries: dto.countries,
        cities: dto.cities,
        professions: dto.professions,
        interests: dto.interests,
        sex: dto.sex,
        ageMin: dto.ageMin,
        ageMax: dto.ageMax,
        isActive: dto.isActive,
      },
    });
    await this.audit.record({
      actorId: userId,
      action: 'criteria.update',
      resource: `SyncCriteria:${id}`,
      before: before,
      after: updated,
      ip,
    });
    return updated;
  }

  async remove(userId: string, id: string, ip?: string): Promise<void> {
    const before = await this.get(userId, id);
    await this.prisma.syncCriteria.delete({ where: { id } });
    await this.audit.record({
      actorId: userId,
      action: 'criteria.delete',
      resource: `SyncCriteria:${id}`,
      before: before,
      ip,
    });
  }

  /** Match count for a saved criteria; also refreshes its cached count. */
  async preview(userId: string, id: string): Promise<{ criteriaId: string; matchCount: number }> {
    const criteria = await this.get(userId, id);
    const where = this.toMatch(criteria);
    const matchCount = await this.matchCount(userId, where);
    await this.prisma.syncCriteria.update({
      where: { id },
      data: { lastCheckedAt: new Date(), lastMatchCount: matchCount },
    });
    return { criteriaId: id, matchCount };
  }

  /** Match count for unsaved criteria (live count on the create screen, §10). */
  async previewAdhoc(userId: string, dto: PreviewCriteriaDto): Promise<{ matchCount: number }> {
    return { matchCount: await this.matchCount(userId, this.dtoToMatch(dto)) };
  }

  /**
   * The headline count the member is asking for: SBC's own total for the
   * criteria, computed cheaply and cached. Falls back to the mirror count when
   * SBC can't answer (down, or the caller's session lapsed) — the old
   * behaviour. Either way the deep walk that fills the mirror is enqueued, so
   * the matches list catches up to this number in the background.
   */
  private async matchCount(userId: string, where: MatchCriteria): Promise<number> {
    const sbcTotal = await this.hydration.previewTotal(userId, where);
    return sbcTotal ?? this.match.count(where);
  }

  async matches(
    userId: string,
    id: string,
    pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<MemberView>> {
    const criteria = await this.get(userId, id);
    const where = this.toMatch(criteria);
    // Keep filling the mirror in the background so paging reaches the whole
    // country; the page itself is served from whatever is mirrored so far, so it
    // is always full rows the member can save — never an empty page ahead of the
    // walk.
    await this.hydration.enqueueDeepWalk(userId, where);
    const [rows, total] = await Promise.all([
      this.match.find(where, { skip: pagination.skip, take: pagination.limit }),
      this.match.count(where),
    ]);
    const annotated = await this.members.annotate(userId, rows);
    return paginate(annotated, total, pagination.page, pagination.limit);
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

  private dtoToMatch(dto: PreviewCriteriaDto): MatchCriteria {
    return {
      countries: dto.countries ?? [],
      cities: dto.cities ?? [],
      professions: dto.professions ?? [],
      interests: dto.interests ?? [],
      sex: dto.sex ?? null,
      ageMin: dto.ageMin ?? null,
      ageMax: dto.ageMax ?? null,
    };
  }
}

import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { SyncCriteria } from '@prisma/client';
import { PaginatedResult, PaginationQueryDto, paginate } from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { MemberMatchService } from '../../members/member-match.service';
import { MembersService } from '../../members/members.service';
import { MatchCriteria, MemberView } from '../../members/member.view';
import { StatusBoostService } from '../../status-boost/status-boost.service';
import { CreateCriteriaDto, PreviewCriteriaDto, UpdateCriteriaDto } from '../dto/criteria.dto';
import { CriteriaHydrationService } from './criteria-hydration.service';
import { CriteriaMatchResolver } from './criteria-match.resolver';

/** Saved sync criteria (cahier §10): CRUD + live match-count preview + matches. */
@Injectable()
export class CriteriaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly match: MemberMatchService,
    private readonly members: MembersService,
    private readonly audit: AuditService,
    private readonly hydration: CriteriaHydrationService,
    private readonly resolver: CriteriaMatchResolver,
    private readonly statusBoost: StatusBoostService,
  ) {}

  async create(userId: string, dto: CreateCriteriaDto, ip?: string): Promise<SyncCriteria> {
    if (dto.statusBoost) return this.withCount(await this.createStatusBoost(userId, dto.label, ip));
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

  /**
   * "Enregistrer tous les membres de la liste" from "Augmenter mes vues
   * WhatsApp". Only for a member in the list — the deal is mutual — and one per
   * member: asking again turns the existing one back on rather than adding a
   * second that saves the same people.
   */
  private async createStatusBoost(
    userId: string,
    label: string,
    ip?: string,
  ): Promise<SyncCriteria> {
    await this.assertInStatusBoost(userId);
    const existing = await this.prisma.syncCriteria.findFirst({
      where: { userId, statusBoost: true },
    });
    if (existing) {
      return existing.isActive
        ? existing
        : this.update(userId, existing.id, { isActive: true }, ip);
    }
    const created = await this.prisma.syncCriteria.create({
      data: {
        userId,
        label,
        statusBoost: true,
        // Same baseline as any criteria: those already in the list are the
        // ones the member is saving now, not news.
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

  /**
   * A list criteria's size is known up front, so its card need not read 0 until
   * the next sweep.
   */
  private async withCount(c: SyncCriteria): Promise<SyncCriteria> {
    const { sbcIds } = await this.resolver.resolve(c);
    return this.prisma.syncCriteria.update({
      where: { id: c.id },
      data: { lastMatchCount: sbcIds?.length ?? 0 },
    });
  }

  private async assertInStatusBoost(userId: string): Promise<void> {
    if (!(await this.statusBoost.isOptedIn(userId))) {
      throw new ForbiddenException(
        'Rejoins "Augmenter mes vues WhatsApp" pour enregistrer ses membres',
      );
    }
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
    if (before.statusBoost) {
      // Its members are the list, not filters: only the name and the switch.
      if (dto.isActive) await this.assertInStatusBoost(userId);
      dto = { label: dto.label, isActive: dto.isActive };
    }
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
    const where = await this.resolver.resolve(criteria);
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
    const where = await this.resolver.resolve(criteria);
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

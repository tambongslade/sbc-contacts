import { Injectable, NotFoundException } from '@nestjs/common';
import { SyncCriteria } from '@prisma/client';
import { PaginatedResult, PaginationQueryDto, paginate } from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { MemberMatchService } from '../../members/member-match.service';
import { MembersService } from '../../members/members.service';
import { MatchCriteria, MemberView } from '../../members/member.view';
import { CreateCriteriaDto, PreviewCriteriaDto, UpdateCriteriaDto } from '../dto/criteria.dto';

/** Saved sync criteria (cahier §10): CRUD + live match-count preview + matches. */
@Injectable()
export class CriteriaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly match: MemberMatchService,
    private readonly members: MembersService,
    private readonly audit: AuditService,
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
    const matchCount = await this.match.count(this.toMatch(criteria));
    await this.prisma.syncCriteria.update({
      where: { id },
      data: { lastCheckedAt: new Date(), lastMatchCount: matchCount },
    });
    return { criteriaId: id, matchCount };
  }

  /** Match count for unsaved criteria (live count on the create screen, §10). */
  async previewAdhoc(_userId: string, dto: PreviewCriteriaDto): Promise<{ matchCount: number }> {
    const matchCount = await this.match.count(this.dtoToMatch(dto));
    return { matchCount };
  }

  async matches(
    userId: string,
    id: string,
    pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<MemberView>> {
    const criteria = await this.get(userId, id);
    const where = this.toMatch(criteria);
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

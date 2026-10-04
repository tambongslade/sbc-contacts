import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { DispatchStatus, Prisma, RequestStatus } from '@prisma/client';
import { PaginatedResult, paginate } from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { missingFields, sanitise } from '../ai/pro-setup-assistant';
import { SbcDataAiService } from '../ai/sbc-data-ai.service';
import {
  AdminListQueryDto,
  AdminProsQueryDto,
  AdminRequestsQueryDto,
  AdminServiceUpdateDto,
  SetReceivingDto,
  UnfulfilledAnalyticsQueryDto,
} from '../dto/sbc-data.dto';
import { serviceDocument } from '../matching/request-matching.service';
import { isReceivingActive } from '../sbc-data.views';

const OPEN_DISPATCH: DispatchStatus[] = [
  DispatchStatus.SENT,
  DispatchStatus.VIEWED,
  DispatchStatus.INTERESTED,
  DispatchStatus.QUESTION,
];

/** The audit action a requester's "prestation non réalisée" is filed under. */
export const REPORT_ACTION = 'sbc-data.request.reported';

/**
 * The SBC back-office (Data §21): supervise requests and pros, correct the
 * services, switch reception on, read why a request went to whom. Every write
 * is audit-logged with the admin who made it.
 */
@Injectable()
export class SbcDataAdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly ai: SbcDataAiService,
  ) {}

  // ── Dashboard ─────────────────────────────────────────────────────────────

  async stats() {
    const now = new Date();
    const since30 = new Date(now.getTime() - 30 * 86_400_000);
    const [
      requestsByStatus,
      requests30,
      pros,
      receiving,
      services,
      dispatchesByStatus,
      reports,
      topServices,
      topCities,
    ] = await this.prisma.$transaction([
      this.prisma.serviceRequest.groupBy({
        by: ['status'],
        _count: { _all: true },
        orderBy: { status: 'asc' },
      }),
      this.prisma.serviceRequest.count({ where: { createdAt: { gte: since30 } } }),
      this.prisma.proProfile.count(),
      this.prisma.proProfile.count({
        where: {
          receivingEnabled: true,
          OR: [{ receivingUntil: null }, { receivingUntil: { gt: now } }],
        },
      }),
      this.prisma.proService.count({ where: { isActive: true } }),
      this.prisma.requestDispatch.groupBy({
        by: ['status'],
        _count: { _all: true },
        orderBy: { status: 'asc' },
      }),
      this.prisma.auditLog.count({ where: { action: REPORT_ACTION } }),
      this.prisma.serviceRequest.groupBy({
        by: ['service'],
        where: { service: { not: null } },
        _count: { _all: true },
        orderBy: { _count: { service: 'desc' } },
        take: 8,
      }),
      this.prisma.serviceRequest.groupBy({
        by: ['city'],
        where: { city: { not: null } },
        _count: { _all: true },
        orderBy: { _count: { city: 'desc' } },
        take: 8,
      }),
    ]);

    const n = (rows: Array<{ _count: unknown }>, pick: (r: never) => boolean) =>
      rows
        .filter((r) => pick(r as never))
        .reduce((sum, r) => sum + ((r._count as { _all: number })._all ?? 0), 0);
    const byReq = (s: RequestStatus) =>
      n(requestsByStatus, (r: { status: RequestStatus }) => r.status === s);
    const byDisp = (s: DispatchStatus) =>
      n(dispatchesByStatus, (r: { status: DispatchStatus }) => r.status === s);

    const dispatched = n(dispatchesByStatus, () => true);
    const answered = dispatched - byDisp(DispatchStatus.SENT) - byDisp(DispatchStatus.VIEWED);
    const interested =
      byDisp(DispatchStatus.INTERESTED) +
      byDisp(DispatchStatus.SELECTED) +
      byDisp(DispatchStatus.LOST);

    return {
      requests: {
        total: n(requestsByStatus, () => true),
        last30Days: requests30,
        byStatus: Object.fromEntries(Object.values(RequestStatus).map((s) => [s, byReq(s)])),
      },
      pros: { total: pros, receiving, services },
      dispatches: {
        total: dispatched,
        answered,
        selected: byDisp(DispatchStatus.SELECTED),
        responseRate: dispatched ? answered / dispatched : 0,
        conversionRate: interested ? byDisp(DispatchStatus.SELECTED) / interested : 0,
      },
      reports,
      topServices: topServices.map((r) => ({
        name: r.service as string,
        count: (r._count as { _all: number })._all,
      })),
      topCities: topCities.map((r) => ({
        name: r.city as string,
        count: (r._count as { _all: number })._all,
      })),
    };
  }

  // ── Requests ──────────────────────────────────────────────────────────────

  async requests(q: AdminRequestsQueryDto): Promise<PaginatedResult<unknown>> {
    const term = q.search?.trim();
    const where: Prisma.ServiceRequestWhereInput = {
      ...(q.status ? { status: q.status } : {}),
      ...(term
        ? {
            OR: [
              { rawText: { contains: term, mode: 'insensitive' } },
              { service: { contains: term, mode: 'insensitive' } },
              { city: { contains: term, mode: 'insensitive' } },
              { user: { name: { contains: term, mode: 'insensitive' } } },
            ],
          }
        : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.serviceRequest.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: q.skip,
        take: q.limit,
        select: {
          id: true,
          rawText: true,
          service: true,
          profession: true,
          city: true,
          mode: true,
          budget: true,
          status: true,
          createdAt: true,
          hiddenAt: true,
          user: { select: { id: true, name: true, phoneNumber: true } },
          _count: { select: { dispatches: true } },
          dispatches: { where: { respondedAt: { not: null } }, select: { id: true } },
        },
      }),
      this.prisma.serviceRequest.count({ where }),
    ]);
    const items = rows.map(({ dispatches, _count, ...r }) => ({
      ...r,
      dispatchedCount: _count.dispatches,
      answeredCount: dispatches.length,
    }));
    return paginate(items, total, q.page, q.limit);
  }

  /** Everything about one request, including the matching log (Data §21). */
  async request(id: string) {
    const found = await this.prisma.serviceRequest.findUnique({
      where: { id },
      include: {
        user: { select: { id: true, name: true, phoneNumber: true, email: true } },
        dispatches: {
          orderBy: { score: 'desc' },
          include: {
            service: { select: { id: true, name: true, category: true } },
            pro: {
              select: {
                userId: true,
                profession: true,
                city: true,
                user: { select: { name: true, phoneNumber: true } },
              },
            },
          },
        },
      },
    });
    if (!found) throw new NotFoundException('Demande introuvable');
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { embedding, ...request } = found;
    const reports = await this.prisma.auditLog.findMany({
      where: { action: REPORT_ACTION, resource: `ServiceRequest:${id}` },
      orderBy: { createdAt: 'desc' },
    });
    return { ...request, reports };
  }

  /** Take a request off the market: pros stop seeing it as open. */
  async suspendRequest(adminId: string, id: string) {
    const request = await this.prisma.serviceRequest.findUnique({ where: { id } });
    if (!request) throw new NotFoundException('Demande introuvable');
    const closed: RequestStatus[] = [RequestStatus.COMPLETED, RequestStatus.CANCELLED];
    if (closed.includes(request.status)) {
      throw new BadRequestException('Cette demande est déjà close');
    }
    await this.prisma.$transaction([
      this.prisma.requestDispatch.updateMany({
        where: { requestId: id, status: { in: OPEN_DISPATCH } },
        data: { status: DispatchStatus.LOST },
      }),
      this.prisma.serviceRequest.update({
        where: { id },
        data: { status: RequestStatus.CANCELLED },
      }),
    ]);
    await this.audit.record({
      actorId: adminId,
      action: 'sbc-data.admin.request.suspend',
      resource: `ServiceRequest:${id}`,
      before: { status: request.status },
      after: { status: RequestStatus.CANCELLED },
    });
    return this.request(id);
  }

  // ── Pros ──────────────────────────────────────────────────────────────────

  async pros(q: AdminProsQueryDto) {
    const term = q.search?.trim();
    const now = new Date();
    const where: Prisma.ProProfileWhereInput = {
      ...(term
        ? {
            OR: [
              { profession: { contains: term, mode: 'insensitive' } },
              { city: { contains: term, mode: 'insensitive' } },
              { user: { name: { contains: term, mode: 'insensitive' } } },
              { user: { phoneNumber: { contains: term } } },
            ],
          }
        : {}),
      ...(q.receiving === 'on'
        ? {
            receivingEnabled: true,
            OR: [{ receivingUntil: null }, { receivingUntil: { gt: now } }],
          }
        : q.receiving === 'off'
          ? { OR: [{ receivingEnabled: false }, { receivingUntil: { lte: now } }] }
          : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.proProfile.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: q.skip,
        take: q.limit,
        include: {
          user: { select: { id: true, name: true, phoneNumber: true, country: true } },
          services: { where: { isActive: true }, select: { name: true } },
          _count: { select: { dispatches: true } },
        },
      }),
      this.prisma.proProfile.count({ where }),
    ]);
    const items = rows.map((p) => ({
      userId: p.userId,
      name: p.user.name,
      phoneNumber: p.whatsapp ?? p.user.phoneNumber,
      country: p.user.country,
      profession: p.profession,
      city: p.city,
      receivingEnabled: p.receivingEnabled,
      receivingUntil: p.receivingUntil,
      receivingActive: isReceivingActive(p, now),
      services: p.services.map((s) => s.name),
      requestsReceived: p._count.dispatches,
      missing: setupMissing(p, p.services.length > 0),
      createdAt: p.createdAt,
    }));
    return paginate(items, total, q.page, q.limit);
  }

  async pro(userId: string) {
    const p = await this.prisma.proProfile.findUnique({
      where: { userId },
      include: {
        user: { select: { id: true, name: true, phoneNumber: true, email: true, country: true } },
        services: { orderBy: [{ category: 'asc' }, { name: 'asc' }] },
      },
    });
    if (!p) throw new NotFoundException('Ce membre n’a pas de profil professionnel');
    const [byStatus, recent] = await this.prisma.$transaction([
      this.prisma.requestDispatch.groupBy({
        by: ['status'],
        where: { proId: p.id },
        _count: { _all: true },
        orderBy: { status: 'asc' },
      }),
      this.prisma.requestDispatch.findMany({
        where: { proId: p.id },
        orderBy: { createdAt: 'desc' },
        take: 20,
        include: {
          request: {
            select: { id: true, service: true, city: true, status: true, createdAt: true },
          },
        },
      }),
    ]);
    return {
      ...p,
      services: p.services.map(({ embedding, ...s }) => ({
        ...s,
        hasEmbedding: embedding.length > 0,
      })),
      receivingActive: isReceivingActive(p),
      missing: setupMissing(
        p,
        p.services.some((s) => s.isActive),
      ),
      activity: Object.fromEntries(
        byStatus.map((r) => [r.status, (r._count as { _all: number })._all]),
      ),
      recent,
    };
  }

  /** Reception on/off and subscription end — stands in for payments (Data §17). */
  async setReceiving(adminId: string, userId: string, dto: SetReceivingDto) {
    const before = await this.prisma.proProfile.findUnique({ where: { userId } });
    if (!before) throw new NotFoundException('Ce membre n’a pas de profil professionnel');
    const after = await this.prisma.proProfile.update({
      where: { userId },
      data: {
        receivingEnabled: dto.enabled,
        receivingUntil: dto.until ? new Date(dto.until) : null,
      },
      select: { userId: true, receivingEnabled: true, receivingUntil: true },
    });
    await this.audit.record({
      actorId: adminId,
      action: 'sbc-data.pro.receiving',
      resource: `ProProfile:${before.id}`,
      before: { receivingEnabled: before.receivingEnabled, receivingUntil: before.receivingUntil },
      after,
    });
    return after;
  }

  // ── Services (référentiel) ────────────────────────────────────────────────

  async services(q: AdminListQueryDto) {
    const term = q.search?.trim();
    const where: Prisma.ProServiceWhereInput = term
      ? {
          OR: [
            { name: { contains: term, mode: 'insensitive' } },
            { category: { contains: term, mode: 'insensitive' } },
            { profession: { contains: term, mode: 'insensitive' } },
            { synonyms: { has: term.toLowerCase() } },
            { pro: { user: { name: { contains: term, mode: 'insensitive' } } } },
          ],
        }
      : {};
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.proService.findMany({
        where,
        orderBy: [{ profession: 'asc' }, { name: 'asc' }],
        skip: q.skip,
        take: q.limit,
        include: {
          pro: { select: { userId: true, city: true, user: { select: { name: true } } } },
          _count: { select: { dispatches: true } },
        },
      }),
      this.prisma.proService.count({ where }),
    ]);
    const items = rows.map(({ embedding, _count, ...s }) => ({
      ...s,
      hasEmbedding: embedding.length > 0,
      requestsMatched: _count.dispatches,
    }));
    return paginate(items, total, q.page, q.limit);
  }

  /** Fix a misclassified service or add synonyms (Data §5). Re-embeds on text changes. */
  async updateService(adminId: string, id: string, dto: AdminServiceUpdateDto) {
    const before = await this.prisma.proService.findUnique({ where: { id } });
    if (!before) throw new NotFoundException('Service introuvable');
    const data: Prisma.ProServiceUpdateInput = {};
    if (dto.name !== undefined) data.name = dto.name.trim();
    if (dto.category !== undefined) data.category = dto.category.trim();
    if (dto.profession !== undefined) data.profession = dto.profession.trim();
    if (dto.synonyms !== undefined) data.synonyms = tidy(dto.synonyms);
    if (dto.specialties !== undefined) data.specialties = tidy(dto.specialties);
    if (dto.isActive !== undefined) data.isActive = dto.isActive;

    const textChanged = ['name', 'category', 'profession', 'synonyms', 'specialties'].some(
      (k) => k in data,
    );
    if (textChanged) {
      const merged = { ...before, ...data } as typeof before;
      const [embedding] = await this.ai.embed([serviceDocument(merged)], 'RETRIEVAL_DOCUMENT');
      if (embedding.length) data.embedding = embedding;
    }
    const after = await this.prisma.proService.update({ where: { id }, data });
    await this.audit.record({
      actorId: adminId,
      action: 'sbc-data.admin.service.update',
      resource: `ProService:${id}`,
      before: pickService(before),
      after: pickService(after),
    });
    return pickService(after);
  }

  /**
   * Merge two services of the same pro (Data §21): the source's synonyms and
   * specialties join the target, its matching history moves over, and the
   * source is deleted.
   */
  async mergeService(adminId: string, sourceId: string, targetId: string) {
    if (sourceId === targetId) throw new BadRequestException('Choisis deux services différents');
    const [source, target] = await Promise.all([
      this.prisma.proService.findUnique({ where: { id: sourceId } }),
      this.prisma.proService.findUnique({ where: { id: targetId } }),
    ]);
    if (!source || !target) throw new NotFoundException('Service introuvable');
    if (source.proId !== target.proId) {
      throw new BadRequestException('On ne fusionne que deux services du même professionnel');
    }
    const synonyms = tidy([...target.synonyms, ...source.synonyms, source.name]).filter(
      (s) => s.toLowerCase() !== target.name.toLowerCase(),
    );
    const specialties = tidy([...target.specialties, ...source.specialties]);
    const [embedding] = await this.ai.embed(
      [serviceDocument({ ...target, synonyms, specialties })],
      'RETRIEVAL_DOCUMENT',
    );
    await this.prisma.$transaction([
      this.prisma.requestDispatch.updateMany({
        where: { serviceId: sourceId },
        data: { serviceId: targetId },
      }),
      this.prisma.proService.update({
        where: { id: targetId },
        data: { synonyms, specialties, ...(embedding.length ? { embedding } : {}) },
      }),
      this.prisma.proService.delete({ where: { id: sourceId } }),
    ]);
    await this.audit.record({
      actorId: adminId,
      action: 'sbc-data.admin.service.merge',
      resource: `ProService:${targetId}`,
      metadata: { mergedFrom: pickService(source) },
    });
    return pickService((await this.prisma.proService.findUnique({ where: { id: targetId } }))!);
  }

  async deleteService(adminId: string, id: string) {
    const before = await this.prisma.proService.findUnique({ where: { id } });
    if (!before) throw new NotFoundException('Service introuvable');
    await this.prisma.proService.delete({ where: { id } });
    await this.audit.record({
      actorId: adminId,
      action: 'sbc-data.admin.service.delete',
      resource: `ProService:${id}`,
      before: pickService(before),
    });
  }

  // ── Unfulfilled demand ────────────────────────────────────────────────────

  /** Needs the platform cannot serve yet, grouped by term, to target recruitment. */
  async unfulfilled(query: UnfulfilledAnalyticsQueryDto) {
    const createdAt =
      query.from || query.to
        ? {
            ...(query.from ? { gte: new Date(query.from) } : {}),
            ...(query.to ? { lte: new Date(query.to) } : {}),
          }
        : undefined;
    const windowWhere: Prisma.SearchAnalyticsWhereInput = createdAt ? { createdAt } : {};

    const gaps = await this.prisma.searchAnalytics.groupBy({
      by: ['term'],
      where: { ...windowWhere, fulfilled: false },
      _count: { term: true },
      _max: { createdAt: true },
      orderBy: { _count: { term: 'desc' } },
      take: query.limit,
    });
    const [searches, unfulfilled] = await Promise.all([
      this.prisma.searchAnalytics.count({ where: windowWhere }),
      this.prisma.searchAnalytics.count({ where: { ...windowWhere, fulfilled: false } }),
    ]);
    return {
      window: { from: query.from ?? null, to: query.to ?? null },
      totals: {
        searches,
        unfulfilled,
        fulfilmentRate: searches ? (searches - unfulfilled) / searches : 1,
      },
      gaps: gaps.map((g) => ({
        term: g.term,
        count: g._count.term,
        lastSearchedAt: g._max?.createdAt ?? null,
      })),
    };
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /** "Prestation non réalisée" reports from requesters (Data §15, §21). */
  async reports(q: AdminListQueryDto) {
    const where = { action: REPORT_ACTION };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.auditLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: q.skip,
        take: q.limit,
      }),
      this.prisma.auditLog.count({ where }),
    ]);
    const requestIds = rows.map((r) => r.resource.replace('ServiceRequest:', ''));
    const proIds = rows
      .map((r) => (r.metadata as { proId?: string } | null)?.proId)
      .filter((v): v is string => Boolean(v));
    const actorIds = rows.map((r) => r.actorId).filter((v): v is string => Boolean(v));
    const [requests, pros, actors] = await Promise.all([
      this.prisma.serviceRequest.findMany({
        where: { id: { in: requestIds } },
        select: { id: true, service: true, city: true },
      }),
      this.prisma.proProfile.findMany({
        where: { id: { in: proIds } },
        select: { id: true, userId: true, profession: true, user: { select: { name: true } } },
      }),
      this.prisma.user.findMany({
        where: { id: { in: actorIds } },
        select: { id: true, name: true, phoneNumber: true },
      }),
    ]);
    const items = rows.map((r) => {
      const meta = (r.metadata ?? {}) as { proId?: string; comment?: string | null };
      const pro = pros.find((p) => p.id === meta.proId);
      return {
        id: r.id,
        createdAt: r.createdAt,
        comment: meta.comment ?? null,
        request: requests.find((x) => `ServiceRequest:${x.id}` === r.resource) ?? null,
        pro: pro ? { userId: pro.userId, name: pro.user.name, profession: pro.profession } : null,
        reporter: actors.find((a) => a.id === r.actorId) ?? null,
      };
    });
    return paginate(items, total, q.page, q.limit);
  }
}

function setupMissing(
  p: {
    profession: string;
    description: string;
    city: string;
    zones: string[];
    modes: import('@prisma/client').ServiceMode[];
    availability: string;
    priceMin: number | null;
    priceMax: number | null;
    shopUrl: string;
  },
  hasServices: boolean,
) {
  return missingFields(sanitise({ profile: { ...p }, services: [] }), hasServices);
}

function pickService(s: {
  id: string;
  name: string;
  category: string;
  profession: string;
  synonyms: string[];
  specialties: string[];
  isActive: boolean;
}) {
  return {
    id: s.id,
    name: s.name,
    category: s.category,
    profession: s.profession,
    synonyms: s.synonyms,
    specialties: s.specialties,
    isActive: s.isActive,
  };
}

function tidy(values: string[]): string[] {
  const seen = new Set<string>();
  return values
    .map((v) => v.trim())
    .filter((v) => {
      const k = v.toLowerCase();
      if (!v || seen.has(k)) return false;
      seen.add(k);
      return true;
    });
}

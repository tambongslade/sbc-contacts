import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  DispatchStatus,
  NotificationType,
  Prisma,
  ProService as ProServiceRow,
  RequestStatus,
} from '@prisma/client';
import { PaginatedResult, paginate } from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { AuditService } from '../../audit/audit.service';
import { NotificationsService } from '../../notifications/notifications.service';
import { AssistantTurn, ProDraft, ProSetupAssistant, sanitise } from '../ai/pro-setup-assistant';
import { SbcDataAiService, StructuredServices } from '../ai/sbc-data-ai.service';
import {
  AddServicesDto,
  AssistantTurnDto,
  InboxQueryDto,
  ProServiceInputDto,
  RespondDto,
  UpdateServiceDto,
  UpsertProProfileDto,
} from '../dto/sbc-data.dto';
import { serviceDocument } from '../matching/request-matching.service';
import {
  InboxItemView,
  ProProfileView,
  isReceivingActive,
  stripService,
  toInboxItem,
} from '../sbc-data.views';

/** Dispatch states in which the pro can still answer. */
const OPEN_DISPATCH: DispatchStatus[] = [
  DispatchStatus.SENT,
  DispatchStatus.VIEWED,
  DispatchStatus.QUESTION,
];
/** Request states in which answers are still useful. */
const OPEN_REQUEST: RequestStatus[] = [RequestStatus.SENT, RequestStatus.RESPONDED];

export interface ProStats {
  received: number;
  responded: number;
  interested: number;
  selected: number;
  completed: number;
  /** Share of received requests the pro answered, 0–1. */
  responseRate: number;
  /** Share of "interested" answers that won, 0–1. */
  conversionRate: number;
  topServices: Array<{ name: string; count: number }>;
}

/**
 * The professional's side of SBC Data: profile, services, inbox, answers,
 * statistics (Data §3, §4, §10, §18).
 */
@Injectable()
export class ProfessionalService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ai: SbcDataAiService,
    private readonly notifications: NotificationsService,
    private readonly audit: AuditService,
    private readonly assistant: ProSetupAssistant,
  ) {}

  async getProfile(userId: string): Promise<ProProfileView> {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: {
        name: true,
        avatarUrl: true,
        phoneNumber: true,
        country: true,
        proProfile: { include: { services: { orderBy: [{ category: 'asc' }, { name: 'asc' }] } } },
      },
    });
    const { proProfile, ...identity } = user;
    if (!proProfile) return { profile: null, identity, services: [], receivingActive: false };

    const { services, userId: _owner, ...profile } = proProfile;
    void _owner;
    return {
      profile,
      identity,
      services: services.map(stripService),
      receivingActive: isReceivingActive(proProfile),
    };
  }

  async upsertProfile(userId: string, dto: UpsertProProfileDto): Promise<ProProfileView> {
    if (dto.priceMin != null && dto.priceMax != null && dto.priceMin > dto.priceMax) {
      throw new BadRequestException('priceMin must not exceed priceMax');
    }
    const data = {
      profession: dto.profession.trim(),
      description: dto.description.trim(),
      city: dto.city.trim(),
      zones: tidy(dto.zones),
      modes: dto.modes,
      availability: dto.availability.trim(),
      priceMin: dto.priceMin ?? null,
      priceMax: dto.priceMax ?? null,
      shopUrl: dto.shopUrl.trim(),
      whatsapp: dto.whatsapp?.trim() || null,
    };
    await this.prisma.proProfile.upsert({
      where: { userId },
      create: { userId, ...data },
      update: data,
    });
    return this.getProfile(userId);
  }

  /** AI proposals only — nothing is saved until the pro validates (Data §4). */
  structure(text: string): Promise<StructuredServices> {
    return this.ai.structureServices(text);
  }

  /**
   * One turn of the setup conversation. Nothing is saved: the app confirms
   * the finished draft through [upsertProfile] and [addServices]. The first
   * turn starts from whatever profile already exists, so a pro whose profile
   * holds placeholders is only asked for what is really missing.
   */
  async assistantTurn(userId: string, dto: AssistantTurnDto): Promise<AssistantTurn> {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: {
        name: true,
        country: true,
        proProfile: {
          include: { services: { where: { isActive: true }, select: { name: true } } },
        },
      },
    });
    const pro = user.proProfile;
    const start: ProDraft = (dto.draft as ProDraft | undefined) ?? {
      profile: {
        profession: pro?.profession ?? null,
        description: pro?.description ?? null,
        city: pro?.city ?? null,
        zones: pro?.zones ?? [],
        modes: pro?.modes ?? [],
        availability: pro?.availability ?? null,
        priceMin: pro?.priceMin ?? null,
        priceMax: pro?.priceMax ?? null,
        shopUrl: pro?.shopUrl ?? null,
      },
      services: [],
    };
    return this.assistant.turn(
      {
        name: user.name,
        country: user.country,
        existingServices: pro?.services.map((s) => s.name) ?? [],
      },
      dto.messages,
      sanitise(start),
    );
  }

  async addServices(userId: string, dto: AddServicesDto): Promise<ProProfileView> {
    const pro = await this.requireProfile(userId);
    const rows = dto.services.map((s) => serviceData(s, pro.profession));
    const embeddings = await this.ai.embed(rows.map(serviceDocument), 'RETRIEVAL_DOCUMENT');
    await this.prisma.proService.createMany({
      data: rows.map((row, i) => ({ ...row, proId: pro.id, embedding: embeddings[i] })),
    });
    return this.getProfile(userId);
  }

  async updateService(
    userId: string,
    serviceId: string,
    dto: UpdateServiceDto,
  ): Promise<ProProfileView> {
    const pro = await this.requireProfile(userId);
    const current = await this.ownService(pro.id, serviceId);
    const merged = { ...current, ...definedOnly(dto) } as ProServiceRow;
    const textChanged = (
      ['name', 'category', 'profession', 'synonyms', 'specialties'] as const
    ).some((k) => dto[k] !== undefined);
    const [embedding] = textChanged
      ? await this.ai.embed([serviceDocument(merged)], 'RETRIEVAL_DOCUMENT')
      : [undefined];

    await this.prisma.proService.update({
      where: { id: serviceId },
      data: { ...definedOnly(dto), ...(embedding ? { embedding } : {}) },
    });
    return this.getProfile(userId);
  }

  async deleteService(userId: string, serviceId: string): Promise<ProProfileView> {
    const pro = await this.requireProfile(userId);
    await this.ownService(pro.id, serviceId);
    await this.prisma.proService.delete({ where: { id: serviceId } });
    return this.getProfile(userId);
  }

  // ── Inbox ─────────────────────────────────────────────────────────────────

  async inbox(userId: string, query: InboxQueryDto): Promise<PaginatedResult<InboxItemView>> {
    const pro = await this.requireProfile(userId);
    const where: Prisma.RequestDispatchWhereInput = {
      proId: pro.id,
      ...(query.status ? { status: query.status } : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.requestDispatch.findMany({
        where,
        include: { request: true, service: true },
        orderBy: { createdAt: 'desc' },
        skip: query.skip,
        take: query.limit,
      }),
      this.prisma.requestDispatch.count({ where }),
    ]);
    return paginate(rows.map(toInboxItem), total, query.page, query.limit);
  }

  /** Opening a request marks it seen and is logged (Data §22). */
  async inboxItem(userId: string, requestId: string): Promise<InboxItemView> {
    const dispatch = await this.ownDispatch(userId, requestId);
    if (dispatch.status === DispatchStatus.SENT) {
      await this.prisma.requestDispatch.update({
        where: { id: dispatch.id },
        data: { status: DispatchStatus.VIEWED, viewedAt: new Date() },
      });
      dispatch.status = DispatchStatus.VIEWED;
      dispatch.viewedAt = new Date();
    }
    await this.audit.record({
      actorId: userId,
      action: 'sbc-data.request.view',
      resource: `ServiceRequest:${requestId}`,
    });
    return toInboxItem(dispatch);
  }

  async respond(userId: string, requestId: string, dto: RespondDto): Promise<InboxItemView> {
    const dispatch = await this.ownDispatch(userId, requestId);
    if (
      !OPEN_DISPATCH.includes(dispatch.status) ||
      !OPEN_REQUEST.includes(dispatch.request.status)
    ) {
      throw new ConflictException('Cette demande n’accepte plus de réponse');
    }
    if (dto.action === 'INTERESTED' && !dto.availability?.trim()) {
      throw new BadRequestException('La disponibilité est obligatoire pour une proposition');
    }
    if (dto.action === 'QUESTION' && !dto.message?.trim()) {
      throw new BadRequestException('Écris ta question');
    }

    const status = DispatchStatus[dto.action];
    const updated = await this.prisma.$transaction(async (tx) => {
      const row = await tx.requestDispatch.update({
        where: { id: dispatch.id },
        data: {
          status,
          price: dto.price ?? null,
          availability: dto.availability?.trim() || null,
          delay: dto.delay?.trim() || null,
          message: dto.message?.trim() || null,
          respondedAt: new Date(),
          viewedAt: dispatch.viewedAt ?? new Date(),
        },
        include: { request: true, service: true },
      });
      if (status === DispatchStatus.INTERESTED && row.request.status === RequestStatus.SENT) {
        await tx.serviceRequest.update({
          where: { id: requestId },
          data: { status: RequestStatus.RESPONDED },
        });
        row.request.status = RequestStatus.RESPONDED;
      }
      return row;
    });

    if (status === DispatchStatus.INTERESTED || status === DispatchStatus.QUESTION) {
      const pro = await this.prisma.proProfile.findUniqueOrThrow({
        where: { id: dispatch.proId },
        select: { profession: true, user: { select: { name: true } } },
      });
      const who = pro.user.name?.trim() || pro.profession;
      const what = dispatch.request.service ?? 'ta demande';
      await this.notifications.create({
        userId: dispatch.request.userId,
        type: NotificationType.REQUEST_RESPONSE,
        title:
          status === DispatchStatus.INTERESTED
            ? 'Nouvelle réponse à ta demande'
            : 'Un professionnel a une question',
        body:
          status === DispatchStatus.INTERESTED
            ? `${who} est disponible pour : ${what}.`
            : `${who} : ${dto.message!.trim()}`,
        data: { requestId, dispatchId: dispatch.id },
      });
    }
    return toInboxItem(updated);
  }

  async stats(userId: string): Promise<ProStats> {
    const pro = await this.requireProfile(userId);
    const [byStatus, completed, services] = await this.prisma.$transaction([
      this.prisma.requestDispatch.groupBy({
        by: ['status'],
        where: { proId: pro.id },
        _count: { _all: true },
        orderBy: { status: 'asc' },
      }),
      this.prisma.requestDispatch.count({
        where: {
          proId: pro.id,
          status: DispatchStatus.SELECTED,
          request: { status: RequestStatus.COMPLETED },
        },
      }),
      this.prisma.requestDispatch.groupBy({
        by: ['serviceId'],
        where: { proId: pro.id, serviceId: { not: null } },
        _count: { _all: true },
        orderBy: { _count: { serviceId: 'desc' } },
        take: 5,
      }),
    ]);

    const count = (s: DispatchStatus) =>
      (byStatus.find((r) => r.status === s)?._count as { _all: number } | undefined)?._all ?? 0;
    const received = Object.values(DispatchStatus).reduce((n, s) => n + count(s), 0);
    const unanswered = count(DispatchStatus.SENT) + count(DispatchStatus.VIEWED);
    const selected = count(DispatchStatus.SELECTED);
    // Won or lost after answering "interested" — the pool conversion is measured on.
    const interested = count(DispatchStatus.INTERESTED) + selected + count(DispatchStatus.LOST);
    const responded = received - unanswered;

    const names = await this.prisma.proService.findMany({
      where: { id: { in: services.map((s) => s.serviceId!) } },
      select: { id: true, name: true },
    });
    return {
      received,
      responded,
      interested,
      selected,
      completed,
      responseRate: received ? responded / received : 0,
      conversionRate: interested ? selected / interested : 0,
      topServices: services.map((s) => ({
        name: names.find((n) => n.id === s.serviceId)?.name ?? '—',
        count: (s._count as { _all: number })._all,
      })),
    };
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  private async requireProfile(userId: string) {
    const pro = await this.prisma.proProfile.findUnique({ where: { userId } });
    if (!pro) throw new NotFoundException('Crée d’abord ton profil professionnel');
    return pro;
  }

  private async ownService(proId: string, serviceId: string) {
    const service = await this.prisma.proService.findUnique({ where: { id: serviceId } });
    if (!service || service.proId !== proId) throw new NotFoundException('Service introuvable');
    return service;
  }

  /** The pro's dispatch for [requestId] — a request never sent to you does not exist for you. */
  private async ownDispatch(userId: string, requestId: string) {
    const pro = await this.requireProfile(userId);
    const dispatch = await this.prisma.requestDispatch.findUnique({
      where: { requestId_proId: { requestId, proId: pro.id } },
      include: { request: true, service: true },
    });
    if (!dispatch) throw new NotFoundException('Demande introuvable');
    if (dispatch.request.status === RequestStatus.CANCELLED) {
      throw new ForbiddenException('Cette demande a été annulée');
    }
    return dispatch;
  }
}

function serviceData(s: ProServiceInputDto, fallbackProfession: string) {
  return {
    name: s.name.trim(),
    category: s.category.trim() || s.name.trim(),
    profession: s.profession.trim() || fallbackProfession,
    synonyms: tidy(s.synonyms),
    specialties: tidy(s.specialties),
    description: s.description?.trim() || null,
    priceMin: s.priceMin ?? null,
    priceMax: s.priceMax ?? null,
    modes: s.modes ?? [],
    zones: tidy(s.zones),
    delay: s.delay?.trim() || null,
  };
}

function tidy(values: string[] | undefined): string[] {
  return [...new Set((values ?? []).map((v) => v.trim()).filter(Boolean))];
}

function definedOnly<T extends object>(o: T): Partial<T> {
  return Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as Partial<T>;
}

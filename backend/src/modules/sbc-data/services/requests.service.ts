import { InjectQueue } from '@nestjs/bullmq';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  DispatchStatus,
  NotificationType,
  Prisma,
  RequestStatus,
  ServiceMode,
  ServiceRequest,
} from '@prisma/client';
import { Queue } from 'bullmq';
import { PaginatedResult, paginate } from '../../../common/dto/pagination.dto';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { QUEUE_NAMES } from '../../../infrastructure/queue/queue.module';
import { AuditService } from '../../audit/audit.service';
import { NotificationsService } from '../../notifications/notifications.service';
import { confidenceScore } from '../../reviews/confidence-score';
import { ReviewsService } from '../../reviews/reviews.service';
import { RequestAnalysis, SbcDataAiService } from '../ai/sbc-data-ai.service';
import {
  CompleteRequestDto,
  CreateRequestDto,
  RequestsQueryDto,
  UpdateRequestDto,
} from '../dto/sbc-data.dto';
import {
  MAX_RESPONSES,
  MatchCandidate,
  RequestMatchingService,
} from '../matching/request-matching.service';
import { RequestView, ResponseView, toPublicView } from '../sbc-data.views';

/** Answers the requester sees and can choose from (Data §11). */
const VISIBLE_ANSWERS: DispatchStatus[] = [
  DispatchStatus.INTERESTED,
  DispatchStatus.QUESTION,
  DispatchStatus.SELECTED,
  DispatchStatus.LOST,
];

/** Dispatches that close once somebody else is chosen. */
const STILL_OPEN: DispatchStatus[] = [
  DispatchStatus.SENT,
  DispatchStatus.VIEWED,
  DispatchStatus.INTERESTED,
  DispatchStatus.QUESTION,
];

const MODE_LABEL: Record<ServiceMode, string> = {
  HOME: 'À domicile',
  ON_SITE: 'Sur place',
  ONLINE: 'En ligne',
  DELIVERY: 'Livraison',
};

/** Routed but still unanswered after this long → NO_RESPONSE (Data §16). */
const RESPONSE_TIMEOUT_MS = 48 * 60 * 60 * 1000; // 48h

/**
 * The requester's side of SBC Data: describe → check the AI's reading →
 * send → compare answers → choose → confirm and rate (Data §6–§16).
 */
@Injectable()
export class RequestsService {
  private readonly logger = new Logger(RequestsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly ai: SbcDataAiService,
    private readonly matching: RequestMatchingService,
    private readonly notifications: NotificationsService,
    private readonly reviews: ReviewsService,
    private readonly audit: AuditService,
    @InjectQueue(QUEUE_NAMES.SBC_DATA) private readonly queue: Queue,
  ) {}

  /** Analyse the free text and keep it as a draft to review (Data §6: summary before sending). */
  async create(userId: string, dto: CreateRequestDto): Promise<RequestView> {
    const analysis = await this.ai.analyzeRequest(dto.text);
    const request = await this.prisma.serviceRequest.create({
      data: {
        userId,
        rawText: dto.text.trim(),
        ...analysisData(analysis),
        // What the requester typed in the optional fields beats the AI's reading.
        ...(dto.city ? { city: dto.city.trim() } : {}),
        ...(dto.budget != null ? { budget: dto.budget } : {}),
        ...(dto.desiredDate ? { desiredDate: dto.desiredDate.trim() } : {}),
        ...(dto.mode ? { mode: dto.mode } : {}),
      },
    });
    return this.view(request);
  }

  /** Correct the reading, or answer the AI's question (which re-runs the analysis). */
  async update(userId: string, id: string, dto: UpdateRequestDto): Promise<RequestView> {
    const current = await this.own(userId, id);
    if (current.status !== RequestStatus.DRAFT) {
      throw new ConflictException('Une demande envoyée ne se modifie plus');
    }

    let data: Prisma.ServiceRequestUpdateInput = {};
    const answer = dto.clarificationAnswer?.trim();
    if (answer) {
      const analysis = await this.ai.analyzeRequest(current.rawText, answer);
      data = { ...analysisData(analysis), clarificationAnswer: answer };
    }
    const { clarificationAnswer: _answer, ...fields } = dto;
    void _answer;
    for (const [key, value] of Object.entries(fields)) {
      if (value !== undefined)
        (data as Record<string, unknown>)[key] = typeof value === 'string' ? value.trim() : value;
    }

    const request = await this.prisma.serviceRequest.update({ where: { id }, data });
    return this.view(request);
  }

  /** "Envoyer ma demande" — matching and routing happen on the queue. */
  async send(userId: string, id: string): Promise<RequestView> {
    const current = await this.own(userId, id);
    if (current.status !== RequestStatus.DRAFT) {
      throw new ConflictException('Cette demande est déjà envoyée');
    }
    if (current.clarificationQuestion && !current.clarificationAnswer) {
      throw new BadRequestException('Réponds d’abord à la question');
    }
    const request = await this.prisma.serviceRequest.update({
      where: { id },
      data: { status: RequestStatus.MATCHING, sentAt: new Date() },
    });
    await this.queue.add('match', { requestId: id }, { jobId: `match-${id}` });
    return this.view(request);
  }

  /**
   * Queue worker: find the pros, route the request, tell them (Data §8, §9).
   * Idempotent — a retried job only finishes a request still MATCHING.
   */
  async runMatching(id: string): Promise<void> {
    const request = await this.prisma.serviceRequest.findUnique({ where: { id } });
    if (!request || request.status !== RequestStatus.MATCHING) return;

    let embedding = request.embedding;
    if (embedding.length === 0) {
      [embedding] = await this.ai.embed([requestDocument(request)], 'RETRIEVAL_QUERY');
    }
    const candidates = await this.matching.match({ ...request, embedding });

    await this.prisma.$transaction(async (tx) => {
      if (candidates.length) {
        await tx.requestDispatch.createMany({
          data: candidates.map((c) => dispatchData(id, c)),
          skipDuplicates: true,
        });
      }
      await tx.serviceRequest.update({
        where: { id },
        data: {
          embedding,
          status: candidates.length ? RequestStatus.SENT : RequestStatus.NO_MATCH,
        },
      });
      // Predictive market analytics (Data §E): log what was sought and how many
      // pros it reached. A zero here is an unfulfilled demand the admin report
      // aggregates to find which professions to recruit for.
      await tx.searchAnalytics.create({
        data: {
          userId: request.userId,
          requestId: id,
          term: analyticsTerm(request),
          profession: request.profession,
          city: request.city,
          mode: request.mode,
          matchedVendorCount: candidates.length,
          fulfilled: candidates.length > 0,
        },
      });
    });
    this.logger.log(`Request ${id} routed to ${candidates.length} pro(s)`);

    if (candidates.length === 0) return;
    const pros = await this.prisma.proProfile.findMany({
      where: { id: { in: candidates.map((c) => c.proId) } },
      select: { id: true, userId: true },
    });
    for (const pro of pros) {
      await this.notifications.create({
        userId: pro.userId,
        type: NotificationType.REQUEST_RECEIVED,
        title: 'Nouvelle demande correspondant à vos services',
        body: notificationBody(request),
        data: { requestId: id },
      });
    }
  }

  async list(userId: string, query: RequestsQueryDto): Promise<PaginatedResult<RequestView>> {
    const where: Prisma.ServiceRequestWhereInput = {
      userId,
      ...(query.status ? { status: query.status } : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.serviceRequest.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: query.skip,
        take: query.limit,
      }),
      this.prisma.serviceRequest.count({ where }),
    ]);
    const items = await Promise.all(rows.map((r) => this.view(r)));
    return paginate(items, total, query.page, query.limit);
  }

  async get(userId: string, id: string): Promise<RequestView> {
    return this.view(await this.own(userId, id));
  }

  /** "Retenir ce professionnel" (Data §12). The others learn it is closed. */
  async select(userId: string, id: string, dispatchId: string): Promise<RequestView> {
    const request = await this.own(userId, id);
    const choosable: RequestStatus[] = [
      RequestStatus.SENT,
      RequestStatus.RESPONDED,
      RequestStatus.LOCKED,
    ];
    if (!choosable.includes(request.status)) {
      throw new ConflictException('Un professionnel est déjà retenu, ou la demande est close');
    }
    const chosen = await this.prisma.requestDispatch.findUnique({
      where: { id: dispatchId },
      include: { pro: { select: { userId: true } } },
    });
    if (!chosen || chosen.requestId !== id) throw new NotFoundException('Réponse introuvable');
    if (chosen.status !== DispatchStatus.INTERESTED && chosen.status !== DispatchStatus.QUESTION) {
      throw new ConflictException('Ce professionnel ne s’est pas proposé');
    }

    const others = await this.prisma.requestDispatch.findMany({
      where: { requestId: id, id: { not: dispatchId }, status: { in: STILL_OPEN } },
      include: { pro: { select: { userId: true } } },
    });
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.requestDispatch.update({
        where: { id: dispatchId },
        data: { status: DispatchStatus.SELECTED },
      });
      await tx.requestDispatch.updateMany({
        where: { id: { in: others.map((o) => o.id) } },
        data: { status: DispatchStatus.LOST },
      });
      return tx.serviceRequest.update({
        where: { id },
        data: { status: RequestStatus.SELECTED, selectedDispatchId: dispatchId },
      });
    });

    const what = request.service ?? 'la demande';
    await this.notifications.create({
      userId: chosen.pro.userId,
      type: NotificationType.REQUEST_SELECTED,
      title: 'Ta proposition a été retenue',
      body: `Pour : ${what}. La personne qui a fait la demande va te contacter.`,
      data: { requestId: id },
    });
    // Only pros who spent effort answering hear back; the silent ones just see
    // the request as closed in their inbox.
    for (const o of others.filter((o) => o.respondedAt)) {
      await this.notifications.create({
        userId: o.pro.userId,
        type: NotificationType.REQUEST_CLOSED,
        title: 'Demande pourvue',
        body: `Un autre professionnel a été retenu pour : ${what}.`,
        data: { requestId: id },
      });
    }
    return this.view(updated);
  }

  /** Confirm the job and rate the pro, or report it as not done (Data §15). */
  async complete(
    userId: string,
    sbcUserId: string,
    id: string,
    dto: CompleteRequestDto,
  ): Promise<RequestView> {
    const request = await this.own(userId, id);
    if (request.status !== RequestStatus.SELECTED || !request.selectedDispatchId) {
      throw new ConflictException('Retiens d’abord un professionnel');
    }
    const chosen = await this.prisma.requestDispatch.findUniqueOrThrow({
      where: { id: request.selectedDispatchId },
      include: { pro: { include: { user: { select: { sbcUserId: true } } } } },
    });

    const updated = await this.prisma.serviceRequest.update({
      where: { id },
      data: {
        status: RequestStatus.COMPLETED,
        completedAt: new Date(),
        wasPerformed: dto.performed,
      },
    });

    if (dto.performed && dto.stars) {
      // Ratings go through the member reviews, so the pro's "score de
      // confiance" everywhere in the app reflects jobs actually done.
      await this.reviews.upsert(userId, sbcUserId, {
        memberSbcId: chosen.pro.user.sbcUserId,
        stars: dto.stars,
        comment: dto.comment,
      });
    }
    if (!dto.performed) {
      // A report for the back-office (Data §15, §21) until it has its own screen.
      await this.audit.record({
        actorId: userId,
        action: 'sbc-data.request.reported',
        resource: `ServiceRequest:${id}`,
        metadata: { proId: chosen.proId, comment: dto.comment ?? null },
      });
    }
    return this.view(updated);
  }

  async cancel(userId: string, id: string): Promise<RequestView> {
    const request = await this.own(userId, id);
    const closed: RequestStatus[] = [RequestStatus.COMPLETED, RequestStatus.CANCELLED];
    if (closed.includes(request.status))
      throw new ConflictException('Cette demande est déjà close');
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.requestDispatch.updateMany({
        where: { requestId: id, status: { in: STILL_OPEN } },
        data: { status: DispatchStatus.LOST },
      });
      return tx.serviceRequest.update({ where: { id }, data: { status: RequestStatus.CANCELLED } });
    });
    return this.view(updated);
  }

  /**
   * Queue sweep: a request routed but never accepted within RESPONSE_TIMEOUT_MS
   * is closed as NO_RESPONSE and the requester is told (Data §16). An accepted
   * request has already left SENT (the first "interested" flips it to
   * RESPONDED), so "still SENT past the deadline" is exactly "nobody answered".
   */
  async closeStale(now = new Date()): Promise<number> {
    const cutoff = new Date(now.getTime() - RESPONSE_TIMEOUT_MS);
    const stale = await this.prisma.serviceRequest.findMany({
      where: { status: RequestStatus.SENT, sentAt: { lt: cutoff } },
      select: { id: true, userId: true, service: true },
    });
    for (const r of stale) {
      await this.prisma.$transaction([
        this.prisma.requestDispatch.updateMany({
          where: { requestId: r.id, status: { in: STILL_OPEN } },
          data: { status: DispatchStatus.LOST },
        }),
        this.prisma.serviceRequest.update({
          where: { id: r.id },
          data: { status: RequestStatus.NO_RESPONSE },
        }),
      ]);
      await this.notifications.create({
        userId: r.userId,
        type: NotificationType.REQUEST_NO_RESPONSE,
        title: 'Aucune réponse à ta demande',
        body: `Personne n’a répondu à temps pour : ${r.service ?? 'ta demande'}. Tu peux la renvoyer ou l’ajuster.`,
        data: { requestId: r.id },
      });
    }
    if (stale.length) this.logger.log(`Closed ${stale.length} stale request(s) as NO_RESPONSE`);
    return stale.length;
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  private async own(userId: string, id: string): Promise<ServiceRequest> {
    const request = await this.prisma.serviceRequest.findUnique({ where: { id } });
    if (!request || request.userId !== userId) throw new NotFoundException('Demande introuvable');
    return request;
  }

  private async view(request: ServiceRequest): Promise<RequestView> {
    const dispatches = await this.prisma.requestDispatch.findMany({
      where: { requestId: request.id },
      include: {
        service: { select: { name: true } },
        pro: {
          include: {
            user: { select: { sbcUserId: true, name: true, avatarUrl: true, phoneNumber: true } },
          },
        },
      },
      orderBy: [{ respondedAt: 'asc' }],
    });
    const answered = dispatches.filter((d) => VISIBLE_ANSWERS.includes(d.status) && d.respondedAt);
    const scores = await this.prisma.memberScore.findMany({
      where: { memberSbcId: { in: answered.map((d) => d.pro.user.sbcUserId) } },
    });

    const responses: ResponseView[] = answered.map((d) => {
      const score = scores.find((s) => s.memberSbcId === d.pro.user.sbcUserId);
      return {
        dispatchId: d.id,
        status: d.status,
        pro: {
          userId: d.pro.userId,
          sbcUserId: d.pro.user.sbcUserId,
          name: d.pro.user.name,
          avatarUrl: d.pro.user.avatarUrl,
          profession: d.pro.profession,
          city: d.pro.city,
          whatsapp: d.pro.whatsapp ?? d.pro.user.phoneNumber,
          shopUrl: d.pro.shopUrl,
          confidenceScore: confidenceScore(score?.averageStars ?? 0, score?.reviewCount ?? 0),
          reviewCount: score?.reviewCount ?? 0,
        },
        serviceName: d.service?.name ?? null,
        price: d.price,
        availability: d.availability,
        delay: d.delay,
        message: d.message,
        respondedAt: d.respondedAt,
      };
    });

    return {
      ...toPublicView(request),
      clarificationQuestion: request.clarificationQuestion,
      clarificationOptions: request.clarificationOptions,
      clarificationAnswer: request.clarificationAnswer,
      sentAt: request.sentAt,
      completedAt: request.completedAt,
      wasPerformed: request.wasPerformed,
      selectedDispatchId: request.selectedDispatchId,
      dispatchedCount: dispatches.length,
      responseCount: request.responseCount,
      responseLimit: MAX_RESPONSES,
      responses,
    };
  }
}

function analysisData(a: RequestAnalysis) {
  return {
    profession: a.profession,
    service: a.service,
    specialties: a.specialties,
    city: a.city,
    district: a.district,
    mode: a.mode,
    desiredDate: a.desiredDate,
    desiredTime: a.desiredTime,
    budget: a.budget,
    constraints: a.constraints,
    clarificationQuestion: a.clarificationQuestion,
    clarificationOptions: a.clarificationOptions,
  };
}

function dispatchData(requestId: string, c: MatchCandidate): Prisma.RequestDispatchCreateManyInput {
  return {
    requestId,
    proId: c.proId,
    serviceId: c.serviceId,
    score: c.score,
    reasons: c.reasons as unknown as Prisma.InputJsonValue,
  };
}

/** The search term an analytics event is grouped by (Data §E). */
function analyticsTerm(r: Pick<ServiceRequest, 'service' | 'profession' | 'rawText'>): string {
  return (r.service || r.profession || r.rawText).trim().slice(0, 120);
}

/** What the request is embedded as for semantic matching. */
export function requestDocument(
  r: Pick<ServiceRequest, 'rawText' | 'profession' | 'service' | 'specialties'>,
): string {
  return [r.profession, r.service, r.specialties.join(', '), r.rawText].filter(Boolean).join('. ');
}

/** The notification a pro receives (Data §9). */
export function notificationBody(
  r: Pick<ServiceRequest, 'service' | 'city' | 'district' | 'mode' | 'desiredDate' | 'budget'>,
): string {
  const place = [r.district, r.city].filter(Boolean).join(', ');
  return [
    `Besoin : ${r.service ?? 'voir la demande'}`,
    place && `Lieu : ${place}`,
    r.mode && `Prestation : ${MODE_LABEL[r.mode]}`,
    r.desiredDate && `Date : ${r.desiredDate}`,
    r.budget && `Budget : ${r.budget.toLocaleString('fr-FR')} FCFA`,
  ]
    .filter(Boolean)
    .join('\n');
}

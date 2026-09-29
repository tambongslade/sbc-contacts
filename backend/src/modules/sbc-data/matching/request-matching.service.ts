import { Injectable } from '@nestjs/common';
import { ProProfile, ProService, ServiceMode, ServiceRequest } from '@prisma/client';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { SbcDataAiService } from '../ai/sbc-data-ai.service';
import { cosine, coverage, fold, samePlace, tokens } from '../text';

/** Most pros one request is sent to. More would only spam the long tail. */
export const MAX_DISPATCHES = 10;
/** Most services the AI judge sees for one request. */
const SHORTLIST = 20;
/** Below this, a service is not a candidate at all. */
const MIN_RETRIEVAL = 0.25;
/** Below this AI relevance, a shortlisted service is dropped. */
const MIN_RELEVANCE = 0.5;

type ServiceWithPro = ProService & { pro: ProProfile };

type RequestForMatching = Pick<
  ServiceRequest,
  | 'userId'
  | 'rawText'
  | 'profession'
  | 'service'
  | 'specialties'
  | 'city'
  | 'district'
  | 'mode'
  | 'budget'
  | 'embedding'
>;

/** Why a pro was picked — stored on the dispatch for the matching logs (Data §21). */
export interface MatchReasons {
  keyword: number;
  semantic: number;
  profession: boolean;
  budgetFit: number;
  retrieval: number;
  relevance: number | null;
  location: string;
}

export interface MatchCandidate {
  proId: string;
  serviceId: string;
  score: number;
  reasons: MatchReasons;
}

/**
 * Decides which pros receive a request (Data §8).
 *
 * Three stages, cheapest first:
 *  1. hard filters — active subscription, location, delivery mode;
 *  2. retrieval — keyword coverage + embedding similarity + profession + budget;
 *  3. an AI judge over the shortlist only, because embeddings alone rank a
 *     plumber's "réparation de fuites" close to a "réparation de locks".
 */
@Injectable()
export class RequestMatchingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ai: SbcDataAiService,
  ) {}

  async match(request: RequestForMatching, now = new Date()): Promise<MatchCandidate[]> {
    const services = await this.prisma.proService.findMany({
      where: {
        isActive: true,
        pro: {
          receivingEnabled: true,
          userId: { not: request.userId },
          OR: [{ receivingUntil: null }, { receivingUntil: { gt: now } }],
        },
      },
      include: { pro: true },
    });

    const shortlist = bestPerPro(
      services
        .map((s) => scoreService(request, s))
        .filter((c): c is MatchCandidate => c !== null && c.reasons.retrieval >= MIN_RETRIEVAL),
    )
      .sort((a, b) => b.score - a.score)
      .slice(0, SHORTLIST);

    const byId = new Map(services.map((s) => [s.id, s]));
    const verdicts = await this.ai.judge(
      request,
      shortlist.map((c) => {
        const s = byId.get(c.serviceId)!;
        return {
          id: s.id,
          service: s.name,
          category: s.category,
          profession: s.profession,
          specialties: s.specialties,
        };
      }),
    );

    return applyVerdicts(shortlist, verdicts).slice(0, MAX_DISPATCHES);
  }
}

/** Stage 1 + 2 for one service; null when a hard filter rules it out. */
export function scoreService(
  request: RequestForMatching,
  service: ServiceWithPro,
): MatchCandidate | null {
  const modes = service.modes.length ? service.modes : service.pro.modes;
  const zones = service.zones.length ? service.zones : service.pro.zones;

  // Delivery mode: a pro who never comes to the client can't take a HOME job.
  // An empty list means the pro did not say, which we do not hold against them.
  if (request.mode && modes.length && !modes.includes(request.mode)) return null;

  // Location matters unless the job is done remotely.
  let location = 'non précisé';
  const remote = request.mode === ServiceMode.ONLINE || request.mode === ServiceMode.DELIVERY;
  if (request.city && !remote) {
    const place = [service.pro.city, ...zones].find(
      (z) => samePlace(z, request.city) || (request.district && samePlace(z, request.district)),
    );
    if (!place) return null;
    location = place;
  } else if (remote) {
    location = 'à distance';
  }

  const need = tokens(
    request.service,
    ...request.specialties,
    request.service ? null : request.rawText,
  );
  const offer = tokens(
    service.name,
    service.category,
    service.profession,
    ...service.synonyms,
    ...service.specialties,
  );
  const keyword = coverage(need, offer);
  const semantic = Math.max(0, cosine(request.embedding, service.embedding));
  const profession =
    coverage(tokens(request.profession), tokens(service.profession, service.pro.profession)) > 0;
  const budgetFit = budgetScore(request.budget, service.priceMin ?? service.pro.priceMin);

  // Embeddings sit around 0.6–0.75 for anything in the same language, so only
  // the part above 0.6 carries signal.
  const semanticSignal = Math.max(0, (semantic - 0.6) / 0.4);
  const retrieval = Math.min(1, 0.45 * keyword + 0.35 * semanticSignal + (profession ? 0.2 : 0));

  return {
    proId: service.proId,
    serviceId: service.id,
    score: retrieval * 0.9 + budgetFit * 0.1,
    reasons: { keyword, semantic, profession, budgetFit, retrieval, relevance: null, location },
  };
}

/** 1 = within budget or unknown, falling to 0 at twice the budget. */
export function budgetScore(budget: number | null, priceFrom: number | null | undefined): number {
  if (!budget || !priceFrom) return 1;
  if (priceFrom <= budget) return 1;
  return Math.max(0, 1 - (priceFrom - budget) / budget);
}

/** A pro receives a request once, for their best-fitting service. */
export function bestPerPro(candidates: MatchCandidate[]): MatchCandidate[] {
  const best = new Map<string, MatchCandidate>();
  for (const c of candidates) {
    const cur = best.get(c.proId);
    if (!cur || c.score > cur.score) best.set(c.proId, c);
  }
  return [...best.values()];
}

/**
 * Stage 3. With a verdict, relevance dominates the ranking and weak matches are
 * dropped; without one (AI down), only services whose words actually meet the
 * request survive, so an outage narrows the audience instead of spamming it.
 */
export function applyVerdicts(
  shortlist: MatchCandidate[],
  verdicts: Map<string, number> | null,
): MatchCandidate[] {
  const kept = shortlist.flatMap((c) => {
    if (verdicts === null) return c.reasons.keyword > 0 ? [c] : [];
    const relevance = verdicts.get(c.serviceId) ?? 0;
    if (relevance < MIN_RELEVANCE) return [];
    return [{ ...c, score: 0.6 * relevance + 0.4 * c.score, reasons: { ...c.reasons, relevance } }];
  });
  return kept.sort((a, b) => b.score - a.score);
}

/** The text a service is embedded as — also what the judge reads. */
export function serviceDocument(
  s: Pick<ProService, 'name' | 'category' | 'profession' | 'synonyms' | 'specialties'>,
): string {
  return [s.profession, s.category, s.name, s.synonyms.join(', '), s.specialties.join(', ')]
    .filter((p) => fold(p))
    .join('. ');
}

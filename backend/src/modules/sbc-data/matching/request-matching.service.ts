import { Injectable } from '@nestjs/common';
import { ProProfile, ProService, ServiceMode, ServiceRequest } from '@prisma/client';
import { distanceKm, toLatLng } from '../../../common/utils/geo';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { SbcDataAiService } from '../ai/sbc-data-ai.service';
import { cosine, coverage, fold, samePlace, tokens } from '../text';

/** Most pros one request is sent to. More would only spam the long tail. */
export const MAX_DISPATCHES = 10;
/**
 * Most "interested" answers a request accepts before it auto-locks (Data §C).
 * The request is broadcast to up to MAX_DISPATCHES pros, but the first
 * MAX_RESPONSES to say they can do it close it — the rest learn it is full.
 */
export const MAX_RESPONSES = 5;
/** Most services the AI judge sees for one request. */
const SHORTLIST = 20;
/** Below this, a service is not a candidate at all. */
const MIN_RETRIEVAL = 0.25;
/** Below this AI relevance, a shortlisted service is dropped. */
const MIN_RELEVANCE = 0.5;
/** Within this, a pro is "près de toi": they qualify whatever their zones say. */
export const NEARBY_KM = 15;
/** With no city named, a pro further than this is in another town. */
export const FAR_KM = 50;
/**
 * A pro's position older than this no longer counts as where they are. Pros are
 * mostly stationary — a shop, a usual working area — and many open the app only
 * every few days, so a 3-day window needlessly dropped them from "près de toi"
 * and could exclude them when a city was named. Two weeks keeps a recent fix
 * useful without pinning a pro to a place they may have left.
 */
export const PRO_LOCATION_TTL_MS = 14 * 24 * 60 * 60 * 1000;

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
  | 'latitude'
  | 'longitude'
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
  /** Requester ↔ pro, exact; only ever shown rounded. Null when unknown. */
  distanceKm: number | null;
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

    // Local pros first. When the request's town has none — a thin market, not a
    // bad fit — widening the net beats answering NO_MATCH: the requester still
    // reaches the pros whose service matches, wherever they are. The AI judge
    // still drops irrelevant services and the proximity ranking keeps the far
    // ones from topping the list, so this rescues, it does not spam.
    let scored = retrieve(request, services, now, false);
    if (scored.length === 0) scored = retrieve(request, services, now, true);

    const shortlist = bestPerPro(scored)
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
  now = new Date(),
  relaxLocation = false,
): MatchCandidate | null {
  const modes = service.modes.length ? service.modes : service.pro.modes;
  const zones = service.zones.length ? service.zones : service.pro.zones;

  // Delivery mode: a pro who never comes to the client can't take a HOME job.
  // An empty list means the pro did not say, which we do not hold against them.
  if (request.mode && modes.length && !modes.includes(request.mode)) return null;

  // Location matters unless the job is done remotely. A pro close by
  // qualifies on distance alone; otherwise the zones they named decide, as
  // they do for every pro who has not shared a position.
  let location = 'non précisé';
  const remote = request.mode === ServiceMode.ONLINE || request.mode === ServiceMode.DELIVERY;
  const distance = remote ? null : proDistance(request, service.pro, now);
  if (remote) {
    location = 'à distance';
  } else if (distance !== null && distance <= NEARBY_KM) {
    location = 'près de toi';
  } else if (request.city) {
    const place = [service.pro.city, ...zones].find(
      (z) => samePlace(z, request.city) || (request.district && samePlace(z, request.district)),
    );
    if (place) location = place;
    else if (!relaxLocation) return null;
    else location = 'autre zone';
  } else if (distance !== null && distance > FAR_KM) {
    if (!relaxLocation) return null;
    location = 'autre zone';
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
    score: retrieval * 0.75 + budgetFit * 0.1 + proximityScore(distance) * 0.15,
    reasons: {
      keyword,
      semantic,
      profession,
      budgetFit,
      retrieval,
      relevance: null,
      location,
      distanceKm: distance,
    },
  };
}

/** Requester ↔ pro in km, when both shared a position and the pro's is recent. */
export function proDistance(
  request: Pick<ServiceRequest, 'latitude' | 'longitude'>,
  pro: Pick<ProProfile, 'latitude' | 'longitude' | 'locatedAt'>,
  now = new Date(),
): number | null {
  const from = toLatLng(request);
  const to = toLatLng(pro);
  if (!from || !to || !pro.locatedAt) return null;
  if (now.getTime() - pro.locatedAt.getTime() > PRO_LOCATION_TTL_MS) return null;
  return distanceKm(from, to);
}

/**
 * 1 next door, falling to 0 at NEARBY_KM. Only a pro known to be close is
 * lifted: one who shares no position ranks like one who is far, as before.
 */
export function proximityScore(km: number | null): number {
  if (km === null) return 0;
  return Math.max(0, 1 - km / NEARBY_KM);
}

/** 1 = within budget or unknown, falling to 0 at twice the budget. */
export function budgetScore(budget: number | null, priceFrom: number | null | undefined): number {
  if (!budget || !priceFrom) return 1;
  if (priceFrom <= budget) return 1;
  return Math.max(0, 1 - (priceFrom - budget) / budget);
}

/** Stage 1 + 2 over every service, keeping only the real candidates. */
function retrieve(
  request: RequestForMatching,
  services: ServiceWithPro[],
  now: Date,
  relaxLocation: boolean,
): MatchCandidate[] {
  return services
    .map((s) => scoreService(request, s, now, relaxLocation))
    .filter((c): c is MatchCandidate => c !== null && c.reasons.retrieval >= MIN_RETRIEVAL);
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

import {
  DispatchStatus,
  ProProfile,
  ProService,
  RequestDispatch,
  RequestStatus,
  ServiceMode,
  ServiceRequest,
} from '@prisma/client';

/** What a pro sees of a request: the need, never who asked (Data §22). */
export interface RequestPublicView {
  id: string;
  rawText: string;
  status: RequestStatus;
  profession: string | null;
  service: string | null;
  specialties: string[];
  city: string | null;
  district: string | null;
  mode: ServiceMode | null;
  desiredDate: string | null;
  desiredTime: string | null;
  budget: number | null;
  constraints: string[];
  createdAt: Date;
}

/** The requester's own view, including the AI's question. */
export interface RequestView extends RequestPublicView {
  clarificationQuestion: string | null;
  clarificationOptions: string[];
  clarificationAnswer: string | null;
  sentAt: Date | null;
  completedAt: Date | null;
  wasPerformed: boolean | null;
  selectedDispatchId: string | null;
  /** Pros the request went to; answers are in `responses`. */
  dispatchedCount: number;
  responses: ResponseView[];
}

/** One pro's answer, as a comparable card (Data §11). */
export interface ResponseView {
  dispatchId: string;
  status: DispatchStatus;
  pro: {
    userId: string;
    sbcUserId: string;
    name: string | null;
    avatarUrl: string | null;
    profession: string;
    city: string;
    whatsapp: string | null;
    shopUrl: string;
    confidenceScore: number;
    reviewCount: number;
  };
  serviceName: string | null;
  price: number | null;
  availability: string | null;
  delay: string | null;
  message: string | null;
  respondedAt: Date | null;
}

/** A pro's inbox row (Data §18). */
export interface InboxItemView {
  dispatchId: string;
  status: DispatchStatus;
  matchedService: string | null;
  request: RequestPublicView;
  price: number | null;
  availability: string | null;
  delay: string | null;
  message: string | null;
  viewedAt: Date | null;
  respondedAt: Date | null;
  createdAt: Date;
}

export function toPublicView(r: ServiceRequest): RequestPublicView {
  return {
    id: r.id,
    rawText: r.rawText,
    status: r.status,
    profession: r.profession,
    service: r.service,
    specialties: r.specialties,
    city: r.city,
    district: r.district,
    mode: r.mode,
    desiredDate: r.desiredDate,
    desiredTime: r.desiredTime,
    budget: r.budget,
    constraints: r.constraints,
    createdAt: r.createdAt,
  };
}

export function toInboxItem(
  d: RequestDispatch & { request: ServiceRequest; service: ProService | null },
): InboxItemView {
  return {
    dispatchId: d.id,
    status: d.status,
    matchedService: d.service?.name ?? null,
    request: toPublicView(d.request),
    price: d.price,
    availability: d.availability,
    delay: d.delay,
    message: d.message,
    viewedAt: d.viewedAt,
    respondedAt: d.respondedAt,
    createdAt: d.createdAt,
  };
}

/** A pro's own profile and services, SBC identity included (Data §2–§3). */
export interface ProProfileView {
  profile: Omit<ProProfile, 'userId'> | null;
  identity: {
    name: string | null;
    avatarUrl: string | null;
    phoneNumber: string | null;
    country: string | null;
  };
  services: Array<Omit<ProService, 'embedding' | 'proId'>>;
  receivingActive: boolean;
}

export function isReceivingActive(
  p: Pick<ProProfile, 'receivingEnabled' | 'receivingUntil'> | null,
  now = new Date(),
): boolean {
  return Boolean(p?.receivingEnabled && (!p.receivingUntil || p.receivingUntil > now));
}

export function stripService(s: ProService): Omit<ProService, 'embedding' | 'proId'> {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const { embedding, proId, ...rest } = s;
  return rest;
}

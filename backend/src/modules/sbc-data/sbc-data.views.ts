import {
  DispatchMessage,
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
  /** "Interested" answers received so far, and the cap that locks it (Data §C). */
  responseCount: number;
  responseLimit: number;
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
  messages: MessageView[];
}

/** A pro's inbox row (Data §18). */
/** Dispatch states in which the pro and the requester can still talk. */
export const CONVERSATION_DISPATCH: DispatchStatus[] = [
  DispatchStatus.QUESTION,
  DispatchStatus.INTERESTED,
  DispatchStatus.SELECTED,
];

/** Request states that are over: no more talking, can be relaunched. */
export const CLOSED_REQUEST: RequestStatus[] = [
  RequestStatus.COMPLETED,
  RequestStatus.CANCELLED,
  RequestStatus.NO_MATCH,
  RequestStatus.NO_RESPONSE,
];

/** One line of a request conversation (Data §10). */
export interface MessageView {
  id: string;
  author: 'PRO' | 'REQUESTER';
  text: string;
  createdAt: Date;
}

export function toMessages(rows: DispatchMessage[] | undefined): MessageView[] {
  return (rows ?? []).map((m) => ({
    id: m.id,
    author: m.author,
    text: m.text,
    createdAt: m.createdAt,
  }));
}

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
  messages: MessageView[];
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
  d: RequestDispatch & {
    request: ServiceRequest;
    service: ProService | null;
    messages?: DispatchMessage[];
  },
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
    messages: toMessages(d.messages),
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

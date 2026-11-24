import {
  Attachment,
  DispatchMessage,
  Prisma,
  DispatchStatus,
  ProProfile,
  ProService,
  RequestDispatch,
  RequestStatus,
  ServiceMode,
  ServiceRequest,
} from '@prisma/client';
import { BadRequestException } from '@nestjs/common';
import { approximateKm } from '../../common/utils/geo';
import { AttachmentView, toAttachments } from '../media/media-url';

export type { AttachmentView };

type WithAttachments<T> = T & { attachments?: Attachment[] };

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
  /** Photos, videos or files the requester sent with the need. */
  attachments: AttachmentView[];
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
    /** Rounded, from where both were at matching time; null when unknown. */
    distanceKm: number | null;
    whatsapp: string | null;
    shopUrl: string | null;
    confidenceScore: number;
    reviewCount: number;
  };
  serviceName: string | null;
  price: number | null;
  availability: string | null;
  delay: string | null;
  message: string | null;
  /** Photos, videos or a PDF quote sent with the proposal. */
  attachments: AttachmentView[];
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
  /** Empty when the message is only attachments. */
  text: string;
  attachments: AttachmentView[];
  createdAt: Date;
}

export function toMessages(rows: WithAttachments<DispatchMessage>[] | undefined): MessageView[] {
  return (rows ?? []).map((m) => ({
    id: m.id,
    author: m.author,
    text: m.text,
    attachments: toAttachments(m.attachments),
    createdAt: m.createdAt,
  }));
}

/** A message's text, or what it carries when it has none (notifications). */
export function messagePreview(text: string | undefined, attachmentCount: number): string {
  const t = text?.trim() ?? '';
  if (t) return t.slice(0, 140);
  return attachmentCount > 1 ? `📎 ${attachmentCount} pièces jointes` : '📎 Pièce jointe';
}

/** A message needs words or something attached. */
export function requireContent(
  text: string | undefined,
  attachmentIds: string[] | undefined,
): void {
  if (!text?.trim() && !attachmentIds?.length) {
    throw new BadRequestException('Écris un message ou joins un fichier');
  }
}

/** Prisma include for a conversation, with what each message carries. */
export const MESSAGES_INCLUDE = {
  orderBy: { createdAt: 'asc' },
  include: { attachments: true },
} satisfies Prisma.DispatchMessageFindManyArgs;

/** Prisma include for a pro's dispatch: the request (and its media), the offer, the conversation. */
export const INBOX_INCLUDE = {
  request: { include: { attachments: true } },
  service: true,
  attachments: true,
  messages: MESSAGES_INCLUDE,
} satisfies Prisma.RequestDispatchInclude;

export interface InboxItemView {
  dispatchId: string;
  status: DispatchStatus;
  matchedService: string | null;
  /** How far the requester is, rounded; null when either shared no position. */
  distanceKm: number | null;
  request: RequestPublicView;
  price: number | null;
  availability: string | null;
  delay: string | null;
  message: string | null;
  /** The pro's own proposal attachments. */
  attachments: AttachmentView[];
  viewedAt: Date | null;
  respondedAt: Date | null;
  createdAt: Date;
  messages: MessageView[];
}

export function toPublicView(r: WithAttachments<ServiceRequest>): RequestPublicView {
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
    attachments: toAttachments(r.attachments),
    createdAt: r.createdAt,
  };
}

/** The matching distance stored on a dispatch, rounded for showing (Data §22). */
export function shownDistance(reasons: Prisma.JsonValue | null): number | null {
  const km = (reasons as { distanceKm?: unknown } | null)?.distanceKm;
  return typeof km === 'number' ? approximateKm(km) : null;
}

export function toInboxItem(
  d: WithAttachments<RequestDispatch> & {
    request: WithAttachments<ServiceRequest>;
    service: ProService | null;
    messages?: WithAttachments<DispatchMessage>[];
  },
): InboxItemView {
  return {
    dispatchId: d.id,
    status: d.status,
    matchedService: d.service?.name ?? null,
    distanceKm: shownDistance(d.reasons),
    request: toPublicView(d.request),
    price: d.price,
    availability: d.availability,
    delay: d.delay,
    message: d.message,
    attachments: toAttachments(d.attachments),
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

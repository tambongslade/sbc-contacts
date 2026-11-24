import { createHmac, timingSafeEqual } from 'node:crypto';
import { Attachment } from '@prisma/client';

/**
 * Signed links to attachments. Views are built in plain functions all over
 * SBC Data, so the signing key is set once at start-up (MediaService) rather
 * than injected into each of them.
 *
 * A link is valid for 7 to 14 days. Expiry is rounded to a week boundary, so
 * the same attachment keeps the same link for a week and the apps' image
 * caches work.
 */
let signingKey: Buffer | null = null;
const WEEK_S = 7 * 24 * 3600;

export function configureMediaSigning(secret: string): void {
  signingKey = createHmac('sha256', secret).update('sbc-media-links').digest();
}

function signature(id: string, exp: number): string {
  if (!signingKey) throw new Error('Media signing is not configured');
  return createHmac('sha256', signingKey).update(`${id}.${exp}`).digest('base64url');
}

/** Path below the API host, e.g. "/api/v1/media/<id>?exp=…&sig=…". */
export function mediaPath(id: string, now = Date.now()): string {
  const exp = (Math.floor(now / 1000 / WEEK_S) + 2) * WEEK_S;
  return `/api/v1/media/${id}?exp=${exp}&sig=${signature(id, exp)}`;
}

export function verifyMediaLink(id: string, exp: number, sig: string, now = Date.now()): boolean {
  if (!Number.isFinite(exp) || exp * 1000 < now) return false;
  const expected = Buffer.from(signature(id, exp));
  const given = Buffer.from(sig);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

export interface AttachmentView {
  id: string;
  kind: Attachment['kind'];
  mimeType: string;
  size: number;
  fileName: string | null;
  width: number | null;
  height: number | null;
  durationSec: number | null;
  /** Signed path below the API host; resolve it against the API origin. */
  url: string;
}

export function toAttachments(rows: Attachment[] | undefined): AttachmentView[] {
  return [...(rows ?? [])]
    .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
    .map((a) => ({
      id: a.id,
      kind: a.kind,
      mimeType: a.mimeType,
      size: a.size,
      fileName: a.fileName,
      width: a.width,
      height: a.height,
      durationSec: a.durationSec,
      url: mediaPath(a.id),
    }));
}

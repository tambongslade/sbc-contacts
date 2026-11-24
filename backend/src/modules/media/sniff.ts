import { AttachmentKind } from '@prisma/client';

export interface Sniffed {
  kind: AttachmentKind;
  mimeType: string;
  ext: string;
}

/**
 * What a file really is, from its first bytes: the name and the type the
 * phone claims are not trusted. Only the formats the apps can show are let in.
 */
export function sniff(head: Buffer): Sniffed | null {
  const ascii = (from: number, to: number) => head.subarray(from, to).toString('latin1');
  if (head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) {
    return { kind: AttachmentKind.IMAGE, mimeType: 'image/jpeg', ext: 'jpg' };
  }
  if (
    head.length >= 8 &&
    head.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
  ) {
    return { kind: AttachmentKind.IMAGE, mimeType: 'image/png', ext: 'png' };
  }
  if (head.length >= 12 && ascii(0, 4) === 'RIFF' && ascii(8, 12) === 'WEBP') {
    return { kind: AttachmentKind.IMAGE, mimeType: 'image/webp', ext: 'webp' };
  }
  if (head.length >= 5 && ascii(0, 5) === '%PDF-') {
    return { kind: AttachmentKind.FILE, mimeType: 'application/pdf', ext: 'pdf' };
  }
  if (head.length >= 12 && ascii(4, 8) === 'ftyp') {
    const brand = ascii(8, 12);
    if (['heic', 'heix', 'heim', 'heis', 'mif1', 'msf1'].includes(brand)) {
      return { kind: AttachmentKind.IMAGE, mimeType: 'image/heic', ext: 'heic' };
    }
    if (brand === 'qt  ')
      return { kind: AttachmentKind.VIDEO, mimeType: 'video/quicktime', ext: 'mov' };
    if (/^(isom|iso[2-9]|mp41|mp42|avc1|M4V |M4VP|dash|3gp\d|3g2\w|MSNV|XAVC)$/.test(brand)) {
      return { kind: AttachmentKind.VIDEO, mimeType: 'video/mp4', ext: 'mp4' };
    }
  }
  return null;
}

/** Largest file allowed per kind, in bytes. */
export const MAX_BYTES: Record<AttachmentKind, number> = {
  IMAGE: 10 * 1024 * 1024,
  VIDEO: 50 * 1024 * 1024,
  FILE: 20 * 1024 * 1024,
};

/** Attachments one request, proposal or message may carry. */
export const MAX_ATTACHMENTS = 5;

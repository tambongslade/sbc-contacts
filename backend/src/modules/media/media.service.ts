import { randomUUID } from 'node:crypto';
import { mkdir, open, rename, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AttachmentKind, Prisma } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { AttachmentView, configureMediaSigning, toAttachments, verifyMediaLink } from './media-url';
import { MAX_ATTACHMENTS, MAX_BYTES, sniff } from './sniff';

/** What an attachment is claimed by: exactly one of them. */
export type AttachmentTarget =
  { requestId: string } | { dispatchId: string } | { messageId: string };

export interface UploadMeta {
  fileName?: string;
  width?: number;
  height?: number;
  durationSec?: number;
}

/** A file multer wrote to the temporary folder. */
export interface UploadedTemp {
  path: string;
  size: number;
  originalname?: string;
}

const UNCLAIMED_TTL_MS = 24 * 3600 * 1000;
const UPLOADS_PER_HOUR = 60;

/**
 * Photos, videos and PDFs sent in SBC Data (a request, a proposal, a
 * message). Files live on the server's disk under MEDIA_DIR; a later move to
 * object storage only changes this service.
 */
@Injectable()
export class MediaService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MediaService.name);
  readonly root: string;
  private sweeper?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    config: ConfigService,
  ) {
    this.root = resolve(config.get<string>('MEDIA_DIR') || join(process.cwd(), 'storage', 'media'));
    // Links are signed with a key derived from the access-token secret: no
    // extra secret to manage, and rotating that secret also expires links.
    configureMediaSigning(config.getOrThrow<string>('jwt.accessSecret'));
  }

  get tempDir(): string {
    return join(this.root, 'tmp');
  }

  async onModuleInit(): Promise<void> {
    await mkdir(this.tempDir, { recursive: true });
    this.sweeper = setInterval(() => void this.sweep().catch(() => undefined), 3600_000);
    this.sweeper.unref();
  }

  onModuleDestroy(): void {
    if (this.sweeper) clearInterval(this.sweeper);
  }

  /** Keeps an uploaded file, unclaimed until a request, proposal or message takes it. */
  async upload(userId: string, file: UploadedTemp, meta: UploadMeta): Promise<AttachmentView> {
    try {
      const recent = await this.prisma.attachment.count({
        where: { uploaderId: userId, createdAt: { gt: new Date(Date.now() - 3600_000) } },
      });
      if (recent >= UPLOADS_PER_HOUR) {
        throw new HttpException(
          'Trop d’envois, réessaie dans un moment',
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
      const head = Buffer.alloc(16);
      const fh = await open(file.path, 'r');
      try {
        await fh.read(head, 0, 16, 0);
      } finally {
        await fh.close();
      }
      const type = sniff(head);
      if (!type) {
        throw new BadRequestException('Format non pris en charge : photo, vidéo ou PDF uniquement');
      }
      if (file.size > MAX_BYTES[type.kind]) {
        const mb = MAX_BYTES[type.kind] / 1024 / 1024;
        throw new BadRequestException(`Fichier trop lourd (${mb} Mo maximum)`);
      }
      const id = randomUUID();
      const now = new Date();
      const dir = `${now.getUTCFullYear()}/${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
      const storageKey = `${dir}/${id}.${type.ext}`;
      await mkdir(join(this.root, dir), { recursive: true });
      await rename(file.path, join(this.root, storageKey));
      const row = await this.prisma.attachment.create({
        data: {
          id,
          uploaderId: userId,
          kind: type.kind,
          mimeType: type.mimeType,
          size: file.size,
          fileName: cleanName(meta.fileName ?? file.originalname, type.ext),
          width: positiveInt(meta.width),
          height: positiveInt(meta.height),
          durationSec:
            type.kind === AttachmentKind.VIDEO && meta.durationSec && meta.durationSec > 0
              ? meta.durationSec
              : null,
          storageKey,
        },
      });
      return toAttachments([row])[0];
    } finally {
      await rm(file.path, { force: true });
    }
  }

  /**
   * Hands the uploader's own, still unclaimed attachments to what they are
   * sent with. Run inside the transaction that creates it.
   */
  async claim(
    tx: Prisma.TransactionClient,
    uploaderId: string,
    ids: string[] | undefined,
    target: AttachmentTarget,
  ): Promise<void> {
    const unique = [...new Set(ids ?? [])];
    if (unique.length === 0) return;
    if (unique.length > MAX_ATTACHMENTS) {
      throw new BadRequestException(`${MAX_ATTACHMENTS} pièces jointes maximum`);
    }
    const claimed = await tx.attachment.updateMany({
      where: { id: { in: unique }, uploaderId, requestId: null, dispatchId: null, messageId: null },
      data: target,
    });
    if (claimed.count !== unique.length) {
      throw new BadRequestException('Pièce jointe introuvable ou déjà envoyée');
    }
  }

  /** The file behind a signed link. */
  async resolveLink(
    id: string,
    exp: number,
    sig: string,
  ): Promise<{ path: string; mimeType: string; fileName: string | null }> {
    if (!verifyMediaLink(id, exp, sig)) throw new NotFoundException();
    const row = await this.prisma.attachment.findUnique({ where: { id } });
    if (!row) throw new NotFoundException();
    return {
      path: join(this.root, row.storageKey),
      mimeType: row.mimeType,
      fileName: row.fileName,
    };
  }

  /** "Signaler": kept in the audit log for the back-office to review. */
  async report(userId: string, id: string, reason?: string): Promise<void> {
    const row = await this.prisma.attachment.findUnique({ where: { id } });
    if (!row) throw new NotFoundException('Pièce jointe introuvable');
    await this.audit.record({
      actorId: userId,
      action: 'media.report',
      resource: `Attachment:${id}`,
      after: {
        reason: reason?.trim().slice(0, 500) || null,
        uploaderId: row.uploaderId,
        requestId: row.requestId,
        dispatchId: row.dispatchId,
        messageId: row.messageId,
      },
    });
  }

  /** Uploads never sent with anything, and leftovers in the temporary folder. */
  async sweep(now = Date.now()): Promise<number> {
    const stale = await this.prisma.attachment.findMany({
      where: {
        requestId: null,
        dispatchId: null,
        messageId: null,
        createdAt: { lt: new Date(now - UNCLAIMED_TTL_MS) },
      },
      select: { id: true, storageKey: true },
      take: 500,
    });
    for (const a of stale) {
      await rm(join(this.root, a.storageKey), { force: true });
    }
    if (stale.length) {
      await this.prisma.attachment.deleteMany({ where: { id: { in: stale.map((a) => a.id) } } });
      this.logger.log(`Swept ${stale.length} unsent attachment(s)`);
    }
    return stale.length;
  }
}

function positiveInt(v: number | undefined): number | null {
  return v != null && Number.isFinite(v) && v > 0 ? Math.round(v) : null;
}

/** A display name only (never a path): what the phone called it, tidied. */
function cleanName(name: string | undefined, ext: string): string | null {
  const base = (name ?? '')
    .split(/[\\/]/)
    .pop()
    ?.replace(/[\u0000-\u001f"]/g, '')
    .trim();
  if (!base) return null;
  const short = base.slice(0, 120);
  return short.toLowerCase().endsWith(`.${ext}`) || ext !== 'pdf' ? short : `${short}.${ext}`;
}

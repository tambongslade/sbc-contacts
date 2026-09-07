import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';

export interface AuditEntry {
  actorId?: string;
  action: string; // e.g. "criteria.create", "sync.report"
  resource: string; // e.g. "SyncCriteria:<id>"
  before?: unknown;
  after?: unknown;
  metadata?: unknown;
  ip?: string;
}

/** JSON-normalise arbitrary values (Dates → ISO strings) for a Json column. */
function toJson(value: unknown): Prisma.InputJsonValue | undefined {
  if (value === undefined) return undefined;
  return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
}

/**
 * Reusable audit trail (brief §11). Records who did what to which resource, with
 * before/after snapshots. Audit failures are logged but never break the business
 * operation that triggered them.
 */
@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  async record(entry: AuditEntry): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          actorId: entry.actorId,
          action: entry.action,
          resource: entry.resource,
          before: toJson(entry.before),
          after: toJson(entry.after),
          metadata: toJson(entry.metadata),
          ip: entry.ip,
        },
      });
    } catch (err) {
      this.logger.error(`Failed to write audit log for ${entry.action}: ${(err as Error).message}`);
    }
  }
}

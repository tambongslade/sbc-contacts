import { Injectable } from '@nestjs/common';
import { NotificationType } from '@prisma/client';
import { PaginatedResult, PaginationQueryDto, paginate } from '../../common/dto/pagination.dto';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { MembersService } from '../members/members.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreateAddedEventDto } from './dto/create-added-event.dto';

/** Confirmation that a direct add was recorded. */
export interface RecordAddResult {
  recorded: true;
  memberSbcId: string;
}

/** One actor who added the caller to their contacts (§21). */
export interface AddedByUserView {
  actorUserId: string;
  name: string | null;
  avatarUrl: string | null;
  phoneNumber: string | null;
  country: string | null;
  addedAt: Date;
}

/**
 * "Qui m'a ajouté ?" (cahier §21). A direct "Ajouter au téléphone" add writes to
 * the phone but doesn't go through the sync report, so the app pings us here.
 * We record a SyncedContact (so it appears in "Mes contacts SBC") AND an
 * AddedEvent (so the target can see who added them), and notify the target once.
 */
@Injectable()
export class AddedEventsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly members: MembersService,
    private readonly notifications: NotificationsService,
  ) {}

  /** Record a direct add: SyncedContact + AddedEvent, then notify the target. */
  async record(userId: string, dto: CreateAddedEventDto): Promise<RecordAddResult> {
    const member = await this.members.getBySbcIdOrThrow(dto.memberSbcId);

    const { isNew } = await this.prisma.$transaction(async (tx) => {
      // 1. SyncedContact (deviceId null for a direct add) → makes it show in
      // "Mes contacts SBC". Compound-unique upsert with a null component is
      // awkward, so find-then-update/create.
      const existingContact = await tx.syncedContact.findFirst({
        where: { userId, memberId: member.id, deviceId: null },
      });
      if (existingContact) {
        await tx.syncedContact.update({
          where: { id: existingContact.id },
          data: {
            status: 'SYNCED',
            deviceContactId: dto.deviceContactId ?? null,
            syncedAt: new Date(),
          },
        });
      } else {
        await tx.syncedContact.create({
          data: {
            userId,
            memberId: member.id,
            deviceId: null,
            status: 'SYNCED',
            deviceContactId: dto.deviceContactId ?? null,
            syncedAt: new Date(),
          },
        });
      }

      // 2. AddedEvent (§21). Track whether this is the first time so we only
      // notify the target on a genuinely new add.
      const existingEvent = await tx.addedEvent.findUnique({
        where: {
          actorId_targetMemberSbcId: { actorId: userId, targetMemberSbcId: member.sbcId },
        },
        select: { id: true },
      });
      await tx.addedEvent.upsert({
        where: {
          actorId_targetMemberSbcId: { actorId: userId, targetMemberSbcId: member.sbcId },
        },
        create: { actorId: userId, targetMemberSbcId: member.sbcId },
        update: { confirmedAt: new Date() },
      });

      return { isNew: !existingEvent };
    });

    // 3. Notify the target once, best-effort, outside the transaction (enqueues
    // a job). Only on a newly-created event to avoid re-notifying on repeat adds.
    if (isNew) {
      const targetUser = await this.prisma.user.findFirst({
        where: { sbcUserId: member.sbcId },
        select: { id: true },
      });
      if (targetUser) {
        const actor = await this.prisma.user.findUnique({
          where: { id: userId },
          select: { name: true },
        });
        const actorName = actor?.name ?? 'Un membre SBC';
        await this.notifications.create({
          userId: targetUser.id,
          type: NotificationType.ADDED_BY_CONTACT,
          title: 'Nouveau contact',
          body: `${actorName} vous a ajouté à ses contacts`,
          data: { actorUserId: userId, memberSbcId: member.sbcId },
        });
      }
    }

    return { recorded: true, memberSbcId: member.sbcId };
  }

  /** People who added the caller to their contacts, newest first (§21). */
  async whoAddedMe(
    userSbcId: string,
    pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<AddedByUserView>> {
    const where = { targetMemberSbcId: userSbcId };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.addedEvent.findMany({
        where,
        include: {
          actor: {
            select: { id: true, name: true, avatarUrl: true, phoneNumber: true, country: true },
          },
        },
        orderBy: { confirmedAt: 'desc' },
        skip: pagination.skip,
        take: pagination.limit,
      }),
      this.prisma.addedEvent.count({ where }),
    ]);

    const items: AddedByUserView[] = rows.map((r) => ({
      actorUserId: r.actor.id,
      name: r.actor.name,
      avatarUrl: r.actor.avatarUrl,
      phoneNumber: r.actor.phoneNumber,
      country: r.actor.country,
      addedAt: r.confirmedAt,
    }));
    return paginate(items, total, pagination.page, pagination.limit);
  }
}

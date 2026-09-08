import { Injectable, NotFoundException } from '@nestjs/common';
import { Member } from '@prisma/client';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { SbcContact } from '../sbc-client/interfaces/sbc.interface';
import { confidenceScore } from '../reviews/confidence-score';
import { MemberView } from './member.view';

/** Plain, concrete write shape usable for both create and update. */
interface MemberWriteData {
  name: string | null;
  firstName: string | null;
  profession: string | null;
  city: string | null;
  country: string | null;
  sex: string | null;
  age: number | null;
  interests: string[];
  skills: string[];
  avatarUrl: string | null;
  phoneNumber: string | null;
  lastSeenAt: Date;
}

/**
 * Custodian of the SBC member MIRROR. SBC remains the source of truth; this is a
 * queryable cache hydrated cache-through from proxied searches (and, later,
 * webhook/bulk import). Favorites/sync reference members by our local uuid.
 */
@Injectable()
export class MembersService {
  constructor(private readonly prisma: PrismaService) {}

  async findBySbcId(sbcId: string): Promise<Member | null> {
    return this.prisma.member.findUnique({ where: { sbcId } });
  }

  async findManyBySbcIds(sbcIds: string[]): Promise<Member[]> {
    if (sbcIds.length === 0) return [];
    return this.prisma.member.findMany({ where: { sbcId: { in: sbcIds } } });
  }

  /**
   * Attach the caller's favorite/sync state to a set of members, in bulk (no
   * N+1). Shared by directory search, profiles, and sync-criteria matches.
   */
  async annotate(userId: string, members: Member[]): Promise<MemberView[]> {
    if (members.length === 0) return [];
    const memberIds = members.map((m) => m.id);
    const sbcIds = members.map((m) => m.sbcId);

    const [favorites, synced, scores, myReviews] = await Promise.all([
      this.prisma.favorite.findMany({
        where: { userId, memberId: { in: memberIds } },
        select: { memberId: true },
      }),
      this.prisma.syncedContact.findMany({
        where: { userId, memberId: { in: memberIds }, status: 'SYNCED' },
        select: { memberId: true },
      }),
      // Reputation is keyed by the durable SBC id, not the local mirror uuid.
      this.prisma.memberScore.findMany({
        where: { memberSbcId: { in: sbcIds } },
        select: { memberSbcId: true, averageStars: true, reviewCount: true },
      }),
      this.prisma.memberReview.findMany({
        where: { reviewerUserId: userId, memberSbcId: { in: sbcIds } },
        select: { memberSbcId: true, stars: true },
      }),
    ]);
    const favSet = new Set(favorites.map((f) => f.memberId));
    const syncSet = new Set(synced.map((s) => s.memberId));
    const scoreBySbcId = new Map(scores.map((s) => [s.memberSbcId, s]));
    const myStarsBySbcId = new Map(myReviews.map((r) => [r.memberSbcId, r.stars]));

    return members.map((m) => {
      const score = scoreBySbcId.get(m.sbcId);
      const averageStars = score?.averageStars ?? null;
      const reviewCount = score?.reviewCount ?? 0;
      return {
        id: m.id,
        sbcId: m.sbcId,
        name: m.name,
        firstName: m.firstName,
        profession: m.profession,
        city: m.city,
        country: m.country,
        sex: m.sex,
        age: m.age,
        interests: m.interests,
        skills: m.skills,
        avatarUrl: m.avatarUrl,
        phoneNumber: m.phoneNumber,
        isFavorite: favSet.has(m.id),
        isSynced: syncSet.has(m.id),
        confidenceScore: confidenceScore(averageStars ?? 0, reviewCount),
        averageRating: averageStars,
        reviewCount,
        myRating: myStarsBySbcId.get(m.sbcId) ?? null,
      };
    });
  }

  async getBySbcIdOrThrow(sbcId: string): Promise<Member> {
    const member = await this.findBySbcId(sbcId);
    if (!member) {
      throw new NotFoundException('Member not found in directory; open its profile first');
    }
    return member;
  }

  /** Upsert one SBC contact into the mirror, preserving a non-search `source`. */
  async upsertFromSbc(contact: SbcContact): Promise<Member> {
    const data = this.toData(contact);
    return this.prisma.member.upsert({
      where: { sbcId: contact.id },
      create: { sbcId: contact.id, ...data },
      update: data, // note: does not downgrade `source` on update
    });
  }

  /** Bulk hydrate a page of search results in a single transaction. */
  async upsertMany(contacts: SbcContact[]): Promise<Member[]> {
    const valid = contacts.filter((c) => c.id);
    if (valid.length === 0) return [];
    return this.prisma.$transaction(
      valid.map((c) => {
        const data = this.toData(c);
        return this.prisma.member.upsert({
          where: { sbcId: c.id },
          create: { sbcId: c.id, ...data },
          update: data,
        });
      }),
    );
  }

  private toData(c: SbcContact): MemberWriteData {
    return {
      name: c.name ?? null,
      firstName: c.firstName ?? null,
      profession: c.profession ?? null,
      city: c.city ?? null,
      country: c.country ?? null,
      sex: c.sex ?? null,
      age: c.age ?? null,
      interests: c.interests ?? [],
      skills: c.skills ?? [],
      avatarUrl: c.avatarUrl ?? null,
      phoneNumber: c.phoneNumber ?? null,
      lastSeenAt: new Date(),
    };
  }
}

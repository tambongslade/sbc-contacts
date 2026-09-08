import { ForbiddenException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PaginatedResult, PaginationQueryDto, paginate } from '../../common/dto/pagination.dto';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { CreateReviewDto } from './dto/create-review.dto';
import { confidenceScore } from './confidence-score';

/** A single review as returned to clients. */
export interface ReviewView {
  id: string;
  memberSbcId: string;
  stars: number;
  comment: string | null;
  reviewerName: string | null;
  reviewerAvatarUrl: string | null;
  isMine: boolean;
  createdAt: Date;
  updatedAt: Date;
}

/** Aggregate reputation for a member. */
export interface ScoreSummary {
  memberSbcId: string;
  averageStars: number;
  reviewCount: number;
  confidenceScore: number;
}

/** Paginated reviews for a member, plus the aggregate and the caller's own review. */
export interface MemberReviewsResult extends PaginatedResult<ReviewView> {
  summary: ScoreSummary;
  myReview: ReviewView | null;
}

type ReviewWithReviewer = Prisma.MemberReviewGetPayload<{
  include: { reviewer: { select: { name: true; avatarUrl: true } } };
}>;

/**
 * Reviews & confidence score ("Score de confiance"). One editable review per
 * (reviewer, member); the member is addressed by its durable SBC id so scores
 * survive member-cache churn. Every write recomputes the aggregate in the same
 * transaction so directory annotation stays a single cheap lookup.
 */
@Injectable()
export class ReviewsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Create or update the caller's review, then return the fresh aggregate. */
  async upsert(
    userId: string,
    userSbcId: string,
    dto: CreateReviewDto,
  ): Promise<{ review: ReviewView; summary: ScoreSummary }> {
    if (dto.memberSbcId === userSbcId) {
      throw new ForbiddenException('You cannot rate yourself');
    }
    const comment = dto.comment?.trim() ? dto.comment.trim() : null;

    const review = await this.prisma.$transaction(async (tx) => {
      const saved = await tx.memberReview.upsert({
        where: {
          reviewerUserId_memberSbcId: { reviewerUserId: userId, memberSbcId: dto.memberSbcId },
        },
        create: {
          reviewerUserId: userId,
          memberSbcId: dto.memberSbcId,
          stars: dto.stars,
          comment,
        },
        update: { stars: dto.stars, comment },
        include: { reviewer: { select: { name: true, avatarUrl: true } } },
      });
      await this.recompute(tx, dto.memberSbcId);
      return saved;
    });

    return {
      review: this.toView(review, userId),
      summary: await this.summary(dto.memberSbcId),
    };
  }

  /** Delete the caller's own review (idempotent), then recompute the aggregate. */
  async remove(userId: string, memberSbcId: string): Promise<ScoreSummary> {
    await this.prisma.$transaction(async (tx) => {
      await tx.memberReview.deleteMany({ where: { reviewerUserId: userId, memberSbcId } });
      await this.recompute(tx, memberSbcId);
    });
    return this.summary(memberSbcId);
  }

  /** Paginated reviews (newest first) + aggregate + the caller's own review. */
  async listForMember(
    memberSbcId: string,
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<MemberReviewsResult> {
    const [rows, total, mine, summary] = await this.prisma.$transaction([
      this.prisma.memberReview.findMany({
        where: { memberSbcId },
        include: { reviewer: { select: { name: true, avatarUrl: true } } },
        orderBy: { updatedAt: 'desc' },
        skip: pagination.skip,
        take: pagination.limit,
      }),
      this.prisma.memberReview.count({ where: { memberSbcId } }),
      this.prisma.memberReview.findUnique({
        where: { reviewerUserId_memberSbcId: { reviewerUserId: userId, memberSbcId } },
        include: { reviewer: { select: { name: true, avatarUrl: true } } },
      }),
      this.prisma.memberScore.findUnique({ where: { memberSbcId } }),
    ]);

    const items = rows.map((r) => this.toView(r, userId));
    const averageStars = summary?.averageStars ?? 0;
    const reviewCount = summary?.reviewCount ?? 0;
    return {
      ...paginate(items, total, pagination.page, pagination.limit),
      summary: {
        memberSbcId,
        averageStars,
        reviewCount,
        confidenceScore: confidenceScore(averageStars, reviewCount),
      },
      myReview: mine ? this.toView(mine, userId) : null,
    };
  }

  /** Recompute and persist a member's aggregate within a transaction. */
  private async recompute(tx: Prisma.TransactionClient, memberSbcId: string): Promise<void> {
    const agg = await tx.memberReview.aggregate({
      where: { memberSbcId },
      _avg: { stars: true },
      _count: true,
    });
    const averageStars = agg._avg.stars ?? 0;
    const reviewCount = agg._count;

    if (reviewCount === 0) {
      // No reviews left → drop the aggregate row so the member reverts to 50.
      await tx.memberScore.deleteMany({ where: { memberSbcId } });
      return;
    }
    await tx.memberScore.upsert({
      where: { memberSbcId },
      create: { memberSbcId, averageStars, reviewCount },
      update: { averageStars, reviewCount },
    });
  }

  private async summary(memberSbcId: string): Promise<ScoreSummary> {
    const row = await this.prisma.memberScore.findUnique({ where: { memberSbcId } });
    const averageStars = row?.averageStars ?? 0;
    const reviewCount = row?.reviewCount ?? 0;
    return {
      memberSbcId,
      averageStars,
      reviewCount,
      confidenceScore: confidenceScore(averageStars, reviewCount),
    };
  }

  private toView(r: ReviewWithReviewer, callerUserId: string): ReviewView {
    return {
      id: r.id,
      memberSbcId: r.memberSbcId,
      stars: r.stars,
      comment: r.comment,
      reviewerName: r.reviewer?.name ?? null,
      reviewerAvatarUrl: r.reviewer?.avatarUrl ?? null,
      isMine: r.reviewerUserId === callerUserId,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    };
  }
}

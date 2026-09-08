import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../common/decorators/current-user.decorator';
import { PaginationQueryDto } from '../../common/dto/pagination.dto';
import { CreateReviewDto } from './dto/create-review.dto';
import {
  MemberReviewsResult,
  ReviewView,
  ReviewsService,
  ScoreSummary,
} from './reviews.service';

@ApiTags('reviews')
@ApiBearerAuth()
@Controller({ path: 'reviews', version: '1' })
export class ReviewsController {
  constructor(private readonly reviews: ReviewsService) {}

  @Post()
  @ApiOperation({ summary: 'Create or update the caller\'s review for a member' })
  upsert(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateReviewDto,
  ): Promise<{ review: ReviewView; summary: ScoreSummary }> {
    return this.reviews.upsert(user.userId, user.sbcUserId, dto);
  }

  @Get(':memberSbcId')
  @ApiOperation({ summary: 'List a member\'s reviews with the aggregate score' })
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Param('memberSbcId') memberSbcId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<MemberReviewsResult> {
    return this.reviews.listForMember(memberSbcId, user.userId, pagination);
  }

  @Delete(':memberSbcId')
  @ApiOperation({ summary: 'Remove the caller\'s own review' })
  remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('memberSbcId') memberSbcId: string,
  ): Promise<ScoreSummary> {
    return this.reviews.remove(user.userId, memberSbcId);
  }
}

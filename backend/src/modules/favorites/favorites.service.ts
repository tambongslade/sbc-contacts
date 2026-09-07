import { Injectable } from '@nestjs/common';
import { PaginatedResult, PaginationQueryDto, paginate } from '../../common/dto/pagination.dto';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { MembersService } from '../members/members.service';

export interface FavoriteItem {
  memberSbcId: string;
  name: string | null;
  firstName: string | null;
  profession: string | null;
  city: string | null;
  country: string | null;
  avatarUrl: string | null;
  phoneNumber: string | null;
  favoritedAt: Date;
}

/** Favorites (cahier §18). Idempotent add/remove keyed by (user, member). */
@Injectable()
export class FavoritesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly members: MembersService,
  ) {}

  async add(userId: string, memberSbcId: string): Promise<FavoriteItem> {
    const member = await this.members.getBySbcIdOrThrow(memberSbcId);
    const favorite = await this.prisma.favorite.upsert({
      where: { userId_memberId: { userId, memberId: member.id } },
      create: { userId, memberId: member.id },
      update: {},
      include: { member: true },
    });
    return this.toItem(favorite.createdAt, favorite.member);
  }

  async remove(userId: string, memberSbcId: string): Promise<void> {
    const member = await this.members.findBySbcId(memberSbcId);
    if (!member) return; // idempotent
    await this.prisma.favorite.deleteMany({ where: { userId, memberId: member.id } });
  }

  async list(userId: string, pagination: PaginationQueryDto): Promise<PaginatedResult<FavoriteItem>> {
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.favorite.findMany({
        where: { userId },
        include: { member: true },
        orderBy: { createdAt: 'desc' },
        skip: pagination.skip,
        take: pagination.limit,
      }),
      this.prisma.favorite.count({ where: { userId } }),
    ]);
    const items = rows.map((f) => this.toItem(f.createdAt, f.member));
    return paginate(items, total, pagination.page, pagination.limit);
  }

  private toItem(
    favoritedAt: Date,
    m: {
      sbcId: string;
      name: string | null;
      firstName: string | null;
      profession: string | null;
      city: string | null;
      country: string | null;
      avatarUrl: string | null;
      phoneNumber: string | null;
    },
  ): FavoriteItem {
    return {
      memberSbcId: m.sbcId,
      name: m.name,
      firstName: m.firstName,
      profession: m.profession,
      city: m.city,
      country: m.country,
      avatarUrl: m.avatarUrl,
      phoneNumber: m.phoneNumber,
      favoritedAt,
    };
  }
}

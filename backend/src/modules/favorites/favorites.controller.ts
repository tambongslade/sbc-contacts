import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../common/decorators/current-user.decorator';
import { PaginatedResult, PaginationQueryDto } from '../../common/dto/pagination.dto';
import { AddFavoriteDto } from './dto/add-favorite.dto';
import { FavoriteItem, FavoritesService } from './favorites.service';

@ApiTags('favorites')
@ApiBearerAuth()
@Controller({ path: 'favorites', version: '1' })
export class FavoritesController {
  constructor(private readonly favorites: FavoritesService) {}

  @Get()
  @ApiOperation({ summary: "List the caller's favorites" })
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Query() pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<FavoriteItem>> {
    return this.favorites.list(user.userId, pagination);
  }

  @Post()
  @ApiOperation({ summary: 'Add a member to favorites' })
  add(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: AddFavoriteDto,
  ): Promise<FavoriteItem> {
    return this.favorites.add(user.userId, dto.memberSbcId);
  }

  @Delete(':memberSbcId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Remove a member from favorites' })
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('memberSbcId') memberSbcId: string,
  ): Promise<void> {
    await this.favorites.remove(user.userId, memberSbcId);
  }
}

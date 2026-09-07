import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  Req,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { SyncCriteria } from '@prisma/client';
import { Request } from 'express';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../../common/decorators/current-user.decorator';
import { PaginatedResult, PaginationQueryDto } from '../../../common/dto/pagination.dto';
import { MemberView } from '../../members/member.view';
import { CreateCriteriaDto, PreviewCriteriaDto, UpdateCriteriaDto } from '../dto/criteria.dto';
import { CriteriaService } from '../services/criteria.service';

@ApiTags('sync-criteria')
@ApiBearerAuth()
@Controller({ path: 'sync/criteria', version: '1' })
export class CriteriaController {
  constructor(private readonly criteria: CriteriaService) {}

  @Get()
  @ApiOperation({ summary: "List the caller's saved sync criteria" })
  list(@CurrentUser() user: AuthenticatedUser): Promise<SyncCriteria[]> {
    return this.criteria.list(user.userId);
  }

  @Post()
  @ApiOperation({ summary: 'Create a sync criteria' })
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateCriteriaDto,
    @Req() req: Request,
  ): Promise<SyncCriteria> {
    return this.criteria.create(user.userId, dto, req.ip);
  }

  @Post('preview')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Live match count for unsaved criteria (§10)' })
  previewAdhoc(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: PreviewCriteriaDto,
  ): Promise<{ matchCount: number }> {
    return this.criteria.previewAdhoc(user.userId, dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get one criteria' })
  get(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<SyncCriteria> {
    return this.criteria.get(user.userId, id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update a criteria' })
  update(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() dto: UpdateCriteriaDto,
    @Req() req: Request,
  ): Promise<SyncCriteria> {
    return this.criteria.update(user.userId, id, dto, req.ip);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete a criteria' })
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Req() req: Request,
  ): Promise<void> {
    await this.criteria.remove(user.userId, id, req.ip);
  }

  @Get(':id/preview')
  @ApiOperation({ summary: 'Match count for a saved criteria (refreshes cache)' })
  preview(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<{ criteriaId: string; matchCount: number }> {
    return this.criteria.preview(user.userId, id);
  }

  @Get(':id/matches')
  @ApiOperation({ summary: 'Members currently matching a saved criteria' })
  matches(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<PaginatedResult<MemberView>> {
    return this.criteria.matches(user.userId, id, pagination);
  }
}

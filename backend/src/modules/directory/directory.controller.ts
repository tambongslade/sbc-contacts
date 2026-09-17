import { Controller, Get, Param, Query, Res } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../common/decorators/current-user.decorator';
import { Raw } from '../../common/decorators/raw-response.decorator';
import { PaginatedResult } from '../../common/dto/pagination.dto';
import { RegionEntry } from '../../common/utils/regions';
import { MemberView } from '../members/member.view';
import { DirectoryService } from './directory.service';
import { SearchQueryDto } from './dto/search-query.dto';

@ApiTags('directory')
@ApiBearerAuth()
@Controller({ path: 'directory', version: '1' })
export class DirectoryController {
  constructor(private readonly directory: DirectoryService) {}

  @Get('search')
  @ApiOperation({ summary: 'Search the SBC member directory (proxied + cached)' })
  search(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: SearchQueryDto,
  ): Promise<PaginatedResult<MemberView>> {
    return this.directory.search(user.userId, query);
  }

  @Get('regions')
  @ApiOperation({
    summary: 'Régions per country, from members already mirrored',
    description:
      'Distinct régions (with member counts) grouped by ISO country code. ' +
      'Pass `country` (code or name) to get a single country.',
  })
  @ApiQuery({ name: 'country', required: false, example: 'CM' })
  regions(@Query('country') country?: string): Promise<{ regions: RegionEntry[] }> {
    return this.directory.regions(country);
  }

  @Get('members/:sbcId')
  @ApiOperation({ summary: 'Member profile (from the mirror, populated by search)' })
  profile(
    @CurrentUser() user: AuthenticatedUser,
    @Param('sbcId') sbcId: string,
  ): Promise<MemberView> {
    return this.directory.getProfile(user.userId, sbcId);
  }

  @Get('export')
  @Raw()
  @ApiOperation({ summary: 'Export the member list as a VCF file' })
  async export(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: SearchQueryDto,
    @Res({ passthrough: true }) res: Response,
  ): Promise<string> {
    const file = await this.directory.export(user.userId, query);
    res.setHeader('Content-Type', file.contentType);
    res.setHeader('Content-Disposition', `attachment; filename="${file.filename}"`);
    return file.body;
  }
}

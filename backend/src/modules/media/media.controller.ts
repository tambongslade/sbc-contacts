import { mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Res,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsNumber, IsOptional, IsString, MaxLength, Min } from 'class-validator';
import type { Response } from 'express';
import { diskStorage } from 'multer';
import { AuthenticatedUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Public } from '../../common/decorators/public.decorator';
import { AttachmentView } from './media-url';
import { MediaService } from './media.service';
import { MAX_BYTES } from './sniff';

class UploadMetaDto {
  @IsOptional() @IsString() @MaxLength(200) fileName?: string;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) width?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) height?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) durationSec?: number;
}

class ReportDto {
  @IsOptional() @IsString() @MaxLength(500) reason?: string;
}

class LinkQueryDto {
  @Type(() => Number) @IsNumber() exp!: number;
  @IsString() @MaxLength(100) sig!: string;
}

/** Multer writes uploads here first; MediaService moves the ones it keeps. */
function tempDir(): string {
  const dir = join(process.env.MEDIA_DIR || join(process.cwd(), 'storage', 'media'), 'tmp');
  try {
    mkdirSync(dir, { recursive: true });
    return dir;
  } catch {
    return tmpdir();
  }
}

@ApiTags('media')
@Controller({ path: 'media', version: '1' })
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Post()
  @ApiBearerAuth()
  @ApiConsumes('multipart/form-data')
  @ApiOperation({
    summary: 'Upload a photo (10 Mo), a video (50 Mo) or a PDF (20 Mo), then send its id',
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({ destination: (_req, _file, cb) => cb(null, tempDir()) }),
      limits: { fileSize: MAX_BYTES.VIDEO, files: 1 },
    }),
  )
  upload(
    @CurrentUser() user: AuthenticatedUser,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() meta: UploadMetaDto,
  ): Promise<AttachmentView> {
    if (!file) throw new BadRequestException('Aucun fichier reçu');
    return this.media.upload(user.userId, file, meta);
  }

  /** The signed link from a view: the signature is the permission. */
  @Get(':id')
  @Public()
  async download(
    @Param('id', ParseUUIDPipe) id: string,
    @Query() q: LinkQueryDto,
    @Res() res: Response,
  ): Promise<void> {
    const file = await this.media.resolveLink(id, q.exp, q.sig);
    const name = file.fileName ? `; filename*=UTF-8''${encodeURIComponent(file.fileName)}` : '';
    res.sendFile(file.path, {
      headers: {
        'Content-Type': file.mimeType,
        'Content-Disposition': `inline${name}`,
        'Cache-Control': 'private, max-age=604800, immutable',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  }

  @Post(':id/report')
  @HttpCode(204)
  @ApiBearerAuth()
  @ApiOperation({ summary: '"Signaler" a photo, video or file' })
  report(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReportDto,
  ): Promise<void> {
    return this.media.report(user.userId, id, dto.reason);
  }
}

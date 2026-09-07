import { Controller, Headers, HttpCode, HttpStatus, Post, Req } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { RawBodyRequest } from '@nestjs/common';
import { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { WebhooksService } from './webhooks.service';

@ApiTags('webhooks')
@Controller({ path: 'webhooks', version: '1' })
export class WebhooksController {
  constructor(private readonly webhooks: WebhooksService) {}

  /**
   * SBC → us. NOT JWT-protected: authenticated by HMAC signature over the raw
   * body. Returns 202 immediately; processing happens on the WEBHOOKS queue.
   */
  @Public()
  @Post('sbc')
  @HttpCode(HttpStatus.ACCEPTED)
  @ApiOperation({ summary: 'Receive an SBC webhook (signature-verified, idempotent)' })
  receive(
    @Req() req: RawBodyRequest<Request>,
    @Headers('x-sbc-signature') signature?: string,
  ): Promise<{ received: boolean; duplicate: boolean; id?: string }> {
    return this.webhooks.ingest(req.rawBody, signature);
  }
}

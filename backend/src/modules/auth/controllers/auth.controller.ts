import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Req,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Request } from 'express';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../../../common/decorators/current-user.decorator';
import { Public } from '../../../common/decorators/public.decorator';
import { RefreshTokenDto } from '../dto/refresh-token.dto';
import { SsoCallbackDto } from '../dto/sso-callback.dto';
import { IssuedTokens, SessionMeta } from '../services/token.service';
import { AuthService, AuthResult, PublicUser } from '../services/auth.service';

@ApiTags('auth')
@Controller({ path: 'auth', version: '1' })
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('sso-callback')
  @HttpCode(HttpStatus.OK)
  // Strict: this hits SBC and creates sessions — abuse target (brief §9).
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: 'Exchange an SBC authorization code for an app session' })
  ssoCallback(@Body() dto: SsoCallbackDto, @Req() req: Request): Promise<AuthResult> {
    return this.auth.ssoCallback(dto.code, this.meta(req, dto.deviceId), dto.redirectUri);
  }

  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({ summary: 'Rotate the app access/refresh token pair' })
  refresh(@Body() dto: RefreshTokenDto, @Req() req: Request): Promise<IssuedTokens> {
    return this.auth.refresh(dto.refreshToken, this.meta(req, dto.deviceId));
  }

  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Revoke the current refresh-token family' })
  async logout(@Body() dto: RefreshTokenDto): Promise<void> {
    await this.auth.logout(dto.refreshToken);
  }

  @Get('me')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Current authenticated user (local snapshot)' })
  me(@CurrentUser() user: AuthenticatedUser): Promise<PublicUser> {
    return this.auth.me(user.userId);
  }

  @Get('me/refresh-profile')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Re-pull the profile from SBC (fresh subscription state)' })
  refreshProfile(@CurrentUser() user: AuthenticatedUser): Promise<PublicUser> {
    return this.auth.refreshProfile(user.userId);
  }

  private meta(req: Request, deviceId?: string): SessionMeta {
    return {
      deviceId,
      userAgent: req.headers['user-agent'],
      ip: req.ip,
    };
  }
}

import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { EncryptionService } from '../../../common/crypto/encryption.service';
import { PrismaService } from '../../../infrastructure/prisma/prisma.service';
import { SbcClientService } from '../../sbc-client/sbc-client.service';
import { SbcRefreshResponse, SbcTokenResponse } from '../../sbc-client/interfaces/sbc.interface';

/**
 * Custodian of each user's SBC tokens. Stores them ENCRYPTED at rest and hands
 * out a *valid* SBC access token to other modules (directory/sync), transparently
 * refreshing + rolling the refresh token when it's within the skew window
 * (guide: "if the JWT's exp is < 1 minute from now, hit /sso/refresh").
 */
@Injectable()
export class SbcTokenService {
  private readonly logger = new Logger(SbcTokenService.name);
  private static readonly REFRESH_SKEW_MS = 60_000; // refresh 1 min early
  private static readonly REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000; // SBC: 30d

  constructor(
    private readonly prisma: PrismaService,
    private readonly enc: EncryptionService,
    private readonly sbc: SbcClientService,
  ) {}

  /** Persist tokens from a code exchange (login). */
  async storeFromExchange(userId: string, res: SbcTokenResponse): Promise<void> {
    await this.persist(userId, res.access_token, res.refresh_token, res.expires_in, res.scope);
  }

  /**
   * Return a currently-valid SBC access token for the user, refreshing first if
   * it is expired or about to expire. Throws 401 if no token or refresh fails.
   */
  async getValidAccessToken(userId: string): Promise<string> {
    const record = await this.prisma.sbcToken.findUnique({ where: { userId } });
    if (!record) throw new UnauthorizedException('No SBC session; please log in again');

    const stillValid =
      record.accessExpiresAt.getTime() - SbcTokenService.REFRESH_SKEW_MS > Date.now();
    if (stillValid) {
      return this.enc.decrypt(record.accessTokenEnc);
    }

    if (record.refreshExpiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException('SBC session expired; please log in again');
    }

    return this.refresh(userId, this.enc.decrypt(record.refreshTokenEnc));
  }

  private async refresh(userId: string, refreshToken: string): Promise<string> {
    let res: SbcRefreshResponse;
    try {
      res = await this.sbc.refresh(refreshToken);
    } catch {
      this.logger.warn(`SBC refresh failed for user ${userId}`);
      throw new UnauthorizedException('Could not refresh SBC session; please log in again');
    }
    await this.persist(userId, res.access_token, res.refresh_token, res.expires_in, res.scope);
    return res.access_token;
  }

  private async persist(
    userId: string,
    accessToken: string,
    refreshToken: string,
    expiresIn: number,
    scope: string,
  ): Promise<void> {
    const accessExpiresAt = new Date(Date.now() + expiresIn * 1000);
    const refreshExpiresAt = new Date(Date.now() + SbcTokenService.REFRESH_TTL_MS);
    const data = {
      accessTokenEnc: this.enc.encrypt(accessToken),
      refreshTokenEnc: this.enc.encrypt(refreshToken),
      scope,
      accessExpiresAt,
      refreshExpiresAt,
    };
    await this.prisma.sbcToken.upsert({
      where: { userId },
      create: { userId, ...data },
      update: data,
    });
  }
}

import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/**
 * Rate limits per signed-in user, and per client IP otherwise.
 *
 * Keyed on the IP alone, every member behind the same carrier NAT shared one
 * bucket. The user id is only set by JwtAuthGuard once the token is verified
 * (it runs first), so a forged token cannot pick its own bucket.
 */
@Injectable()
export class UserThrottlerGuard extends ThrottlerGuard {
  protected override async getTracker(req: Record<string, any>): Promise<string> {
    const userId: string | undefined = req.user?.userId;
    return userId ? `user:${userId}` : `ip:${req.ips?.length ? req.ips[0] : req.ip}`;
  }
}

import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RedisService } from '../../infrastructure/cache/redis.service';

/** Whose traffic this is. User-facing calls come first; background yields. */
export type SbcCaller = 'user' | 'background';

/**
 * The single throttle in front of SBC — every SBC HTTP call passes through
 * [acquire] before it goes out. Backed by Redis so all pm2 processes (api +
 * any worker) share one budget rather than each keeping its own.
 *
 * Two things it guarantees:
 *
 *  1. A shared token bucket caps the total rate of SBC calls. Background work
 *     (the hydration walk) may only spend tokens while a reserve remains, so a
 *     walk can never drain the budget out from under a member browsing the
 *     annuaire — user calls always find a token first.
 *
 *  2. When SBC answers 429 (its 15-minute per-IP ban), [pauseBackground] flips
 *     a shared flag for that window. Background callers check [isPaused] and
 *     stop; user calls keep trying, since the member is waiting and the
 *     directory falls back to its cached pages.
 *
 * The bucket is a best-effort limiter, not a correctness lock: if Redis is
 * unreachable it fails OPEN (lets the call through) — throttling must never be
 * the reason a member can't load the annuaire.
 */
@Injectable()
export class SbcRateLimiterService {
  private readonly logger = new Logger(SbcRateLimiterService.name);

  private readonly capacity: number;
  private readonly refillPerSec: number;
  private readonly backgroundReserve: number;

  private static readonly BUCKET_KEY = 'sbc:ratelimit:v1';
  private static readonly PAUSE_KEY = 'sbc:paused:v1';

  /** SBC's ban window. A 429 pauses background work for exactly this long. */
  static readonly PAUSE_SECONDS = 15 * 60;

  /** How long a user call will wait for a token before going anyway (ms). */
  private static readonly USER_MAX_WAIT_MS = 3_000;
  /** How long a background call waits before giving up its turn (ms). */
  private static readonly BG_MAX_WAIT_MS = 30_000;
  /** Never sleep longer than this between token checks (ms). */
  private static readonly MAX_SLEEP_MS = 1_000;

  /**
   * Atomic token bucket in one round-trip. Refills against Redis server time
   * (TIME) so every process reads the same clock. A caller consumes one token
   * only if doing so leaves at least `reserve` behind — that reserve is how
   * background yields to users. Returns [allowed, secondsUntilAllowed].
   */
  private static readonly LUA = `
    local key = KEYS[1]
    local capacity = tonumber(ARGV[1])
    local refill = tonumber(ARGV[2])
    local reserve = tonumber(ARGV[3])
    local t = redis.call('TIME')
    local now = tonumber(t[1]) + tonumber(t[2]) / 1000000
    local tokens = tonumber(redis.call('HGET', key, 'tokens'))
    local ts = tonumber(redis.call('HGET', key, 'ts'))
    if tokens == nil then tokens = capacity; ts = now end
    tokens = math.min(capacity, tokens + math.max(0, now - ts) * refill)
    local allowed = 0
    local wait = 0
    if tokens - 1 >= reserve then
      tokens = tokens - 1
      allowed = 1
    else
      wait = ((reserve + 1) - tokens) / refill
    end
    redis.call('HSET', key, 'tokens', tokens, 'ts', now)
    redis.call('EXPIRE', key, math.ceil(capacity / refill) + 60)
    return {allowed, tostring(wait)}
  `;

  constructor(
    private readonly redis: RedisService,
    config: ConfigService,
  ) {
    // Estimates, tuned against SBC's real per-IP budget (its 429 says "after 15
    // minutes", so the window is ~900s). Defaults model ~120 calls / 15 min,
    // with a third of that reserved for members.
    this.capacity = config.get<number>('sbc.rateCapacity') ?? 120;
    this.refillPerSec = config.get<number>('sbc.rateRefillPerSec') ?? 120 / 900;
    this.backgroundReserve = config.get<number>('sbc.rateBackgroundReserve') ?? 40;
  }

  /**
   * Block until this caller may make one SBC call. User calls give up waiting
   * after a short cap and proceed anyway (best-effort — never strand a member);
   * background calls throw once their patience runs out so the walk stops
   * cleanly and lets the queue retry later.
   */
  async acquire(caller: SbcCaller): Promise<void> {
    if (caller === 'background' && (await this.isPaused())) {
      throw new Error('SBC background work is paused (rate-limit cooldown)');
    }
    const reserve = caller === 'background' ? this.backgroundReserve : 0;
    const maxWait =
      caller === 'background'
        ? SbcRateLimiterService.BG_MAX_WAIT_MS
        : SbcRateLimiterService.USER_MAX_WAIT_MS;
    const deadline = Date.now() + maxWait;

    for (;;) {
      const waitMs = await this.tryAcquire(reserve);
      if (waitMs === 0) return; // got a token
      if (waitMs < 0) return; // limiter unavailable — fail open

      if (Date.now() + waitMs > deadline) {
        if (caller === 'background') {
          throw new Error('SBC rate budget exhausted for background work');
        }
        return; // user proceeds regardless; the real SBC limit still guards us
      }
      await this.sleep(Math.min(waitMs, SbcRateLimiterService.MAX_SLEEP_MS));
    }
  }

  /** One bucket check. 0 = token taken, >0 = ms to wait, <0 = limiter down. */
  private async tryAcquire(reserve: number): Promise<number> {
    try {
      const res = (await this.redis.client.eval(
        SbcRateLimiterService.LUA,
        1,
        SbcRateLimiterService.BUCKET_KEY,
        this.capacity,
        this.refillPerSec,
        reserve,
      )) as [number, string];
      const allowed = Number(res[0]) === 1;
      if (allowed) return 0;
      return Math.max(0, Math.ceil(parseFloat(res[1]) * 1000));
    } catch (err) {
      this.logger.warn(`Rate limiter unavailable, failing open: ${(err as Error).message}`);
      return -1;
    }
  }

  /** SBC 429'd — stop all background SBC work for the ban window. */
  async pauseBackground(seconds = SbcRateLimiterService.PAUSE_SECONDS): Promise<void> {
    try {
      await this.redis.client.set(SbcRateLimiterService.PAUSE_KEY, '1', 'EX', seconds);
      this.logger.warn(`SBC returned 429 — pausing background SBC work for ${seconds}s`);
    } catch (err) {
      this.logger.warn(`Could not set SBC pause flag: ${(err as Error).message}`);
    }
  }

  /** Is background SBC work currently in the post-429 cooldown? */
  async isPaused(): Promise<boolean> {
    try {
      return (await this.redis.client.exists(SbcRateLimiterService.PAUSE_KEY)) === 1;
    } catch {
      return false; // fail open — a Redis blip must not wedge the walk forever
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

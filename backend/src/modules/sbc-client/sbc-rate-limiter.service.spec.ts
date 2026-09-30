import { ConfigService } from '@nestjs/config';
import { RedisService } from '../../infrastructure/cache/redis.service';
import { SbcRateLimiterService } from './sbc-rate-limiter.service';

describe('SbcRateLimiterService', () => {
  const config = { get: () => undefined } as unknown as ConfigService;

  function build(client: Partial<Record<'eval' | 'set' | 'exists', jest.Mock>>) {
    const redis = { client } as unknown as RedisService;
    return new SbcRateLimiterService(redis, config);
  }

  it('acquires a token when the bucket allows it', async () => {
    const evalFn = jest.fn().mockResolvedValue([1, '0']);
    const svc = build({ eval: evalFn, exists: jest.fn().mockResolvedValue(0) });
    await expect(svc.acquire('user')).resolves.toBeUndefined();
    expect(evalFn).toHaveBeenCalledTimes(1);
    // Background reserves headroom (ARGV[3] > 0); user does not (0).
    const userReserve = evalFn.mock.calls[0][evalFn.mock.calls[0].length - 1];
    expect(Number(userReserve)).toBe(0);
  });

  it('refuses background work outright while SBC is in cooldown', async () => {
    const evalFn = jest.fn();
    const svc = build({ eval: evalFn, exists: jest.fn().mockResolvedValue(1) });
    await expect(svc.acquire('background')).rejects.toThrow(/paused/i);
    expect(evalFn).not.toHaveBeenCalled(); // never even touched the bucket
  });

  it('fails OPEN when Redis is unreachable — throttling must not strand a member', async () => {
    const svc = build({
      eval: jest.fn().mockRejectedValue(new Error('redis down')),
      exists: jest.fn().mockResolvedValue(0),
    });
    await expect(svc.acquire('user')).resolves.toBeUndefined();
  });

  it('sets a pause flag for the ban window on 429', async () => {
    const setFn = jest.fn().mockResolvedValue('OK');
    const svc = build({ set: setFn });
    await svc.pauseBackground(900);
    expect(setFn).toHaveBeenCalledWith('sbc:paused:v1', '1', 'EX', 900);
  });

  it('reports paused state from the flag', async () => {
    const svc = build({ exists: jest.fn().mockResolvedValue(1) });
    await expect(svc.isPaused()).resolves.toBe(true);
  });
});

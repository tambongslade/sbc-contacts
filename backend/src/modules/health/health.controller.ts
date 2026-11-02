import { Controller, Get } from '@nestjs/common';
import {
  HealthCheck,
  HealthCheckResult,
  HealthCheckService,
  HealthIndicatorResult,
} from '@nestjs/terminus';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { Raw } from '../../common/decorators/raw-response.decorator';
import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { RedisService } from '../../infrastructure/cache/redis.service';
import { SbcDataAiService } from '../sbc-data/ai/sbc-data-ai.service';

@ApiTags('health')
@Public()
@Controller('health')
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly ai: SbcDataAiService,
  ) {}

  /** Liveness: is the process up? */
  @Get('live')
  @Raw()
  live(): { status: string } {
    return { status: 'ok' };
  }

  /**
   * Which AI provider backs each job and whether it is configured. Not part of
   * readiness: AI is optional and degrades to keyword matching when off.
   */
  @Get('ai')
  @Raw()
  aiStatus(): SbcDataAiService['status'] {
    return this.ai.status;
  }

  /** Readiness: are our critical dependencies reachable? (brief §23) */
  @Get('ready')
  @Raw()
  @HealthCheck()
  ready(): Promise<HealthCheckResult> {
    return this.health.check([() => this.checkDb(), () => this.checkRedis()]);
  }

  private async checkDb(): Promise<HealthIndicatorResult> {
    try {
      await this.prisma.ping();
      return { database: { status: 'up' } };
    } catch (e) {
      return { database: { status: 'down', message: (e as Error).message } };
    }
  }

  private async checkRedis(): Promise<HealthIndicatorResult> {
    try {
      const ok = await this.redis.ping();
      return { redis: { status: ok ? 'up' : 'down' } };
    } catch (e) {
      return { redis: { status: 'down', message: (e as Error).message } };
    }
  }
}

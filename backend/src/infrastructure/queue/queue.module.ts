import { BullModule } from '@nestjs/bullmq';
import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/** Central queue names — reference these constants, never string literals. */
export const QUEUE_NAMES = {
  MATCHING: 'matching', // new-member detection (§11)
  NOTIFICATIONS: 'notifications', // push/sms/email dispatch (§19)
  WEBHOOKS: 'webhooks', // inbound SBC webhook processing (§20)
} as const;

/**
 * Global BullMQ setup with sane defaults for every queue:
 * exponential-backoff retries, retention limits, and a dead-letter-friendly
 * "keep failed jobs" policy (brief §13).
 */
@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        connection: {
          host: config.get<string>('redis.host'),
          port: config.get<number>('redis.port'),
          password: config.get<string>('redis.password'),
          db: config.get<number>('redis.db'),
        },
        defaultJobOptions: {
          attempts: 3,
          backoff: { type: 'exponential', delay: 5000 },
          removeOnComplete: { age: 3600, count: 1000 },
          removeOnFail: { age: 24 * 3600 }, // keep for inspection / DLQ handling
        },
      }),
    }),
    BullModule.registerQueue(
      { name: QUEUE_NAMES.MATCHING },
      { name: QUEUE_NAMES.NOTIFICATIONS },
      { name: QUEUE_NAMES.WEBHOOKS },
    ),
  ],
  exports: [BullModule],
})
export class QueueModule {}

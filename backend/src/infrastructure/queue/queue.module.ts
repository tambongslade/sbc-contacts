import { BullModule } from '@nestjs/bullmq';
import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/** Central queue names — reference these constants, never string literals. */
export const QUEUE_NAMES = {
  MATCHING: 'matching', // new-member detection (§11)
  NOTIFICATIONS: 'notifications', // push/sms/email dispatch (§19)
  WEBHOOKS: 'webhooks', // inbound SBC webhook processing (§20)
  CRITERIA_SWEEP: 'criteria-sweep', // periodic re-check of active criteria (§11)
  SBC_DATA: 'sbc-data', // SBC Data: match a sent request and route it to pros
  HYDRATION: 'hydration', // deep mirror fill for a criteria (§10)
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
      { name: QUEUE_NAMES.CRITERIA_SWEEP },
      { name: QUEUE_NAMES.SBC_DATA },
      { name: QUEUE_NAMES.HYDRATION },
    ),
  ],
  exports: [BullModule],
})
export class QueueModule {}

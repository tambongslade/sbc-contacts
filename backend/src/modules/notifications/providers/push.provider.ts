import { Injectable, Logger } from '@nestjs/common';
import { NotificationPayload, NotificationProvider } from './notification-provider.interface';

/**
 * Push channel. Stubbed for now — logs the dispatch instead of calling FCM/APNs.
 * Swap the body of send() for a real FCM call without touching any caller
 * (that's the point of the provider abstraction). Fails soft: a provider error
 * is logged, not thrown, so one dead token can't fail a whole batch.
 */
@Injectable()
export class PushProvider implements NotificationProvider {
  readonly channel = 'push';
  private readonly logger = new Logger(PushProvider.name);

  async send(payload: NotificationPayload): Promise<void> {
    if (payload.deviceTokens.length === 0) {
      this.logger.debug(`No device tokens for user ${payload.userId}; skipping push`);
      return;
    }
    // TODO(prod): call FCM/APNs here with payload.deviceTokens.
    this.logger.log(
      `[push:stub] -> ${payload.deviceTokens.length} device(s) | ${payload.type}: ${payload.title}`,
    );
  }
}

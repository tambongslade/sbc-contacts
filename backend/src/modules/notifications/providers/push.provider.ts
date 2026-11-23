import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { DevicesService } from '../devices.service';
import { NotificationPayload, NotificationProvider } from './notification-provider.interface';

/** FCM errors meaning the token will never work again. */
const DEAD_TOKEN = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/**
 * Push channel over Firebase Cloud Messaging (FCM): the Flutter app on
 * Android. The native iOS app is reached over APNs (ApnsProvider).
 *
 * Config-gated: with no FCM credentials the provider stays a no-op that logs
 * the dispatch, so the app boots and every other channel keeps working without
 * them (the previous stub behaviour). Once FIREBASE_* env vars are set it sends
 * a real multicast. Fails soft — a provider error is logged, not thrown, so one
 * dead token can't fail a whole batch (the processor isolates providers too).
 */
@Injectable()
export class PushProvider implements NotificationProvider {
  readonly channel = 'push';
  private readonly logger = new Logger(PushProvider.name);
  private readonly app: App | null;

  constructor(
    config: ConfigService,
    private readonly devices: DevicesService,
  ) {
    const projectId = config.get<string>('fcm.projectId');
    const clientEmail = config.get<string>('fcm.clientEmail');
    const privateKey = config.get<string>('fcm.privateKey');

    if (projectId && clientEmail && privateKey) {
      // A fixed app name so a pm2/HMR reload reuses the instance instead of
      // throwing "app already exists".
      const name = 'sbc-contacts-fcm';
      this.app =
        getApps().find((a) => a.name === name) ??
        initializeApp({ credential: cert({ projectId, clientEmail, privateKey }) }, name);
      this.logger.log(`FCM push enabled (project ${projectId})`);
    } else {
      this.app = null;
      this.logger.warn('FCM not configured — push notifications are logged, not sent');
    }
  }

  async send(payload: NotificationPayload): Promise<void> {
    if (payload.deviceTokens.length === 0) {
      this.logger.debug(`No device tokens for user ${payload.userId}; skipping push`);
      return;
    }

    if (!this.app) {
      this.logger.log(
        `[fcm:stub] -> ${payload.deviceTokens.length} device(s) | ${payload.type}: ${payload.title}`,
      );
      return;
    }

    // FCM data values must be strings; stringify anything non-trivial. `link`
    // is what the app opens when the notification is tapped.
    const data: Record<string, string> = { type: payload.type, notificationId: payload.notificationId };
    for (const [k, v] of Object.entries(payload.data ?? {})) {
      data[k] = typeof v === 'string' ? v : JSON.stringify(v);
    }
    if (payload.link) data.link = payload.link;

    const res = await getMessaging(this.app).sendEachForMulticast({
      tokens: payload.deviceTokens,
      notification: { title: payload.title, body: payload.body },
      data,
      android: {
        priority: 'high',
        // Grouped per notification, so a re-sent one replaces rather than stacks.
        notification: { tag: payload.notificationId, channelId: 'sbc_alerts' },
      },
    });

    const dead = res.responses
      .map((r, i) => (!r.success && DEAD_TOKEN.has(r.error?.code ?? '') ? payload.deviceTokens[i] : null))
      .filter((t): t is string => t !== null);
    await this.devices.forgetTokens(dead);

    if (res.failureCount > 0) {
      const reasons = res.responses
        .filter((r) => !r.success)
        .map((r) => r.error?.code ?? 'unknown')
        .join(', ');
      this.logger.warn(
        `push ${payload.type}: ${res.successCount}/${payload.deviceTokens.length} delivered (failures: ${reasons})`,
      );
    }
  }
}

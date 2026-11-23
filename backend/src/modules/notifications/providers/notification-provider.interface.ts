import { NotificationType } from '@prisma/client';

export interface NotificationPayload {
  userId: string;
  notificationId: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  /** App path the notification opens (see notificationLink); null = Alertes tab. */
  link: string | null;
  /** The user's unread count, for the iOS app badge. */
  badge: number;
  /** FCM registration tokens (the Flutter app on Android). */
  deviceTokens: string[];
  /** APNs device tokens (the native iOS app). */
  apnsTokens: string[];
}

/**
 * A delivery channel (push/SMS/email/WhatsApp). Business modules depend on this
 * abstraction, never on a concrete provider (cahier §15 notification system /
 * brief §15). Swap or add providers without touching callers.
 */
export interface NotificationProvider {
  readonly channel: string;
  send(payload: NotificationPayload): Promise<void>;
}

export const NOTIFICATION_PROVIDERS = Symbol('NOTIFICATION_PROVIDERS');

import { NotificationType } from '@prisma/client';

export interface NotificationPayload {
  userId: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  deviceTokens: string[];
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

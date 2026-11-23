import { NotificationType } from '@prisma/client';

/**
 * The app screen a notification opens, as an app path both clients understand
 * (the Flutter go_router paths; the iOS app maps the same paths onto its
 * routes). Sent with every push as `link` and returned on every listed
 * notification, so a tap on the push and a tap in "Alertes" land on the same
 * page. Null when there is nothing more specific than the Alertes tab.
 */
export function notificationLink(
  type: NotificationType,
  data: Record<string, unknown> | null | undefined,
): string | null {
  const str = (key: string): string | null => {
    const v = data?.[key];
    return typeof v === 'string' && v.trim() ? encodeURIComponent(v.trim()) : null;
  };
  const requestId = str('requestId');

  switch (type) {
    case NotificationType.NEW_MATCH: {
      const sbcId = str('memberSbcId');
      return sbcId ? `/profile/${sbcId}` : null;
    }
    case NotificationType.CONTACT_SAVED:
      return '/sync/saved-me';

    // To the pro: the request in their inbox.
    case NotificationType.REQUEST_RECEIVED:
    case NotificationType.REQUEST_SELECTED:
    case NotificationType.REQUEST_CLOSED:
      return requestId ? `/inbox/${requestId}` : null;

    // To the requester: their own request and its answers.
    case NotificationType.REQUEST_RESPONSE:
    case NotificationType.REQUEST_NO_RESPONSE:
      return requestId ? `/requests/${requestId}` : null;

    // Both ways. A pro writing to the requester names its dispatch; the
    // requester writing to a pro does not (the pro has only one per request).
    case NotificationType.REQUEST_MESSAGE:
      if (!requestId) return null;
      return str('dispatchId') ? `/requests/${requestId}` : `/inbox/${requestId}`;

    default:
      return null;
  }
}

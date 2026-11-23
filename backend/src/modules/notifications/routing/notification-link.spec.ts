import { NotificationType } from '@prisma/client';
import { notificationLink } from './notification-link';

describe('notificationLink', () => {
  it('opens the matched member', () => {
    expect(notificationLink(NotificationType.NEW_MATCH, { memberSbcId: 'abc' })).toBe('/profile/abc');
    expect(notificationLink(NotificationType.NEW_MATCH, {})).toBeNull();
  });

  it('opens who saved me', () => {
    expect(notificationLink(NotificationType.CONTACT_SAVED, { actorUserId: 'u' })).toBe('/sync/saved-me');
  });

  it('sends a pro to the inbox and a requester to the request', () => {
    expect(notificationLink(NotificationType.REQUEST_RECEIVED, { requestId: 'r1' })).toBe('/inbox/r1');
    expect(notificationLink(NotificationType.REQUEST_SELECTED, { requestId: 'r1' })).toBe('/inbox/r1');
    expect(notificationLink(NotificationType.REQUEST_CLOSED, { requestId: 'r1' })).toBe('/inbox/r1');
    expect(notificationLink(NotificationType.REQUEST_RESPONSE, { requestId: 'r1', dispatchId: 'd' })).toBe(
      '/requests/r1',
    );
    expect(notificationLink(NotificationType.REQUEST_NO_RESPONSE, { requestId: 'r1' })).toBe('/requests/r1');
  });

  it('routes a message by who it is for', () => {
    expect(notificationLink(NotificationType.REQUEST_MESSAGE, { requestId: 'r1', dispatchId: 'd' })).toBe(
      '/requests/r1',
    );
    expect(notificationLink(NotificationType.REQUEST_MESSAGE, { requestId: 'r1' })).toBe('/inbox/r1');
  });

  it('falls back to null', () => {
    expect(notificationLink(NotificationType.SYNC_ERROR, null)).toBeNull();
    expect(notificationLink(NotificationType.REQUEST_RECEIVED, {})).toBeNull();
  });
});

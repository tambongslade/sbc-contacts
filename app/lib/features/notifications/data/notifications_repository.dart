import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/network/paginated.dart';
import 'package:sbc_contacts/features/notifications/domain/app_notification.dart';

class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  Future<Paginated<AppNotification>> list({
    int page = 1,
    int limit = 30,
    bool unreadOnly = false,
  }) async {
    final data = await _api.get(
      '/notifications',
      query: {'page': page, 'limit': limit, if (unreadOnly) 'unreadOnly': true},
    ) as Map<String, dynamic>;
    return Paginated.fromJson(data, AppNotification.fromJson);
  }

  Future<int> unreadCount() async {
    final data =
        await _api.get('/notifications/unread-count') as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) => _api.post('/notifications/$id/read');

  Future<void> markAllRead() => _api.post('/notifications/read-all');

  /// Returns the backend's device id, needed to unregister on sign-out.
  Future<String?> registerDevice({
    required String platform,
    String? pushToken,
  }) async {
    final data = await _api.post(
      '/notifications/devices',
      body: {
        'platform': platform,
        if (pushToken != null) 'pushToken': pushToken,
      },
    );
    return data is Map ? data['id']?.toString() : null;
  }

  Future<void> removeDevice(String id) =>
      _api.delete('/notifications/devices/$id');
}

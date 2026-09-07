@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/storage/token_storage.dart';
import 'package:sbc_contacts/features/auth/data/auth_repository.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';
import 'package:sbc_contacts/features/favorites/data/favorites_repository.dart';
import 'package:sbc_contacts/features/notifications/data/notifications_repository.dart';
import 'package:sbc_contacts/features/sync/data/sync_repository.dart';

/// End-to-end integration against a LIVE backend on localhost:3030 (started with
/// the mock SBC). Run: flutter test --tags integration \
///   --dart-define=API_BASE_URL=http://localhost:3030/api/v1
///
/// Exercises the real Dio client + repositories over HTTP — the actual
/// app↔backend contract, not mocks.
void main() {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3030/api/v1',
  );

  final storage = InMemoryTokenStorage();
  final api = ApiClient(storage: storage, baseUrl: baseUrl);
  final auth = AuthRepository(api, storage);
  final directory = DirectoryRepository(api);
  final favorites = FavoritesRepository(api);
  final sync = SyncRepository(api);
  final notifications = NotificationsRepository(api);

  test('SSO login stores tokens and returns the user', () async {
    final user = await auth.ssoCallback('valid-code', deviceId: 'flutter-test');
    expect(user.sbcUserId, isNotEmpty);
    expect(await storage.readAccess(), isNotNull);
    expect(await storage.readRefresh(), isNotNull);
  });

  test('authenticated /auth/me works with the stored token', () async {
    final me = await auth.me();
    expect(me.sbcUserId, isNotEmpty);
  });

  test('directory search returns members and hydrates the mirror', () async {
    final page = await directory.search(const SearchFilters(country: 'CM'));
    expect(page.items, isNotEmpty);
    expect(page.items.first.sbcId, isNotEmpty);
  });

  test('favorites add → list → remove round-trips', () async {
    final page = await directory.search(const SearchFilters(country: 'CM'));
    final target = page.items.first.sbcId;

    await favorites.add(target);
    final afterAdd = await favorites.list();
    expect(afterAdd.items.any((m) => m.sbcId == target), isTrue);

    await favorites.remove(target);
    final afterRemove = await favorites.list();
    expect(afterRemove.items.any((m) => m.sbcId == target), isFalse);
  });

  test('sync criteria create → preview → matches', () async {
    final criteria = await sync.createCriteria({
      'label': 'Flutter test',
      'countries': ['CM'],
      'professions': ['Designer'],
    });
    expect(criteria.id, isNotEmpty);

    final count = await sync.preview(criteria.id);
    expect(count, greaterThanOrEqualTo(0));

    final adhoc = await sync.previewAdhoc({'countries': ['CM']});
    expect(adhoc, greaterThanOrEqualTo(0));

    final matches = await sync.matches(criteria.id);
    expect(matches.total, greaterThanOrEqualTo(0));

    await sync.deleteCriteria(criteria.id);
  });

  test('sync summary and notifications endpoints respond', () async {
    final summary = await sync.summary();
    expect(summary.syncedCount, greaterThanOrEqualTo(0));

    final notifs = await notifications.list();
    expect(notifs.page, 1);
    final unread = await notifications.unreadCount();
    expect(unread, greaterThanOrEqualTo(0));
  });

  test('logout clears the session', () async {
    await auth.logout();
    expect(await storage.readAccess(), isNull);
  });
}

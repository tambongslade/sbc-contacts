import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/storage/token_storage.dart';
import 'package:sbc_contacts/features/auth/data/auth_repository.dart';
import 'package:sbc_contacts/features/contacts/contact_service.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';
import 'package:sbc_contacts/features/favorites/data/favorites_repository.dart';
import 'package:sbc_contacts/features/notifications/data/notifications_repository.dart';
import 'package:sbc_contacts/features/sync/data/sync_repository.dart';

/// Overridden in tests with an [InMemoryTokenStorage].
final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());

/// Overridden in integration tests to point at the local backend.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(storage: ref.watch(tokenStorageProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);

final directoryRepositoryProvider =
    Provider<DirectoryRepository>((ref) => DirectoryRepository(ref.watch(apiClientProvider)));

final favoritesRepositoryProvider =
    Provider<FavoritesRepository>((ref) => FavoritesRepository(ref.watch(apiClientProvider)));

final syncRepositoryProvider =
    Provider<SyncRepository>((ref) => SyncRepository(ref.watch(apiClientProvider)));

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

final contactServiceProvider = Provider<ContactService>((ref) => ContactService());

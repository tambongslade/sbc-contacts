import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/notifications/domain/app_notification.dart';

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  FutureOr<List<AppNotification>> build() async {
    final result = await ref.watch(notificationsRepositoryProvider).list();
    return result.items;
  }

  Future<void> markRead(String id) async {
    await ref.read(notificationsRepositoryProvider).markRead(id);
    ref.invalidateSelf();
    ref.invalidate(unreadCountProvider);
  }

  Future<void> markAllRead() async {
    await ref.read(notificationsRepositoryProvider).markAllRead();
    ref.invalidateSelf();
    ref.invalidate(unreadCountProvider);
  }
}

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

final unreadCountProvider = FutureProvider<int>(
  (ref) => ref.watch(notificationsRepositoryProvider).unreadCount(),
);

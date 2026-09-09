import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/theme/app_theme.dart';
import 'package:sbc_contacts/features/notifications/application/notifications_controller.dart';
import 'package:sbc_contacts/features/notifications/domain/app_notification.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(String type) => switch (type) {
        'NEW_MATCH' => Icons.person_add_alt_1,
        'NEW_CORRESPONDENCE' => Icons.group_add,
        'SYNC_AVAILABLE' => Icons.sync,
        'SYNC_ERROR' => Icons.sync_problem,
        _ => Icons.notifications,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(notificationsControllerProvider.notifier).markAllRead(),
            child: const Text('Tout lire'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, title: 'Erreur', message: e.toString()),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'Aucune notification',
              message: 'Tu seras notifié des nouveaux membres correspondant à tes critères.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsControllerProvider),
            child: ListView.separated(
              padding: EdgeInsets.only(bottom: AppTheme.navInsetOf(context)),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _tile(context, ref, items[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, AppNotification n) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: n.isRead
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primary.withValues(alpha: 0.15),
        child: Icon(_iconFor(n.type),
            color: n.isRead ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary),
      ),
      title: Text(
        n.title,
        style: TextStyle(fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w700),
      ),
      subtitle: Text(n.body),
      trailing: Text(
        DateFormat('dd/MM HH:mm').format(n.createdAt.toLocal()),
        style: theme.textTheme.labelSmall,
      ),
      onTap: n.isRead
          ? null
          : () => ref.read(notificationsControllerProvider.notifier).markRead(n.id),
    );
  }
}

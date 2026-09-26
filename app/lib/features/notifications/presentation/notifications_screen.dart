import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/app_theme.dart';
import 'package:sbc_contacts/features/notifications/application/notifications_controller.dart';
import 'package:sbc_contacts/features/notifications/domain/app_notification.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_card.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(String type) => switch (type) {
        'NEW_MATCH' => Icons.person_add_alt_1,
        'NEW_CORRESPONDENCE' => Icons.group_add,
        'SYNC_AVAILABLE' => Icons.sync,
        'SYNC_ERROR' => Icons.sync_problem,
        // "Quelqu'un t'a enregistré" (§21) — a person acting on you, which is
        // why it gets the badge icon rather than the sync one.
        'CONTACT_SAVED' => Icons.how_to_reg_rounded,
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
              message: 'Tu seras notifié quand un membre enregistre ton contact, et des '
                    'nouveaux membres correspondant à tes critères.',
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(n.body),
          // §11 is "tell me when a new member matches"; being told is only half
          // of it, so the alert that names somebody offers to save them.
          if (_savableMemberId(n) case final sbcId?)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SaveMatchButton(sbcId: sbcId),
              ),
            ),
        ],
      ),
      isThreeLine: _savableMemberId(n) != null,
      trailing: Text(
        DateFormat('dd/MM HH:mm').format(n.createdAt.toLocal()),
        style: theme.textTheme.labelSmall,
      ),
      onTap: n.isRead
          ? null
          : () => ref.read(notificationsControllerProvider.notifier).markRead(n.id),
    );
  }

  /// The member a NEW_MATCH is about, when the payload names one. Older rows
  /// were written before the backend attached it, so this stays optional.
  static String? _savableMemberId(AppNotification n) {
    if (n.type != 'NEW_MATCH') return null;
    final raw = n.data['memberSbcId'];
    final sbcId = raw?.toString() ?? '';
    return sbcId.isEmpty ? null : sbcId;
  }
}

/// Saves a matched member to the phone book straight from the alert.
///
/// The notification carries only an sbcId, so the member is fetched first — the
/// same record the profile screen saves, so the written contact is identical.
class _SaveMatchButton extends ConsumerStatefulWidget {
  const _SaveMatchButton({required this.sbcId});

  final String sbcId;

  @override
  ConsumerState<_SaveMatchButton> createState() => _SaveMatchButtonState();
}

class _SaveMatchButtonState extends ConsumerState<_SaveMatchButton> {
  bool _busy = false;
  bool _saved = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final member =
          await ref.read(directoryRepositoryProvider).profile(widget.sbcId);
      if (!mounted) return;
      await addMemberToPhone(context, ref, member);
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy || _saved ? null : _save,
      icon: _busy
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_saved ? Icons.check : Icons.person_add_alt_1, size: 18),
      label: Text(_saved ? 'Enregistré' : 'Enregistrer'),
    );
  }
}

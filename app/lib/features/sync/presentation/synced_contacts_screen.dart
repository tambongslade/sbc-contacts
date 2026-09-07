import 'package:flutter/material.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/whatsapp_button.dart';

/// "Mes contacts SBC" (cahier §16): what has been written to the phone, and
/// with what outcome. Filterable by sync status.
class SyncedContactsScreen extends ConsumerStatefulWidget {
  const SyncedContactsScreen({super.key});

  @override
  ConsumerState<SyncedContactsScreen> createState() => _SyncedContactsScreenState();
}

class _SyncedContactsScreenState extends ConsumerState<SyncedContactsScreen> {
  String? _status;

  static const _filters = <String?, String>{
    null: 'Tous',
    'SYNCED': 'Synchronisés',
    'PENDING': 'En attente',
    'FAILED': 'Échecs',
    'STALE': 'À mettre à jour',
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(syncedContactsProvider(_status));

    return Scaffold(
      appBar: AppBar(title: const Text('Mes contacts SBC')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (_) => setState(() => _status = e.key),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const ListSkeleton(),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Erreur',
                message: e.toString(),
                action: FilledButton(
                  onPressed: () => ref.invalidate(syncedContactsProvider(_status)),
                  child: const Text('Réessayer'),
                ),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.contact_page_outlined,
                    title: 'Aucun contact',
                    message:
                        'Les membres que vous enregistrez apparaîtront ici avec '
                        'leur statut de synchronisation.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(syncedContactsProvider(_status)),
                  child: ListView.separated(
                    itemCount: page.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _ContactTile(contact: page.items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact});
  final SyncedContact contact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color colour, String label) = switch (contact.status) {
      'SYNCED' => (Icons.check_circle, scheme.secondary, 'Synchronisé'),
      'PENDING' => (Icons.schedule, scheme.tertiary, 'En attente'),
      'FAILED' => (Icons.error_outline, scheme.error, 'Échec'),
      'STALE' => (Icons.update, scheme.tertiary, 'À mettre à jour'),
      _ => (Icons.help_outline, scheme.onSurfaceVariant, contact.status),
    };

    final subtitle = [contact.profession, contact.location]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');

    return ListTile(
      leading: MemberAvatar(
        initials: _initials(contact.displayName),
        avatarUrl: contact.avatarUrl,
      ),
      title: Text(contact.displayName),
      subtitle: Text(subtitle.isEmpty ? label : '$subtitle · $label'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 8),
          WhatsAppButton(phoneNumber: contact.phoneNumber, size: 36),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

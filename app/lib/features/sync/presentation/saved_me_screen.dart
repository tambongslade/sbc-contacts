import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';
import 'package:sbc_contacts/shared/widgets/whatsapp_button.dart';

/// "Qui m'a enregistré ?" (cahier §21) — the members who saved you.
///
/// The counterpart of "Mes contacts SBC": that screen says who you kept, this
/// one says who kept you. Only additions a device actually confirmed are
/// listed, so the screen never suggests someone saved you when they only
/// looked at your profile.
class SavedMeScreen extends ConsumerWidget {
  const SavedMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedMeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Qui m'a enregistré")),
      body: async.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Erreur',
          message: e.toString(),
          action: FilledButton(
            onPressed: () => ref.invalidate(savedMeProvider),
            child: const Text('Réessayer'),
          ),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return const EmptyState(
              icon: Icons.person_add_alt_outlined,
              title: 'Personne pour le moment',
              message:
                  "Quand un membre enregistre ton contact dans son téléphone, "
                  'il apparaît ici — et tu reçois une notification.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(savedMeProvider),
            child: ListView.separated(
              itemCount: page.items.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => i == 0
                  ? _CountHeader(total: page.total)
                  : _SavedMeTile(entry: page.items[i - 1]),
            ),
          );
        },
      ),
    );
  }
}

class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 17, color: SbcColors.secondary),
          const Gap(8),
          Expanded(
            child: Text(
              total == 1
                  ? '1 membre a enregistré ton contact'
                  : '$total membres ont enregistré ton contact',
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedMeTile extends StatelessWidget {
  const _SavedMeTile({required this.entry});
  final SavedMeEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [entry.profession, entry.location]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');

    return ListTile(
      leading: MemberAvatar(
        initials: _initials(entry.displayName),
        avatarUrl: entry.avatarUrl,
      ),
      title: Text(entry.displayName),
      subtitle: Text(
        subtitle.isEmpty
            ? _when(entry.savedAt)
            : '$subtitle · ${_when(entry.savedAt)}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: WhatsAppButton(phoneNumber: entry.phoneNumber, size: 36),
    );
  }

  /// Relative for the recent past, absolute once "il y a N jours" stops being
  /// easier to read than the date itself.
  static String _when(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return "à l'instant";
    if (delta.inMinutes < 60) return 'il y a ${delta.inMinutes} min';
    if (delta.inHours < 24) return 'il y a ${delta.inHours} h';
    if (delta.inDays < 7) return 'il y a ${delta.inDays} j';
    return DateFormat('d MMM y', 'fr').format(at);
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

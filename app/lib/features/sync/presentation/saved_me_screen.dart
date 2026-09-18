import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
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

class _SavedMeTile extends ConsumerStatefulWidget {
  const _SavedMeTile({required this.entry});
  final SavedMeEntry entry;

  @override
  ConsumerState<_SavedMeTile> createState() => _SavedMeTileState();
}

class _SavedMeTileState extends ConsumerState<_SavedMeTile> {
  /// Local so the row answers the tap immediately; the list is only refetched
  /// on a pull-to-refresh, and re-reading it just to flip one button would
  /// scroll the member back to the top.
  late bool _saved = widget.entry.alreadySaved;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
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
      // The reciprocal (§21): they kept you, so the one thing this row is for
      // is keeping them back — it sits before WhatsApp, which is the follow-up.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AddBackButton(
            saved: _saved,
            saving: _saving,
            onPressed: _addBack,
          ),
          const Gap(4),
          WhatsAppButton(
            phoneNumber: entry.phoneNumber,
            contactName: entry.displayName,
            size: 36,
          ),
        ],
      ),
    );
  }

  /// Writes them into the phone book and records it, so they also turn up in
  /// "Mes contacts SBC" — that screen reads the backend, not the phone book.
  Future<void> _addBack() async {
    final entry = widget.entry;
    final messenger = ScaffoldMessenger.of(context);
    final contacts = ref.read(contactServiceProvider);
    setState(() => _saving = true);

    try {
      if (!await contacts.requestPermission()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Permission contacts refusée')),
        );
        return;
      }

      final phone = entry.phoneNumber;
      // Already in the phone book: nothing to write, but it still belongs in
      // "Mes contacts SBC" — that list reports what is on the device, and it is.
      final present =
          phone != null && phone.isNotEmpty && await contacts.existsByPhone(phone);

      String? deviceContactId;
      if (!present) {
        final result = await contacts.addSbcContact(
          displayName: entry.displayName,
          phone: phone,
          profession: entry.profession,
          city: entry.city,
          country: entry.country,
        );
        if (!result.success) {
          messenger.showSnackBar(
            SnackBar(content: Text('Échec : ${result.error}')),
          );
          return;
        }
        deviceContactId = result.deviceContactId;
      }

      var recorded = true;
      try {
        recorded = await ref.read(syncRepositoryProvider).recordSingleContact(
              memberSbcId: entry.actorSbcId,
              deviceContactId: deviceContactId,
            );
      } catch (_) {
        // The contact IS on the phone; only the bookkeeping failed. Saying it
        // failed outright would send the member to save it a second time.
        recorded = false;
      }

      if (!mounted) return;
      setState(() => _saved = true);
      ref
        ..invalidate(syncSummaryProvider)
        ..invalidate(syncedContactsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            present
                ? 'Déjà dans ton répertoire'
                : recorded
                    ? 'Contact ajouté — visible dans « Mes contacts SBC »'
                    : 'Contact ajouté au téléphone (pas encore synchronisé au serveur)',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

/// "Ajouter" / "Ajouté", as a compact outlined pill rather than an icon: this
/// is the action the screen exists for, and an icon alone would not say which
/// direction the contact goes.
class _AddBackButton extends StatelessWidget {
  const _AddBackButton({
    required this.saved,
    required this.saving,
    required this.onPressed,
  });

  final bool saved;
  final bool saving;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (saved) {
      return Tooltip(
        message: 'Déjà dans ton répertoire',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, size: 16, color: SbcColors.success),
              const Gap(4),
              Text(
                'Ajouté',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: SbcColors.success),
              ),
            ],
          ),
        ),
      );
    }

    return OutlinedButton(
      onPressed: saving ? null : () => onPressed(),
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: SbcColors.primary,
      ),
      child: saving
          ? const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Ajouter'),
    );
  }
}

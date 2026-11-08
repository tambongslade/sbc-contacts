import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/spotlight/spotlight.dart';
import 'package:sbc_contacts/features/status_boost/status_boost.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';

/// "En vedette": members who pay to be shown first, at the top of "Qui m'a
/// enregistré" and "Augmenter mes vues WhatsApp". A member saved here leaves
/// the block for good — that contact is won — and the next one takes the place.
class FeaturedSection extends ConsumerStatefulWidget {
  const FeaturedSection({super.key});

  @override
  ConsumerState<FeaturedSection> createState() => _FeaturedSectionState();
}

class _FeaturedSectionState extends ConsumerState<FeaturedSection> {
  final Set<String> _saving = {};

  Future<void> _save(StatusBoostEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving.add(entry.sbcId));
    try {
      if (!await ref.read(contactServiceProvider).requestPermission()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Permission contacts refusée')),
        );
        return;
      }
      final ok = await ref.read(sbcContactWriterProvider)(entry);
      if (!mounted) return;
      if (ok) {
        // The server leaves out whoever this member saved: refetching brings the next one.
        ref
          ..invalidate(spotlightFeaturedProvider)
          ..invalidate(syncSummaryProvider)
          ..invalidate(syncedContactsProvider);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Contact ajouté — visible dans « Mes contacts SBC »'
                : "Impossible d'ajouter ce contact",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(entry.sbcId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final featured = ref.watch(spotlightFeaturedProvider).value ?? const [];
    final me = ref.watch(spotlightMeProvider).value;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (featured.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: SbcColors.accent,
                ),
                const Gap(6),
                Text(
                  'En vedette',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    'Enregistre-les, ils te verront aussi',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: SbcColors.accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: SbcColors.accent.withValues(alpha: 0.35),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < featured.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  _FeaturedRow(
                    entry: featured[i],
                    saving: _saving.contains(featured[i].sbcId),
                    onSave: () => _save(featured[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (me != null) _OwnSpotlight(status: me),
      ],
    );
  }
}

class _FeaturedRow extends StatelessWidget {
  const _FeaturedRow({
    required this.entry,
    required this.saving,
    required this.onSave,
  });

  final StatusBoostEntry entry;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          MemberAvatar(
            initials: entry.initials,
            avatarUrl: entry.avatarUrl,
            radius: 22,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(4),
                Text(
                  entry.savedMe
                      ? "T'a déjà enregistré — enregistre-le en retour"
                      : "T'a déjà enregistré",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SbcColors.whatsapp,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Gap(8),
          FilledButton(
            onPressed: saving ? null : onSave,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

/// The member's own "Mise en avant": active, or how to get it. The price is
/// never shown on iOS, where a feature paid outside the app may not be sold.
class _OwnSpotlight extends StatelessWidget {
  const _OwnSpotlight({required this.status});
  final SpotlightStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String text;
    if (status.active) {
      final until = status.until;
      text = until == null
          ? 'Ton profil est en vedette : les membres te voient en premier ici.'
          : "Ton profil est en vedette jusqu'au ${DateFormat('d MMMM', 'fr').format(until)} : "
                'les membres te voient en premier ici.';
    } else if (Platform.isIOS) {
      return const SizedBox.shrink();
    } else {
      final price = NumberFormat.decimalPattern('fr').format(status.priceFcfa);
      text =
          'Mets ton profil en vedette : les membres te voient en premier ici et t’enregistrent. '
          'Active la mise en avant ($price FCFA/mois) auprès de SBC.';
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status.active ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 20,
            color: SbcColors.accent,
          ),
          const Gap(10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

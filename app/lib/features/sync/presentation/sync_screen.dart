import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/theme/app_theme.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/shared/widgets/dark_pill_button.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';

/// Synchronisation home (cahier §10, §16, §17): the dashboard counters, the
/// saved criteria, and the way into "Mes contacts SBC" and the history.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(syncSummaryProvider);
    final criteria = ref.watch(criteriaControllerProvider);

    return Scaffold(
      // The FAB has to clear the floating nav bar the body runs under. The
      // Scaffold already floats it 16 off the bottom, so only the remainder is
      // added here.
      floatingActionButton: Padding(
        // Full nav inset, no shaving: the floating bar is painted after the
        // FAB, so 16 px of borrowed room came out of the FAB's corner.
        padding: EdgeInsets.only(bottom: AppTheme.navInsetOf(context)),
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/criteria/new'),
          shape: const StadiumBorder(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouveau critère'),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(syncSummaryProvider)
              ..invalidate(criteriaControllerProvider);
          },
          child: ListView(
            padding: EdgeInsets.only(bottom: AppTheme.navInsetOf(context)),
            children: [
              ScreenHeader(
                title: 'Synchronisation',
                trailing: DarkPillButton(
                  icon: Icons.history_rounded,
                  label: 'Historique',
                  onPressed: () => context.push('/sync/history'),
                ),
              ),
              summary.when(
                loading: SummarySkeleton.new,
                error: (e, _) => const SizedBox.shrink(),
                data: (s) => _SummaryCard(summary: s),
              ),
              const _Shortcut(
                icon: Icons.contact_page_rounded,
                label: 'Mes contacts SBC',
                route: '/sync/contacts',
                tint: SbcColors.primary,
              ),
              const Gap(8),
              // The counterpart: that screen says who you kept, this one says
              // who kept you (§21).
              const _Shortcut(
                icon: Icons.person_add_alt_1_rounded,
                label: "Qui m'a enregistré",
                route: '/sync/saved-me',
                tint: SbcColors.secondary,
              ),
              const _SectionLabel('Mes critères'),
              criteria.when(
                loading: () => const CardListSkeleton(rows: 3),
                error: (e, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Erreur',
                  message: e.toString(),
                  action: FilledButton(
                    onPressed: () => ref.invalidate(criteriaControllerProvider),
                    child: const Text('Réessayer'),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.tune,
                      title: 'Aucun critère',
                      message:
                          'Définis les catégories de membres à enregistrer : pays, '
                          "région, profession, centres d'intérêt, âge.",
                    );
                  }
                  return Column(
                    children: [for (final c in list) _CriteriaTile(criteria: c)],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small all-caps eyebrow. Sections are separated by a label and whitespace
/// rather than a rule — nothing on this screen is boxed in.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Way into a sub-screen, as a card rather than a button: these are
/// destinations, and the rest of this screen is made of cards.
class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.route,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String route;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
                const Gap(12),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleSmall),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four dashboard counters.
///
/// Laid out 2x2 rather than as one row of four: "Correspondances" cannot be
/// read at a quarter of a phone's width, and the counters are the first thing
/// this screen has to say. Each cell is its own soft tile, so the card reads as
/// four facts instead of one block of numbers.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final stats = [
      (
        label: 'Synchronisés',
        value: summary.syncedCount,
        icon: Icons.check_circle_rounded,
        color: SbcColors.success,
      ),
      (
        label: 'En attente',
        value: summary.pendingCount,
        icon: Icons.schedule_rounded,
        color: SbcColors.accent,
      ),
      (
        label: 'Correspondances',
        value: summary.currentMatches,
        icon: Icons.group_rounded,
        color: SbcColors.primary,
      ),
      (
        label: 'Critères',
        value: summary.activeCriteria,
        icon: Icons.tune_rounded,
        color: SbcColors.secondaryDark,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              Row(
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    Expanded(child: _StatTile(stat: stats[row * 2 + col])),
                    if (col == 0) const Gap(8),
                  ],
                ],
              ),
            if (summary.failedCount > 0) ...[
              const Gap(6),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 15, color: scheme.error),
                    const Gap(6),
                    Expanded(
                      child: Text(
                        '${summary.failedCount} échec(s) — voir Mes contacts SBC',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final ({String label, int value, IconData icon, Color color}) stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: SbcColors.surfaceTint.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: stat.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(stat.icon, size: 16, color: stat.color),
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  '${stat.value}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(fontSize: 21),
                ),
              ),
            ],
          ),
          const Gap(7),
          Text(
            stat.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One saved criterion: what it selects, how many members it currently matches,
/// and the two things you can do with it.
///
/// The match count sits in a pill next to the label rather than at the end of
/// the description, because it is the number the member checks before deciding
/// whether to run the sync at all.
class _CriteriaTile extends ConsumerWidget {
  const _CriteriaTile({required this.criteria});
  final SyncCriteria criteria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bits = [
      ...criteria.countries,
      ...criteria.cities,
      ...criteria.professions,
      ...criteria.interests,
    ];
    final desc = bits.isEmpty ? 'Tous les membres' : bits.take(4).join(' · ');
    final more = bits.length > 4 ? ' +${bits.length - 4}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      criteria.label,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: SbcColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group_rounded,
                            size: 13, color: SbcColors.primary),
                        const Gap(5),
                        Text(
                          '${criteria.lastMatchCount}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: SbcColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(5),
              Text(
                '$desc$more',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Gap(10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/criteria/${criteria.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                  const Gap(6),
                  // Was hidden behind a long-press, which nobody would find.
                  FilledButton.icon(
                    onPressed: () => context.push(
                      '/sync/review/${criteria.id}?label=${Uri.encodeComponent(criteria.label)}',
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Synchroniser'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

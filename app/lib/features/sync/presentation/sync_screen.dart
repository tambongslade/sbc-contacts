import 'package:flutter/material.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';

/// Synchronisation home (cahier §10, §16, §17): the dashboard counters, the
/// saved criteria, and the way into "Mes contacts SBC" and the history.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(syncSummaryProvider);
    final criteria = ref.watch(criteriaControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Synchronisation'),
        actions: [
          IconButton(
            tooltip: 'Historique',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/sync/history'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/criteria/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau critère'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(syncSummaryProvider)
            ..invalidate(criteriaControllerProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            summary.when(
              loading: SummarySkeleton.new,
              error: (e, _) => const SizedBox.shrink(),
              data: (s) => _SummaryCard(summary: s),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () => context.push('/sync/contacts'),
                icon: const Icon(Icons.contact_page_outlined),
                label: const Text('Mes contacts SBC'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Mes critères',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
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
                        'région, profession, centres d\'intérêt, âge.',
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
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget stat(String label, int value, IconData icon, Color color) => Expanded(
          child: Column(
            children: [
              Icon(icon, color: color),
              const Gap(4),
              Text('$value', style: theme.textTheme.titleLarge),
              Text(
                label,
                style: theme.textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                stat('Synchronisés', summary.syncedCount, Icons.check_circle,
                    scheme.secondary),
                stat('En attente', summary.pendingCount, Icons.schedule,
                    scheme.tertiary),
                stat('Correspondances', summary.currentMatches, Icons.group,
                    scheme.primary),
                stat('Critères', summary.activeCriteria, Icons.tune,
                    scheme.onSurfaceVariant),
              ],
            ),
            if (summary.failedCount > 0) ...[
              const Gap(10),
              Text(
                '${summary.failedCount} échec(s) — voir Mes contacts SBC',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    criteria.label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text('${criteria.lastMatchCount}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Gap(2),
            Text(
              '$desc$more',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Gap(4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => context.push('/criteria/${criteria.id}'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Modifier'),
                ),
                const Gap(4),
                // Was hidden behind a long-press, which nobody would find.
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/sync/review/${criteria.id}?label=${Uri.encodeComponent(criteria.label)}',
                  ),
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Synchroniser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

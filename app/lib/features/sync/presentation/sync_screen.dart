import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(syncSummaryProvider);
    final criteria = ref.watch(criteriaControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
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
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            summary.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const SizedBox.shrink(),
              data: (s) => _SummaryCard(summary: s),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Mes critères', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            criteria.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  EmptyState(icon: Icons.error_outline, title: 'Erreur', message: e.toString()),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.tune,
                    title: 'Aucun critère',
                    message: 'Définis les catégories de membres à synchroniser.',
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
    Widget stat(String label, int value, IconData icon, Color color) => Expanded(
          child: Column(
            children: [
              Icon(icon, color: color),
              const Gap(4),
              Text('$value', style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
            ],
          ),
        );
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            stat('Synchronisés', summary.syncedCount, Icons.check_circle, scheme.secondary),
            stat('En attente', summary.pendingCount, Icons.schedule, scheme.tertiary),
            stat('Correspondances', summary.currentMatches, Icons.group, scheme.primary),
            stat('Critères', summary.activeCriteria, Icons.tune, scheme.onSurfaceVariant),
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
    final desc = [
      ...criteria.countries,
      ...criteria.cities,
      ...criteria.professions,
    ].take(4).join(', ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(criteria.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(desc.isEmpty ? 'Tous les membres' : desc),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Chip(
              label: Text('${criteria.lastMatchCount}'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        onTap: () => context.push('/criteria/${criteria.id}'),
        onLongPress: () => _runSync(context, ref, criteria),
      ),
    );
  }

  /// Start a run, write matches to the phone book, and report outcomes (§10/§15).
  Future<void> _runSync(BuildContext context, WidgetRef ref, SyncCriteria c) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(syncRepositoryProvider);
    final contacts = ref.read(contactServiceProvider);

    if (!await contacts.requestPermission()) {
      messenger.showSnackBar(const SnackBar(content: Text('Permission contacts refusée')));
      return;
    }
    SyncRunStart run;
    try {
      run = await repo.startRun(criteriaId: c.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec: $e')));
      return;
    }

    final results = <Map<String, dynamic>>[];
    for (final t in run.items.where((t) => !t.alreadySynced)) {
      final r = await contacts.addSbcContact(
        firstName: t.firstName ?? t.displayName,
        lastName: t.name,
        phone: t.phoneNumber,
        profession: t.profession,
        city: t.city,
        country: t.country,
      );
      results.add({
        'memberSbcId': t.memberSbcId,
        if (r.deviceContactId != null) 'deviceContactId': r.deviceContactId,
        'status': r.success ? 'SYNCED' : 'FAILED',
      });
    }
    if (results.isNotEmpty) {
      await repo.reportRun(run.syncRunId, results);
    }
    ref.invalidate(syncSummaryProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('${results.length} contact(s) synchronisé(s)')),
    );
  }
}

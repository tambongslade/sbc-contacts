import 'package:flutter/material.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';

/// Historique de synchronisation (cahier §17): date, nombre de contacts
/// synchronisés et résultat de l'opération.
class SyncHistoryScreen extends ConsumerWidget {
  const SyncHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: async.when(
        loading: () => const ListSkeleton(hasLeading: false),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Erreur',
          message: e.toString(),
          action: FilledButton(
            onPressed: () => ref.invalidate(syncHistoryProvider),
            child: const Text('Réessayer'),
          ),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'Aucune synchronisation',
              message: 'Les synchronisations effectuées apparaîtront ici.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(syncHistoryProvider),
            child: ListView.separated(
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _RunTile(run: page.items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});
  final SyncRunEntry run;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color colour) = switch (run.status) {
      'COMPLETED' => (Icons.check_circle, scheme.secondary),
      'FAILED' => (Icons.error_outline, scheme.error),
      'RUNNING' => (Icons.sync, scheme.primary),
      _ => (Icons.schedule, scheme.tertiary),
    };

    final when = run.startedAt == null
        ? '—'
        : DateFormat("d MMM yyyy 'à' HH:mm", 'fr').format(run.startedAt!.toLocal());

    final detail = [
      '${run.syncedCount} synchronisé(s)',
      if (run.failedCount > 0) '${run.failedCount} échec(s)',
      'sur ${run.matchCount} correspondance(s)',
    ].join(' · ');

    return ListTile(
      leading: Icon(icon, color: colour),
      title: Text(when),
      subtitle: Text(run.error == null ? detail : '$detail\n${run.error}'),
      isThreeLine: run.error != null,
    );
  }
}

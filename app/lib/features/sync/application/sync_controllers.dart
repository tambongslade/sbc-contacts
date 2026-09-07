import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';

/// Saved criteria list.
class CriteriaController extends AsyncNotifier<List<SyncCriteria>> {
  @override
  FutureOr<List<SyncCriteria>> build() =>
      ref.watch(syncRepositoryProvider).listCriteria();

  Future<SyncCriteria> create(Map<String, dynamic> payload) async {
    final created = await ref.read(syncRepositoryProvider).createCriteria(payload);
    ref.invalidateSelf();
    return created;
  }

  // Named updateCriteria (not `update`) to avoid clashing with AsyncNotifier.update.
  Future<void> updateCriteria(String id, Map<String, dynamic> payload) async {
    await ref.read(syncRepositoryProvider).updateCriteria(id, payload);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(syncRepositoryProvider).deleteCriteria(id);
    ref.invalidateSelf();
  }
}

final criteriaControllerProvider =
    AsyncNotifierProvider<CriteriaController, List<SyncCriteria>>(CriteriaController.new);

/// "Mes contacts SBC" summary.
final syncSummaryProvider = FutureProvider<SyncSummary>(
  (ref) => ref.watch(syncRepositoryProvider).summary(),
);

/// Live match-count preview for an in-progress (unsaved) criteria form.
final adhocPreviewProvider = FutureProvider.family<int, Map<String, dynamic>>(
  (ref, payload) => ref.watch(syncRepositoryProvider).previewAdhoc(payload),
);

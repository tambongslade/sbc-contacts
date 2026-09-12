import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/network/paginated.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
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

/// "Mes contacts SBC" list (cahier §16); [status] filters on the backend enum.
final syncedContactsProvider =
    FutureProvider.family<Paginated<SyncedContact>, String?>(
  (ref, status) => ref.watch(syncRepositoryProvider).syncedContacts(status: status),
);

/// "Qui m'a enregistré ?" (cahier §21) — who has saved you.
final savedMeProvider = FutureProvider<Paginated<SavedMeEntry>>(
  (ref) => ref.watch(syncRepositoryProvider).savedMe(),
);

/// Synchronisation history (cahier §17).
final syncHistoryProvider = FutureProvider<Paginated<SyncRunEntry>>(
  (ref) => ref.watch(syncRepositoryProvider).history(),
);

/// Members matching a saved criteria, for the review-and-select screen (§10).
///
/// Deliberately the read-only endpoint: opening the screen to look must not
/// create a SyncRun. Starting a run happens only when the member presses
/// "Synchroniser", otherwise the history (§17) fills with phantom runs that
/// synced nothing.
final criteriaMatchesProvider =
    FutureProvider.family<Paginated<Member>, String>(
  (ref, criteriaId) => ref.watch(syncRepositoryProvider).matches(criteriaId),
);

/// Live match-count preview for an in-progress (unsaved) criteria form.
final adhocPreviewProvider = FutureProvider.family<int, Map<String, dynamic>>(
  (ref, payload) => ref.watch(syncRepositoryProvider).previewAdhoc(payload),
);

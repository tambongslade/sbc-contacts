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

/// A page of criteria matches plus whether the next page is being fetched, so
/// the list can show a footer spinner without collapsing back to a skeleton.
class MatchesState {
  const MatchesState({required this.page, this.loadingMore = false});

  final Paginated<Member> page;
  final bool loadingMore;

  MatchesState copyWith({Paginated<Member>? page, bool? loadingMore}) => MatchesState(
        page: page ?? this.page,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Members matching a saved criteria, paged lazily for the review-and-select
/// screen (§10). Opening the screen loads the first page; loadMore appends the
/// next as the member scrolls, so a criteria with thousands of matches streams
/// in as they swipe instead of arriving — or being capped — all at once.
///
/// Deliberately the read-only endpoint: opening the screen to look must not
/// create a SyncRun. Starting a run happens only when the member presses
/// "Synchroniser", otherwise the history (§17) fills with phantom runs that
/// synced nothing.
class CriteriaMatchesController extends AsyncNotifier<MatchesState> {
  CriteriaMatchesController(this.criteriaId);

  /// The family argument this notifier was built for.
  final String criteriaId;

  @override
  Future<MatchesState> build() async {
    final page = await ref.watch(syncRepositoryProvider).matches(criteriaId);
    return MatchesState(page: page);
  }

  /// Append the next page, once, as the member nears the end. No-ops when a load
  /// is already in flight or the last page is already in hand.
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.loadingMore || !current.page.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(syncRepositoryProvider)
          .matches(criteriaId, page: current.page.page + 1);
      state = AsyncData(MatchesState(page: current.page.concat(next)));
    } catch (_) {
      // Keep what we already have and drop the spinner; scrolling again retries.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final criteriaMatchesProvider =
    AsyncNotifierProvider.family<CriteriaMatchesController, MatchesState, String>(
  CriteriaMatchesController.new,
);

/// Live match-count preview for an in-progress (unsaved) criteria form.
final adhocPreviewProvider = FutureProvider.family<int, Map<String, dynamic>>(
  (ref, payload) => ref.watch(syncRepositoryProvider).previewAdhoc(payload),
);

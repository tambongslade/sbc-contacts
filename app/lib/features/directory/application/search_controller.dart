import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/network/api_exception.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';

class SearchState {
  const SearchState({
    this.filters = const SearchFilters(),
    this.members = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.page = 1,
    this.total = 0,
    this.error,
    this.errorCode,
  });

  final SearchFilters filters;
  final List<Member> members;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final int page;
  final int total;
  final String? error;
  final String? errorCode;

  bool get subscriptionRequired => errorCode == 'SUBSCRIPTION_REQUIRED';

  SearchState copyWith({
    SearchFilters? filters,
    List<Member>? members,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    int? page,
    int? total,
    String? error,
    String? errorCode,
    bool clearError = false,
  }) =>
      SearchState(
        filters: filters ?? this.filters,
        members: members ?? this.members,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        page: page ?? this.page,
        total: total ?? this.total,
        error: clearError ? null : (error ?? this.error),
        errorCode: clearError ? null : (errorCode ?? this.errorCode),
      );
}

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  DirectoryRepository get _repo => ref.read(directoryRepositoryProvider);

  Future<void> applyFilters(SearchFilters filters) async {
    state = state.copyWith(filters: filters);
    await search();
  }

  Future<void> search() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _repo.search(state.filters);
      state = state.copyWith(
        members: result.items,
        page: result.page,
        hasMore: result.hasMore,
        total: result.total,
        loading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message, errorCode: e.code);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    try {
      final result = await _repo.search(state.filters, page: state.page + 1);
      state = state.copyWith(
        members: [...state.members, ...result.items],
        page: result.page,
        hasMore: result.hasMore,
        loadingMore: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loadingMore: false, error: e.message, errorCode: e.code);
    }
  }

  /// Optimistically reflect a favorite toggle in the current result list.
  void setFavoriteLocal(String sbcId, {required bool isFavorite}) {
    state = state.copyWith(
      members: [
        for (final m in state.members)
          if (m.sbcId == sbcId) m.copyWith(isFavorite: isFavorite) else m,
      ],
    );
  }

  /// Same, for a contact just written to the phone: the row says "déjà dans
  /// ton répertoire" straight away instead of after the next search.
  void setSyncedLocal(String sbcId, {required bool isSynced}) {
    state = state.copyWith(
      members: [
        for (final m in state.members)
          if (m.sbcId == sbcId) m.copyWith(isSynced: isSynced) else m,
      ],
    );
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

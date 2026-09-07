// Hide Flutter's SearchController to avoid a clash with our directory controller.
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/features/directory/application/search_controller.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';
import 'package:sbc_contacts/features/directory/presentation/filter_sheet.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchControllerProvider.notifier).search();
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final current = ref.read(searchControllerProvider).filters;
    final updated = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: current),
    );
    if (updated != null) {
      await ref.read(searchControllerProvider.notifier).applyFilters(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final notifier = ref.read(searchControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechercher'),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
            tooltip: 'Filtres',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher un membre (ex. Designer)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          notifier.applyFilters(state.filters.copyWith(clearSearch: true));
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) =>
                  notifier.applyFilters(state.filters.copyWith(search: v)),
            ),
          ),
          Expanded(child: _buildBody(state, notifier)),
        ],
      ),
    );
  }

  Widget _buildBody(SearchState state, SearchController notifier) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.subscriptionRequired) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Abonnement requis',
        message:
            'Un abonnement SBC actif est nécessaire pour consulter les membres.',
      );
    }
    if (state.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Une erreur est survenue',
        message: state.error,
        action: FilledButton(onPressed: notifier.search, child: const Text('Réessayer')),
      );
    }
    if (state.members.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search,
        title: 'Aucun résultat',
        message: 'Ajuste tes filtres ou ta recherche.',
      );
    }
    return RefreshIndicator(
      onRefresh: notifier.search,
      child: ListView.builder(
        controller: _scroll,
        itemCount: state.members.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= state.members.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final m = state.members[i];
          return MemberCard(member: m, onTap: () => context.push('/profile/${m.sbcId}'));
        },
      ),
    );
  }
}

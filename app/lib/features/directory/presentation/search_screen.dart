// Hide Flutter's SearchController to avoid a clash with our directory controller.
import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/directory/application/search_controller.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';
import 'package:sbc_contacts/features/directory/domain/filter_options.dart';
import 'package:sbc_contacts/features/directory/presentation/filter_sheet.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_card.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';

/// "Rechercher" — the directory.
///
/// The screen is built as one query zone (search field + active filters) sitting
/// on a surface panel, then the results on the scaffold background. The member
/// always knows what is being asked (the field and the chips say it) and what
/// came back (the count line), which matters because the first call to a new
/// query costs ~2.5 s upstream.
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
      unawaited(ref.read(searchControllerProvider.notifier).search());
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      unawaited(ref.read(searchControllerProvider.notifier).loadMore());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  SearchController get _notifier => ref.read(searchControllerProvider.notifier);
  SearchFilters get _filters => ref.read(searchControllerProvider).filters;

  Future<void> _apply(SearchFilters filters) => _notifier.applyFilters(filters);

  Future<void> _openFilters() async {
    final updated = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => FilterSheet(initial: _filters),
    );
    if (updated != null) await _apply(updated);
  }

  /// Submit-driven search (unchanged): the upstream call is slow enough that
  /// firing per keystroke would be worse than an explicit submit.
  void _submitSearch(String raw) {
    final value = raw.trim();
    unawaited(
      _apply(
        value.isEmpty
            ? _filters.copyWith(clearSearch: true)
            : _filters.copyWith(search: value),
      ),
    );
  }

  void _clearSearch() {
    _searchCtrl.clear();
    unawaited(_apply(_filters.copyWith(clearSearch: true)));
  }

  void _removeFilter(ActiveFilter filter) =>
      unawaited(_apply(filter.removedFrom(_filters)));

  void _clearAllFilters() =>
      unawaited(_apply(SearchFilters(search: _filters.search)));

  void _applyProfession(String profession) {
    _searchCtrl.clear();
    unawaited(_apply(SearchFilters(profession: profession)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final active = ActiveFilter.of(state.filters);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechercher'),
        actions: [
          _FilterAction(count: active.length, onPressed: _openFilters),
          const Gap(4),
        ],
        bottom: const _BrandArcLine(),
      ),
      body: Column(
        children: [
          _QueryPanel(
            controller: _searchCtrl,
            filters: active,
            onSubmitted: _submitSearch,
            onClear: _clearSearch,
            onRemoveFilter: _removeFilter,
            onClearAll: _clearAllFilters,
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(SearchState state) {
    if (state.loading) return const CardListSkeleton(rows: 6);

    if (state.subscriptionRequired) {
      return _SubscriptionGate(onRetry: () => unawaited(_notifier.search()));
    }

    if (state.error != null) {
      return _ErrorView(
        message: state.error!,
        onRetry: () => unawaited(_notifier.search()),
      );
    }

    if (state.members.isEmpty) {
      return _NoResultsView(
        filters: state.filters,
        onOpenFilters: _openFilters,
        onClearAll: _clearAllFilters,
        onSuggestion: _applyProfession,
        onRetry: () => unawaited(_notifier.search()),
      );
    }

    return _ResultsList(
      state: state,
      scrollController: _scroll,
      onRefresh: _notifier.search,
      onOpenMember: (sbcId) => context.push('/profile/$sbcId'),
    );
  }
}

// ─────────────────────────────────────────────────────────── query zone ─────

/// The surface panel holding the screen's primary action (search) and the
/// evidence of what is currently being filtered.
class _QueryPanel extends StatelessWidget {
  const _QueryPanel({
    required this.controller,
    required this.filters,
    required this.onSubmitted,
    required this.onClear,
    required this.onRemoveFilter,
    required this.onClearAll,
  });

  final TextEditingController controller;
  final List<ActiveFilter> filters;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final ValueChanged<ActiveFilter> onRemoveFilter;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _SearchField(
              controller: controller,
              onSubmitted: onSubmitted,
              onClear: onClear,
            ),
          ),
          if (filters.isNotEmpty)
            _ActiveFilterBar(
              filters: filters,
              onRemove: onRemoveFilter,
              onClearAll: onClearAll,
            ),
        ],
      ),
    );
  }
}

/// The screen's primary action, styled as one solid object rather than a
/// default outlined input: brand-tinted at rest, brand-bordered on focus, so
/// it is obvious where a search starts.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = _focus.hasFocus;
    final accent = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: focused
            ? theme.colorScheme.surface
            : SbcColors.surfaceTint.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused
              ? accent
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          width: focused ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search_rounded,
              size: 22,
              color: focused ? accent : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onSubmitted,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                hintText: 'Rechercher un membre (ex. Designer)',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Rebuilt from the controller alone, so typing never rebuilds the
          // list behind it.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const Gap(8);
              return IconButton(
                tooltip: 'Effacer la recherche',
                iconSize: 20,
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onClear,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Removable chips for everything the filter sheet is currently imposing.
///
/// Without this the member has no way of knowing why a result set is small —
/// the filter sheet is closed and its state is invisible.
class _ActiveFilterBar extends StatelessWidget {
  const _ActiveFilterBar({
    required this.filters,
    required this.onRemove,
    required this.onClearAll,
  });

  final List<ActiveFilter> filters;
  final ValueChanged<ActiveFilter> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              filters.length > 1
                  ? '${filters.length} filtres'
                  : '1 filtre',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(10),
            for (final f in filters) ...[
              _RemovableFilterChip(filter: f, onRemove: () => onRemove(f)),
              const Gap(8),
            ],
            TextButton.icon(
              onPressed: onClearAll,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Tout effacer'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole chip removes the filter, not just the small × — a 16 dp delete
/// icon is not a usable target on a phone.
class _RemovableFilterChip extends StatelessWidget {
  const _RemovableFilterChip({required this.filter, required this.onRemove});

  final ActiveFilter filter;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputChip(
      avatar: Icon(filter.icon, size: 16, color: theme.colorScheme.primary),
      label: Text(filter.label),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      tooltip: 'Retirer le filtre ${filter.label}',
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      onPressed: onRemove,
      onDeleted: onRemove,
      backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      side: BorderSide(
        color: theme.colorScheme.primary.withValues(alpha: 0.28),
      ),
    );
  }
}

/// A 3 dp blue → green → orange rule under the app bar: the same signature
/// used on the profile and login screens, at the smallest possible dose.
class _BrandArcLine extends StatelessWidget implements PreferredSizeWidget {
  const _BrandArcLine();

  @override
  Size get preferredSize => const Size.fromHeight(3);

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 3,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: SbcColors.brandArc),
        ),
      );
}

/// Filter entry point. Carries its own count so "filtered" is never signalled
/// by colour alone.
class _FilterAction extends StatelessWidget {
  const _FilterAction({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = count > 0;
    return Badge(
      isLabelVisible: active,
      label: Text('$count'),
      backgroundColor: theme.colorScheme.tertiary,
      offset: const Offset(-4, 4),
      child: IconButton(
        onPressed: onPressed,
        tooltip: active ? '$count filtre(s) actif(s)' : 'Filtres',
        icon: const Icon(Icons.tune_rounded),
        style: active
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              )
            : null,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────── results ─────

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.state,
    required this.scrollController,
    required this.onRefresh,
    required this.onOpenMember,
  });

  final SearchState state;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onOpenMember;

  /// Only the first screenful is staggered — animating rows the member scrolls
  /// to would fight the scroll.
  static const _animatedRows = 6;

  @override
  Widget build(BuildContext context) {
    final members = state.members;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 28),
        itemCount: members.length + (state.hasMore ? 2 : 1),
        itemBuilder: (context, i) {
          if (i == 0) return _ResultCount(total: state.total, shown: members.length);
          final index = i - 1;
          if (index >= members.length) return const _LoadMoreFooter();

          final member = members[index];
          final card = MemberCard(
            member: member,
            onTap: () => onOpenMember(member.sbcId),
          );
          if (index >= _animatedRows) return card;
          return card
              .animate()
              .fadeIn(duration: const Duration(milliseconds: 220))
              .slideY(
                begin: 0.06,
                end: 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
        },
      ),
    );
  }
}

/// Answers "did my filter do anything?" — the cheapest useful feedback on the
/// screen.
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.total, required this.shown});

  final int total;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = total > 0 ? total : shown;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Text(
        count > 1 ? '$count membres trouvés' : '$count membre trouvé',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const Gap(10),
          Text(
            'Chargement des membres suivants…',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── empty states ───

/// Keeps a centred state centred on a big screen, but lets it scroll instead
/// of overflowing once the member scales their font up.
class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

/// No results: always offers the next move (retirer un filtre, en changer, ou
/// partir d'une profession qui existe réellement dans la base).
class _NoResultsView extends StatelessWidget {
  const _NoResultsView({
    required this.filters,
    required this.onOpenFilters,
    required this.onClearAll,
    required this.onSuggestion,
    required this.onRetry,
  });

  final SearchFilters filters;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearAll;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onRetry;

  /// Verbatim values from the live SBC vocabulary — a suggestion that returns
  /// nothing would be worse than no suggestion at all.
  static const _suggestions = [
    'Etudiant(e)',
    'Enseignant',
    'Electricien',
    'Vendeur/Vendeuse',
  ];

  @override
  Widget build(BuildContext context) {
    final search = filters.search;
    final hasSearch = search != null && search.isNotEmpty;
    final hasFilters = ActiveFilter.of(filters).isNotEmpty;

    if (!hasSearch && !hasFilters) {
      return _ScrollableCenter(
        child: EmptyState(
          icon: Icons.people_outline,
          title: 'Aucun membre à afficher',
          message: 'Le répertoire n’a rien renvoyé pour le moment.',
          action: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Actualiser'),
          ),
        ),
      );
    }

    return _ScrollableCenter(
      child: EmptyState(
        icon: Icons.person_search_outlined,
        title: 'Aucun membre trouvé',
        message: hasSearch
            ? 'Aucun membre ne correspond à « $search ». Vérifie l’orthographe '
                'ou essaie un mot plus court.'
            : 'Aucun membre ne correspond à cette combinaison de filtres.',
        action: Column(
          children: [
            if (hasFilters)
              FilledButton.icon(
                onPressed: onClearAll,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
                label: const Text('Effacer les filtres'),
              ),
            const Gap(4),
            TextButton.icon(
              onPressed: onOpenFilters,
              icon: const Icon(Icons.tune_rounded, size: 20),
              label: const Text('Modifier les filtres'),
            ),
            const Gap(12),
            _SuggestionBlock(
              suggestions: _suggestions,
              onSelected: onSuggestion,
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionBlock extends StatelessWidget {
  const _SuggestionBlock({required this.suggestions, required this.onSelected});

  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Essaie une profession',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Gap(8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(
                avatar: Icon(
                  Icons.work_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                label: Text(s),
                onPressed: () => onSelected(s),
              ),
          ],
        ),
      ],
    );
  }
}

/// Errors are shown as a cause the member can act on. The raw API message is
/// never surfaced — it is English, technical, and sometimes a Dio string.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  bool get _offline {
    final m = message.toLowerCase();
    return m.contains('network') ||
        m.contains('socket') ||
        m.contains('timeout') ||
        m.contains('connection');
  }

  @override
  Widget build(BuildContext context) {
    return _ScrollableCenter(
      child: EmptyState(
        icon: _offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
        title: _offline ? 'Pas de connexion' : 'Répertoire indisponible',
        message: _offline
            ? 'Vérifie ta connexion internet, puis réessaie.'
            : 'Impossible de joindre SBC pour le moment. Réessaie dans quelques '
                'instants.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('Réessayer'),
        ),
      ),
    );
  }
}

/// The paywall. This is the one moment on the screen worth a brand treatment:
/// it has to explain what is behind the lock, not just refuse.
class _SubscriptionGate extends StatelessWidget {
  const _SubscriptionGate({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 4,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: SbcColors.brandArc),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: theme.colorScheme.tertiary,
                      size: 24,
                    ),
                  ),
                  const Gap(16),
                  Text(
                    'Réservé aux abonnés SBC',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    'L’annuaire des membres est réservé aux abonnés SBC. '
                    'Active ton abonnement, puis actualise cette page.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const Gap(18),
                  const _GateBenefit(
                    icon: Icons.groups_2_outlined,
                    label: 'Tout le répertoire des membres SBC',
                  ),
                  const Gap(10),
                  const _GateBenefit(
                    icon: Icons.tune_rounded,
                    label: 'Filtres par métier, région, âge et centres '
                        'd’intérêt',
                  ),
                  const Gap(10),
                  const _GateBenefit(
                    icon: Icons.chat_bubble_outline,
                    label: 'Contact WhatsApp direct et ajout au répertoire',
                  ),
                  const Gap(20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('J’ai activé mon abonnement'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          'Ton abonnement se gère dans l’onglet Profil.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: const Duration(milliseconds: 240)),
    );
  }
}

class _GateBenefit extends StatelessWidget {
  const _GateBenefit({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const Gap(10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────── active filters ─────

/// Which field of [SearchFilters] a chip stands for.
enum FilterKind { country, region, city, profession, sex, age, interest }

/// One human-readable, removable filter derived from [SearchFilters].
///
/// `SearchFilters.copyWith` cannot set a field back to null, so removal
/// rebuilds the value object field by field instead — no repository change.
class ActiveFilter {
  const ActiveFilter({
    required this.kind,
    required this.icon,
    required this.label,
    this.value,
  });

  final FilterKind kind;
  final IconData icon;
  final String label;

  /// Only used by [FilterKind.interest], where each entry is removable on its
  /// own.
  final String? value;

  static List<ActiveFilter> of(SearchFilters f) => [
        if (f.country != null)
          ActiveFilter(
            kind: FilterKind.country,
            icon: Icons.public,
            label: FilterOptions.countries[f.country] ?? f.country!,
          ),
        if (f.region != null)
          ActiveFilter(
            kind: FilterKind.region,
            icon: Icons.location_on_outlined,
            label: f.region!,
          ),
        if (f.city != null)
          ActiveFilter(
            kind: FilterKind.city,
            icon: Icons.location_city_outlined,
            label: f.city!,
          ),
        if (f.profession != null)
          ActiveFilter(
            kind: FilterKind.profession,
            icon: Icons.work_outline,
            label: f.profession!,
          ),
        if (f.sex != null)
          ActiveFilter(
            kind: FilterKind.sex,
            icon: Icons.person_outline,
            label: FilterOptions.sexes[f.sex] ?? f.sex!,
          ),
        if (f.ageMin != null || f.ageMax != null)
          ActiveFilter(
            kind: FilterKind.age,
            icon: Icons.cake_outlined,
            label: '${f.ageMin ?? 16} – ${f.ageMax ?? 80} ans',
          ),
        for (final i in f.interests)
          ActiveFilter(
            kind: FilterKind.interest,
            icon: Icons.favorite_outline,
            label: i,
            value: i,
          ),
      ];

  /// [SearchFilters] without this one filter, everything else untouched.
  SearchFilters removedFrom(SearchFilters f) => SearchFilters(
        search: f.search,
        country: kind == FilterKind.country ? null : f.country,
        region: kind == FilterKind.region ? null : f.region,
        city: kind == FilterKind.city ? null : f.city,
        profession: kind == FilterKind.profession ? null : f.profession,
        sex: kind == FilterKind.sex ? null : f.sex,
        ageMin: kind == FilterKind.age ? null : f.ageMin,
        ageMax: kind == FilterKind.age ? null : f.ageMax,
        interests: kind == FilterKind.interest
            ? [
                for (final i in f.interests)
                  if (i != value) i,
              ]
            : f.interests,
      );
}

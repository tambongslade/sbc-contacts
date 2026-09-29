import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/application/sync_runner.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';

/// Review the members a criteria matches, choose which to save, then write them
/// to the phone book (cahier §10: "synchroniser tous les contacts proposés ou
/// effectuer une sélection").
///
/// Selection is the point of this screen. Syncing everything blindly is what
/// §11 warns against — every write is confirmed by the member first.
class SyncReviewScreen extends ConsumerStatefulWidget {
  const SyncReviewScreen({required this.criteriaId, required this.label, super.key});

  final String criteriaId;
  final String label;

  @override
  ConsumerState<SyncReviewScreen> createState() => _SyncReviewScreenState();
}

class _SyncReviewScreenState extends ConsumerState<SyncReviewScreen> {
  final Set<String> _selected = {};
  final Set<String> _primed = {};
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Ask for the next page once the member is within a screenful of the end, so
  /// the list keeps growing as they swipe rather than stopping at page one.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      unawaited(ref.read(criteriaMatchesProvider(widget.criteriaId).notifier).loadMore());
    }
  }

  /// Everything not already on the device starts selected — the common case is
  /// "save them all", with opting out one tap away. Runs per member id (not once
  /// overall) so members from a freshly loaded page arrive pre-selected too,
  /// while any the member deliberately unchecked stay unchecked.
  void _prime(List<Member> items) {
    for (final t in items) {
      if (!_primed.add(t.sbcId)) continue; // already seen this one
      if (!t.isSynced) _selected.add(t.sbcId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(criteriaMatchesProvider(widget.criteriaId));
    final progress = ref.watch(syncRunnerProvider);

    ref.listen(syncRunnerProvider, (_, next) {
      if (next.finished && next.error != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(widget.label)),
      body: async.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Impossible de charger les correspondances',
          message: e.toString(),
          action: FilledButton(
            onPressed: () => ref.invalidate(criteriaMatchesProvider(widget.criteriaId)),
            child: const Text('Réessayer'),
          ),
        ),
        data: (matches) {
          final page = matches.page;
          if (page.items.isEmpty) {
            return const EmptyState(
              icon: Icons.person_search,
              title: 'Aucune correspondance',
              message: 'Aucun membre ne correspond encore à ce critère.',
            );
          }
          _prime(page.items);
          return Column(
            children: [
              _Header(total: page.total, selected: _selected.length),
              if (progress.running) _ProgressBar(progress: progress),
              if (progress.finished && !progress.running)
                _Outcome(progress: progress),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  // One extra row for the footer while more pages remain: a
                  // spinner as they load, a nudge to keep scrolling otherwise.
                  itemCount: page.items.length + (page.hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= page.items.length) {
                      return _LoadMoreFooter(loading: matches.loadingMore);
                    }
                    final t = page.items[i];
                    return _TargetTile(
                      target: t,
                      selected: _selected.contains(t.sbcId),
                      enabled: !progress.running,
                      onChanged: (on) => setState(() {
                        if (on) {
                          _selected.add(t.sbcId);
                        } else {
                          _selected.remove(t.sbcId);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (matches) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: progress.running
                        ? null
                        : () => setState(() {
                              final selectable = matches.page.items
                                  .where((t) => !t.isSynced)
                                  .map((t) => t.sbcId);
                              if (_selected.length == selectable.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(selectable);
                              }
                            }),
                    child: const Text('Tout / rien'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty || progress.running
                        ? null
                        : () => ref.read(syncRunnerProvider.notifier).run(
                              criteriaId: widget.criteriaId,
                              memberSbcIds: _selected.toList(),
                            ),
                    icon: const Icon(Icons.sync),
                    label: Text(
                      _selected.isEmpty
                          ? 'Sélectionne des membres'
                          : 'Synchroniser (${_selected.length})',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.selected});
  final int total;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.group, color: theme.colorScheme.primary),
          const Gap(10),
          Expanded(
            child: Text(
              '$total membre(s) correspondent · $selected sélectionné(s)',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});
  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress.total == 0 ? null : progress.fraction),
          const Gap(6),
          Text(
            'Enregistrement ${progress.done}/${progress.total}…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.progress});
  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      if (progress.synced > 0) '${progress.synced} ajouté(s)',
      if (progress.skipped > 0) '${progress.skipped} déjà présent(s)',
      if (progress.failed > 0) '${progress.failed} échec(s)',
    ];
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        parts.isEmpty ? 'Rien à synchroniser.' : parts.join(' · '),
        style: TextStyle(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                'Faites défiler pour charger plus…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.target,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final Member target;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = [target.profession, target.city, target.country]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');
    final name = target.displayName.isEmpty ? 'Membre SBC' : target.displayName;

    if (target.isSynced) {
      return ListTile(
        leading: MemberAvatar(initials: _initials(name), avatarUrl: target.avatarUrl),
        title: Text(name),
        subtitle: Text(subtitle.isEmpty ? 'Déjà synchronisé' : subtitle),
        trailing: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.secondary),
        enabled: false,
      );
    }

    return CheckboxListTile(
      value: selected,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      secondary: MemberAvatar(initials: _initials(name), avatarUrl: target.avatarUrl),
      title: Text(name),
      subtitle: Text(
        target.phoneNumber == null || target.phoneNumber!.isEmpty
            ? '$subtitle · sans numéro'
            : subtitle,
      ),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

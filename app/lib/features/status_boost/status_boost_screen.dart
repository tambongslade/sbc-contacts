import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/status_boost/status_boost.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';

final statusBoostRepositoryProvider = Provider<StatusBoostRepository>(
  (ref) => StatusBoostRepository(ref.watch(apiClientProvider)),
);

/// "Je veux augmenter mon nombre de vues en statut WhatsApp".
///
/// WhatsApp only shows a status between people who saved each other's number,
/// so members opt in here and save one another. Every save goes through the
/// usual recording, so it lands in "Mes contacts SBC" and the other member is
/// told someone saved them — which is what brings them to save back.
class StatusBoostScreen extends ConsumerStatefulWidget {
  const StatusBoostScreen({super.key});

  @override
  ConsumerState<StatusBoostScreen> createState() => _StatusBoostScreenState();
}

class _StatusBoostScreenState extends ConsumerState<StatusBoostScreen> {
  final _scroll = ScrollController();
  Timer? _debounce;

  StatusBoostMe? _me;
  List<StatusBoostEntry> _items = [];
  List<String> _types = [];
  int _total = 0;
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _toggling = false;
  Object? _error;

  String? _subscription;
  String _search = '';

  /// Saved during this visit — the list is not refetched for each save, which
  /// would scroll the member back to the top.
  final Set<String> _saved = {};
  final Set<String> _saving = {};
  int? _bulkDone;
  int _bulkTotal = 0;

  StatusBoostRepository get _repo => ref.read(statusBoostRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    unawaited(_reload(withMe: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload({bool withMe = false}) async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.list(subscription: _subscription, search: _search),
        if (withMe || _me == null) _repo.me(),
      ]);
      if (!mounted) return;
      final page = results[0] as StatusBoostPage;
      setState(() {
        if (results.length > 1) _me = results[1] as StatusBoostMe;
        _items = page.items;
        _total = page.total;
        _hasMore = page.hasMore;
        _page = 1;
        if (page.subscriptionTypes.isNotEmpty) _types = page.subscriptionTypes;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _maybeLoadMore() async {
    if (!_hasMore || _loadingMore) return;
    if (_scroll.position.extentAfter > 400) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.list(
        subscription: _subscription,
        search: _search,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.hasMore;
        _page += 1;
      });
    } catch (_) {
      // The next scroll tries again.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search = value;
      unawaited(_reload());
    });
  }

  void _onFilter(String? type) {
    if (type == _subscription) return;
    setState(() => _subscription = type);
    unawaited(_reload());
  }

  Future<void> _toggleOptIn({required bool optIn}) async {
    setState(() => _toggling = true);
    try {
      final me = await _repo.setOptIn(optIn: optIn);
      if (mounted) setState(() => _me = me);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Échec : $e')));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  bool _isSaved(StatusBoostEntry e) => e.savedByMe || _saved.contains(e.sbcId);

  /// Writes one member into the phone book and records it. Returns false when
  /// the contact could not be written; a failed recording alone still counts,
  /// since the contact IS on the phone.
  Future<bool> _write(StatusBoostEntry entry) async {
    final contacts = ref.read(contactServiceProvider);
    final present = entry.phoneNumber.isNotEmpty &&
        await contacts.existsByPhone(entry.phoneNumber);
    String? deviceContactId;
    if (!present) {
      final result = await contacts.addSbcContact(
        displayName: entry.name,
        phone: entry.phoneNumber,
        country: entry.country,
      );
      if (!result.success) return false;
      deviceContactId = result.deviceContactId;
    }
    try {
      await ref.read(syncRepositoryProvider).recordSingleContact(
            memberSbcId: entry.sbcId,
            deviceContactId: deviceContactId,
          );
    } catch (_) {
      // Bookkeeping only — the phone book is right either way.
    }
    return true;
  }

  Future<bool> _askPermission() async {
    if (await ref.read(contactServiceProvider).requestPermission()) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission contacts refusée')),
      );
    }
    return false;
  }

  void _refreshSyncScreens() {
    ref
      ..invalidate(syncSummaryProvider)
      ..invalidate(syncedContactsProvider);
  }

  Future<void> _saveOne(StatusBoostEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving.add(entry.sbcId));
    try {
      if (!await _askPermission()) return;
      final ok = await _write(entry);
      if (!mounted) return;
      if (ok) {
        setState(() => _saved.add(entry.sbcId));
        _refreshSyncScreens();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Contact ajouté — visible dans « Mes contacts SBC »'
                : "Impossible d'ajouter ce contact",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(entry.sbcId));
    }
  }

  Future<void> _saveAll() async {
    final pending = _items.where((e) => !_isSaved(e)).toList();
    final messenger = ScaffoldMessenger.of(context);
    if (pending.isEmpty || !await _askPermission()) return;
    setState(() {
      _bulkDone = 0;
      _bulkTotal = pending.length;
    });
    var added = 0;
    for (final entry in pending) {
      if (!mounted) return;
      if (await _write(entry)) {
        added++;
        if (mounted) setState(() => _saved.add(entry.sbcId));
      }
      if (mounted) setState(() => _bulkDone = (_bulkDone ?? 0) + 1);
    }
    if (!mounted) return;
    setState(() => _bulkDone = null);
    _refreshSyncScreens();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added == 1 ? '1 contact ajouté' : '$added contacts ajoutés',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vues WhatsApp')),
      body: RefreshIndicator(
        onRefresh: () => _reload(withMe: true),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Nom ou numéro',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            _OptInCard(
              me: _me,
              busy: _toggling,
              onChanged: (v) => _toggleOptIn(optIn: v),
            ),
            if (_types.isNotEmpty) ...[
              const _Label('Filtrer par abonnement'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _chip('Tous', null),
                    for (final t in _types) _chip(t, t),
                  ],
                ),
              ),
            ],
            ..._list(context),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: _subscription == value,
          onSelected: (_) => _onFilter(value),
        ),
      );

  List<Widget> _list(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const [Gap(12), SizedBox(height: 420, child: ListSkeleton())];
    if (_error != null) {
      return [
        EmptyState(
          icon: Icons.error_outline,
          title: 'Erreur',
          message: _error.toString(),
          action: FilledButton(
            onPressed: () => _reload(withMe: true),
            child: const Text('Réessayer'),
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        EmptyState(
          icon: Icons.visibility_outlined,
          title: _search.isNotEmpty || _subscription != null
              ? 'Aucun membre trouvé'
              : 'Personne pour le moment',
          message: _search.isNotEmpty || _subscription != null
              ? 'Essaie un autre filtre.'
              : 'Active « Je participe » pour être le premier de la liste.',
        ),
      ];
    }

    final remaining = _items.where((e) => !_isSaved(e)).length;
    final bulk = _bulkDone;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _total == 1 ? '1 membre' : '$_total membres',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (remaining > 0 && bulk == null)
              TextButton(
                onPressed: _saveAll,
                child: Text('Tout enregistrer ($remaining)'),
              ),
          ],
        ),
      ),
      if (bulk != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enregistrement… $bulk / $_bulkTotal', style: theme.textTheme.bodySmall),
              const Gap(6),
              LinearProgressIndicator(
                value: _bulkTotal == 0 ? null : bulk / _bulkTotal,
                color: SbcColors.whatsapp,
              ),
            ],
          ),
        ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 72),
              _Row(
                entry: _items[i],
                saved: _isSaved(_items[i]),
                saving: _saving.contains(_items[i].sbcId),
                onSave: bulk == null ? () => _saveOne(_items[i]) : null,
              ),
            ],
          ],
        ),
      ),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
  }
}

class _OptInCard extends StatelessWidget {
  const _OptInCard({required this.me, required this.busy, required this.onChanged});

  final StatusBoostMe? me;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = this.me;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SbcColors.whatsapp,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.visibility_rounded, color: Colors.white),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  'Je veux augmenter mon nombre de vues en statut WhatsApp',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const Gap(10),
          Text(
            'Enregistre les membres de la liste : ils voient tes statuts, tu vois '
            'les leurs. Chaque membre que tu enregistres est prévenu, et peut '
            "t'enregistrer en retour.",
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Je participe', style: theme.textTheme.titleSmall),
                    if (me != null)
                      Text(
                        me.participants == 1
                            ? '1 membre dans la liste'
                            : '${me.participants} membres dans la liste',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              Switch(
                value: me?.optIn ?? false,
                activeTrackColor: SbcColors.whatsapp,
                onChanged: me == null || busy || (!me.hasPhone && !me.optIn) ? null : onChanged,
              ),
            ],
          ),
          if (me != null && !me.hasPhone)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ajoute un numéro de téléphone à ton compte SBC pour participer.',
                style: theme.textTheme.bodySmall?.copyWith(color: SbcColors.warning),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.saved,
    required this.saving,
    required this.onSave,
  });

  final StatusBoostEntry entry;
  final bool saved;
  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          MemberAvatar(initials: entry.initials, avatarUrl: entry.avatarUrl, radius: 22),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const Gap(4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final t in entry.subscriptionTypes) _Tag(t),
                    if (entry.savedMe && !saved)
                      const _Tag("T'a déjà enregistré", color: SbcColors.whatsapp),
                  ],
                ),
              ],
            ),
          ),
          const Gap(8),
          if (saved)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: SbcColors.success),
                const Gap(4),
                Text(
                  'Enregistré',
                  style: theme.textTheme.labelLarge?.copyWith(color: SbcColors.success),
                ),
              ],
            )
          else
            FilledButton(
              onPressed: saving ? null : onSave,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enregistrer'),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? (label == 'CIBLE' ? SbcColors.accent : SbcColors.secondaryDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: tint, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

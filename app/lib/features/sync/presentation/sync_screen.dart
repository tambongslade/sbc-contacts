import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/theme/app_theme.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/shared/widgets/dark_pill_button.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';

/// Synchronisation home (cahier §10, §16, §17): the dashboard, the saved
/// criteria, and the way into "Mes contacts SBC" and the history.
///
/// The dashboard leads with a ring rather than a number grid. The one thing
/// this screen has to say to a member who has configured nothing is "you have
/// configured nothing" — a "0" among four other zeroes says it far too quietly,
/// and the four counters below are the detail you read *after* that.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(syncSummaryProvider);
    final criteria = ref.watch(criteriaControllerProvider);

    return Scaffold(
      // The FAB has to clear the floating nav bar the body runs under. The
      // Scaffold already floats it 16 off the bottom, so only the remainder is
      // added here.
      floatingActionButton: Padding(
        // Full nav inset, no shaving: the floating bar is painted after the
        // FAB, so 16 px of borrowed room came out of the FAB's corner.
        padding: EdgeInsets.only(bottom: AppTheme.navInsetOf(context)),
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/criteria/new'),
          shape: const StadiumBorder(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouveau critère'),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(syncSummaryProvider)
              ..invalidate(criteriaControllerProvider);
          },
          child: ListView(
            padding: EdgeInsets.only(bottom: AppTheme.navInsetOf(context)),
            children: [
              const ScreenHeader(title: 'Synchro', trailing: _LivePill()),
              summary.when(
                loading: SummarySkeleton.new,
                error: (e, _) => const SizedBox.shrink(),
                data: (s) => _Dashboard(summary: s),
              ),
              const Gap(4),
              const _Shortcut(
                icon: Icons.contact_page_rounded,
                label: 'Mes contacts SBC',
                route: '/sync/contacts',
                tint: SbcColors.primary,
              ),
              const Gap(8),
              // The counterpart: that screen says who you kept, this one says
              // who kept you (§21).
              const _Shortcut(
                icon: Icons.person_add_alt_1_rounded,
                label: "Qui m'a enregistré",
                route: '/sync/saved-me',
                tint: SbcColors.secondary,
              ),
              const Gap(8),
              // Moved out of the header: the header now carries the live state,
              // and the history is a destination like the two above it.
              const _Shortcut(
                icon: Icons.history_rounded,
                label: 'Historique',
                route: '/sync/history',
                tint: SbcColors.accent,
              ),
              const _SectionLabel('Mes critères'),
              criteria.when(
                loading: () => const CardListSkeleton(rows: 3),
                error: (e, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Erreur',
                  message: e.toString(),
                  action: FilledButton(
                    onPressed: () => ref.invalidate(criteriaControllerProvider),
                    child: const Text('Réessayer'),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.tune,
                      title: 'Aucun critère',
                      message:
                          'Définis les catégories de membres à enregistrer : pays, '
                          "région, profession, centres d'intérêt, âge.",
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
      ),
    );
  }
}

/// "Live" — the sync is always on, the screen just says so out loud.
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: SbcColors.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: SbcColors.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const Gap(7),
          Text(
            'Live',
            style: theme.textTheme.labelMedium?.copyWith(
              color: SbcColors.secondaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small all-caps eyebrow. Sections are separated by a label and whitespace
/// rather than a rule — nothing on this screen is boxed in.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Way into a sub-screen, as a card rather than a button: these are
/// destinations, and the rest of this screen is made of cards.
class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.route,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String route;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
                const Gap(12),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleSmall),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero ring plus the four counters.
class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.summary});
  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        _CriteriaRingCard(summary: summary),
        const Gap(10),
        // 2x2 rather than a row of four: "Correspondances" cannot be read at a
        // quarter of a phone's width.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Synchronisés',
                      value: summary.syncedCount,
                      icon: Icons.check_circle_rounded,
                      color: SbcColors.success,
                      route: '/sync/contacts',
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: _StatCard(
                      label: 'En attente',
                      value: summary.pendingCount,
                      icon: Icons.schedule_rounded,
                      color: SbcColors.accent,
                      route: '/sync/contacts',
                    ),
                  ),
                ],
              ),
              const Gap(10),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Correspondances',
                      value: summary.currentMatches,
                      icon: Icons.group_rounded,
                      color: SbcColors.primary,
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: _StatCard(
                      label: 'Critères',
                      value: summary.activeCriteria,
                      icon: Icons.tune_rounded,
                      color: SbcColors.secondaryDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (summary.failedCount > 0) ...[
          const Gap(8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 15, color: scheme.error),
                const Gap(6),
                Expanded(
                  child: Text(
                    '${summary.failedCount} échec(s) — voir Mes contacts SBC',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The hero: how many of your criteria are running, as a ring.
///
/// Reads "N / M CRITÈRES" — a ratio, not a total, because a criterion that has
/// been paused is still one you wrote and the member needs to see the gap. With
/// nothing configured the ring is empty and the card says what to do about it,
/// which is the only useful thing this screen can say at that point.
class _CriteriaRingCard extends StatelessWidget {
  const _CriteriaRingCard({required this.summary});
  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = summary.criteriaCount;
    final active = summary.activeCriteria;
    final configured = total > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(
              width: 172,
              height: 172,
              child: CustomPaint(
                painter: _RingPainter(
                  fraction: total == 0 ? 0 : active / total,
                  track: SbcColors.surfaceTint,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$active',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const Gap(4),
                      Text(
                        '/$total CRITÈRES',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  configured ? Icons.sync_rounded : Icons.auto_awesome_rounded,
                  size: 18,
                  color: SbcColors.secondary,
                ),
                const Gap(8),
                Flexible(
                  child: Text(
                    configured
                        ? '${summary.currentMatches} membre(s) à synchroniser'
                        : 'Configure pour débloquer la magie',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The ring itself: a full grey track with the configured share painted over it
/// in the brand blue→green sweep.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.track});

  final double fraction;
  final Color track;

  static const double _stroke = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - _stroke) / 2;
    final arc = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = track,
    );

    if (fraction <= 0) return;
    // From 12 o'clock, clockwise — the direction a progress ring is read.
    const start = -math.pi / 2;
    canvas.drawArc(
      arc,
      start,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        // Rotated rather than given a startAngle: a SweepGradient always
        // sweeps from 3 o'clock, so the rotation is what lines its first stop
        // up with the arc's own start.
        ..shader = const SweepGradient(
          colors: [SbcColors.primary, SbcColors.secondary],
          transform: GradientRotation(start),
        ).createShader(arc),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track;
}

/// One counter, as its own card.
///
/// The label sits on its own line under the number rather than beside the
/// icon: "Correspondances" is fifteen characters and needs the full width of
/// the tile, which a label squeezed in next to the glyph does not have.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.route,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  /// Optional: the screen that explains this number.
  final String? route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const Gap(8),
          Text(
            '$value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const Gap(6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: route == null
          ? content
          : InkWell(onTap: () => context.push(route!), child: content),
    );
  }
}

/// One saved criterion: what it selects, how many members it currently matches,
/// and the two things you can do with it.
///
/// The match count sits in a pill next to the label rather than at the end of
/// the description, because it is the number the member checks before deciding
/// whether to run the sync at all.
class _CriteriaTile extends ConsumerWidget {
  const _CriteriaTile({required this.criteria});
  final SyncCriteria criteria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bits = [
      ...criteria.countries,
      ...criteria.cities,
      ...criteria.professions,
      ...criteria.interests,
    ];
    final desc = bits.isEmpty ? 'Tous les membres' : bits.take(4).join(' · ');
    final more = bits.length > 4 ? ' +${bits.length - 4}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      criteria.label,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: SbcColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group_rounded,
                            size: 13, color: SbcColors.primary),
                        const Gap(5),
                        Text(
                          '${criteria.lastMatchCount}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: SbcColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(5),
              Text(
                '$desc$more',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Gap(10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/criteria/${criteria.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                  const Gap(6),
                  // Was hidden behind a long-press, which nobody would find.
                  FilledButton.icon(
                    onPressed: () => context.push(
                      '/sync/review/${criteria.id}?label=${Uri.encodeComponent(criteria.label)}',
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Synchroniser'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

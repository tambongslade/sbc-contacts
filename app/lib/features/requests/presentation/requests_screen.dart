import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/theme/app_theme.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';
import 'package:sbc_contacts/shared/widgets/dark_pill_button.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';

/// The "Demandes" tab: the member describes a need and follows their
/// requests; a pro also finds here the requests routed to them.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  bool _received = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _received
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: AppTheme.navInsetOf(context)),
              child: FloatingActionButton.extended(
                onPressed: () => context.push('/requests/new'),
                shape: const StadiumBorder(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nouvelle demande'),
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(myRequestsProvider)
              ..invalidate(proSpaceProvider)
              ..invalidate(inboxProvider);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, AppTheme.navInsetOf(context) + 72),
            children: [
              const ScreenHeader(title: 'Demandes'),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Mes demandes')),
                  ButtonSegment(value: true, label: Text('Reçues')),
                ],
                selected: {_received},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _received = s.first),
              ),
              const Gap(16),
              if (_received) const _ReceivedList() else const _MineList(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineList extends ConsumerWidget {
  const _MineList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myRequestsProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _NeedPromptCard(),
        const Gap(16),
        mine.when(
          loading: () => const CardListSkeleton(rows: 2),
          error: (e, _) => EmptyState(
            icon: Icons.error_outline,
            title: 'Erreur',
            message: e.toString(),
            action: FilledButton(onPressed: () => ref.invalidate(myRequestsProvider), child: const Text('Réessayer')),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Tes demandes apparaîtront ici. Les professionnels concernés te répondent, tu compares et tu choisis.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }
            final open = list.where((r) => r.status.isOpen).toList();
            final closed = list.where((r) => !r.status.isOpen).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (open.isNotEmpty) ...[
                  const RequestSectionLabel('En cours'),
                  const Gap(8),
                  for (final r in open) _RequestRow(request: r),
                ],
                if (closed.isNotEmpty) ...[
                  const Gap(8),
                  const RequestSectionLabel('Terminées'),
                  const Gap(8),
                  for (final r in closed) _RequestRow(request: r),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// "De quoi avez-vous besoin ?" — the way in, always at the top.
class _NeedPromptCard extends StatelessWidget {
  const _NeedPromptCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: () => context.push('/requests/new'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('De quoi avez-vous besoin ?',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const Gap(4),
                  Text('Décris ton besoin, on trouve les pros.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const Gap(10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, color: SbcColors.primary, size: 20),
                        const Gap(10),
                        Text('Ex. « réparer mes locks samedi »',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 4, decoration: const BoxDecoration(gradient: SbcColors.brandArc)),
          ],
        ),
      ),
    );
  }
}

class _RequestRow extends ConsumerWidget {
  const _RequestRow({required this.request});
  final ServiceRequestItem request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final answers = request.responses
        .where((r) => r.status == DispatchStatus.interested || r.status == DispatchStatus.question)
        .length;
    final tag = request.status == RequestStatus.responded && answers > 0
        ? ('$answers réponse${answers > 1 ? 's' : ''}', SbcColors.primary)
        : (request.status.label, toneForRequest(request.status));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: request.canDelete ? () => confirmDeleteRequest(context, ref, request) : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => request.status == RequestStatus.draft
              ? context.push('/requests/review', extra: request)
              : context.push('/requests/${request.id}'),
          child: RequestPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(request.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    const Gap(8),
                    StatusTag(tag.$1, tone: tag.$2),
                  ],
                ),
                if (request.subtitle.isNotEmpty) ...[
                  const Gap(6),
                  Text(request.subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                if (request.status == RequestStatus.sent) ...[
                  const Gap(6),
                  Row(
                    children: [
                      const Icon(Icons.check_rounded, size: 16, color: SbcColors.secondaryDark),
                      const Gap(4),
                      Text(
                        'Transmise à ${request.dispatchedCount} professionnel${request.dispatchedCount > 1 ? 's' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: SbcColors.secondaryDark),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Received (pro) ─────────────────────────────────────────────────────────

class _ReceivedList extends ConsumerWidget {
  const _ReceivedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(proSpaceProvider);
    return space.when(
      loading: () => const CardListSkeleton(rows: 2),
      error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Erreur', message: e.toString()),
      data: (s) {
        if (!s.isPro) return const _BecomeProCard();
        final inbox = ref.watch(inboxProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSetupBanner(missing: s.missingSetup),
            if (s.missingSetup.isNotEmpty) const Gap(10),
            _ReceivingBanner(active: s.receivingActive, until: s.profile?.receivingUntil),
            const Gap(12),
            inbox.when(
              loading: () => const CardListSkeleton(rows: 2),
              error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Erreur', message: e.toString()),
              data: (items) => items.isEmpty
                  ? EmptyState(
                      icon: Icons.inbox_outlined,
                      title: "Aucune demande pour l'instant",
                      message: s.services.isEmpty
                          ? 'Ajoute tes services pour recevoir les demandes qui te correspondent.'
                          : 'Les demandes qui correspondent à tes services arriveront ici.',
                    )
                  : Column(children: [for (final i in items) _InboxRow(item: i)]),
            ),
          ],
        );
      },
    );
  }
}

class _ReceivingBanner extends StatelessWidget {
  const _ReceivingBanner({required this.active, required this.until});
  final bool active;
  final DateTime? until;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = active ? SbcColors.secondaryDark : SbcColors.accentDark;
    final text = active
        ? 'Réception active${until != null ? ' · jusqu\'au ${DateFormat('d MMM', 'fr').format(until!)}' : ''}'
        : 'Réception en pause — abonnement Pro requis';
    return Material(
      color: (active ? SbcColors.secondary : SbcColors.accent).withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/pro'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(active ? Icons.verified_user_outlined : Icons.pause_circle_outline, color: fg, size: 18),
              const Gap(10),
              Expanded(
                child: Text(text, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: fg)),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _BecomeProCard extends StatelessWidget {
  const _BecomeProCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RequestPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.work_outline_rounded, color: SbcColors.primary),
          const Gap(10),
          Text('Tu proposes un service ?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const Gap(6),
          Text(
            'Crée ton profil professionnel et décris ce que tu sais faire. Les membres qui en ont besoin t\'envoient leurs demandes.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Gap(14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => context.push('/pro/assistant'), child: const Text('Devenir professionnel')),
          ),
        ],
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item});
  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = item.request;
    Widget fact(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 15), const Gap(4), Text(text, style: theme.textTheme.bodySmall)],
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/inbox/${r.id}', extra: item),
        child: RequestPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.status == DispatchStatus.sent) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: SbcColors.primary, shape: BoxShape.circle),
                    ),
                    const Gap(8),
                  ],
                  Text(item.status.label.toUpperCase(),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w800, color: toneForDispatch(item.status))),
                  Text(' · ${relativeTime(item.createdAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const Gap(8),
              Text(r.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Gap(8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (r.city != null) fact(Icons.place_outlined, r.city!),
                  if (r.mode != null) fact(Icons.home_work_outlined, r.mode!.label),
                  if (r.desiredDate != null) fact(Icons.calendar_today_outlined, r.desiredDate!),
                  if (r.budget != null) fact(Icons.payments_outlined, fcfa(r.budget!)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

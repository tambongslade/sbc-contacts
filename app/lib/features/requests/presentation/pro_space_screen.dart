import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Espace pro": reception, statistics, services and profile (Data §3, §4, §17, §18).
class ProSpaceScreen extends ConsumerWidget {
  const ProSpaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(proSpaceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Espace pro')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(proSpaceProvider)
            ..invalidate(proStatsProvider);
        },
        child: space.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [EmptyState(icon: Icons.error_outline, title: 'Erreur', message: e.toString())]),
          data: (s) {
            final profile = s.profile;
            if (profile == null) {
              return ListView(children: [
                EmptyState(
                  icon: Icons.work_outline,
                  title: 'Pas encore de profil pro',
                  action: FilledButton(
                    onPressed: () => context.push('/pro/assistant'),
                    child: const Text('Devenir professionnel'),
                  ),
                ),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ProSetupBanner(missing: s.missingSetup),
                if (s.missingSetup.isNotEmpty) const Gap(12),
                _SubscriptionCard(active: s.receivingActive, until: profile.receivingUntil),
                const Gap(16),
                const _StatsBlock(),
                const Gap(16),
                _ServicesBlock(services: s.services),
                const Gap(16),
                _ProfileBlock(profile: profile),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.active, required this.until});
  final bool active;
  final DateTime? until;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = active ? SbcColors.secondaryDark : SbcColors.accentDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (active ? SbcColors.secondary : SbcColors.accent).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(active ? Icons.verified_rounded : Icons.pause_circle_rounded, color: tone, size: 26),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Abonnement Pro · 2 000 FCFA/mois',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  active
                      ? (until != null
                          ? "Réception active jusqu'au ${DateFormat('d MMMM y', 'fr').format(until!)}"
                          : 'Réception des demandes active')
                      : 'Réception en pause. Contacte SBC pour activer ton abonnement.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Synchro dashboard's ring and tiles, reused for the pro's numbers.
class _StatsBlock extends ConsumerWidget {
  const _StatsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(proStatsProvider).value;
    if (stats == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final ratio = stats.received == 0 ? 0.0 : stats.responded / stats.received;
    Widget tile(String value, String label, IconData icon, Color tint) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, size: 16, color: tint),
                ),
                const Gap(6),
                Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
    final top = stats.topServices.isEmpty ? 1 : stats.topServices.map((t) => t.count).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RequestSectionLabel('Mes statistiques'),
        const Gap(8),
        RequestPanel(
          child: Row(
            children: [
              SizedBox(
                width: 104,
                height: 104,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: ratio,
                        strokeWidth: 12,
                        backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${stats.responded}',
                            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text('/${stats.received} REÇUES',
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Demandes répondues', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const Gap(4),
                    Text('Réponds vite : les clients choisissent souvent parmi les premières réponses.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Gap(10),
        Row(children: [
          tile('${(stats.responseRate * 100).round()} %', 'Taux de réponse', Icons.send_rounded, SbcColors.primary),
          const Gap(10),
          tile('${stats.selected}', 'Retenues', Icons.check_circle_rounded, SbcColors.success),
        ]),
        const Gap(10),
        Row(children: [
          tile('${(stats.conversionRate * 100).round()} %', 'Conversion', Icons.trending_up_rounded, SbcColors.accentDark),
          const Gap(10),
          tile('${stats.completed}', 'Terminées', Icons.flag_rounded, SbcColors.secondaryDark),
        ]),
        if (stats.topServices.isNotEmpty) ...[
          const Gap(10),
          RequestPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Services les plus demandés', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const Gap(10),
                for (final t in stats.topServices) ...[
                  Row(children: [
                    Expanded(child: Text(t.name, style: theme.textTheme.bodySmall)),
                    Text('${t.count}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                  const Gap(4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: t.count / top, minHeight: 8),
                  ),
                  const Gap(10),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ServicesBlock extends ConsumerWidget {
  const _ServicesBlock({required this.services});
  final List<ProServiceItem> services;

  String _summary(ProServiceItem s) => [
        if (s.category.isNotEmpty) s.category,
        if (s.priceMin != null) 'dès ${fcfa(s.priceMin!)}',
        if (s.modes.isNotEmpty) s.modes.map((m) => m.label).join(', '),
      ].join(' · ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: RequestSectionLabel('Mes services')),
            TextButton.icon(
              onPressed: () => context.push('/pro/services/add'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        if (services.isEmpty)
          RequestPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aucun service', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const Gap(6),
                Text("Décris ce que tu sais faire : l'IA le range en services que les clients trouvent.",
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Gap(10),
                FilledButton(onPressed: () => context.push('/pro/services/add'), child: const Text('Ajouter un service')),
              ],
            ),
          )
        else
          RequestPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < services.length; i++) ...[
                  ListTile(
                    onTap: () => context.push('/pro/services/edit', extra: services[i]),
                    title: Row(children: [
                      Flexible(
                        child: Text(services[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (!services[i].isActive) ...[
                        const Gap(6),
                        StatusTag('En pause', tone: Colors.grey.shade600),
                      ],
                    ]),
                    subtitle: Text(_summary(services[i])),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chevron_right),
                        IconButton(
                          tooltip: 'Supprimer ${services[i].name}',
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          onPressed: () async {
                            final space = await ref.read(requestsRepositoryProvider).deleteService(services[i].id);
                            ref.read(proSpaceProvider.notifier).set(space);
                          },
                        ),
                      ],
                    ),
                  ),
                  if (i < services.length - 1) const Divider(height: 1, indent: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({required this.profile});
  final ProProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: RequestSectionLabel('Mon profil pro')),
            TextButton(onPressed: () => context.push('/pro/profile'), child: const Text('Modifier')),
          ],
        ),
        RequestPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              FactRow('Métier', profile.profession),
              const Divider(height: 1),
              FactRow('Ville', [profile.city, ...profile.zones].join(', ')),
              const Divider(height: 1),
              FactRow('Prestation', profile.modes.isEmpty ? '—' : profile.modes.map((m) => m.label).join(', ')),
              const Divider(height: 1),
              FactRow('Disponibilité', profile.availability),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shopping_bag_outlined, color: SbcColors.primary),
                title: const Text('Ma boutique SBC Shop',
                    style: TextStyle(color: SbcColors.primary, fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.open_in_new, size: 18, color: SbcColors.primary),
                onTap: isRealLink(profile.shopUrl)
                    ? () => launchUrl(Uri.parse(profile.shopUrl), mode: LaunchMode.externalApplication)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

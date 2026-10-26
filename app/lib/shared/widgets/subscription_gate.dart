import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';

/// The paywall, on every screen an SBC account unlocks. It is worth a brand
/// treatment:
/// it has to explain what is behind the lock, not just refuse.
class SubscriptionGate extends StatelessWidget {
  const SubscriptionGate({super.key, this.onRetry, this.networkAccount = false});

  final VoidCallback? onRetry;

  /// An SBC Network account: it needs an SBC account, not a subscription,
  /// and has nothing to retry.
  final bool networkAccount;

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
                    networkAccount ? 'Réservé aux membres SBC' : 'Réservé aux abonnés SBC',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    networkAccount
                        ? 'Active ton compte SBC et profite de toutes les fonctionnalités '
                            'réservées aux membres SBC pour développer ta visibilité sur WhatsApp.'
                        : 'L’annuaire des membres est réservé aux abonnés SBC. '
                            'Si ton abonnement vient d’être activé, actualise cette page.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const Gap(18),
                  if (networkAccount) ...const [
                    _GateBenefit(
                      icon: Icons.visibility_outlined,
                      label: 'Augmente tes vues WhatsApp : plus de visibilité pour '
                          'tes statuts, rapidement',
                    ),
                    Gap(10),
                    _GateBenefit(
                      icon: Icons.groups_2_outlined,
                      label: 'Tout l’annuaire des membres SBC : des milliers de '
                          'contacts qualifiés',
                    ),
                    Gap(10),
                    _GateBenefit(
                      icon: Icons.tune_rounded,
                      label: 'Filtres avancés : par métier, région, âge, centres '
                          'd’intérêt…',
                    ),
                    Gap(10),
                    _GateBenefit(
                      icon: Icons.chat_bubble_outline,
                      label: 'Contact WhatsApp direct : discute et ajoute '
                          'facilement au répertoire',
                    ),
                  ] else ...const [
                    _GateBenefit(
                      icon: Icons.groups_2_outlined,
                      label: 'Tout le répertoire des membres SBC',
                    ),
                    Gap(10),
                    _GateBenefit(
                      icon: Icons.tune_rounded,
                      label: 'Filtres par métier, région, âge et centres '
                          'd’intérêt',
                    ),
                    Gap(10),
                    _GateBenefit(
                      icon: Icons.chat_bubble_outline,
                      label: 'Contact WhatsApp direct et ajout au répertoire',
                    ),
                  ],
                  if (onRetry != null) ...[
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
                  ],
                  if (!networkAccount)
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:sbc_contacts/features/auth/domain/app_user.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// "Mon profil" — identity, subscription status and the sign-out affordance.
///
/// The subscription is the gate to the whole directory, so it is presented as a
/// status badge (and, when missing, as an explicit upsell block) rather than as
/// a quiet list row.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: user == null
          ? const _AccountSkeleton()
          : RefreshIndicator(
              onRefresh: () => ref.read(authControllerProvider.notifier).refreshProfile(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _ProfileHeader(user: user)
                      .animate()
                      .fadeIn(duration: 260.ms)
                      .slideY(begin: 0.04, end: 0, curve: Curves.easeOut),
                  const Gap(20),
                  _SubscriptionBlock(user: user)
                      .animate(delay: 60.ms)
                      .fadeIn(duration: 260.ms)
                      .slideY(begin: 0.04, end: 0, curve: Curves.easeOut),
                  const Gap(20),
                  _InfoBlock(user: user)
                      .animate(delay: 120.ms)
                      .fadeIn(duration: 260.ms)
                      .slideY(begin: 0.04, end: 0, curve: Curves.easeOut),
                  const Gap(28),
                  const _LogoutButton(),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  static const double _bandHeight = 88;
  static const double _avatarRadius = 42;
  static const double _ringWidth = 4;
  static const double _ringGap = 3;

  double get _ringDiameter => (_avatarRadius + _ringWidth + _ringGap) * 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SurfaceCard(
      padding: EdgeInsets.zero,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Column(
            children: [
              // Signature brand arc: blue → green → orange.
              Container(
                height: _bandHeight,
                decoration: const BoxDecoration(gradient: SbcColors.brandArc),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, _ringDiameter / 2 + 12, 20, 20),
                child: Column(
                  children: [
                    Text(
                      user.displayName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (user.email != null && user.email!.isNotEmpty) ...[
                      const Gap(4),
                      Text(
                        user.email!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Gap(14),
                    _SubscriptionBadges(user: user),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: _bandHeight - _ringDiameter / 2,
            child: _GradientAvatarRing(
              initials: _initialsOf(user.displayName),
              avatarUrl: user.avatarUrl,
              radius: _avatarRadius,
              ringWidth: _ringWidth,
              ringGap: _ringGap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar wrapped in a brand-arc ring, separated from the artwork by a thin
/// surface-coloured gap so the gradient reads as a ring and not as a halo.
class _GradientAvatarRing extends StatelessWidget {
  const _GradientAvatarRing({
    required this.initials,
    required this.radius,
    required this.ringWidth,
    required this.ringGap,
    this.avatarUrl,
  });

  final String initials;
  final String? avatarUrl;
  final double radius;
  final double ringWidth;
  final double ringGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(ringWidth),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SbcColors.brandArc,
      ),
      child: Container(
        padding: EdgeInsets.all(ringGap),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
        ),
        child: MemberAvatar(
          initials: initials,
          avatarUrl: avatarUrl,
          radius: radius,
        ),
      ),
    );
  }
}

/// The tier pills (CIBLE / CLASSIQUE / …), or a muted "no subscription" pill.
class _SubscriptionBadges extends StatelessWidget {
  const _SubscriptionBadges({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    if (!user.hasActiveSubscription) {
      return const _StatusPill(
        label: 'Sans abonnement',
        icon: Icons.lock_outline,
        tone: SbcColors.error,
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in user.subscriptionTypes)
          _StatusPill(
            label: _tierLabel(type),
            icon: _tierIcon(type),
            tone: _tierTone(type),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon, required this.tone});

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: tone),
            const Gap(6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subscription block
// ---------------------------------------------------------------------------

class _SubscriptionBlock extends ConsumerWidget {
  const _SubscriptionBlock({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = user.hasActiveSubscription;
    final tone = active ? _tierTone(user.subscriptionTypes.first) : SbcColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Abonnement'),
        const Gap(8),
        _SurfaceCard(
          background: tone.withValues(alpha: 0.06),
          border: tone.withValues(alpha: 0.22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconTile(
                    icon: active ? Icons.verified_rounded : Icons.lock_outline,
                    tone: tone,
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active ? 'Abonnement actif' : 'Aucun abonnement actif',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Gap(4),
                        Text(
                          active
                              ? "Ton offre ${user.subscriptionTypes.join(' · ')} te donne "
                                  "accès à l'annuaire des membres SBC."
                              : "L'annuaire des membres est réservé aux abonnés SBC. "
                                  'Active ton abonnement sur SBC, puis actualise ton profil.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!active) ...[
                const Gap(16),
                FilledButton.icon(
                  onPressed: () => unawaited(
                    ref.read(authControllerProvider.notifier).refreshProfile(),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('Actualiser mon statut'),
                  // Brand blue (not the card's orange tint) so the label keeps
                  // an accessible contrast ratio on the filled surface.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Information block
// ---------------------------------------------------------------------------

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (user.country != null && user.country!.isNotEmpty)
        _InfoRow(icon: Icons.public, label: 'Pays', value: user.country!),
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty)
        _InfoRow(
          icon: Icons.phone_outlined,
          label: 'Téléphone',
          value: user.phoneNumber!,
        ),
      if (user.email != null && user.email!.isNotEmpty)
        _InfoRow(
          icon: Icons.alternate_email,
          label: 'Adresse e-mail',
          value: user.email!,
        ),
      if (user.role.isNotEmpty && user.role != 'USER')
        _InfoRow(icon: Icons.shield_outlined, label: 'Rôle', value: user.role),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Informations'),
        const Gap(8),
        _SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 68, endIndent: 16),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _IconTile(icon: icon, tone: theme.colorScheme.primary),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Gap(2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sign out
// ---------------------------------------------------------------------------

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(authControllerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Tu devras te reconnecter avec ton compte SBC pour retrouver '
          "l'annuaire.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await notifier.logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return TextButton.icon(
      onPressed: () => unawaited(_confirm(context, ref)),
      icon: const Icon(Icons.logout_rounded, size: 20),
      label: const Text('Se déconnecter'),
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: theme.colorScheme.error,
        backgroundColor: theme.colorScheme.error.withValues(alpha: 0.06),
        textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

/// White, softly-shadowed panel — the surface rhythm used across the screen.
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: border ?? theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: SbcColors.primary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// 40×40 tinted square holding a section icon — keeps the iconography aligned
/// on one vertical rhythm across every row.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: tone),
    );
  }
}

/// Loading shape of the screen — the layout the member is about to get.
class _AccountSkeleton extends StatelessWidget {
  const _AccountSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SurfaceCard(
            child: Column(
              children: [
                const CircleAvatar(radius: 42),
                const Gap(12),
                Text('Nom du membre', style: Theme.of(context).textTheme.titleLarge),
                const Gap(6),
                const Text('membre@example.com'),
                const Gap(12),
                const _StatusPill(
                  label: 'ABONNEMENT',
                  icon: Icons.verified_rounded,
                  tone: SbcColors.secondary,
                ),
              ],
            ),
          ),
          const Gap(20),
          const _SurfaceCard(
            child: Row(
              children: [
                _IconTile(icon: Icons.verified_rounded, tone: SbcColors.secondary),
                Gap(12),
                Expanded(child: Text('Abonnement actif\nDétail de ton offre SBC.')),
              ],
            ),
          ),
          const Gap(20),
          const _SurfaceCard(
            child: Row(
              children: [
                _IconTile(icon: Icons.public, tone: SbcColors.primary),
                Gap(12),
                Expanded(child: Text('Pays\nCM')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tier presentation helpers
// ---------------------------------------------------------------------------

/// CIBLE is the premium tier (orange), CLASSIQUE the standard one (green);
/// anything the backend adds later falls back to brand blue.
Color _tierTone(String type) {
  switch (type.toUpperCase()) {
    case 'CIBLE':
      return SbcColors.accent;
    case 'CLASSIQUE':
      return SbcColors.secondary;
    default:
      return SbcColors.primary;
  }
}

IconData _tierIcon(String type) {
  switch (type.toUpperCase()) {
    case 'CIBLE':
      return Icons.workspace_premium_rounded;
    case 'CLASSIQUE':
      return Icons.verified_rounded;
    default:
      return Icons.card_membership_rounded;
  }
}

String _tierLabel(String type) => type.trim().toUpperCase();

String _initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

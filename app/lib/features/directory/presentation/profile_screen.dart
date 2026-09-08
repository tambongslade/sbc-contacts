import 'package:flutter/material.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
import 'package:sbc_contacts/features/reviews/presentation/reviews_section.dart';
import 'package:sbc_contacts/shared/services/whatsapp.dart';
import 'package:sbc_contacts/shared/widgets/confidence_score_badge.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/member_card.dart';

final memberProfileProvider = FutureProvider.family<Member, String>(
  (ref, sbcId) => ref.watch(directoryRepositoryProvider).profile(sbcId),
);

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({required this.sbcId, super.key});
  final String sbcId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memberProfileProvider(sbcId));
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: async.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => EmptyState(
          icon: Icons.person_off,
          title: 'Profil indisponible',
          message: e.toString(),
        ),
        data: (m) => _ProfileBody(member: m),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: MemberAvatar(
            initials: member.initials,
            avatarUrl: member.avatarUrl,
            radius: 48,
          ),
        ),
        const Gap(16),
        Center(
          child: Text(
            member.displayName,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (member.profession != null)
          Center(child: Text(member.profession!, style: theme.textTheme.titleMedium)),
        if (member.location.isNotEmpty)
          Center(
            child: Text(
              member.location,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const Gap(20),
        ConfidenceScoreCard(
          score: member.confidenceScore,
          reviewCount: member.reviewCount,
          averageStars: member.averageRating,
        ),
        const Gap(24),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: member.phoneNumber == null
                    ? null
                    : () => openWhatsApp(member.phoneNumber!),
                icon: const Icon(SimpleIcons.whatsapp, size: 20),
                label: const Text('WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: SbcColors.whatsapp,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => addMemberToPhone(context, ref, member),
                icon: const Icon(Icons.person_add),
                label: const Text('Ajouter'),
              ),
            ),
          ],
        ),
        const Gap(24),
        ReviewsSection(
          member: member,
          isOwnProfile: ref.watch(authControllerProvider).value?.sbcUserId == member.sbcId,
        ),
        const Gap(24),
        if (member.skills.isNotEmpty) ...[
          Text('Compétences', style: theme.textTheme.titleMedium),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final s in member.skills) Chip(label: Text(s))],
          ),
          const Gap(16),
        ],
        if (member.interests.isNotEmpty) ...[
          Text("Centres d'intérêt", style: theme.textTheme.titleMedium),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final s in member.interests) Chip(label: Text(s))],
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/directory/application/search_controller.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
import 'package:sbc_contacts/features/favorites/application/favorites_controller.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/whatsapp_button.dart';

class MemberCard extends ConsumerWidget {
  const MemberCard({required this.member, this.onTap, super.key});

  final Member member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle = [member.profession, member.location]
        .where((e) => e != null && e.isNotEmpty)
        .join(' • ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              MemberAvatar(initials: member.initials, avatarUrl: member.avatarUrl),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.displayName,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (member.isSynced) ...[
                          const Gap(6),
                          Icon(Icons.check_circle, size: 15, color: theme.colorScheme.secondary),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _FavoriteButton(member: member),
              WhatsAppButton(phoneNumber: member.phoneNumber),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: member.isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
      icon: Icon(
        member.isFavorite ? Icons.star : Icons.star_border,
        color: member.isFavorite ? Theme.of(context).colorScheme.tertiary : null,
      ),
      onPressed: () async {
        final favorites = ref.read(favoritesControllerProvider.notifier);
        final search = ref.read(searchControllerProvider.notifier);
        final next = !member.isFavorite;
        search.setFavoriteLocal(member.sbcId, isFavorite: next);
        try {
          if (next) {
            await favorites.add(member.sbcId);
          } else {
            await favorites.remove(member.sbcId);
          }
        } catch (_) {
          search.setFavoriteLocal(member.sbcId, isFavorite: !next); // revert
        }
      },
    );
  }
}

/// Adds a member to the phone contacts via the native service (cahier §9).
Future<void> addMemberToPhone(BuildContext context, WidgetRef ref, Member member) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(contactServiceProvider);
  if (!await service.requestPermission()) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Permission contacts refusée')),
    );
    return;
  }
  if (member.phoneNumber != null && await service.existsByPhone(member.phoneNumber!)) {
    messenger.showSnackBar(const SnackBar(content: Text('Ce contact existe déjà')));
    return;
  }
  final result = await service.addSbcContact(
    firstName: member.firstName ?? member.displayName,
    lastName: member.name,
    phone: member.phoneNumber,
    profession: member.profession,
    city: member.city,
    country: member.country,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(result.success ? 'Contact ajouté au téléphone' : 'Échec: ${result.error}'),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/directory/application/search_controller.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
import 'package:sbc_contacts/features/favorites/application/favorites_controller.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/whatsapp_button.dart';

/// One member in a directory list (recherche, favoris).
///
/// Hierarchy is deliberate: the **name** is the only strong type in the row,
/// the metadata line is muted, and of the two actions only WhatsApp is
/// saturated — it is the one thing the member came here to do. The row itself
/// is the primary target (it opens the profile), so it gets a press response
/// while the two icon buttons stay visually secondary but keep full-size
/// touch targets.
class MemberCard extends ConsumerWidget {
  const MemberCard({required this.member, this.onTap, super.key});

  final Member member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PressableRow(
      onTap: onTap,
      semanticLabel: member.displayName,
      child: Row(
        children: [
          _MemberAvatarBlock(member: member),
          const Gap(12),
          Expanded(child: _MemberIdentity(member: member)),
          const Gap(2),
          _FavoriteButton(member: member),
          WhatsAppButton(phoneNumber: member.phoneNumber, size: 46),
        ],
      ),
    );
  }
}

/// Card shell: flat surface + hairline border instead of an elevated card.
///
/// A long scrolling list of drop shadows reads as noise (and costs a shadow
/// per row on mid-range Android); a hairline keeps the rhythm calm and lets
/// the avatar and the WhatsApp disc be the only saturated things on screen.
class _PressableRow extends StatefulWidget {
  const _PressableRow({
    required this.child,
    required this.semanticLabel,
    this.onTap,
  });

  final Widget child;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  State<_PressableRow> createState() => _PressableRowState();
}

class _PressableRowState extends State<_PressableRow> {
  bool _pressed = false;

  void _setPressed({required bool value}) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedScale(
        // Just enough to acknowledge the touch; anything bigger reads as a bug.
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Material(
          color: theme.colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Semantics(
            button: widget.onTap != null,
            label: widget.semanticLabel,
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: (_) => _setPressed(value: true),
              onTapUp: (_) => _setPressed(value: false),
              onTapCancel: () => _setPressed(value: false),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar, with the "already in your phone contacts" state as a badge on the
/// avatar rather than an icon competing with the name.
class _MemberAvatarBlock extends StatelessWidget {
  const _MemberAvatarBlock({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = MemberAvatar(
      initials: member.initials,
      avatarUrl: member.avatarUrl,
      radius: 23,
    );
    if (!member.isSynced) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Tooltip(
            message: 'Déjà dans tes contacts',
            child: Semantics(
              label: 'Déjà dans tes contacts',
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  size: 15,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Name + metadata. Many members have neither profession nor région, so the
/// metadata line simply disappears and the name centres itself — no "non
/// renseigné" filler, which would only add noise to half the list.
class _MemberIdentity extends StatelessWidget {
  const _MemberIdentity({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProfession = member.profession != null && member.profession!.isNotEmpty;
    final meta = [member.profession, member.location]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          member.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (meta.isNotEmpty) ...[
          const Gap(3),
          Row(
            children: [
              Icon(
                hasProfession ? Icons.work_outline : Icons.place_outlined,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const Gap(5),
              Expanded(
                child: Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFavorite = member.isFavorite;
    // State is carried by the glyph (filled vs outline) as well as the colour,
    // so it survives a colour-blind or greyscale reading.
    final icon = Icon(
      isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
      color: isFavorite
          ? theme.colorScheme.tertiary
          : theme.colorScheme.onSurfaceVariant,
    );

    return IconButton(
      tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
      icon: icon
          .animate(key: ValueKey(isFavorite))
          .scale(
            begin: const Offset(0.7, 0.7),
            end: const Offset(1, 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
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

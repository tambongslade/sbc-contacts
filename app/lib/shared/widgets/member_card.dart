import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/directory/application/search_controller.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
import 'package:sbc_contacts/features/favorites/application/favorites_controller.dart';
import 'package:sbc_contacts/shared/widgets/confidence_score_badge.dart';
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MemberAvatarBlock(member: member),
          const Gap(13),
          Expanded(child: _MemberIdentity(member: member)),
          const Gap(8),
          // The two actions stack rather than sit side by side: WhatsApp is the
          // one thing the member came here to do, so it takes the top slot at
          // full saturation and the favourite toggle tucks under it, quieter.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WhatsAppButton(phoneNumber: member.phoneNumber, size: 46),
              const Gap(2),
              _FavoriteButton(member: member),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card shell: a soft, near-pill surface floating on the tinted ground.
///
/// One low-blur shadow per row rather than a hairline border — the border read
/// as a table rule and flattened the list. The radius is deliberately large so
/// the row reads as a discrete object, and the padding is generous: this list
/// is scanned, not read, and whitespace is what makes it scannable.
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
  /// Near-pill: large enough that the row reads as an object, not a table cell.
  static const double _radius = 26;

  bool _pressed = false;

  void _setPressed({required bool value}) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: AnimatedScale(
        // Just enough to acknowledge the touch; anything bigger reads as a bug.
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
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
                  padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                  child: widget.child,
                ),
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
      radius: 27,
      rounded: true,
    );
    if (!member.isSynced) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Tooltip(
            message: 'Déjà dans tes contacts',
            child: Semantics(
              label: 'Déjà dans tes contacts',
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  size: 14,
                  color: SbcColors.success,
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
/// metadata row simply disappears and the name centres itself — no "non
/// renseigné" filler, which would only add noise to half the list.
///
/// The metadata reads as small pills rather than a run-on line: each fact is a
/// separate object, which is what makes the row scannable at a glance instead
/// of something you have to parse.
class _MemberIdentity extends StatelessWidget {
  const _MemberIdentity({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profession = member.profession;
    final location = member.location;

    final pills = <Widget>[
      if (location.isNotEmpty)
        _MetaPill(icon: Icons.place_rounded, label: location),
      if (profession != null && profession.isNotEmpty)
        _MetaPill(label: profession),
      // Only surface the score once it means something (i.e. it's been rated);
      // an unrated "50" on every row would just be noise.
      if (member.reviewCount > 0) ConfidenceScorePill(score: member.confidenceScore),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          member.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (pills.isNotEmpty) ...[
          const Gap(7),
          // Clipped to one line: a member with a long profession and a long
          // city must not be allowed to grow the row to twice its height.
          SizedBox(
            height: 24,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final pill in pills) ...[pill, const Gap(6)],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One fact about a member, as a soft grey pill.
class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 4, 10, 4),
      decoration: BoxDecoration(
        color: SbcColors.surfaceTint.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const Gap(3),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                color: fg,
              ),
            ),
          ),
        ],
      ),
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

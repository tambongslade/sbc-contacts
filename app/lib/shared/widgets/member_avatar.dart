import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';

/// Avatar with network image + initials fallback (cached, fade-in).
///
/// The fallback is a saturated tile rather than a grey placeholder: most members
/// have no photo, so this is the common case, not the exception. The colour is
/// derived from the initials, which means the same member keeps the same colour
/// on every screen and a scanned list gains a second, non-textual cue.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required this.initials,
    this.avatarUrl,
    this.radius = 24,
    this.rounded = false,
    super.key,
  });

  final String initials;
  final String? avatarUrl;
  final double radius;

  /// Draw as a rounded square instead of a circle. Used in the directory
  /// lists, where the squared tile lines up with the card's own corners.
  final bool rounded;

  /// Deliberately short and well separated in hue; all of them carry white
  /// text at the weight used below.
  static const _palette = <Color>[
    SbcColors.primary,
    SbcColors.secondaryDark,
    SbcColors.accentDark,
    Color(0xFF5B5BD6), // indigo
    Color(0xFF0E9384), // teal
    Color(0xFFD1495B), // coral
    Color(0xFF7A5AF8), // violet
    Color(0xFFEA7317), // amber
  ];

  static Color colorFor(String seed) {
    if (seed.isEmpty) return _palette.first;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  double get _cornerRadius => rounded ? radius * 0.62 : radius;

  @override
  Widget build(BuildContext context) {
    final bg = colorFor(initials);
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_cornerRadius),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.72,
          letterSpacing: -0.5,
        ),
      ),
    );
    if (avatarUrl == null || avatarUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_cornerRadius),
      child: CachedNetworkImage(
        imageUrl: avatarUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';

/// Avatar with network image + initials fallback (cached, fade-in).
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({required this.initials, this.avatarUrl, this.radius = 24, super.key});

  final String initials;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: SbcColors.primary.withValues(alpha: 0.12),
      child: Text(
        initials,
        style: TextStyle(
          color: SbcColors.primaryDark,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.7,
        ),
      ),
    );
    if (avatarUrl == null || avatarUrl!.isEmpty) return fallback;
    return ClipOval(
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

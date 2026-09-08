import 'package:flutter/material.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';

/// Colour tier for a 0-100 confidence score.
Color confidenceColor(int score) {
  if (score >= 80) return SbcColors.success;
  if (score >= 60) return SbcColors.secondary;
  if (score >= 40) return SbcColors.warning;
  return SbcColors.error;
}

/// Compact score chip ("72") for list rows — trust at a glance while scanning.
class ConfidenceScorePill extends StatelessWidget {
  const ConfidenceScorePill({required this.score, super.key});

  final int score;

  @override
  Widget build(BuildContext context) {
    final c = confidenceColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_rounded, size: 13, color: c),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Full score card for the profile: big number out of 100, tier label and the
/// review count. Colour-coded by tier.
class ConfidenceScoreCard extends StatelessWidget {
  const ConfidenceScoreCard({
    required this.score,
    required this.reviewCount,
    this.averageStars,
    super.key,
  });

  final int score;
  final int reviewCount;
  final double? averageStars;

  String get _label {
    if (score >= 80) return 'Très fiable';
    if (score >= 60) return 'Fiable';
    if (score >= 40) return 'Neutre';
    if (score >= 20) return 'Prudence';
    return 'Peu fiable';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = confidenceColor(score);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_rounded, size: 32, color: c),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$score',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: c, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    ' / 100',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              Text(
                'Score de confiance · $_label',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const Spacer(),
          Text(
            reviewCount == 0
                ? 'Aucun avis'
                : '$reviewCount avis',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

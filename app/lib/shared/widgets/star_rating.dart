import 'package:flutter/material.dart';

/// Read-only row of 1-5 stars (supports halves), for displaying an average.
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({
    required this.value,
    this.size = 18,
    this.color,
    super.key,
  });

  /// Rating in stars, 0-5 (may be fractional, e.g. 4.2).
  final double value;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFF59E0B); // amber
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i
                ? Icons.star_rounded
                : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_border_rounded),
            size: size,
            color: c,
          ),
      ],
    );
  }
}

/// Tappable 1-5 star input.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    required this.value,
    required this.onChanged,
    this.size = 40,
    super.key,
  });

  /// Currently selected rating, 0 = none.
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: () => onChanged(i),
            iconSize: size,
            visualDensity: VisualDensity.compact,
            tooltip: '$i',
            icon: Icon(
              value >= i ? Icons.star_rounded : Icons.star_border_rounded,
              color: value >= i ? amber : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

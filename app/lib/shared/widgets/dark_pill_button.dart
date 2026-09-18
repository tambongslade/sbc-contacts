import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';

/// The screen-level action, as the one dark object on an otherwise pale page.
///
/// Used once per screen, for the action that changes what the screen shows
/// (filters, history). Being the only saturated dark element is what makes it
/// findable without a bar to sit in; a second one on the same screen would
/// spend that contrast for nothing.
class DarkPillButton extends StatelessWidget {
  const DarkPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badgeCount = 0,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Drawn as an accent badge on the corner. The number is shown, not just a
  /// dot, so "active" is never signalled by colour alone.
  final int badgeCount;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badged = badgeCount > 0;
    // In dark mode the "dark pill" would vanish into the ground, so it inverts
    // to the lightest container instead of staying near-black.
    final fill = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFF10182B);
    final onFill = theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface
        : Colors.white;

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: fill,
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 18, 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 19, color: onFill),
                    const Gap(8),
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: onFill,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (badged)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SbcColors.accent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: theme.colorScheme.surface, width: 2),
                ),
                child: Text(
                  '$badgeCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Screen title (+ optional trailing action), drawn on the page rather than in
/// an app bar — the header is part of the content, not chrome above it.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.trailing,
    this.dot = false,
    super.key,
  });

  final String title;
  final Widget? trailing;

  /// A small live-state dot after the title.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                if (dot) ...[
                  const Gap(8),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: SbcColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const Gap(10), trailing!],
        ],
      ),
    );
  }
}

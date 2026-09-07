import 'package:flutter/material.dart';

/// The SBC brand lockup, rendered from `assets/brand/`.
///
/// The artwork is black ink on a transparent ground, which disappears on the
/// dark theme — so a light-ink variant is swapped in automatically. Use
/// [SbcLogo.mark] where only the people-in-circle glyph fits.
class SbcLogo extends StatelessWidget {
  const SbcLogo({this.height = 72, super.key}) : _markOnly = false;

  /// Just the people-in-circle glyph, square.
  const SbcLogo.mark({this.height = 72, super.key}) : _markOnly = true;

  final double height;
  final bool _markOnly;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = _markOnly
        ? (dark ? 'mark_dark' : 'mark')
        : (dark ? 'logo_dark' : 'logo');
    return Image.asset(
      'assets/brand/$name.png',
      height: height,
      fit: BoxFit.contain,
      // The lockup carries the product name; screen readers get it once here.
      semanticLabel: 'SBC',
      filterQuality: FilterQuality.medium,
    );
  }
}

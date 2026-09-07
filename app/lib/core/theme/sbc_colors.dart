import 'package:flutter/material.dart';

/// SBC (Sniper Business Center) brand palette, taken from the production
/// `sbcprecom` and `sbc-live` web projects. Seed for the M3 theme.
class SbcColors {
  const SbcColors._();

  // Primary — blue
  static const Color primary = Color(0xFF1862F0);
  static const Color primaryLight = Color(0xFF4285F4);
  static const Color primaryDark = Color(0xFF0F4FB3);

  // Secondary — green
  static const Color secondary = Color(0xFF92B127);
  static const Color secondaryLight = Color(0xFFA5C142);
  static const Color secondaryDark = Color(0xFF7A951F);

  // Accent — orange
  static const Color accent = Color(0xFFF49101);
  static const Color accentLight = Color(0xFFFFA726);
  static const Color accentDark = Color(0xFFE57C00);

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color live = Color(0xFFE5484D);

  /// WhatsApp brand green — used only for the "contacter sur WhatsApp"
  /// affordance, so the action is recognisable at a glance (cahier §8).
  static const Color whatsapp = Color(0xFF25D366);

  // Surfaces
  static const Color bgLight = Color(0xFFF4F7FD);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceTint = Color(0xFFEDF2FB);
  static const Color bgDark = Color(0xFF0B1120);
  static const Color surfaceDark = Color(0xFF121A2E);

  /// Signature 3-stop brand arc: blue → green → orange.
  static const LinearGradient brandArc = LinearGradient(
    colors: [primary, secondary, accent],
    stops: [0, 0.55, 1],
  );
}

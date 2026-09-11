import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';

/// Builds the SBC-branded Material 3 themes via FlexColorScheme, seeded from the
/// brand palette and typed with Montserrat (SBC's product font).
class AppTheme {
  const AppTheme._();

  /// Height of the floating navigation bar's own box (its bottom margin plus
  /// its content), *excluding* the device's bottom inset.
  static const double floatingNavBarHeight = 92;

  /// Room a scroll view — or a floating action button — must leave at the
  /// bottom of a screen inside the home shell so its content clears the
  /// floating nav bar.
  ///
  /// Read from the context rather than baked in as a constant: the gesture
  /// inset differs per device, and if this is short the bar sits on top of what
  /// it was supposed to clear and silently takes its taps.
  static double navInsetOf(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + floatingNavBarHeight;

  static const FlexSchemeColor _light = FlexSchemeColor(
    primary: SbcColors.primary,
    primaryContainer: SbcColors.primaryLight,
    secondary: SbcColors.secondary,
    secondaryContainer: SbcColors.secondaryLight,
    tertiary: SbcColors.accent,
    tertiaryContainer: SbcColors.accentLight,
    error: SbcColors.error,
  );

  static const FlexSchemeColor _dark = FlexSchemeColor(
    primary: SbcColors.primaryLight,
    primaryContainer: SbcColors.primaryDark,
    secondary: SbcColors.secondaryLight,
    secondaryContainer: SbcColors.secondaryDark,
    tertiary: SbcColors.accentLight,
    tertiaryContainer: SbcColors.accentDark,
    error: SbcColors.error,
  );

  static ThemeData light() {
    final base = FlexThemeData.light(
      colors: _light,
      scaffoldBackground: SbcColors.bgLight,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 8,
      // No bar chrome: the header is part of the page, drawn on the same white
      // as the content below it, so the eye reads one continuous surface.
      appBarStyle: FlexAppBarStyle.surface,
      appBarElevation: 0,
      transparentStatusBar: true,
      subThemesData: _subThemes,
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
    );
    return base.copyWith(textTheme: _textTheme(base.textTheme));
  }

  static ThemeData dark() {
    final base = FlexThemeData.dark(
      colors: _dark,
      scaffoldBackground: SbcColors.bgDark,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 12,
      appBarStyle: FlexAppBarStyle.surface,
      appBarElevation: 0,
      transparentStatusBar: true,
      subThemesData: _subThemes,
      useMaterial3: true,
    );
    return base.copyWith(textTheme: _textTheme(base.textTheme));
  }

  /// One idea drives the geometry: every element is a rounded object floating
  /// on the ground, never a boxed-in region. Anything wider than it is tall
  /// (inputs, chips, buttons) is therefore effectively a pill, and the radius
  /// on containers is large enough to read as a discrete card.
  static const FlexSubThemesData _subThemes = FlexSubThemesData(
    defaultRadius: 18,
    cardRadius: 24,
    inputDecoratorRadius: 30,
    inputDecoratorBorderType: FlexInputBorderType.outline,
    inputDecoratorUnfocusedHasBorder: false,
    filledButtonRadius: 28,
    elevatedButtonRadius: 28,
    outlinedButtonRadius: 28,
    textButtonRadius: 28,
    chipRadius: 22,
    dialogRadius: 28,
    bottomSheetRadius: 28,
    popupMenuRadius: 18,
    snackBarRadius: 18,
    bottomNavigationBarElevation: 0,
    navigationBarElevation: 0,
  );

  /// Montserrat, re-scaled to the reference: headings are heavy and optically
  /// tightened, body copy sits at a medium weight so it still holds up against
  /// the bold headings, and the label styles are small, bold and letter-spaced
  /// because they are used as all-caps captions (nav labels, section eyebrows).
  static TextTheme _textTheme(TextTheme base) {
    final t = GoogleFonts.montserratTextTheme(base);
    return t.copyWith(
      headlineMedium: t.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      headlineSmall: t.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: t.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontSize: 16.5,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleSmall: t.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w500),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: t.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      labelSmall: t.labelSmall?.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

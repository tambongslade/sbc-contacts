import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';

/// Builds the SBC-branded Material 3 themes via FlexColorScheme, seeded from the
/// brand palette and typed with Montserrat (SBC's product font).
class AppTheme {
  const AppTheme._();

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
      subThemesData: _subThemes,
      useMaterial3: true,
    );
    return base.copyWith(textTheme: _textTheme(base.textTheme));
  }

  static const FlexSubThemesData _subThemes = FlexSubThemesData(
    defaultRadius: 12,
    cardRadius: 16,
    inputDecoratorRadius: 12,
    inputDecoratorBorderType: FlexInputBorderType.outline,
    filledButtonRadius: 12,
    elevatedButtonRadius: 12,
    chipRadius: 8,
    bottomNavigationBarElevation: 2,
    navigationBarElevation: 2,
  );

  static TextTheme _textTheme(TextTheme base) => GoogleFonts.montserratTextTheme(base);
}

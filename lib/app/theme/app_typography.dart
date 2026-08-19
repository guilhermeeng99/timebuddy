import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The type scale, published as a Material [TextTheme] so widgets inherit it
/// from the theme instead of naming a font family themselves.
///
/// Two families split by role. **Poppins** carries display, headline,
/// `titleLarge` and anything the user reads as a value: it is geometric, so
/// digits stay distinct at a glance. **Inter** carries running text and
/// labels, where legibility at 11–16px beats character.
///
/// Read it through `context.textTheme`; calling `GoogleFonts` inside a widget
/// bypasses the scale and the theme's color application.
///
/// Example:
/// ```dart
/// Text(city.label, style: context.textTheme.titleLarge);
/// ```
abstract class AppTypography {
  /// The 15-style scale. Colors are applied by [ThemeData] via
  /// `.apply(bodyColor:, displayColor:)`, so the styles here carry no color.
  static TextTheme get textTheme => TextTheme(
    displayLarge: GoogleFonts.poppins(
      fontSize: 32,
      fontWeight: FontWeight.bold,
    ),
    displayMedium: GoogleFonts.poppins(
      fontSize: 28,
      fontWeight: FontWeight.bold,
    ),
    displaySmall: GoogleFonts.poppins(
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    headlineLarge: GoogleFonts.poppins(
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: GoogleFonts.poppins(
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: GoogleFonts.poppins(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: GoogleFonts.poppins(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    titleSmall: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      height: 1.5,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      height: 1.5,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      height: 1.5,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
  );

  /// Wall-clock digits, for `ClockText` and `StaticTimeText`.
  ///
  /// Deliberately outside [textTheme]: it is the one style that must carry
  /// [FontFeature.tabularFigures]. With proportional figures every digit has
  /// its own advance width, so a clock that repaints each second visibly
  /// shifts sideways as `1` replaces `8` — 30 rows of that reads as the whole
  /// board twitching.
  ///
  /// Example:
  /// ```dart
  /// Text(
  ///   formatClock(localTime, hourFormat),
  ///   style: AppTypography.clock(color: context.appColors.onBackground),
  /// );
  /// ```
  static TextStyle clock({
    required Color color,
    double fontSize = 18,
  }) => GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

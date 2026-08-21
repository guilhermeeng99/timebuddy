// Palette catalog shared verbatim with the Financo project
// (financo/lib/app/theme/light_palettes.dart). The ids, the labels and every
// hex below are a straight port; editing one value here diverges the two apps
// with no compiler or test to catch it, so a colour change belongs in both
// repositories or in neither.
//
// Financo's finance tokens map onto TimeBuddy's hour bands:
// income -> hourGood, expense -> hourPoor, warning -> hourFair (and stays as
// warning). There is no hourNight field: AppColorsData derives it, so the
// sleeping band always tracks whichever palette is active.

import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_colors.dart';

/// The selectable light-mode palettes, in picker order.
///
/// Persisted by `enum.name`, so renaming a value silently resets every user
/// who had picked it. Append new palettes at the end.
enum LightPalette {
  indigoCloud,
  mintFresh,
  sunsetCoral,
  oceanBreeze,
  lavenderSoft,
  forestSage,
  roseGold,
  slateModern,
  amberWarm,
  cyanPop,
}

/// One catalog entry: the stable [id], the name shown in the picker and the
/// complete token set copied into [AppColors.light] when it is selected.
///
/// [label] is a product name ('Indigo Cloud'), not translated copy, which is
/// why it lives here as a literal instead of going through slang.
class LightPaletteOption {
  const LightPaletteOption({
    required this.id,
    required this.label,
    required this.colors,
  });

  final LightPalette id;
  final String label;
  final AppColorsData colors;
}

/// The light-mode palette catalog.
///
/// Example:
/// ```dart
/// AppColors.light = LightPalettes.colorsFor(preferences.lightPalette);
/// ```
abstract class LightPalettes {
  /// Picker order. The first entry is the default palette.
  static const List<LightPaletteOption> all = [
    LightPaletteOption(
      id: LightPalette.indigoCloud,
      label: 'Indigo Cloud',
      colors: AppColorsData(
        primary: Color(0xFF5B5FEF),
        primaryLight: Color(0xFF7C83FF),
        primaryDark: Color(0xFF3F43C9),
        secondary: Color(0xFF22C55E),
        background: Color(0xFFF6F7FB),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFEEF0F6),
        onBackground: Color(0xFF1A1B1F),
        onBackgroundLight: Color(0xFF676E7B),
        hourGood: Color(0xFF22C55E),
        hourFair: Color(0xFFF59E0B),
        hourPoor: Color(0xFFEF4444),
        warning: Color(0xFFF59E0B),
        success: Color(0xFF22C55E),
        error: Color(0xFFEF4444),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.mintFresh,
      label: 'Mint Fresh',
      colors: AppColorsData(
        primary: Color(0xFF10B981),
        primaryLight: Color(0xFF34D399),
        primaryDark: Color(0xFF047857),
        secondary: Color(0xFF0EA5E9),
        background: Color(0xFFF1FAF6),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFE2F2EA),
        onBackground: Color(0xFF0F2A21),
        onBackgroundLight: Color(0xFF547267),
        hourGood: Color(0xFF059669),
        hourFair: Color(0xFFF59E0B),
        hourPoor: Color(0xFFE11D48),
        warning: Color(0xFFF59E0B),
        success: Color(0xFF10B981),
        error: Color(0xFFE11D48),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.sunsetCoral,
      label: 'Sunset Coral',
      colors: AppColorsData(
        primary: Color(0xFFF97066),
        primaryLight: Color(0xFFFDA29B),
        primaryDark: Color(0xFFD92D20),
        secondary: Color(0xFFFB923C),
        background: Color(0xFFFFF7F3),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFFCE9E0),
        onBackground: Color(0xFF2A1410),
        onBackgroundLight: Color(0xFF7B5A52),
        hourGood: Color(0xFF16A34A),
        hourFair: Color(0xFFF59E0B),
        hourPoor: Color(0xFFDC2626),
        warning: Color(0xFFF59E0B),
        success: Color(0xFF16A34A),
        error: Color(0xFFDC2626),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.oceanBreeze,
      label: 'Ocean Breeze',
      colors: AppColorsData(
        primary: Color(0xFF0EA5E9),
        primaryLight: Color(0xFF38BDF8),
        primaryDark: Color(0xFF0369A1),
        secondary: Color(0xFF14B8A6),
        background: Color(0xFFF0F9FF),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFE0F2FE),
        onBackground: Color(0xFF0C1F2C),
        onBackgroundLight: Color(0xFF52708A),
        hourGood: Color(0xFF059669),
        hourFair: Color(0xFFF59E0B),
        hourPoor: Color(0xFFEF4444),
        warning: Color(0xFFF59E0B),
        success: Color(0xFF059669),
        error: Color(0xFFEF4444),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.lavenderSoft,
      label: 'Lavender Soft',
      colors: AppColorsData(
        primary: Color(0xFF8B5CF6),
        primaryLight: Color(0xFFA78BFA),
        primaryDark: Color(0xFF6D28D9),
        secondary: Color(0xFFEC4899),
        background: Color(0xFFF8F5FF),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFEDE7FA),
        onBackground: Color(0xFF1F1530),
        onBackgroundLight: Color(0xFF6B5C82),
        hourGood: Color(0xFF22C55E),
        hourFair: Color(0xFFF59E0B),
        hourPoor: Color(0xFFEF4444),
        warning: Color(0xFFF59E0B),
        success: Color(0xFF22C55E),
        error: Color(0xFFEF4444),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.forestSage,
      label: 'Forest Sage',
      colors: AppColorsData(
        primary: Color(0xFF4F7942),
        primaryLight: Color(0xFF7BA068),
        primaryDark: Color(0xFF34522D),
        secondary: Color(0xFFCA8A04),
        background: Color(0xFFF5F7F0),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFE7EBDC),
        onBackground: Color(0xFF1A2614),
        onBackgroundLight: Color(0xFF5E6B52),
        hourGood: Color(0xFF4F7942),
        hourFair: Color(0xFFCA8A04),
        hourPoor: Color(0xFFB91C1C),
        warning: Color(0xFFCA8A04),
        success: Color(0xFF4F7942),
        error: Color(0xFFB91C1C),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.roseGold,
      label: 'Rose Gold',
      colors: AppColorsData(
        primary: Color(0xFFE11D74),
        primaryLight: Color(0xFFF472B6),
        primaryDark: Color(0xFF9D174D),
        secondary: Color(0xFFD97706),
        background: Color(0xFFFFF5F8),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFFCE4EC),
        onBackground: Color(0xFF2A1020),
        onBackgroundLight: Color(0xFF7B566A),
        hourGood: Color(0xFF16A34A),
        hourFair: Color(0xFFD97706),
        hourPoor: Color(0xFFE11D48),
        warning: Color(0xFFD97706),
        success: Color(0xFF16A34A),
        error: Color(0xFFE11D48),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.slateModern,
      label: 'Slate Modern',
      colors: AppColorsData(
        primary: Color(0xFF334155),
        primaryLight: Color(0xFF64748B),
        primaryDark: Color(0xFF1E293B),
        secondary: Color(0xFF0EA5E9),
        background: Color(0xFFFAFAFA),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFF1F5F9),
        onBackground: Color(0xFF0F172A),
        onBackgroundLight: Color(0xFF617188),
        hourGood: Color(0xFF059669),
        hourFair: Color(0xFFD97706),
        hourPoor: Color(0xFFDC2626),
        warning: Color(0xFFD97706),
        success: Color(0xFF059669),
        error: Color(0xFFDC2626),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.amberWarm,
      label: 'Amber Warm',
      colors: AppColorsData(
        primary: Color(0xFFD97706),
        primaryLight: Color(0xFFFBBF24),
        primaryDark: Color(0xFF92400E),
        secondary: Color(0xFF059669),
        background: Color(0xFFFFFBEB),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFFEF3C7),
        onBackground: Color(0xFF2A1A0A),
        onBackgroundLight: Color(0xFF7C5E3F),
        hourGood: Color(0xFF059669),
        hourFair: Color(0xFFD97706),
        hourPoor: Color(0xFFDC2626),
        warning: Color(0xFFD97706),
        success: Color(0xFF059669),
        error: Color(0xFFDC2626),
      ),
    ),
    LightPaletteOption(
      id: LightPalette.cyanPop,
      label: 'Cyan Pop',
      colors: AppColorsData(
        primary: Color(0xFF06B6D4),
        primaryLight: Color(0xFF22D3EE),
        primaryDark: Color(0xFF0E7490),
        secondary: Color(0xFF8B5CF6),
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFECFEFF),
        onBackground: Color(0xFF062A33),
        onBackgroundLight: Color(0xFF4D7A84),
        hourGood: Color(0xFF10B981),
        hourFair: Color(0xFFF59E0B),
        hourPoor: Color(0xFFEF4444),
        warning: Color(0xFFF59E0B),
        success: Color(0xFF10B981),
        error: Color(0xFFEF4444),
      ),
    ),
  ];

  /// Tokens for [id], falling back to the first entry.
  ///
  /// The fallback covers a [LightPalette] value with no entry in [all]: the
  /// two lists are maintained by hand, and a missing palette must not take
  /// down the entire theme.
  static AppColorsData colorsFor(LightPalette id) => all
      .firstWhere((option) => option.id == id, orElse: () => all.first)
      .colors;
}

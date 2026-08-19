import 'package:flutter/material.dart';

/// The semantic color tokens of one theme brightness.
///
/// A screen never names a color literally; it names a *role*
/// (`context.appColors.hourGood`) and the active palette decides the hex.
/// That indirection is the whole reason the 20-palette catalog can repaint
/// the app at runtime without a single widget knowing.
///
/// Example:
/// ```dart
/// final colors = context.appColors;
/// ColoredBox(color: colors.hourGood.withValues(alpha: 0.12));
/// ```
class AppColorsData {
  const AppColorsData({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onBackground,
    required this.onBackgroundLight,
    required this.hourGood,
    required this.hourFair,
    required this.hourPoor,
    required this.warning,
    required this.success,
    required this.error,
  });

  /// Brand accent: CTAs, active nav, selection, hour cursor, focus ring.
  final Color primary;

  /// Lighter brand tint: hover states, gradients, disabled-but-branded fills.
  final Color primaryLight;

  /// Darker brand shade: pressed states, text on a light brand wash.
  final Color primaryDark;

  /// Secondary accent. Shares its value with [hourGood] today; see the note
  /// on [AppColors] before assuming they may diverge for free.
  final Color secondary;

  /// Scaffold backdrop, the darkest layer of the three surfaces.
  final Color background;

  /// Card / sheet / app-bar fill, one layer above [background].
  final Color surface;

  /// Input fill, dividers, subtle chips, hover and track colors.
  final Color surfaceVariant;

  /// Primary text and icons drawn on [background] or [surface].
  final Color onBackground;

  /// Muted text: labels, captions, placeholders, inactive nav.
  final Color onBackgroundLight;

  /// Comfortable hour band, inside the user's working hours.
  final Color hourGood;

  /// Borderline hour band, the shoulder hour on either side of the window.
  final Color hourFair;

  /// Bad hour band: awake, but outside the working window.
  final Color hourPoor;

  /// Caution copy and badges.
  final Color warning;

  /// Confirmation feedback.
  final Color success;

  /// Validation and destructive actions.
  final Color error;

  /// Foreground for content sitting **on** a [primary] fill: a filled
  /// button's label, a selected chip's icon, the hour-cursor label.
  ///
  /// Computed instead of being a 16th palette field because it is fully
  /// determined by [primary]. Handing it to the palette catalog would mean
  /// 20 hand-picked values and 20 chances to get it wrong — and the failure
  /// is silent, since a wrong choice only shows up as unreadable text on the
  /// one palette nobody tested.
  Color get onPrimary => foregroundOn(primary);

  /// The sleeping-hours band (23:00 through 06:59 local).
  ///
  /// Computed for the reason [onPrimary] is: it is derived, not chosen. It
  /// must read as *dimmed neutral* rather than as a fourth accent hue, so it
  /// is mixed from the two neutral tokens the palette already owns. Letting
  /// each palette pick a night color invites 20 accidental new accents.
  Color get hourNight => Color.lerp(surfaceVariant, onBackgroundLight, 0.35)!;

  /// Dimming layer behind a modal or a tooltip. Callers choose the alpha.
  ///
  /// Computed and constant for the same reason again: a scrim is black in
  /// every palette, so 20 copies of `0xFF000000` would only create 20 places
  /// for a "themed" scrim to creep in and muddy the dim.
  Color get scrim => const Color(0xFF000000);
}

/// Picks black or white for content drawn on an arbitrary [background].
///
/// Used where the backdrop is a color the theme does not own — a location's
/// user-picked color, a country flag tint — so no semantic token can answer
/// the question.
///
/// The threshold is `0.55` rather than the naive midpoint because mid-tone
/// brand colors read better with white than `0.5` predicts; lowering it makes
/// medium indigos and greens flip to black text and lose contrast.
///
/// Example:
/// ```dart
/// final foreground = foregroundOn(location.tint);
/// ```
Color foregroundOn(Color background) => background.computeLuminance() > 0.55
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

/// The palettes currently in effect, plus the shipped defaults.
///
/// [light] and [dark] are **mutable** on purpose: the user picks a palette
/// from the catalog at runtime and `PreferencesCubit` reassigns these before
/// the app rebuilds `MaterialApp`. Everything downstream reads them through
/// `context.appColors`, so a switch costs one reassignment and one rebuild.
abstract class AppColors {
  /// Active light palette. Reassigned when the user picks another one.
  static AppColorsData light = defaultLight;

  /// Active dark palette. Reassigned when the user picks another one.
  static AppColorsData dark = defaultDark;

  /// Indigo Cloud: the shipped light palette and the fallback whenever a
  /// persisted palette id no longer exists in the catalog.
  static const AppColorsData defaultLight = AppColorsData(
    primary: Color(0xFF5B5FEF),
    primaryLight: Color(0xFF7C83FF),
    primaryDark: Color(0xFF3F43C9),
    secondary: Color(0xFF22C55E),
    background: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEEF0F6),
    onBackground: Color(0xFF1A1B1F),
    onBackgroundLight: Color(0xFF6B7280),
    hourGood: Color(0xFF22C55E),
    hourFair: Color(0xFFF59E0B),
    hourPoor: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    success: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
  );

  /// Indigo Cloud's dark counterpart: the shipped dark palette and the
  /// fallback for an unknown persisted dark palette id.
  static const AppColorsData defaultDark = AppColorsData(
    primary: Color(0xFF7C83FF),
    primaryLight: Color(0xFFA5ABFF),
    primaryDark: Color(0xFF5B5FEF),
    secondary: Color(0xFF22C55E),
    background: Color(0xFF0F1117),
    surface: Color(0xFF181C24),
    surfaceVariant: Color(0xFF212632),
    onBackground: Color(0xFFE6E9F0),
    onBackgroundLight: Color(0xFF9AA3B2),
    hourGood: Color(0xFF22C55E),
    hourFair: Color(0xFFFBBF24),
    hourPoor: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
    success: Color(0xFF22C55E),
    error: Color(0xFFF87171),
  );
}

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

  /// WCAG AA for body copy: what any text below 18pt has to clear.
  static const double minTextRatio = 4.5;

  /// WCAG AA for non-text content: icons that carry meaning, the "now" line,
  /// a progress track. Anything a user has to *see* but does not read.
  static const double minGlyphRatio = 3;

  /// How far a failing accent is pulled toward [onBackground] to repair it.
  ///
  /// One fixed step rather than a search, because a search is a loop in a
  /// getter called from `build`. Measured against the shipped catalog: the
  /// worst palette needs `0.39` to lift `primary` over [minTextRatio] and
  /// `0.23` to lift `warning` over [minGlyphRatio], so `0.40` clears every
  /// one of the twenty with nothing to spare and nothing wasted.
  static const double _repairBlend = 0.40;

  /// [accent] pulled toward [onBackground] until it is legible on
  /// [background] — returned **unchanged** when it already is.
  ///
  /// The palettes are chosen for their fills, where a brand color only has to
  /// be itself. Six of the ten light ones then fail as *content*: Mint Fresh's
  /// `primary` is `2.39:1` against its own page, which is a caption a
  /// low-vision user cannot read and a marker they cannot find. Repairing here
  /// rather than in the catalog is deliberate — the catalog keeps the color
  /// the user picked for every fill, disc and wash, and only the places that
  /// draw the accent *as content* take the darker one.
  ///
  /// Blending toward [onBackground] rather than toward black or white is what
  /// keeps the result inside the palette's own ink family, so a repaired
  /// accent on a dark palette lightens instead of turning muddy. It is the
  /// same move `HourCell` makes on its digits.
  ///
  /// ```dart
  /// Text(label, style: TextStyle(color: colors.inkFor(colors.secondary)));
  /// ```
  Color inkFor(Color accent, {double minRatio = minTextRatio}) =>
      contrastRatio(accent, background) >= minRatio
      ? accent
      : Color.lerp(accent, onBackground, _repairBlend)!;

  /// [primary] as **text**: the `Today` pill, the `Tomorrow` word, a section's
  /// count badge. Never as a fill — a filled control uses [primary] itself and
  /// labels it with [onPrimary].
  Color get primaryInk => inkFor(primary);

  /// [primary] as a **meaningful graphic**: the "now" line, a selected row's
  /// check, the splash's progress track. Held to [minGlyphRatio] rather than
  /// [minTextRatio], because nobody reads a line.
  ///
  /// Decorative uses of the accent keep [primary] itself: an `IconDisc`'s
  /// glyph sits on a wash of its own color and is captioned by the text under
  /// it, so darkening it would repair nothing and change every empty state.
  Color get primaryGlyph => inkFor(primary, minRatio: minGlyphRatio);

  /// [warning] as a meaningful graphic: the banner's triangle, the DST dot,
  /// the sync-failure icon. Raw [warning] is `2.15:1` on the worst light
  /// palette, which is below even the non-text bar.
  Color get warningInk => inkFor(warning, minRatio: minGlyphRatio);

  /// [success] as a meaningful graphic — today, the "everything is synced"
  /// check on the profile page.
  Color get successInk => inkFor(success, minRatio: minGlyphRatio);

  /// [error] as a meaningful graphic. It already clears [minGlyphRatio] on all
  /// twenty palettes; the getter exists so a call site does not have to know
  /// which of the three status colors happens to be safe this month.
  Color get errorInk => inkFor(error, minRatio: minGlyphRatio);
}

/// The WCAG 2.1 contrast ratio between two **opaque** colors, `1.0` to `21.0`.
///
/// Both arguments must be opaque: the formula has nowhere to put an alpha, and
/// a translucent one silently measures a color nobody sees. Composite first —
/// `Color.alphaBlend(fill, page)` — and pass the result.
///
/// The thresholds worth remembering are on [AppColorsData.minTextRatio] and
/// [AppColorsData.minGlyphRatio].
///
/// ```dart
/// contrastRatio(colors.onBackground, colors.background); // 14.4 on Mint Fresh
/// ```
double contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Picks black or white for content drawn on an arbitrary [background].
///
/// Used where the backdrop is a color the theme does not own — a palette's
/// own `primary` behind a filled button's label, a location's user-picked
/// color, a country flag tint — so no semantic token can answer the question.
///
/// **It picks whichever of the two actually measures better, and that is a
/// correction.** This used to be a luminance threshold of `0.55`, justified in
/// a comment that said mid-tone brand colors "read better with white than
/// `0.5` predicts". Measured against the shipped catalog, the opposite is
/// true: the threshold put white on the primary of **14 of the 20 palettes**
/// whose primary should carry black, and since `onPrimary` is what labels
/// every filled button and the selected nav destination, those labels sat as
/// low as **1.81:1** (Deep Ocean, Cyan Neon) against a WCAG AA bar of 4.5.
/// Choosing by contrast lifts all fourteen to between 4.63:1 and 11.62:1 and
/// changes nothing on the six that were already right.
///
/// Comparing the two candidates cannot be worse than any fixed threshold: the
/// threshold is an approximation of exactly this comparison.
/// `test/app/theme/palette_contrast_test.dart` pins it for every palette.
///
/// ```dart
/// final foreground = foregroundOn(location.tint);
/// ```
Color foregroundOn(Color background) {
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);
  return contrastRatio(white, background) >= contrastRatio(black, background)
      ? white
      : black;
}

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
    onBackgroundLight: Color(0xFF676E7B),
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

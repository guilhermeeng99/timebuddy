/// The spacing rhythm of the app.
///
/// Feature code never writes a raw padding number. A screen that invents
/// `13` will not line up with the screen next to it, and nothing catches it
/// in review once two of them exist.
abstract class AppSpacing {
  /// Hairline gap: icon-to-label, chip inner padding.
  static const double xs = 4;

  /// Tight gap between elements inside a single component.
  static const double sm = 8;

  /// Gap between fields inside a form section; common inner padding.
  static const double md = 12;

  /// The standard page gutter. Default for any screen-edge padding.
  static const double lg = 16;

  /// The gap between sections of a form or a page.
  static const double xl = 20;

  /// Large block separation, e.g. above a submit bar or between groups.
  static const double xxl = 24;
}

/// The corner radius scale.
///
/// These five values are the only radii in the app. A sixth one shows up as
/// a card whose corners are subtly wrong next to the card above it.
abstract class AppRadius {
  /// Hairline rounding: tiny badges, progress tracks.
  static const double xs = 4;

  /// Small chips, dots and inline pills.
  static const double sm = 8;

  /// Inputs, buttons and small tiles. The most common radius in the app.
  static const double md = 12;

  /// The `cardTheme` default and medium containers.
  static const double lg = 16;

  /// Content cards, bottom sheets and pill-shaped chips.
  static const double xl = 20;
}

/// Fixed geometry of the time grid.
///
/// Kept apart from [AppSpacing] because these are layout math, not rhythm:
/// the grid's scroll offsets, day boundaries and hour cursor are all computed
/// from them, so changing one changes a calculation, not just a gap.
/// See `docs/specs/time_grid.md`.
abstract class GridMetrics {
  /// Width of one hour column. Sized for a two-digit hour plus the `:30`
  /// suffix that half-hour zones such as `Asia/Kolkata` need.
  static const double hourColumnWidth = 44;

  /// Width of the pinned first column holding the location label.
  static const double labelColumnWidth = 132;

  /// Height of one location row.
  static const double rowHeight = 64;

  /// Height of the sticky day/date header above the hour columns.
  static const double headerHeight = 40;
}

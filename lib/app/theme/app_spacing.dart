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
  /// Reference width of one hour column: what a cell takes when nothing
  /// constrains it, and the size the type scale was chosen against.
  ///
  /// **The grid no longer reads this.** It resolves its column at layout time
  /// through `GridLayout`, which divides the track into whole columns bounded
  /// by `GridLayout.minColumnWidth` and `maxColumnWidth`; a constant column
  /// meant a narrower window clipped the last cell in half rather than showing
  /// fewer, whole ones (docs/specs/time_grid.md rule 12).
  ///
  /// What is still true is why the number is 60 rather than the 44 it was: 44
  /// held a two-digit hour at 11pt and made a half-hour zone's `05:45` shrink
  /// to 9pt to fit, so the rows that most needed explaining — Kolkata,
  /// Kathmandu, Chatham — were the hardest on the screen to read. At 60 the
  /// digits are 15pt for every cell, and `GridLayout`'s 48pt floor is set
  /// where that type still fits.
  static const double hourColumnWidth = 60;

  /// Width of the pinned first column holding the location label.
  ///
  /// 180, up from 132, so a city name is read rather than ellipsed: `Mexico
  /// City` and `Kuala Lumpur` both fit beside their offset badge now.
  static const double labelColumnWidth = 180;

  /// Height of one location row.
  ///
  /// 72, up from 64: the hour digits grew to 15pt and a row still has to hold
  /// a date label above them on the cell where a day turns.
  static const double rowHeight = 72;

  /// Height of the sticky day/date header above the hour columns.
  ///
  /// 48, up from 40, for the same reason the rows grew: the ruler's hour is
  /// 13pt now and a day boundary stacks its date above it.
  static const double headerHeight = 48;
}

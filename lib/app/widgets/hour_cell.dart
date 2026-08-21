import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The single mapping from an [HourBand] to a palette token.
///
/// Exposed so the other band-driven affordances (the day/night dot, a legend)
/// read the same table instead of re-deciding which green means "good". Change
/// it here and every colored hour in the app follows.
///
/// ```dart
/// final tint = hourBandColor(HourBand.fair, context.appColors);
/// ```
Color hourBandColor(HourBand band, AppColorsData colors) => switch (band) {
  HourBand.good => colors.hourGood,
  HourBand.fair => colors.hourFair,
  HourBand.poor => colors.hourPoor,
  HourBand.night => colors.hourNight,
};

/// One hour surface of the grid or the converter strip.
///
/// **Every colored hour in the app goes through this widget.** The band arrives
/// already computed by `hourBandFor(localHour, workingHours)`; the cell decides
/// nothing about time, only how a band looks (design_system §2, time_grid rule
/// 7). That split is what keeps the working-hours preference from having to be
/// re-implemented in each screen that paints hours.
///
/// ```dart
/// HourCell(
///   hour: localTime.hour,
///   band: hourBandFor(localTime.hour, preferences.workingHours),
///   minute: localTime.minute,   // only for :30 / :45 zones
///   isCursor: slot == cursorSlot,
/// );
/// ```
class HourCell extends StatelessWidget {
  const HourCell({
    required this.hour,
    required this.band,
    this.minute,
    this.isCursor = false,
    this.isSelected = false,
    this.height = GridMetrics.rowHeight,
    this.compact = false,
    this.semanticLabel,
    super.key,
  });

  /// The name of [band] in the user's language, as the settings legend and
  /// the day/night dot say it.
  ///
  /// Public so a caller composing a longer label for one cell — the grid's
  /// date turnover, its DST marker — builds it out of the same four words
  /// rather than inventing a fifth.
  static String bandLabel(HourBand band) => switch (band) {
    HourBand.good => t.bands.good,
    HourBand.fair => t.bands.fair,
    HourBand.poor => t.bands.poor,
    HourBand.night => t.bands.night,
  };

  /// Local hour of the cell, `0..23`. Rendered zero-padded.
  final int hour;

  /// How reachable that hour is, from `hourBandFor`.
  final HourBand band;

  /// Minutes to append as `:mm`.
  ///
  /// Pass it only for a row whose offset from the reference zone is not a whole
  /// number of hours — Kolkata `+05:30`, Kathmandu `+05:45`, Chatham `+12:45`.
  /// Hiding those minutes would claim the row lines up with the column when it
  /// does not (time_grid rule 5). `null` or `0` renders the hour alone.
  final int? minute;

  /// Marks the column the shared cursor currently sits on.
  final bool isCursor;

  /// Marks a cell the user has picked, as distinct from the one the cursor is
  /// resting on.
  ///
  /// Nothing sets it today — the meeting planner that did was removed. It is
  /// kept because the distinction is real and cheap: a wash *over* the band
  /// rather than a replacement of it, so a picked slot still says whether it
  /// is a good hour.
  final bool isSelected;

  /// Cell height. Defaults to one grid row.
  final double height;

  /// Renders the small chip form instead of the grid's own.
  ///
  /// The grid cell is a wide, flat, edge-to-edge segment of a timeline: 15pt
  /// digits, no rounding, no gap, so twenty of them read as one continuous
  /// day rather than as twenty floating pills. That form needs the full
  /// `GridMetrics.hourColumnWidth` and has nowhere to go in the settings
  /// preview, whose 24 cells share whatever width the card can spare — as
  /// little as 26pt each. `compact` keeps that caller on the rounded 11pt chip
  /// the grid used to draw everywhere.
  ///
  /// Both forms take their fill from the same `hourBandColor`, which is the
  /// reason this is one widget: the preview is a legend for the grid, and a
  /// legend drawn by a second widget stops matching the first time either is
  /// restyled.
  final bool compact;

  /// Replaces the label a screen reader hears for this cell.
  ///
  /// Pass one when the cell carries marks this widget cannot see — the grid's
  /// day boundary and its DST dot are drawn *over* the cell by
  /// `GridRowView`, so only that caller can say "and the date turns here".
  /// `null` uses [_defaultSemanticLabel], which is the hour and its band.
  final String? semanticLabel;

  /// Band tint under the digits.
  ///
  /// Public, with the three below, so
  /// `test/app/theme/palette_contrast_test.dart` can measure the colour a
  /// cell actually paints instead of a second copy of these numbers that
  /// drifts the first time one is retuned.
  ///
  /// 0.16, up from 0.12: at the old value four bands were four shades of the
  /// same murk on a dark palette, and the colour was carrying no information a
  /// user could act on.
  static const double fillAlpha = 0.16;
  static const double selectedAlpha = 0.18;
  static const double _compactFontSize = 11;
  static const double _comfortableFontSize = 15;

  /// How far the digits are pulled from their band colour toward the page's
  /// foreground.
  ///
  /// The digits are tinted rather than plain, so a cell says which band it is
  /// in even to someone reading one row out of the corner of their eye — and
  /// lerping toward `onBackground` rather than hardcoding a light tint is what
  /// keeps that legible on all twenty palettes, light ones included.
  static const double inkBlend = 0.55;

  /// 0.50, up from 0.45. At 0.45 the cursor's digits measured **4.31:1**
  /// against their own wash on Mint Fresh, just under the 4.5 that 15pt text
  /// owes; 0.50 lifts the worst palette to 4.73:1 and every other one further.
  /// Pinned by `test/app/theme/palette_contrast_test.dart`.
  static const double cursorInkBlend = 0.50;

  /// The cell's digits, through the grid's one formatter.
  ///
  /// A `DateTime` is built here purely as a carrier for the two fields
  /// [formatGridHour] reads; it is not an instant and must never be treated as
  /// one. Going through the shared function rather than interpolating here is
  /// what keeps this cell and the ruler above it from drifting apart, which is
  /// exactly what had happened when both hand-rolled the same `padLeft`.
  String get _label => formatGridHour(DateTime(2000, 1, 1, hour, minute ?? 0));

  /// What a screen reader hears: the hour, then the band it falls in.
  ///
  /// **The band is otherwise carried by colour and nothing else.** The fill is
  /// a 16% wash and the digits are tinted, so a user reading this screen by
  /// voice got twenty-odd bare numbers and no answer to the question the
  /// screen exists to answer — which of these hours is a reasonable one. The
  /// hour alone is not a substitute: "is 03:00 good" depends on a working
  /// window this widget already knows the answer for.
  ///
  /// It is deliberately terse. A grid row is thirty of these in a line, and a
  /// sentence per cell is a screen nobody would listen to the end of.
  String get _defaultSemanticLabel =>
      t.common.hourInBand(hour: _label, band: bandLabel(band));

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      label: semanticLabel ?? _defaultSemanticLabel,
      // The digits are already inside the label, so leaving the `Text` visible
      // to the tree would announce the hour twice.
      excludeSemantics: true,
      child: _sized(context, colors),
    );
  }

  Widget _sized(BuildContext context, AppColorsData colors) {
    return SizedBox(
      width: GridMetrics.hourColumnWidth,
      height: height,
      // No ink response and no tap target: the cursor is set from the ruler
      // (docs/specs/time_grid.md rule 8) and the cells are a read surface, so
      // the whole track is free for the pan. An affordance that splashes and
      // does nothing is worse than one that does not splash.
      //
      // The comfortable cell has no inset: its fill runs to the column's edges
      // so neighbouring hours meet, which is what turns a row of cells into a
      // timeline.
      child: compact
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: _surface(context, colors),
            )
          : _surface(context, colors),
    );
  }

  Widget _surface(BuildContext context, AppColorsData colors) {
    final radius = compact
        ? BorderRadius.circular(AppRadius.sm)
        : BorderRadius.zero;
    final bandColor = hourBandColor(band, colors);
    return DecoratedBox(
      decoration: BoxDecoration(
        // The cursor is a wash of the accent rather than a 2pt ring around the
        // cell. A ring is a fifth box drawn on a screen that already has
        // eighty; a filled column reads as "here" from across the row and
        // costs no extra edge.
        color: isCursor
            ? colors.primary.withValues(alpha: selectedAlpha)
            : bandColor.withValues(alpha: fillAlpha),
        borderRadius: radius,
      ),
      child: DecoratedBox(
        // Selection is a wash *over* the band rather than a replacement of it,
        // so a picked slot still says whether it is a good hour to meet.
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: selectedAlpha)
              : null,
          borderRadius: radius,
        ),
        child: Center(
          child: Text(
            _label,
            maxLines: 1,
            style: context.textTheme.labelSmall?.copyWith(
              // One size for every cell, minutes or not. The old 9pt
              // fallback made exactly the rows that need explaining —
              // Kolkata, Kathmandu, Chatham — the hardest ones to read.
              fontSize: compact ? _compactFontSize : _comfortableFontSize,
              fontWeight: isCursor || isSelected
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: _inkFor(colors, bandColor),
            ),
          ),
        ),
      ),
    );
  }

  /// The digit colour: the band pulled toward the page's foreground, or the
  /// accent pulled the same way on the cursor.
  Color _inkFor(AppColorsData colors, Color bandColor) {
    if (isCursor || isSelected) {
      return Color.lerp(
        colors.primary,
        colors.onBackground,
        cursorInkBlend,
      )!;
    }
    // The compact chip is small enough that a tinted digit loses contrast
    // before it gains meaning, so it keeps the plain foreground.
    if (compact) return colors.onBackground;
    return Color.lerp(bandColor, colors.onBackground, inkBlend)!;
  }
}

import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/hour_band.dart';

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

/// One hour surface of the grid, planner or converter strip.
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
///   onTap: () => cubit.setCursor(slot),
/// );
/// ```
class HourCell extends StatelessWidget {
  const HourCell({
    required this.hour,
    required this.band,
    this.minute,
    this.isCursor = false,
    this.isSelected = false,
    this.onTap,
    this.height = GridMetrics.rowHeight,
    super.key,
  });

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

  /// Marks a cell the user has picked, e.g. a planner candidate slot.
  final bool isSelected;

  /// Tap handler. `null` renders a non-interactive cell with no ink response.
  final VoidCallback? onTap;

  /// Cell height. Defaults to one grid row.
  final double height;

  static const double _fillAlpha = 0.12;
  static const double _selectedAlpha = 0.18;
  static const double _cursorBorderWidth = 2;
  static const double _compactFontSize = 9;

  bool get _hasMinutes => minute != null && minute != 0;

  String get _label {
    final paddedHour = hour.toString().padLeft(2, '0');
    if (!_hasMinutes) return paddedHour;
    return '$paddedHour:${minute!.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: GridMetrics.hourColumnWidth,
      height: height,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: _surface(context, colors),
          ),
        ),
      ),
    );
  }

  Widget _surface(BuildContext context, AppColorsData colors) {
    final radius = BorderRadius.circular(AppRadius.sm);
    final isEmphasised = isCursor || isSelected;
    return DecoratedBox(
      decoration: BoxDecoration(
        // The band token at 12%: enough to read the column as a block of
        // colour, light enough that the digits stay legible on both palettes.
        color: hourBandColor(band, colors).withValues(alpha: _fillAlpha),
        borderRadius: radius,
        border: isCursor
            ? Border.all(color: colors.primary, width: _cursorBorderWidth)
            : null,
      ),
      child: DecoratedBox(
        // Selection is a wash *over* the band rather than a replacement of it,
        // so a picked slot still says whether it is a good hour to meet.
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: _selectedAlpha)
              : null,
          borderRadius: radius,
        ),
        child: Center(
          child: Text(
            _label,
            maxLines: 1,
            style: context.textTheme.labelSmall?.copyWith(
              // Half-hour rows carry two extra glyphs in the same 44px column.
              fontSize: _hasMinutes ? _compactFontSize : null,
              fontWeight: isEmphasised ? FontWeight.w600 : FontWeight.w500,
              color: isEmphasised ? colors.primary : colors.onBackground,
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Number of hour-of-day values, which is always 24.
///
/// This is *not* the "a day is 23 or 25 hours on a transition" case that
/// CLAUDE.md rule 7 forbids hardcoding: the strip has no zone and no date, it
/// enumerates the domain of `hourBandFor`, which is `0..23` by definition.
/// Anything that renders a real day still asks the engine for its length.
const int _hoursOfDay = 24;

/// Below this a cell cannot fit two digits, so the strip scrolls instead of
/// squeezing. On a phone that means the user drags to see the whole day;
/// cramming 24 legible cells into 360 logical pixels is not possible.
const double _minCellWidth = 26;

/// Shorter than `GridMetrics.rowHeight`: this is a swatch of the grid, not a
/// row of it, and a full-height strip would dominate the settings card.
const double _cellHeight = 40;

/// Diameter of a legend dot.
const double _legendDotSize = 10;

/// Labels an hour-of-day under the user's 12h/24h preference.
///
/// Lives here rather than in the settings page because the preview's summary
/// line and the two hour fields above it must label an hour identically; two
/// copies of this drift the moment one of them starts padding.
///
/// The [DateTime] is a formatting vehicle, not an instant: [formatClock] only
/// reads its time fields. Hour 24 rolls into the next day and renders as
/// midnight, which is exactly what an exclusive end hour of 24 means.
///
/// ```dart
/// workingHourLabel(9, ClockFormat.h24);   // '09:00'
/// workingHourLabel(24, ClockFormat.h12);  // '12:00 AM'
/// ```
String workingHourLabel(int hour, ClockFormat format) =>
    formatClock(DateTime(2000, 1, 1, hour), format);

/// The 24 hour bands produced by a candidate [workingHours], rendered with the
/// real [HourCell].
///
/// This is the entire justification for the two hour fields above it
/// (docs/specs/preferences.md, Settings page): working hours are not a
/// cosmetic setting, they drive `hourBandFor` and therefore every colour in
/// the grid and every verdict in the planner. This strip is the only place a
/// user sees that consequence before committing to it.
///
/// ```dart
/// WorkingHoursPreview(
///   workingHours: const WorkingHours(startHour: 22, endHour: 6),
///   hourFormat: ClockFormat.h24,
/// );
/// ```
class WorkingHoursPreview extends StatelessWidget {
  const WorkingHoursPreview({
    required this.workingHours,
    required this.hourFormat,
    super.key,
  });

  final WorkingHours workingHours;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewHeader(workingHours: workingHours, hourFormat: hourFormat),
        const SizedBox(height: AppSpacing.sm),
        _BandStrip(workingHours: workingHours),
        const SizedBox(height: AppSpacing.md),
        const _BandLegend(),
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.workingHours, required this.hourFormat});

  final WorkingHours workingHours;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final summary = t.settings.workingHoursSummary(
      start: workingHourLabel(workingHours.startHour, hourFormat),
      end: workingHourLabel(workingHours.endHour, hourFormat),
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            t.settings.workingHoursPreview.toUpperCase(),
            style: context.textTheme.labelSmall?.copyWith(
              color: colors.onBackgroundLight,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Text(
          summary,
          style: context.textTheme.labelMedium?.copyWith(
            color: colors.onBackground,
          ),
        ),
      ],
    );
  }
}

class _BandStrip extends StatelessWidget {
  const _BandStrip({required this.workingHours});

  final WorkingHours workingHours;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Share the available width when the cells stay legible, and fall back
        // to a scrolling strip when they would not.
        final cellWidth = math.max(
          constraints.maxWidth / _hoursOfDay,
          _minCellWidth,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var hour = 0; hour < _hoursOfDay; hour++)
                // The real grid cell, not a coloured box: a preview drawn by a
                // second widget would stop matching the grid the first time
                // either one is restyled. The SizedBox tightens the cell's own
                // grid width down to whatever the strip can afford.
                SizedBox(
                  width: cellWidth,
                  child: HourCell(
                    hour: hour,
                    band: hourBandFor(hour, workingHours),
                    height: _cellHeight,
                    // 24 cells sharing one card: this strip is a legend, and
                    // the grid's comfortable cell has nowhere to go at 26pt.
                    compact: true,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// What the four fills mean. Without it the strip is a pretty gradient.
class _BandLegend extends StatelessWidget {
  const _BandLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        _LegendItem(band: HourBand.good, label: t.bands.good),
        _LegendItem(band: HourBand.fair, label: t.bands.fair),
        _LegendItem(band: HourBand.poor, label: t.bands.poor),
        _LegendItem(band: HourBand.night, label: t.bands.night),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.band, required this.label});

  final HourBand band;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _legendDotSize,
          height: _legendDotSize,
          decoration: BoxDecoration(
            // Through the same table the cells use, so the legend can never
            // claim a colour the strip does not paint.
            color: hourBandColor(band, context.appColors),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: context.textTheme.labelMedium?.copyWith(
            color: context.appColors.onBackgroundLight,
          ),
        ),
      ],
    );
  }
}

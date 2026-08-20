import 'package:flutter/material.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The sun / moon indicator on a clock row, driven by an [HourBand].
///
/// It takes the band rather than an hour so the "is this a reasonable moment"
/// decision keeps living in `hourBandFor(localHour, workingHours)` and the
/// band-to-color decision in [hourBandColor]. A dot that re-derived either
/// would be a second copy of the working-hours rule, and the copy is the one
/// that would keep painting 22:00 as asleep after the user moved to nights.
///
/// **It answers "is this person likely awake", not "is the sun up".** The band
/// already folds in the user's working window, so a night-shift user's 23:00
/// is [HourBand.good] and draws a sun. That is deliberate: an astronomical dot
/// would need a latitude and a sunrise table this app does not carry, and
/// would tell the user something they did not ask about.
///
/// ```dart
/// DayNightDot(band: hourBandFor(localTime.hour, preferences.workingHours));
/// ```
class DayNightDot extends StatelessWidget {
  const DayNightDot({required this.band, this.size = _defaultSize, super.key});

  /// The band of the local hour being shown, from `hourBandFor`.
  final HourBand band;

  /// Glyph size. Defaults to a size that sits inside a list row without
  /// pushing its line height.
  final double size;

  static const double _defaultSize = 14;

  @override
  Widget build(BuildContext context) {
    return Icon(
      band == HourBand.night ? Icons.nightlight_round : Icons.wb_sunny_rounded,
      size: size,
      color: hourBandColor(band, context.appColors),
      // Without a label the glyph is invisible to a screen reader, and the
      // band it encodes is exactly the thing a sighted user reads off it.
      semanticLabel: _semanticLabel,
    );
  }

  String get _semanticLabel => switch (band) {
    HourBand.good => t.bands.good,
    HourBand.fair => t.bands.fair,
    HourBand.poor => t.bands.poor,
    HourBand.night => t.bands.night,
  };
}

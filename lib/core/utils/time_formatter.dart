/// Rendering helpers for values that are **already wall-clock time in the
/// target zone**.
///
/// Every function here reads the calendar fields of the `DateTime` it is given
/// and prints them verbatim. None of them converts anything, and none of them
/// can tell a converted value from an unconverted one. Passing a UTC instant
/// is therefore a silent bug: it renders a plausible-looking hour that is
/// wrong for every zone except UTC, and it survives review precisely because
/// `03:00` looks like a time. Convert first with
/// `TimeZoneEngine.wallTimeAt(zoneId: ..., instant: ...)`, then format.
library;

import 'package:intl/intl.dart';
import 'package:timebuddy/core/time/time_formats.dart';

/// Formats a UTC offset as `+05:30`, `-03:00`, `+00:00`.
///
/// The sign is always present and both components are zero-padded, so labels
/// stack in a column without jitter. Minutes are rendered because offsets are
/// not whole hours: India is `+05:30`, Nepal `+05:45`, Chatham `+12:45`. Any
/// hand-rolled `'${d.inHours}h'` drops them (timezone_engine.md rule 9).
///
/// ```dart
/// offsetLabel(const Duration(hours: 5, minutes: 30));  // '+05:30'
/// offsetLabel(const Duration(hours: -3));              // '-03:00'
/// offsetLabel(Duration.zero);                          // '+00:00'
/// ```
String offsetLabel(Duration offset) {
  final magnitude = offset.abs();
  final hours = magnitude.inHours.toString().padLeft(2, '0');
  final minutes = (magnitude.inMinutes % 60).toString().padLeft(2, '0');
  return '${offset.isNegative ? '-' : '+'}$hours:$minutes';
}

/// Formats a zone-to-zone difference as `+4h` or `-3h30`, or `null` when the
/// two zones are on the same offset.
///
/// `null` rather than `'+0h'` because a row that matches the home zone should
/// show no badge at all: the absence is the information. Callers render the
/// label only when it is non-null.
///
/// ```dart
/// relativeOffsetLabel(const Duration(hours: 4));               // '+4h'
/// relativeOffsetLabel(const Duration(hours: -3, minutes: -30)); // '-3h30'
/// relativeOffsetLabel(Duration.zero);                          // null
/// ```
String? relativeOffsetLabel(Duration offset) {
  if (offset == Duration.zero) return null;
  final magnitude = offset.abs();
  final sign = offset.isNegative ? '-' : '+';
  final minutes = magnitude.inMinutes % 60;
  if (minutes == 0) return '$sign${magnitude.inHours}h';
  return '$sign${magnitude.inHours}h${minutes.toString().padLeft(2, '0')}';
}

/// Formats a wall-clock time under the user's [ClockFormat].
///
/// [localTime] must already be wall-clock time in the zone being displayed;
/// see the warning at the top of this library.
///
/// The am/pm marker follows `Intl.defaultLocale`, which the app sets from the
/// resolved locale, so a Portuguese UI gets its own marker without this
/// function taking a locale it would ignore in 24-hour mode.
///
/// ```dart
/// final wall = engine.wallTimeAt(zoneId: 'Asia/Kolkata', instant: nowUtc);
/// formatClock(wall, ClockFormat.h24);                     // '19:05'
/// formatClock(wall, ClockFormat.h12, showSeconds: true);  // '7:05:42 PM'
/// ```
String formatClock(
  DateTime localTime,
  ClockFormat format, {
  bool showSeconds = false,
}) {
  final pattern = switch (format) {
    ClockFormat.h24 => showSeconds ? 'HH:mm:ss' : 'HH:mm',
    ClockFormat.h12 => showSeconds ? 'h:mm:ss a' : 'h:mm a',
  };
  return DateFormat(pattern).format(localTime);
}

/// Formats the weekday and day-of-month of a wall-clock time, e.g. `Tue 24`.
///
/// The grid labels the date per row, never once per screen: at a given instant
/// Kiritimati and Niue are on different calendar days (timezone_engine.md,
/// date-line edge case), so one shared header would be wrong for half the
/// board.
///
/// [localTime] must already be wall-clock time in the zone being displayed.
/// [localeTag] accepts either separator (`pt-BR` or `pt_BR`); its date symbols
/// must be loaded, which `flutter_localizations` does for the app's locales.
String formatDayMonth(DateTime localTime, String localeTag) =>
    DateFormat('EEE d', localeTag).format(localTime);

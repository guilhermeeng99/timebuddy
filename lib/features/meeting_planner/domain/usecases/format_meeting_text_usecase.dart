import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';

/// Renders a summary as the plain text the copy action puts on the clipboard
/// (rule 9). Pure, and the only place that text is built: a widget
/// interpolating its own string is how two shapes become five.
///
/// The output carries no translated words at all, only values the locale
/// already decides: weekday names come from `formatDayMonth`, the clock shape
/// from [ClockFormat], and everything between them is punctuation. That is
/// deliberate. A pasted line has to survive being read by someone who is not
/// running this app in this language, and it keeps the pasteable text out of
/// the `t.planner.*` surface, where a translator editing one key would
/// silently change the format of every meeting a user has ever sent.
///
/// ```dart
/// const FormatMeetingTextUseCase()(
///   summary: summary,
///   style: MeetingTextStyle.compact,
///   hourFormat: preferences.hourFormat,
///   localeTag: preferences.localeTag ?? 'en',
/// );
/// // Sao Paulo, Tue 24, 14:00 - 15:00
/// // London, 18:00 - 19:00
/// // Los Angeles, Mon 23, 10:00 - 11:00
/// ```
class FormatMeetingTextUseCase {
  const FormatMeetingTextUseCase();

  /// One line per location, home first (rule 5), joined by newlines.
  ///
  /// [localeTag] is the tag rather than a `Locale` so this matches
  /// `formatDayMonth` and `BuildGridUseCase`, which take the same value; it
  /// accepts either separator (`pt-BR` or `pt_BR`) and its date symbols must
  /// already be loaded.
  String call({
    required MeetingSummary summary,
    required MeetingTextStyle style,
    required ClockFormat hourFormat,
    String localeTag = 'en',
  }) {
    final lines = summary.allLines;
    return [
      for (var i = 0; i < lines.length; i++)
        _lineText(
          line: lines[i],
          summary: summary,
          style: style,
          hourFormat: hourFormat,
          localeTag: localeTag,
          isHome: i == 0,
        ),
    ].join('\n');
  }

  String _lineText({
    required MeetingLine line,
    required MeetingSummary summary,
    required MeetingTextStyle style,
    required ClockFormat hourFormat,
    required String localeTag,
    required bool isHome,
  }) {
    final isVerbose = style == MeetingTextStyle.verbose;
    final parts = <String>[line.location.label];

    // Rule 5: a line is marked when its local date differs from home's. The
    // home line always carries its date because it is what the others are
    // read against, so an ordinary same-day meeting pastes as short lines and
    // a selection across midnight (rule 4) spells the dates out by itself.
    if (isVerbose || isHome || line.dayDelta != 0) {
      parts.add(formatDayMonth(line.localStart, localeTag));
    }
    parts.add(
      '${formatClock(line.localStart, hourFormat)} - '
      '${formatClock(line.localEnd, hourFormat)}',
    );

    if (!isVerbose) return parts.join(', ');
    return '${parts.join(', ')} (UTC${offsetLabel(line.offsetFromUtc)})'
        '${isHome ? ' [${_durationLabel(summary.duration)}]' : ''}';
  }

  /// The real length, as `3h` or `1h30`.
  ///
  /// Carried on the verbose home line because rule 8 makes the local times
  /// unable to say it: a meeting written `01:00 - 05:00` across a
  /// spring-forward lasts three hours, and the reader of a pasted invite has
  /// no way to know that from the two clock readings alone. Bracketed and
  /// wordless so it needs no translation and cannot be mistaken for a third
  /// time of day.
  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes.abs() % 60;
    if (minutes == 0) return '${duration.inHours}h';
    return '${duration.inHours}h${minutes.toString().padLeft(2, '0')}';
  }
}

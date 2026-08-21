import 'package:flutter/material.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// `Tue 24 · Tomorrow`: which calendar day a row's reading belongs to.
///
/// The line under the digits on a world-clock tile and under the reading on a
/// converter row. Both drew it themselves, from the same `Text.rich`, the same
/// accented `' · $dayWord'` span and the same `maxLines`/`overflow`/`textAlign`
/// — the two questions ("what time is it there now" and "what time is it there
/// then") differ, but the answer's date half does not (world_clock.md rule 6,
/// time_converter.md rule 7).
///
/// It is a single span rather than two `Text`s: two `Flexible`s split the free
/// width evenly regardless of what they need, so `Tomorrow` would ellipsize
/// beside a `Tue 24` sitting in half a column it never asked for. One line
/// lays out once and clips at its own end.
///
/// [localTime] must already be wall-clock time in the zone being shown —
/// `formatDayMonth` reads its calendar fields verbatim and cannot tell a
/// converted value from a raw UTC instant.
///
/// ```dart
/// LocalDateLine(localTime: tile.localTime, dayDelta: tile.dayDelta);
/// ```
class LocalDateLine extends StatelessWidget {
  const LocalDateLine({
    required this.localTime,
    required this.dayDelta,
    super.key,
  });

  /// Wall-clock time in the zone this row is about.
  final DateTime localTime;

  /// Calendar days from the reference zone's date to this one's, for
  /// [relativeDayWord].
  final int dayDelta;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dayWord = relativeDayWord(dayDelta);
    // Per row, never once per page: at a single instant two cities can be on
    // different calendar dates, which is the whole point of the rule.
    final localeTag = LocaleSettings.currentLocale.languageTag;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: formatDayMonth(localTime, localeTag)),
          if (dayWord != null)
            TextSpan(
              text: ' · $dayWord',
              // The accent, because on a board that crosses the date line this
              // is the fact the user came for.
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.primaryInk,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: context.textTheme.labelMedium?.copyWith(
        color: colors.onBackgroundLight,
      ),
    );
  }
}

/// "Tomorrow" / "Yesterday" for a day delta, or `null` when there is nothing
/// to say (world_clock.md rule 6, time_converter.md rule 7).
///
/// `null` for `0` because the row then shares the reference zone's date, and
/// also for the `±2` a Kiritimati-to-Niue board really can produce: naming
/// that "Yesterday" would be wrong by a day, and the date beside it is already
/// exact.
///
/// Public and outside [LocalDateLine] because the location detail sheet needs
/// the word without the line: it renders the same two facts in one plain
/// `bodyMedium` string rather than in an accented span, and reaching for the
/// widget there would repaint the sheet.
///
/// ```dart
/// relativeDayWord(1);   // 'Tomorrow'
/// relativeDayWord(-2);  // null
/// ```
String? relativeDayWord(int dayDelta) => switch (dayDelta) {
  1 => t.worldClock.tomorrow,
  -1 => t.worldClock.yesterday,
  _ => null,
};

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';

import '../../harness/helpers.dart';

void main() {
  // The app gets its date symbols from flutter_localizations; a test process
  // has to load them itself, or every locale but en_US falls back to English.
  setUpAll(initializeDateFormatting);

  // formatClock reads the am/pm marker from the ambient locale, so pin it
  // rather than inherit whatever the host reports.
  setUp(() => Intl.defaultLocale = 'en_US');
  tearDown(() => Intl.defaultLocale = null);

  // These functions read calendar fields and print them verbatim: they are
  // given wall-clock time, not an instant. Building the values with utcDate
  // keeps the fields identical on every machine (a bare DateTime(...) would
  // be host-local) without implying a conversion happened here.
  final evening = utcDate(2024, 9, 24, 19, 5, 42);
  final morning = utcDate(2024, 9, 24, 7, 5);
  final justAfterMidnight = utcDate(2024, 9, 24, 0, 5);

  group('offsetLabel', () {
    test('renders a positive whole-hour offset', () {
      expect(offsetLabel(const Duration(hours: 4)), '+04:00');
    });

    test('renders a negative whole-hour offset', () {
      expect(offsetLabel(const Duration(hours: -3)), '-03:00');
    });

    test('renders zero with a sign and full padding', () {
      expect(offsetLabel(Duration.zero), '+00:00');
    });

    test('keeps the minutes of a fractional-hour zone', () {
      expect(offsetLabel(const Duration(hours: 5, minutes: 30)), '+05:30');
      expect(offsetLabel(const Duration(hours: 5, minutes: 45)), '+05:45');
      expect(offsetLabel(const Duration(hours: 12, minutes: 45)), '+12:45');
    });

    test('keeps the minutes of a negative fractional-hour zone', () {
      // Marquesas, -09:30: the case a hand-rolled '${d.inHours}h' rounds away.
      expect(offsetLabel(const Duration(hours: -9, minutes: -30)), '-09:30');
      expect(offsetLabel(const Duration(hours: -3, minutes: -30)), '-03:30');
    });

    test('renders every offset at the same width, so a column lines up', () {
      final labels = [
        offsetLabel(const Duration(hours: 14)),
        offsetLabel(const Duration(hours: -11)),
        offsetLabel(const Duration(hours: 5, minutes: 45)),
        offsetLabel(Duration.zero),
      ];
      expect(labels.map((label) => label.length).toSet(), {6});
    });
  });

  group('relativeOffsetLabel', () {
    test('returns null for a zone on the same offset as home', () {
      // Absence is the information: the row shows no badge at all.
      expect(relativeOffsetLabel(Duration.zero), isNull);
    });

    test('renders a whole-hour difference without minutes', () {
      expect(relativeOffsetLabel(const Duration(hours: 4)), '+4h');
      expect(relativeOffsetLabel(const Duration(hours: -1)), '-1h');
      expect(relativeOffsetLabel(const Duration(hours: 11)), '+11h');
    });

    test('renders a negative fractional difference as -3h30', () {
      expect(
        relativeOffsetLabel(const Duration(hours: -3, minutes: -30)),
        '-3h30',
      );
    });

    test('renders a positive fractional difference', () {
      expect(
        relativeOffsetLabel(const Duration(hours: 5, minutes: 30)),
        '+5h30',
      );
      expect(
        relativeOffsetLabel(const Duration(hours: 12, minutes: 45)),
        '+12h45',
      );
    });

    test('renders a sub-hour difference, which real zone pairs produce', () {
      // Kolkata to Kathmandu is 15 minutes apart.
      expect(relativeOffsetLabel(const Duration(minutes: 15)), '+0h15');
    });
  });

  group('formatClock', () {
    test('renders 24 hour time with a padded hour', () {
      expect(formatClock(evening, ClockFormat.h24), '19:05');
      expect(formatClock(morning, ClockFormat.h24), '07:05');
      expect(formatClock(justAfterMidnight, ClockFormat.h24), '00:05');
    });

    test('renders 24 hour time with seconds when asked', () {
      expect(
        formatClock(evening, ClockFormat.h24, showSeconds: true),
        '19:05:42',
      );
    });

    test('renders 12 hour time with an am/pm marker and no padded hour', () {
      expect(formatClock(evening, ClockFormat.h12), '7:05 PM');
      expect(formatClock(morning, ClockFormat.h12), '7:05 AM');
      expect(formatClock(justAfterMidnight, ClockFormat.h12), '12:05 AM');
    });

    test('renders 12 hour time with seconds when asked', () {
      expect(
        formatClock(evening, ClockFormat.h12, showSeconds: true),
        '7:05:42 PM',
      );
    });

    test('omits seconds by default, so the digits do not jump width', () {
      expect(formatClock(evening, ClockFormat.h24).length, 5);
      expect(formatClock(evening, ClockFormat.h12), isNot(contains(':42')));
    });
  });

  group('formatDayMonth', () {
    final tuesday = utcDate(2024, 9, 24);

    test('renders the weekday and day of month in English', () {
      expect(formatDayMonth(tuesday, 'en'), 'Tue 24');
    });

    test('renders the weekday in the requested locale', () {
      final label = formatDayMonth(tuesday, 'pt-BR');
      expect(label.toLowerCase(), startsWith('ter'));
      expect(label, contains('24'));
      expect(label, isNot(formatDayMonth(tuesday, 'en')));
    });

    test('accepts either locale separator', () {
      expect(
        formatDayMonth(tuesday, 'pt_BR'),
        formatDayMonth(tuesday, 'pt-BR'),
      );
    });

    test('labels each row from its own date, not from a shared header', () {
      // At one instant Kiritimati and Niue are on different calendar days, so
      // two rows of the same grid legitimately disagree here.
      final wednesday = utcDate(2024, 9, 25);
      expect(formatDayMonth(wednesday, 'en'), 'Wed 25');
    });
  });
}

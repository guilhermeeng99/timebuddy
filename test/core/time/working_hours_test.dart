import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/working_hours.dart';

void main() {
  const dayShift = WorkingHours.defaultHours;
  const nightShift = WorkingHours(startHour: 22, endHour: 6);

  group('defaultHours', () {
    test('is the 09-17 window and is itself valid', () {
      expect(dayShift.startHour, 9);
      expect(dayShift.endHour, 17);
      expect(dayShift.lengthInHours, 8);
      expect(dayShift.isValid, isTrue);
    });

    test('pins the length bounds the settings form relies on', () {
      expect(WorkingHours.minLength, 1);
      expect(WorkingHours.maxLength, 16);
    });
  });

  group('contains', () {
    test('is inclusive at the start and exclusive at the end', () {
      expect(dayShift.contains(9), isTrue);
      expect(dayShift.contains(16), isTrue);
      expect(dayShift.contains(17), isFalse);
      expect(dayShift.contains(8), isFalse);
    });

    test('wraps past midnight', () {
      expect(nightShift.contains(22), isTrue);
      expect(nightShift.contains(23), isTrue);
      expect(nightShift.contains(0), isTrue);
      expect(nightShift.contains(5), isTrue);
      expect(nightShift.contains(6), isFalse);
      expect(nightShift.contains(21), isFalse);
    });

    test('covers exactly lengthInHours hours', () {
      for (final window in [dayShift, nightShift]) {
        final covered = [
          for (var hour = 0; hour < 24; hour++)
            if (window.contains(hour)) hour,
        ];
        expect(covered, hasLength(window.lengthInHours), reason: '$window');
      }
    });

    test('takes the hour modulo 24, so neighbours need no guard', () {
      // hourBandFor passes (hour + 1) % 24 and (hour + 23) % 24 straight in;
      // the same tolerance keeps any other caller from having to normalise.
      expect(nightShift.contains(24), nightShift.contains(0));
      expect(nightShift.contains(25), nightShift.contains(1));
      expect(nightShift.contains(-1), nightShift.contains(23));
      expect(dayShift.contains(-15), dayShift.contains(9));
    });

    test('excludes midnight when the window ends at 24', () {
      const untilMidnight = WorkingHours(startHour: 9, endHour: 24);
      expect(untilMidnight.contains(23), isTrue);
      expect(untilMidnight.contains(0), isFalse);
    });

    test('covers every hour when the window is a full day', () {
      const allDay = WorkingHours(startHour: 0, endHour: 24);
      for (var hour = 0; hour < 24; hour++) {
        expect(allDay.contains(hour), isTrue, reason: 'hour $hour');
      }
    });
  });

  group('lengthInHours', () {
    test('measures a same-day window as the plain difference', () {
      expect(dayShift.lengthInHours, 8);
      expect(const WorkingHours(startHour: 9, endHour: 24).lengthInHours, 15);
    });

    test('measures a wrapping window across midnight', () {
      expect(nightShift.lengthInHours, 8);
      expect(const WorkingHours(startHour: 20, endHour: 4).lengthInHours, 8);
      // Measured before isValid gets a say: a 0 end is rejected there, not
      // here, so the arithmetic still has to be well defined for it.
      expect(const WorkingHours(startHour: 23, endHour: 0).lengthInHours, 1);
    });

    test('reads a start equal to the end as a full day, not an empty one', () {
      expect(const WorkingHours(startHour: 9, endHour: 9).lengthInHours, 24);
    });
  });

  group('isValid', () {
    test('accepts a window of exactly the minimum length', () {
      expect(const WorkingHours(startHour: 9, endHour: 10).isValid, isTrue);
      expect(const WorkingHours(startHour: 23, endHour: 24).isValid, isTrue);
    });

    test('accepts a window of exactly the maximum length', () {
      expect(const WorkingHours(startHour: 0, endHour: 16).isValid, isTrue);
      expect(const WorkingHours(startHour: 22, endHour: 14).isValid, isTrue);
    });

    test('rejects a window one hour past the maximum length', () {
      expect(const WorkingHours(startHour: 0, endHour: 17).isValid, isFalse);
      expect(const WorkingHours(startHour: 22, endHour: 15).isValid, isFalse);
    });

    test('rejects a full day, which start == end produces', () {
      expect(const WorkingHours(startHour: 9, endHour: 9).isValid, isFalse);
      expect(const WorkingHours(startHour: 0, endHour: 24).isValid, isFalse);
    });

    test('rejects hours outside the clock before doing span arithmetic', () {
      expect(const WorkingHours(startHour: -1, endHour: 8).isValid, isFalse);
      expect(const WorkingHours(startHour: 24, endHour: 8).isValid, isFalse);
      expect(const WorkingHours(startHour: 9, endHour: 25).isValid, isFalse);
    });

    test('rejects an end of 0, because midnight is written as 24', () {
      expect(const WorkingHours(startHour: 9, endHour: 0).isValid, isFalse);
    });
  });

  group('clamped', () {
    test('returns the same instance when the window is valid', () {
      expect(dayShift.clamped(), same(dayShift));
      expect(nightShift.clamped(), same(nightShift));
    });

    test('falls back to the defaults for an over-long window', () {
      expect(
        const WorkingHours(startHour: 0, endHour: 17).clamped(),
        WorkingHours.defaultHours,
      );
    });

    test('falls back to the defaults for out-of-range hours', () {
      expect(
        const WorkingHours(startHour: -3, endHour: 40).clamped(),
        WorkingHours.defaultHours,
      );
    });

    test('never partially repairs a window', () {
      // 09-00 could plausibly be read as 09-24, but a pair that survived a bad
      // parse carries no intent worth guessing at.
      expect(
        const WorkingHours(startHour: 9, endHour: 0).clamped(),
        WorkingHours.defaultHours,
      );
    });
  });

  group('copyWith', () {
    test('replaces only the field it is given', () {
      final extended = dayShift.copyWith(endHour: 18);
      expect(extended.startHour, 9);
      expect(extended.endHour, 18);
      expect(extended.lengthInHours, 9);
    });

    test('returns an equal window when given nothing', () {
      expect(dayShift.copyWith(), dayShift);
    });
  });

  group('equality', () {
    test('compares by value, not identity', () {
      expect(
        const WorkingHours(startHour: 22, endHour: 6),
        const WorkingHours(startHour: 22, endHour: 6),
      );
      expect(nightShift, isNot(dayShift));
    });

    test('exposes both ends as props', () {
      expect(dayShift.props, [9, 17]);
    });
  });
}

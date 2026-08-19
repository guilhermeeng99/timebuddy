import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/working_hours.dart';

void main() {
  const dayShift = WorkingHours.defaultHours;
  const nightShift = WorkingHours(startHour: 22, endHour: 6);
  const afternoon = WorkingHours(startHour: 14, endHour: 18);
  const earlyMorning = WorkingHours(startHour: 0, endHour: 8);
  const untilMidnight = WorkingHours(startHour: 16, endHour: 24);

  // The two windows below are spelled out hour by hour instead of being
  // derived from the rules, so a change in the classification shows up as a
  // diff on the exact hour that moved rather than as a green test.
  const dayShiftBands = <HourBand>[
    HourBand.night, // 00
    HourBand.night, // 01
    HourBand.night, // 02
    HourBand.night, // 03
    HourBand.night, // 04
    HourBand.night, // 05
    HourBand.night, // 06
    HourBand.poor, // 07
    HourBand.fair, // 08
    HourBand.good, // 09
    HourBand.good, // 10
    HourBand.good, // 11
    HourBand.good, // 12
    HourBand.good, // 13
    HourBand.good, // 14
    HourBand.good, // 15
    HourBand.good, // 16
    HourBand.fair, // 17
    HourBand.poor, // 18
    HourBand.poor, // 19
    HourBand.poor, // 20
    HourBand.poor, // 21
    HourBand.poor, // 22
    HourBand.night, // 23
  ];

  const nightShiftBands = <HourBand>[
    HourBand.good, // 00
    HourBand.good, // 01
    HourBand.good, // 02
    HourBand.good, // 03
    HourBand.good, // 04
    HourBand.good, // 05
    HourBand.fair, // 06
    HourBand.poor, // 07
    HourBand.poor, // 08
    HourBand.poor, // 09
    HourBand.poor, // 10
    HourBand.poor, // 11
    HourBand.poor, // 12
    HourBand.poor, // 13
    HourBand.poor, // 14
    HourBand.poor, // 15
    HourBand.poor, // 16
    HourBand.poor, // 17
    HourBand.poor, // 18
    HourBand.poor, // 19
    HourBand.poor, // 20
    HourBand.fair, // 21
    HourBand.good, // 22
    HourBand.good, // 23
  ];

  group('hourBandFor', () {
    test('classifies every hour against the default 09-17 window', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(
          hourBandFor(hour, dayShift),
          dayShiftBands[hour],
          reason: 'local hour $hour',
        );
      }
    });

    test('classifies every hour against a 22-06 night-shift window', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(
          hourBandFor(hour, nightShift),
          nightShiftBands[hour],
          reason: 'local hour $hour',
        );
      }
    });

    group('step 1, inside the window', () {
      test('reads good on the inclusive start and the last covered hour', () {
        expect(hourBandFor(9, dayShift), HourBand.good);
        expect(hourBandFor(16, dayShift), HourBand.good);
      });

      test('reads good across midnight for a night shift', () {
        // The case the whole precedence order exists for: 23:00 and 02:00 are
        // working hours for a 22-06 window, so they must not read as night.
        expect(hourBandFor(23, nightShift), HourBand.good);
        expect(hourBandFor(2, nightShift), HourBand.good);
      });

      test('reads good for every hour of a 24 hour window', () {
        // hourBandFor classifies whatever window it is handed; rejecting an
        // over-long one is WorkingHours.clamped's job, upstream of here.
        const allDay = WorkingHours(startHour: 0, endHour: 24);
        for (var hour = 0; hour < 24; hour++) {
          expect(hourBandFor(hour, allDay), HourBand.good, reason: '$hour');
        }
      });
    });

    group('step 2, the shoulder hours', () {
      test('reads fair on either side of a 09-17 window', () {
        expect(hourBandFor(8, dayShift), HourBand.fair);
        expect(hourBandFor(17, dayShift), HourBand.fair);
      });

      test('reads fair on either side of a 14-18 window', () {
        expect(hourBandFor(13, afternoon), HourBand.fair);
        expect(hourBandFor(18, afternoon), HourBand.fair);
      });

      test('wraps past midnight when looking for the neighbour hour', () {
        // 23:00 sits one hour before a 00-08 window, so the shoulder check
        // has to wrap; without the wrap it would fall through to night.
        expect(hourBandFor(23, earlyMorning), HourBand.fair);
        expect(hourBandFor(0, untilMidnight), HourBand.fair);
      });

      test('beats the night window even when the hour is a night hour', () {
        expect(hourBandFor(6, nightShift), HourBand.fair);
        expect(hourBandFor(8, earlyMorning), HourBand.fair);
      });
    });

    group('step 3, the fixed night window', () {
      test('reads night from 23:00 through 06:59 when no window claims it', () {
        for (final hour in [23, 0, 3, 6]) {
          expect(hourBandFor(hour, dayShift), HourBand.night, reason: '$hour');
        }
      });

      test('stops at 07:00, which is poor rather than night', () {
        expect(hourBandFor(7, dayShift), HourBand.poor);
      });

      test('starts at 23:00, so 22:00 is poor rather than night', () {
        expect(hourBandFor(22, dayShift), HourBand.poor);
        expect(hourBandFor(23, dayShift), HourBand.night);
      });

      test('never applies to a night-shift window', () {
        final bands = [
          for (var hour = 0; hour < 24; hour++)
            hourBandFor(hour, nightShift),
        ];
        expect(bands, isNot(contains(HourBand.night)));
      });
    });

    group('step 4, everything else', () {
      test('reads poor for a waking hour outside every window', () {
        expect(hourBandFor(11, afternoon), HourBand.poor);
        expect(hourBandFor(19, dayShift), HourBand.poor);
      });

      test('reads poor for the hour two steps outside the window', () {
        expect(hourBandFor(12, afternoon), HourBand.poor);
        expect(hourBandFor(20, afternoon), HourBand.poor);
      });
    });
  });
}

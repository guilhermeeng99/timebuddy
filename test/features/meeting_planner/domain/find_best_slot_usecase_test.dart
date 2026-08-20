import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/find_best_slot_usecase.dart';

import '../../../harness/helpers.dart';

// The search is scored through `hourBandFor`, so every expectation below is
// read off one working window and one real day:
//
//   WorkingHours.defaultHours is 09:00-17:00, which makes 09..16 good, 08 and
//     17 fair, 07 and 18..22 poor, and 23..06 night.
//   UTC never moves, so a slot index on 2024-09-24 is its own hour and the
//     arithmetic under test is the scoring, not the tzdata.
//   Europe/Berlin is CEST (+02:00) on 2024-09-24: DST there ends on 27
//     October, so this date is inside the summer rules.
//   Asia/Tokyo is +09:00 all year, no DST.
//   America/New_York falls back on 3 November 2024 at 06:00 UTC, so that
//     local day holds 25 slots and its first local 09:00 sits at index 10,
//     not 9.

const String _utc = 'UTC';
const String _berlin = 'Europe/Berlin';
const String _newYork = 'America/New_York';
const String _tokyo = 'Asia/Tokyo';

/// A zone id no tzdata release will ever carry.
const String _unknownZone = 'Mars/Olympus_Mons';

SavedLocationEntity _location(String zoneId, int sortIndex) =>
    SavedLocationEntity(
      id: 'row-$sortIndex-$zoneId',
      zoneId: zoneId,
      label: zoneId.split('/').last.replaceAll('_', ' '),
      countryCode: 'ZZ',
      sortIndex: sortIndex,
      addedAt: utcDate(2024),
    );

BoardEntity _board(String homeZoneId, List<String> zoneIds) => BoardEntity(
  homeZoneId: homeZoneId,
  locations: [
    for (var i = 0; i < zoneIds.length; i++) _location(zoneIds[i], i),
  ],
  revision: 3,
  updatedAt: utcDate(2024),
);

void main() {
  final engine = TzTimeZoneEngine();
  final findBestSlot = FindBestSlotUseCase(engine: engine);

  setUpAll(() async {
    initTestTimeZones();
    await engine.initialize();
  });

  List<DateTime> daySlotsOf(String zoneId, DateTime localDate) =>
      engine.dayIn(zoneId: zoneId, localDate: localDate).hours;

  MeetingSelection? bestSlot({
    required String home,
    required List<DateTime> daySlots,
    int slotCount = 1,
    List<String> zoneIds = const [],
    WorkingHours workingHours = WorkingHours.defaultHours,
  }) {
    return findBestSlot(
      board: _board(home, zoneIds),
      daySlots: daySlots,
      slotCount: slotCount,
      workingHours: workingHours,
    );
  }

  group('rule 7: the search minimises how badly the range lands', () {
    test('it picks the earliest hour every row is good', () {
      // UTC is good 09..16 and Berlin, on +02:00, is good 07..14, so the two
      // overlap from 09:00 UTC and the earliest of those wins.
      final best = bestSlot(
        home: _utc,
        zoneIds: [_berlin],
        daySlots: daySlotsOf(_utc, utcDate(2024, 9, 24)),
      );

      expect(best, isNotNull);
      expect(best!.startInstant, utcDate(2024, 9, 24, 9));
      expect(best.endInstant, utcDate(2024, 9, 24, 10));
      expect(best.slotCount, 1);
    });

    test('the home zone is scored even with no row of its own', () {
      // Home has no board row here, so it is the only zone there is to
      // score. Leaving it out would make every range in the day cost
      // nothing, which reads as "nothing improves" and answers null.
      final best = bestSlot(
        home: _utc,
        daySlots: daySlotsOf(_utc, utcDate(2024, 9, 24)),
      );

      expect(best!.startInstant, utcDate(2024, 9, 24, 9));
    });

    test('a poor row costs more than a fair one', () {
      // 17:00 is the shoulder of the window and 18:00 is outside it. Counting
      // the two buckets together, or counting fair first, would pick 18:00.
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));
      final best = bestSlot(home: _utc, daySlots: day.sublist(17, 19));

      expect(best!.startInstant, utcDate(2024, 9, 24, 17));
    });

    test('a row asleep costs more than a row merely off-hours', () {
      // 22:00 is poor and 23:00 is night. The spec names two buckets because
      // it names three verdicts; HourBand carries a fourth and it is worse.
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));
      final best = bestSlot(home: _utc, daySlots: day.sublist(22, 24));

      expect(best!.startInstant, utcDate(2024, 9, 24, 22));
      expect(best.endInstant, utcDate(2024, 9, 24, 23));
    });

    test('a tie breaks toward the earlier start', () {
      // 15:00 and 16:00 are both good; 17:00 is fair and 18:00 poor.
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));
      final best = bestSlot(home: _utc, daySlots: day.sublist(15, 19));

      expect(best!.startInstant, utcDate(2024, 9, 24, 15));
    });

    test('a longer range is scored over every hour it covers', () {
      // 09:00-12:00 is the earliest three-hour stretch nobody pays for; an
      // 08:00 start would drag one fair hour in with it.
      final best = bestSlot(
        home: _utc,
        daySlots: daySlotsOf(_utc, utcDate(2024, 9, 24)),
        slotCount: 3,
      );

      expect(best!.startInstant, utcDate(2024, 9, 24, 9));
      expect(best.endInstant, utcDate(2024, 9, 24, 12));
      expect(best.slotCount, 3);
    });

    test('a range ending on the last column still ends at a real instant', () {
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));
      final best = bestSlot(
        home: _utc,
        daySlots: day.sublist(15, 19),
        slotCount: 2,
      );

      expect(best!.startInstant, utcDate(2024, 9, 24, 15));
      expect(best.endInstant, utcDate(2024, 9, 24, 17));
      expect(best.slotCount, 2);
    });
  });

  group('rule 7: nothing to improve on gives no suggestion', () {
    test('a day whose every range is equally good suggests nothing', () {
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));

      expect(bestSlot(home: _utc, daySlots: day.sublist(9, 13)), isNull);
    });

    test('a day whose every range is equally bad suggests nothing', () {
      // The "every row is poor" edge case: an equally bad alternative is
      // worse than none, so the panel says there is none.
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));

      expect(bestSlot(home: _utc, daySlots: day.sublist(1, 5)), isNull);
    });

    test('a range longer than the day suggests nothing', () {
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));

      expect(
        bestSlot(home: _utc, daySlots: day.sublist(9, 11), slotCount: 3),
        isNull,
      );
    });

    test('a slot count outside rule 3 suggests nothing', () {
      final day = daySlotsOf(_utc, utcDate(2024, 9, 24));

      expect(bestSlot(home: _utc, daySlots: day, slotCount: 0), isNull);
      expect(
        bestSlot(
          home: _utc,
          daySlots: day,
          slotCount: MeetingSelection.maxSlots + 1,
        ),
        isNull,
      );
    });

    test('an empty day suggests nothing', () {
      expect(bestSlot(home: _utc, daySlots: const []), isNull);
    });
  });

  group('the search reads the day it was handed', () {
    test('a 25-hour day is searched to its real length', () {
      final day = daySlotsOf(_newYork, utcDate(2024, 11, 3));
      final best = bestSlot(home: _newYork, daySlots: day);

      // 01:00 happens twice on that day, so the first local 09:00 is column
      // 10. A search that assumed 24 columns would land an hour early, on a
      // fair 08:00.
      expect(day, hasLength(25));
      expect(best!.startInstant, utcDate(2024, 11, 3, 14));
      expect(
        engine.wallTimeAt(zoneId: _newYork, instant: best.startInstant),
        utcDate(2024, 11, 3, 9),
      );
    });

    test('a row the tzdata cannot resolve is not scored as UTC', () {
      final day = daySlotsOf(_tokyo, utcDate(2024, 9, 24));
      final withJunk = bestSlot(
        home: _tokyo,
        zoneIds: [_unknownZone],
        daySlots: day,
      );

      // Tokyo alone is good from its own 09:00, which is 00:00 UTC. A junk
      // row degraded to UTC would be asleep then and push the answer to
      // 08:00 UTC, so this pins that it is dropped rather than degraded.
      expect(withJunk, bestSlot(home: _tokyo, daySlots: day));
      expect(withJunk!.startInstant, utcDate(2024, 9, 24));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/build_meeting_summary_usecase.dart';

import '../../../harness/helpers.dart';

// Every instant below is a real IANA transition or a real fixed offset,
// pinned to its year, because an offset is a function of an instant:
//
//   America/Sao_Paulo - DST abolished in 2019, so it sits at -03:00 all
//     through 2024 and makes a reference row whose clocks never move. Local
//     midnight on 2024-09-24 is therefore 03:00 UTC.
//   America/New_York 2024 - springs forward 10 March, 02:00 EST -> 03:00 EDT
//     at 07:00 UTC, so that local day holds 23 slots and its slot list runs
//     00:00, 01:00, 03:00, 04:00; falls back 3 November, 02:00 EDT -> 01:00
//     EST at 06:00 UTC, so that one holds 25 and reads 01:00 twice.
//   Asia/Tokyo is +09:00 and Asia/Kolkata +05:30 all year, no DST.
//   Pacific/Kiritimati is +14:00 and Pacific/Niue -11:00 all year: 25 hours
//     apart, which is how two lines of one summary land on different dates.

const String _saoPaulo = 'America/Sao_Paulo';
const String _saoPauloLegacy = 'Brazil/East';
const String _newYork = 'America/New_York';
const String _london = 'Europe/London';
const String _tokyo = 'Asia/Tokyo';
const String _kolkata = 'Asia/Kolkata';
const String _kiritimati = 'Pacific/Kiritimati';
const String _niue = 'Pacific/Niue';

/// A zone id no tzdata release will ever carry, so `zoneOrNull` returns null
/// and the row takes the dropped path.
const String _unknownZone = 'Mars/Olympus_Mons';

/// The night shift of preferences rule 4, which `hourBandFor` must score
/// ahead of its fixed night window.
const WorkingHours _nightShift = WorkingHours(startHour: 22, endHour: 6);

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

MeetingLine _line(MeetingSummary summary, String zoneId) =>
    summary.lines.firstWhere((line) => line.location.zoneId == zoneId);

void main() {
  final engine = TzTimeZoneEngine();
  final buildSummary = BuildMeetingSummaryUseCase(engine: engine);

  setUpAll(() async {
    initTestTimeZones();
    await engine.initialize();
  });

  List<DateTime> daySlotsOf(String zoneId, DateTime localDate) =>
      engine.dayIn(zoneId: zoneId, localDate: localDate).hours;

  /// A selection of [slotCount] columns starting at [startInstant], with the
  /// end derived the way the grid derives it: one real hour per column.
  MeetingSelection selectionAt(DateTime startInstant, int slotCount) =>
      MeetingSelection(
        startInstant: startInstant,
        endInstant: startInstant.add(Duration(hours: slotCount)),
        slotCount: slotCount,
      );

  MeetingSummary summaryOf({
    required String home,
    required MeetingSelection selection,
    List<String> zoneIds = const [],
    WorkingHours workingHours = WorkingHours.defaultHours,
    MeetingSelection? suggestion,
  }) {
    return buildSummary(
      board: _board(home, zoneIds),
      selection: selection,
      workingHours: workingHours,
      suggestion: suggestion,
    );
  }

  group('rule 1 and rule 3: a selection is instants, capped at 12 slots', () {
    // Sao Paulo never moves its clocks in 2024, so these indexes are stable
    // hours and the arithmetic under test is the clamping, not the tzdata.
    late List<DateTime> slots;

    setUp(() {
      slots = daySlotsOf(_saoPaulo, utcDate(2024, 9, 24));
    });

    test('one column is one slot ending at the next column', () {
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 14,
        cursorIndex: 14,
      );

      expect(selection.slotCount, 1);
      // Local 14:00 in Sao Paulo, which is -03:00 all year.
      expect(selection.startInstant, utcDate(2024, 9, 24, 17));
      expect(selection.endInstant, utcDate(2024, 9, 24, 18));
    });

    test('a backwards drag selects the same range as a forwards one', () {
      final forwards = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 14,
        cursorIndex: 16,
      );
      final backwards = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 16,
        cursorIndex: 14,
      );

      expect(forwards, backwards);
      expect(forwards.slotCount, 3);
      expect(forwards.endInstant, utcDate(2024, 9, 24, 20));
    });

    test('dragging forwards past the cap stops at 12 slots', () {
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 0,
        cursorIndex: 23,
      );

      expect(selection.slotCount, MeetingSelection.maxSlots);
      expect(selection.startInstant, slots[0]);
      expect(selection.endInstant, slots[12]);
    });

    test('dragging backwards past the cap leaves the anchor where it is', () {
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 20,
        cursorIndex: 0,
      );

      expect(selection.slotCount, MeetingSelection.maxSlots);
      // The cap is measured from the anchor, so the end the user is holding
      // still is the one that survives.
      expect(selection.startInstant, slots[9]);
      expect(selection.endInstant, slots[21]);
    });

    test('indexes outside the column set are pulled inside it', () {
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: -5,
        cursorIndex: 100,
      );

      expect(selection.startInstant, slots.first);
      expect(selection.slotCount, MeetingSelection.maxSlots);
    });

    test('a range ending on the last column still ends at a real instant', () {
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: slots.length - 1,
        cursorIndex: slots.length - 1,
      );

      expect(selection.startInstant, slots.last);
      expect(selection.endInstant, slots.last.add(const Duration(hours: 1)));
    });

    test('a selection needs at least one column to sit on', () {
      expect(
        () => MeetingSelection.fromSlots(
          slots: const [],
          anchorIndex: 0,
          cursorIndex: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('rule 5: home leads, then board order', () {
    test('the home row leads and is not repeated in the lines', () {
      final summary = summaryOf(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _tokyo],
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      expect(summary.home.location.zoneId, _saoPaulo);
      expect(summary.home.location.id, 'row-0-$_saoPaulo');
      expect(summary.lines.map((line) => line.location.zoneId), [_tokyo]);
    });

    test('a home zone with no board row still gets a stand-in line', () {
      final summary = summaryOf(
        home: _london,
        zoneIds: [_tokyo],
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      expect(summary.home.location.zoneId, _london);
      // The empty id is what marks a row that is not on the board, so nothing
      // downstream can mistake it for one and write it back.
      expect(summary.home.location.id, isEmpty);
      expect(summary.lines, hasLength(1));
    });

    test('a legacy alias of the home zone is the home row, not a line', () {
      final summary = summaryOf(
        home: _saoPaulo,
        zoneIds: [_saoPauloLegacy, _tokyo],
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      expect(summary.home.location.zoneId, _saoPauloLegacy);
      expect(summary.lines.map((line) => line.location.zoneId), [_tokyo]);
    });

    test('a row whose zone the tzdata cannot resolve is left out', () {
      final summary = summaryOf(
        home: _saoPaulo,
        zoneIds: [_tokyo, _unknownZone],
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      // Degrading it to UTC would paste a plausible, wrong hour into a
      // message, which is worse than one line short.
      expect(summary.lines.map((line) => line.location.zoneId), [_tokyo]);
    });

    test('the ordering of allLines is home first, then the board', () {
      final summary = summaryOf(
        home: _london,
        zoneIds: [_tokyo, _kolkata],
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      expect(summary.allLines.map((line) => line.location.zoneId), [
        _london,
        _tokyo,
        _kolkata,
      ]);
    });
  });

  group('rule 6: the verdict is the worst band in the range', () {
    test('a range entirely inside the working window is good', () {
      // 13:00 UTC is 10:00 in Sao Paulo; the range covers 10, 11 and 12.
      final summary = summaryOf(
        home: _saoPaulo,
        selection: selectionAt(utcDate(2024, 9, 24, 13), 3),
      );

      expect(summary.home.verdict, HourBand.good);
    });

    test('one fair hour at the end drags the whole range to fair', () {
      // 18:00 UTC is 15:00 in Sao Paulo; the range covers 15, 16 and 17, and
      // 17:00 is the shoulder of a 09:00-17:00 window.
      final summary = summaryOf(
        home: _saoPaulo,
        selection: selectionAt(utcDate(2024, 9, 24, 18), 3),
      );

      expect(summary.home.verdict, HourBand.fair);
    });

    test('one poor hour at the end drags the whole range to poor', () {
      // 19:00 UTC is 16:00 in Sao Paulo; the range covers 16, 17 and 18.
      final summary = summaryOf(
        home: _saoPaulo,
        selection: selectionAt(utcDate(2024, 9, 24, 19), 3),
      );

      expect(summary.home.verdict, HourBand.poor);
    });

    test('a row asleep for the whole range is night', () {
      // The same instants read 04:00, 05:00 and 06:00 in Tokyo.
      final summary = summaryOf(
        home: _saoPaulo,
        zoneIds: [_tokyo],
        selection: selectionAt(utcDate(2024, 9, 24, 19), 3),
      );

      expect(_line(summary, _tokyo).verdict, HourBand.night);
    });

    test('the verdict follows the user working window, not the clock', () {
      // 02:00 UTC on the 25th is 23:00 in Sao Paulo; the range covers 23, 00
      // and 01, which a night shift is awake for and the default window is
      // not (preferences rule 4).
      final selection = selectionAt(utcDate(2024, 9, 25, 2), 3);

      expect(
        summaryOf(
          home: _saoPaulo,
          selection: selection,
          workingHours: _nightShift,
        ).home.verdict,
        HourBand.good,
      );
      expect(
        summaryOf(home: _saoPaulo, selection: selection).home.verdict,
        HourBand.night,
      );
    });
  });

  group('dayDelta is measured against the home line date', () {
    test('a row already on tomorrow carries +1', () {
      // 19:00 UTC is 16:00 on the 24th in Sao Paulo and 04:00 on the 25th in
      // Tokyo.
      final summary = summaryOf(
        home: _saoPaulo,
        zoneIds: [_tokyo],
        selection: selectionAt(utcDate(2024, 9, 24, 19), 1),
      );

      expect(summary.home.dayDelta, 0);
      expect(_line(summary, _tokyo).dayDelta, 1);
    });

    test('a row still on yesterday carries -1', () {
      // 19:00 UTC on the 23rd is 09:00 on the 24th in Kiritimati (+14:00) and
      // 08:00 on the 23rd in Niue (-11:00).
      final summary = summaryOf(
        home: _kiritimati,
        zoneIds: [_niue],
        selection: selectionAt(utcDate(2024, 9, 23, 19), 1),
      );

      expect(summary.home.localStart, utcDate(2024, 9, 24, 9));
      expect(_line(summary, _niue).localStart, utcDate(2024, 9, 23, 8));
      expect(_line(summary, _niue).dayDelta, -1);
    });
  });

  group('rule 8: the duration comes off the instants', () {
    test('a spring-forward range is shorter than its local times read', () {
      final slots = daySlotsOf(_newYork, utcDate(2024, 3, 10));
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 1,
        cursorIndex: 3,
      );
      final summary = summaryOf(home: _newYork, selection: selection);

      // The day is 23 hours, and the three columns run 01:00 EST, 03:00 EDT
      // and 04:00 EDT.
      expect(slots, hasLength(23));
      expect(selection.slotCount, 3);
      expect(summary.duration, const Duration(hours: 3));
      expect(summary.home.localStart, utcDate(2024, 3, 10, 1));
      // Four wall-clock hours apart, three real hours long: reading the
      // duration off the local times is the bug this rule exists to stop.
      expect(summary.home.localEnd, utcDate(2024, 3, 10, 5));
      expect(summary.home.crossesDst, isTrue);
      expect(summary.crossesDst, isTrue);
    });

    test('a fall-back range is longer than its local times read', () {
      final slots = daySlotsOf(_newYork, utcDate(2024, 11, 3));
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 1,
        cursorIndex: 2,
      );
      final summary = summaryOf(home: _newYork, selection: selection);

      // The day is 25 hours, and 01:00 happens twice: once EDT, once EST.
      expect(slots, hasLength(25));
      expect(selection.slotCount, 2);
      expect(summary.duration, const Duration(hours: 2));
      expect(summary.home.localStart, utcDate(2024, 11, 3, 1));
      expect(summary.home.localEnd, utcDate(2024, 11, 3, 2));
      expect(summary.home.crossesDst, isTrue);
    });

    test('a range on a zone that never moves its clocks is not flagged', () {
      final summary = summaryOf(
        home: _saoPaulo,
        zoneIds: [_tokyo],
        selection: selectionAt(utcDate(2024, 3, 10, 13), 3),
      );

      expect(summary.home.crossesDst, isFalse);
      expect(_line(summary, _tokyo).crossesDst, isFalse);
      expect(summary.crossesDst, isFalse);
    });

    test('a change landing on the exclusive end is not a crossing', () {
      final slots = daySlotsOf(_newYork, utcDate(2024, 3, 10));
      // Columns 0 and 1 end exactly at 07:00 UTC, which is the change; the
      // meeting is over by the time the clocks move.
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 0,
        cursorIndex: 1,
      );
      final summary = summaryOf(home: _newYork, selection: selection);

      expect(selection.endInstant, utcDate(2024, 3, 10, 7));
      expect(summary.home.crossesDst, isFalse);
      expect(summary.duration, const Duration(hours: 2));
    });

    test('a change landing on the inclusive start is not a crossing', () {
      final slots = daySlotsOf(_newYork, utcDate(2024, 3, 10));
      // Column 2 begins at 07:00 UTC, so the range runs entirely on EDT.
      final selection = MeetingSelection.fromSlots(
        slots: slots,
        anchorIndex: 2,
        cursorIndex: 2,
      );
      final summary = summaryOf(home: _newYork, selection: selection);

      expect(selection.startInstant, utcDate(2024, 3, 10, 7));
      expect(summary.home.crossesDst, isFalse);
      expect(summary.home.offsetFromUtc, const Duration(hours: -4));
    });

    test('one ordinary column is one hour long', () {
      final summary = summaryOf(
        home: _saoPaulo,
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      expect(summary.duration, const Duration(hours: 1));
    });
  });

  group('the line carries its own offset', () {
    test('a half-hour zone keeps its minutes', () {
      final summary = summaryOf(
        home: _saoPaulo,
        zoneIds: [_kolkata],
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      expect(
        _line(summary, _kolkata).offsetFromUtc,
        const Duration(hours: 5, minutes: 30),
      );
      expect(summary.home.offsetFromUtc, const Duration(hours: -3));
    });
  });

  group('rule 7: the suggestion is carried, not computed here', () {
    test('there is no suggestion unless one is handed in', () {
      final summary = summaryOf(
        home: _saoPaulo,
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
      );

      expect(summary.suggestion, isNull);
    });

    test('a supplied suggestion survives untouched', () {
      final suggestion = selectionAt(utcDate(2024, 9, 24, 13), 1);
      final summary = summaryOf(
        home: _saoPaulo,
        selection: selectionAt(utcDate(2024, 9, 24, 17), 1),
        suggestion: suggestion,
      );

      expect(summary.suggestion, suggestion);
      expect(summary.copyWith(clearSuggestion: true).suggestion, isNull);
    });
  });
}

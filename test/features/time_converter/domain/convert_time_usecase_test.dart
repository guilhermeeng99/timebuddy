import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/time_converter/domain/entities/conversion_result.dart';
import 'package:timebuddy/features/time_converter/domain/usecases/convert_time_usecase.dart';

import '../../../harness/helpers.dart';

// Every date below is pinned to its year because the whole point of this use
// case is that a zone's rules are a function of the instant, not of the zone:
//
//   America/Sao_Paulo ran DST until it was abolished in 2019, so 15 January
//     2018 sits on -02:00 and the same calendar date in 2025 sits on -03:00.
//     The 2017/2018 season ran from 15 October to February, so mid-January is
//     well inside it whichever February date that release carries.
//   America/New_York 2024 - springs forward 10 March, 02:00 EST -> 03:00 EDT
//     at 07:00 UTC, so 02:30 never happens; falls back 3 November, 02:00 EDT
//     -> 01:00 EST at 06:00 UTC, so 01:30 happens at 05:30 UTC and again at
//     06:30 UTC.
//   Australia/Lord_Howe falls back 7 April 2024 by **30 minutes**, so its
//     repeated window is 01:30..02:00 and a hard-coded one-hour step would
//     answer the wrong second occurrence.
//   Asia/Kolkata is +05:30 and Asia/Kathmandu +05:45 all year, no DST.
//   Pacific/Kiritimati is +14:00 and Pacific/Niue -11:00 all year, 25 hours
//     apart, which is how a target lands on another date.

const String _saoPaulo = 'America/Sao_Paulo';
const String _saoPauloLegacy = 'Brazil/East';
const String _newYork = 'America/New_York';
const String _london = 'Europe/London';
const String _lisbon = 'Europe/Lisbon';
const String _lordHowe = 'Australia/Lord_Howe';
const String _utc = 'UTC';
const String _tokyo = 'Asia/Tokyo';
const String _kolkata = 'Asia/Kolkata';
const String _kathmandu = 'Asia/Kathmandu';
const String _kiritimati = 'Pacific/Kiritimati';
const String _niue = 'Pacific/Niue';

/// A zone id no tzdata release will ever carry.
const String _unknownZone = 'Mars/Olympus_Mons';

/// The night shift of preferences rule 4.
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

ConversionLine _line(ConversionResult result, String zoneId) =>
    result.lines.firstWhere((line) => line.location.zoneId == zoneId);

void main() {
  final engine = TzTimeZoneEngine();
  final convertTime = ConvertTimeUseCase(engine: engine);

  setUpAll(() async {
    initTestTimeZones();
    await engine.initialize();
  });

  ConversionResult convert({
    required String sourceZoneId,
    required int year,
    required int month,
    required int day,
    int hour = 12,
    int minute = 0,
    List<String> zoneIds = const [],
    AmbiguousPick ambiguousPick = AmbiguousPick.first,
    WorkingHours workingHours = WorkingHours.defaultHours,
  }) {
    return convertTime(
      board: _board(sourceZoneId, zoneIds),
      input: ConversionInput(
        sourceZoneId: sourceZoneId,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        ambiguousPick: ambiguousPick,
      ),
      workingHours: workingHours,
    );
  }

  group('rule 1: local fields become an instant first', () {
    test('an ordinary local time resolves exactly', () {
      final result = convert(
        sourceZoneId: _saoPaulo,
        year: 2024,
        month: 9,
        day: 24,
        hour: 15,
        zoneIds: [_saoPaulo],
      );

      expect(result.resolution, TimeResolution.exact);
      expect(result.isDisclosed, isFalse);
      expect(result.instant, utcDate(2024, 9, 24, 18));
      expect(result.source.localTime, utcDate(2024, 9, 24, 15));
      expect(result.source.dayDelta, 0);
      expect(result.source.offsetFromSource, Duration.zero);
      expect(result.source.offsetFromUtc, const Duration(hours: -3));
      expect(result.source.band, HourBand.good);
    });

    test('the input is carried back untouched', () {
      final result = convert(
        sourceZoneId: _saoPaulo,
        year: 2024,
        month: 9,
        day: 24,
        hour: 15,
        minute: 45,
      );

      expect(result.input.hour, 15);
      expect(result.input.minute, 45);
      expect(result.input.sourceZoneId, _saoPaulo);
    });
  });

  group('rule 6: every line is read off the resolved instant', () {
    test('a target on DST while the source is not, six months out', () {
      // Sao Paulo has had no DST since 2019, so it is -03:00 in July while
      // New York is on EDT and London on BST.
      final result = convert(
        sourceZoneId: _saoPaulo,
        year: 2025,
        month: 7,
        day: 15,
        hour: 10,
        zoneIds: [_newYork, _london],
      );

      expect(result.instant, utcDate(2025, 7, 15, 13));
      expect(result.source.isDst, isFalse);

      final newYork = _line(result, _newYork);
      expect(newYork.localTime, utcDate(2025, 7, 15, 9));
      expect(newYork.isDst, isTrue);
      expect(newYork.abbreviation, 'EDT');
      expect(newYork.offsetFromSource, const Duration(hours: -1));
      expect(newYork.band, HourBand.good);

      final london = _line(result, _london);
      expect(london.localTime, utcDate(2025, 7, 15, 14));
      expect(london.isDst, isTrue);
      expect(london.offsetFromSource, const Duration(hours: 4));
    });

    test('a 2018 Sao Paulo date runs on that year rules, a 2025 one does '
        'not', () {
      // The abolition case, and the reason this feature exists: identical
      // local fields, ten minutes of typing apart, seven years of law apart.
      final withDst = convert(
        sourceZoneId: _saoPaulo,
        year: 2018,
        month: 1,
        day: 15,
      );
      final withoutDst = convert(
        sourceZoneId: _saoPaulo,
        year: 2025,
        month: 1,
        day: 15,
      );

      expect(withDst.instant, utcDate(2018, 1, 15, 14));
      expect(withDst.source.offsetFromUtc, const Duration(hours: -2));
      expect(withDst.source.isDst, isTrue);

      expect(withoutDst.instant, utcDate(2025, 1, 15, 15));
      expect(withoutDst.source.offsetFromUtc, const Duration(hours: -3));
      expect(withoutDst.source.isDst, isFalse);
    });

    test('a target reads the chosen date rules, not today', () {
      final in2018 = convert(
        sourceZoneId: _utc,
        year: 2018,
        month: 1,
        day: 15,
        zoneIds: [_saoPaulo],
      );
      final in2025 = convert(
        sourceZoneId: _utc,
        year: 2025,
        month: 1,
        day: 15,
        zoneIds: [_saoPaulo],
      );

      expect(_line(in2018, _saoPaulo).localTime, utcDate(2018, 1, 15, 10));
      expect(
        _line(in2018, _saoPaulo).offsetFromSource,
        const Duration(hours: -2),
      );
      expect(_line(in2025, _saoPaulo).localTime, utcDate(2025, 1, 15, 9));
      expect(
        _line(in2025, _saoPaulo).offsetFromSource,
        const Duration(hours: -3),
      );
    });

    test('a half-hour target keeps its minutes', () {
      final result = convert(
        sourceZoneId: _utc,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_kolkata, _kathmandu],
      );

      expect(_line(result, _kolkata).localTime, utcDate(2024, 9, 24, 17, 30));
      expect(
        _line(result, _kolkata).offsetFromSource,
        const Duration(hours: 5, minutes: 30),
      );
      expect(_line(result, _kathmandu).localTime, utcDate(2024, 9, 24, 17, 45));
      expect(
        _line(result, _kathmandu).offsetFromUtc,
        const Duration(hours: 5, minutes: 45),
      );
    });

    test('the band follows the user working window', () {
      // 17:30 in Kolkata is the shoulder of a 09:00-17:00 window and squarely
      // outside a night shift.
      final byDay = convert(
        sourceZoneId: _utc,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_kolkata],
      );
      final byNight = convert(
        sourceZoneId: _utc,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_kolkata],
        workingHours: _nightShift,
      );

      expect(_line(byDay, _kolkata).band, HourBand.fair);
      expect(_line(byNight, _kolkata).band, HourBand.poor);
    });
  });

  group('rule 4: a nonexistent local time resolves forward and is told', () {
    test('02:30 on the US spring-forward day is disclosed as 03:30', () {
      final result = convert(
        sourceZoneId: _newYork,
        year: 2024,
        month: 3,
        day: 10,
        hour: 2,
        minute: 30,
      );

      expect(result.resolution, TimeResolution.shiftedForward);
      expect(result.isDisclosed, isTrue);
      expect(result.isAmbiguous, isFalse);
      expect(result.instant, utcDate(2024, 3, 10, 7, 30));
      // Never silently answers a different question: the shown local time is
      // the one past the gap, and the banner says so.
      expect(result.source.localTime, utcDate(2024, 3, 10, 3, 30));
      expect(result.input.hour, 2);
      expect(result.input.minute, 30);
    });

    test('the ambiguity toggle cannot move a shifted-forward answer', () {
      final result = convert(
        sourceZoneId: _newYork,
        year: 2024,
        month: 3,
        day: 10,
        hour: 2,
        minute: 30,
        ambiguousPick: AmbiguousPick.second,
      );

      expect(result.instant, utcDate(2024, 3, 10, 7, 30));
      expect(result.resolution, TimeResolution.shiftedForward);
    });
  });

  group('rule 5: an ambiguous local time discloses both occurrences', () {
    test('01:30 on the US fall-back day defaults to the earlier instant', () {
      final result = convert(
        sourceZoneId: _newYork,
        year: 2024,
        month: 11,
        day: 3,
        hour: 1,
        minute: 30,
      );

      expect(result.resolution, TimeResolution.ambiguousFirst);
      expect(result.isAmbiguous, isTrue);
      expect(result.instant, utcDate(2024, 11, 3, 5, 30));
      expect(result.source.localTime, utcDate(2024, 11, 3, 1, 30));
      expect(result.source.abbreviation, 'EDT');
      expect(result.source.isDst, isTrue);
    });

    test('the second occurrence is the same wall clock, an hour later', () {
      final result = convert(
        sourceZoneId: _newYork,
        year: 2024,
        month: 11,
        day: 3,
        hour: 1,
        minute: 30,
        ambiguousPick: AmbiguousPick.second,
      );

      expect(result.instant, utcDate(2024, 11, 3, 6, 30));
      expect(result.source.localTime, utcDate(2024, 11, 3, 1, 30));
      expect(result.source.abbreviation, 'EST');
      expect(result.source.isDst, isFalse);
      // The resolution describes the local time, not which occurrence is on
      // screen; the input's pick says that.
      expect(result.resolution, TimeResolution.ambiguousFirst);
      expect(result.input.ambiguousPick, AmbiguousPick.second);
    });

    test('a 30-minute fall-back moves the second occurrence by 30 minutes', () {
      // Lord Howe drops half an hour, so a hard-coded one-hour step would
      // hand back an instant whose local time is not what the user picked.
      final first = convert(
        sourceZoneId: _lordHowe,
        year: 2024,
        month: 4,
        day: 7,
        hour: 1,
        minute: 45,
      );
      final second = convert(
        sourceZoneId: _lordHowe,
        year: 2024,
        month: 4,
        day: 7,
        hour: 1,
        minute: 45,
        ambiguousPick: AmbiguousPick.second,
      );

      expect(first.instant, utcDate(2024, 4, 6, 14, 45));
      expect(second.instant, utcDate(2024, 4, 6, 15, 15));
      expect(second.source.localTime, utcDate(2024, 4, 7, 1, 45));
    });

    test('the toggle leaves an unambiguous local time alone', () {
      final result = convert(
        sourceZoneId: _saoPaulo,
        year: 2024,
        month: 9,
        day: 24,
        hour: 15,
        ambiguousPick: AmbiguousPick.second,
      );

      expect(result.resolution, TimeResolution.exact);
      expect(result.instant, utcDate(2024, 9, 24, 18));
    });
  });

  group('rule 3: targets are the board minus the source', () {
    test('the source zone is not listed as a target of itself', () {
      final result = convert(
        sourceZoneId: _saoPaulo,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_saoPaulo, _tokyo],
      );

      expect(result.lines.map((line) => line.location.zoneId), [_tokyo]);
      expect(result.source.location.zoneId, _saoPaulo);
      expect(result.source.location.id, 'row-0-$_saoPaulo');
    });

    test('a legacy alias of the source excludes the canonical row', () {
      final result = convertTime(
        board: _board(_saoPaulo, [_saoPauloLegacy, _tokyo]),
        input: const ConversionInput(
          sourceZoneId: _saoPaulo,
          year: 2024,
          month: 9,
          day: 24,
          hour: 12,
          minute: 0,
        ),
        workingHours: WorkingHours.defaultHours,
      );

      // Brazil/East and America/Sao_Paulo are one clock, so a literal
      // comparison would have listed the source as a target of itself.
      expect(result.lines.map((line) => line.location.zoneId), [_tokyo]);
    });

    test('a source that is not on the board still gets a line', () {
      final result = convertTime(
        board: _board(_tokyo, [_tokyo]),
        input: const ConversionInput(
          sourceZoneId: _lisbon,
          year: 2024,
          month: 9,
          day: 24,
          hour: 12,
          minute: 0,
        ),
        workingHours: WorkingHours.defaultHours,
      );

      expect(result.source.location.zoneId, _lisbon);
      // The empty id marks a row that is not on the board and must never be
      // written back to one.
      expect(result.source.location.id, isEmpty);
      expect(result.lines.map((line) => line.location.zoneId), [_tokyo]);
    });

    test('a board holding only the source yields no target lines', () {
      final result = convert(
        sourceZoneId: _saoPaulo,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_saoPaulo],
      );

      expect(result.lines, isEmpty);
      expect(result.source.location.zoneId, _saoPaulo);
    });

    test('a row whose zone the tzdata cannot resolve is left out', () {
      final result = convert(
        sourceZoneId: _saoPaulo,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_tokyo, _unknownZone],
      );

      expect(result.lines.map((line) => line.location.zoneId), [_tokyo]);
    });

    test('lines keep board order', () {
      final result = convert(
        sourceZoneId: _utc,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_tokyo, _kolkata, _london],
      );

      expect(result.lines.map((line) => line.location.zoneId), [
        _tokyo,
        _kolkata,
        _london,
      ]);
    });
  });

  group('rule 7: the local date is shown when it differs', () {
    test('a target across the date line carries +1', () {
      // 10:00 in Niue (-11:00) is 21:00 UTC, which is already the next
      // morning in Kiritimati (+14:00).
      final result = convert(
        sourceZoneId: _niue,
        year: 2024,
        month: 9,
        day: 24,
        hour: 10,
        zoneIds: [_kiritimati],
      );

      expect(result.instant, utcDate(2024, 9, 24, 21));
      expect(_line(result, _kiritimati).localTime, utcDate(2024, 9, 25, 11));
      expect(_line(result, _kiritimati).dayDelta, 1);
    });

    test('a target still on yesterday carries -1', () {
      final result = convert(
        sourceZoneId: _kiritimati,
        year: 2024,
        month: 9,
        day: 24,
        hour: 9,
        zoneIds: [_niue],
      );

      expect(result.instant, utcDate(2024, 9, 23, 19));
      expect(_line(result, _niue).localTime, utcDate(2024, 9, 23, 8));
      expect(_line(result, _niue).dayDelta, -1);
    });

    test('a target on the same date carries 0', () {
      final result = convert(
        sourceZoneId: _utc,
        year: 2024,
        month: 9,
        day: 24,
        zoneIds: [_london],
      );

      expect(_line(result, _london).dayDelta, 0);
    });
  });

  group('rule 8: the date range is bounded to a decade either side', () {
    final now = utcDate(2026, 8, 20, 15, 30);

    ConversionInput inputOn(int year, int month, int day) => ConversionInput(
      sourceZoneId: _saoPaulo,
      year: year,
      month: month,
      day: day,
      hour: 12,
      minute: 0,
    );

    test('the window is ten years wide on both sides', () {
      expect(ConversionInput.rangeYears, 10);
      expect(ConversionInput.earliestDate(now), utcDate(2016, 8, 20));
      expect(ConversionInput.latestDate(now), utcDate(2036, 8, 20));
    });

    test('a date inside the window is accepted', () {
      expect(inputOn(2026, 8, 20).isWithinRange(now), isTrue);
      expect(inputOn(2016, 8, 20).isWithinRange(now), isTrue);
      expect(inputOn(2036, 8, 20).isWithinRange(now), isTrue);
    });

    test('a date past either edge is refused', () {
      // Beyond a decade tzdata carries projections rather than law, and
      // presenting one as an answer is overconfident.
      expect(inputOn(2016, 8, 19).isWithinRange(now), isFalse);
      expect(inputOn(2036, 8, 21).isWithinRange(now), isFalse);
    });
  });
}

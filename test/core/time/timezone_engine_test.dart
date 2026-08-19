import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';

import '../../harness/helpers.dart';

// Every date in this file is a real IANA transition, verified against the
// tzdata rules rather than guessed:
//
//   United States 2024 - DST starts on the second Sunday in March
//     (2024-03-10, 02:00 EST -> 03:00 EDT, i.e. 07:00 UTC) and ends on the
//     first Sunday in November (2024-11-03, 02:00 EDT -> 01:00 EST, 06:00 UTC).
//   United Kingdom 2024 - BST starts 2024-03-31 and ends 2024-10-27, both at
//     01:00 UTC. The three-week offset from the US dates is what makes London
//     four hours from New York instead of five for part of the year.
//   Australia/Lord_Howe 2024 - falls back 2024-04-07 02:00 -> 01:30 local and
//     springs forward 2024-10-06 02:00 -> 02:30 local. The jump is 30 minutes.
//   America/Santiago 2024 - springs forward at 2024-09-08 00:00 local, so the
//     local day begins on the transition and midnight never happens.
//   America/Sao_Paulo - DST ran 2017-10-15 to 2018-02-18 and was abolished in
//     April 2019, so 15 January answers -02:00 in 2018 and -03:00 in 2024.
//   Pacific/Chatham - +12:45 standard, +13:45 in NZ summer. The 45 minutes are
//     the point: any API that returned whole hours would pass by accident.

/// The channel `flutter_timezone` speaks over.
///
/// Mocked in the device-zone group so the assertions never depend on the
/// timezone of the machine running the suite.
const _deviceZoneChannel = MethodChannel('flutter_timezone');

const _est = Duration(hours: -5);
const _edt = Duration(hours: -4);
const Duration _gmt = Duration.zero;
const _bst = Duration(hours: 1);
const _ist = Duration(hours: 5, minutes: 30);
const _lhStandard = Duration(hours: 10, minutes: 30);
const _lhDaylight = Duration(hours: 11);
const _halfHour = Duration(minutes: 30);

/// The wall-clock hour of every slot in [day], in order.
///
/// A spring-forward day is missing one of them and a fall-back day repeats
/// one, which is the only observable difference between a correct hour list
/// and a `for (var h = 0; h < 24; h++)` one of the same length.
List<int> _localHoursIn(TimeZoneEngine engine, ZoneDay day) => <int>[
  for (final instant in day.hours)
    engine.wallTimeAt(zoneId: day.zoneId, instant: instant).hour,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final engine = TzTimeZoneEngine();

  setUpAll(() async {
    initTestTimeZones();
    await engine.initialize();
  });

  group('initialize', () {
    test('is idempotent and leaves the harness database intact', () async {
      await engine.initialize();
      await engine.initialize();

      // A second initialize() that reloaded tzdata would rebuild every
      // Location and invalidate the ones already handed out.
      expect(
        engine.stateAt(
          zoneId: 'Asia/Kolkata',
          instant: utcDate(2024, 6, 15, 12),
        ).offset,
        _ist,
      );
    });
  });

  group('stateAt', () {
    test('America/Sao_Paulo is -02:00 on 2018-01-15, inside its last DST', () {
      final state = engine.stateAt(
        zoneId: 'America/Sao_Paulo',
        instant: utcDate(2018, 1, 15, 12),
      );

      expect(state.offset, const Duration(hours: -2));
      expect(state.isDst, isTrue);
      expect(state.zoneId, 'America/Sao_Paulo');
    });

    test('America/Sao_Paulo is -03:00 on 2024-01-15, DST abolished', () {
      final state = engine.stateAt(
        zoneId: 'America/Sao_Paulo',
        instant: utcDate(2024, 1, 15, 12),
      );

      expect(state.offset, const Duration(hours: -3));
      expect(state.isDst, isFalse);
    });

    test('the same calendar date answers differently in 2018 and 2024', () {
      Duration offsetOn(int year) => engine.stateAt(
        zoneId: 'America/Sao_Paulo',
        instant: utcDate(year, 1, 15, 12),
      ).offset;

      // Rule 2: an offset belongs to an instant, never to a zone. Caching the
      // 2024 answer and reusing it for a 2018 converter query is one hour out.
      expect(offsetOn(2018) - offsetOn(2024), const Duration(hours: 1));
    });

    test('Asia/Kolkata is +05:30 all year', () {
      final winter = engine.stateAt(
        zoneId: 'Asia/Kolkata',
        instant: utcDate(2024, 1, 15, 12),
      );
      final summer = engine.stateAt(
        zoneId: 'Asia/Kolkata',
        instant: utcDate(2024, 6, 15, 12),
      );

      expect(winter.offset, _ist);
      expect(summer.offset, _ist);
      expect(summer.abbreviation, 'IST');
      expect(summer.isDst, isFalse);
    });

    test('Asia/Kathmandu is +05:45', () {
      expect(
        engine.stateAt(
          zoneId: 'Asia/Kathmandu',
          instant: utcDate(2024, 6, 15, 12),
        ).offset,
        const Duration(hours: 5, minutes: 45),
      );
    });

    test('Pacific/Chatham is +12:45 in NZ winter and +13:45 in summer', () {
      final winter = engine.stateAt(
        zoneId: 'Pacific/Chatham',
        instant: utcDate(2024, 7),
      );
      final summer = engine.stateAt(
        zoneId: 'Pacific/Chatham',
        instant: utcDate(2024, 1, 15),
      );

      expect(winter.offset, const Duration(hours: 12, minutes: 45));
      expect(winter.isDst, isFalse);
      expect(summer.offset, const Duration(hours: 13, minutes: 45));
      expect(summer.isDst, isTrue);
    });

    test('America/New_York reports EST and EDT with the right offsets', () {
      final winter = engine.stateAt(
        zoneId: 'America/New_York',
        instant: utcDate(2024, 1, 15, 12),
      );
      final summer = engine.stateAt(
        zoneId: 'America/New_York',
        instant: utcDate(2024, 6, 15, 12),
      );

      expect(winter.offset, _est);
      expect(winter.abbreviation, 'EST');
      expect(winter.isDst, isFalse);
      expect(summer.offset, _edt);
      expect(summer.abbreviation, 'EDT');
      expect(summer.isDst, isTrue);
    });

    test('Australia/Sydney is on DST in January, not July', () {
      // Southern-hemisphere DST spans the new year, so "is it summer in the
      // northern sense" is not a proxy for "is DST on".
      final january = engine.stateAt(
        zoneId: 'Australia/Sydney',
        instant: utcDate(2024, 1, 15),
      );
      final july = engine.stateAt(
        zoneId: 'Australia/Sydney',
        instant: utcDate(2024, 7, 15),
      );

      expect(january.offset, const Duration(hours: 11));
      expect(january.isDst, isTrue);
      expect(july.offset, const Duration(hours: 10));
      expect(july.isDst, isFalse);
    });

    test('a legacy id is answered under its canonical name', () {
      final state = engine.stateAt(
        zoneId: 'Asia/Calcutta',
        instant: utcDate(2024, 6, 15, 12),
      );

      expect(state.zoneId, 'Asia/Kolkata');
      expect(state.offset, _ist);
    });

    test('an unknown id degrades to UTC instead of throwing', () {
      final state = engine.stateAt(
        zoneId: 'Not/AZone',
        instant: utcDate(2024, 6, 15, 12),
      );

      expect(state.zoneId, utcZoneId);
      expect(state.offset, Duration.zero);
      expect(state.isDst, isFalse);
    });
  });

  group('wallTimeAt', () {
    test('carries the half-hour offset into the wall clock', () {
      expect(
        engine.wallTimeAt(
          zoneId: 'Asia/Kolkata',
          instant: utcDate(2024, 6, 15, 12),
        ),
        utcDate(2024, 6, 15, 17, 30),
      );
    });

    test('two date-line zones read different calendar dates at once', () {
      final instant = utcDate(2024, 6, 15, 12);

      // +14:00 against -11:00 is 25 hours apart, so a grid that labels the
      // date once per screen is wrong for one of these rows.
      expect(
        engine.wallTimeAt(zoneId: 'Pacific/Kiritimati', instant: instant),
        utcDate(2024, 6, 16, 2),
      );
      expect(
        engine.wallTimeAt(zoneId: 'Pacific/Niue', instant: instant),
        utcDate(2024, 6, 15, 1),
      );
    });
  });

  group('instantFor', () {
    test('an ordinary local time resolves exactly', () {
      final resolved = engine.instantFor(
        zoneId: 'America/New_York',
        year: 2024,
        month: 6,
        day: 15,
        hour: 9,
      );

      expect(resolved.resolution, TimeResolution.exact);
      expect(resolved.utcInstant, utcDate(2024, 6, 15, 13));
    });

    test('01:30 on the 2024 US spring-forward day is still exact', () {
      // The gap opens at 02:00; the hour before it must not be flagged.
      final resolved = engine.instantFor(
        zoneId: 'America/New_York',
        year: 2024,
        month: 3,
        day: 10,
        hour: 1,
        minute: 30,
      );

      expect(resolved.resolution, TimeResolution.exact);
      expect(resolved.utcInstant, utcDate(2024, 3, 10, 6, 30));
    });

    test('02:00 on the 2024 US spring-forward day shifts to 03:00', () {
      final resolved = engine.instantFor(
        zoneId: 'America/New_York',
        year: 2024,
        month: 3,
        day: 10,
        hour: 2,
      );

      expect(resolved.resolution, TimeResolution.shiftedForward);
      expect(resolved.utcInstant, utcDate(2024, 3, 10, 7));
      // 07:00 UTC is 03:00 EDT: forward past the gap, never back to the 9th.
      expect(
        engine.wallTimeAt(
          zoneId: 'America/New_York',
          instant: resolved.utcInstant,
        ),
        utcDate(2024, 3, 10, 3),
      );
    });

    test('02:30 on the 2024 US spring-forward day shifts to 03:30', () {
      final resolved = engine.instantFor(
        zoneId: 'America/New_York',
        year: 2024,
        month: 3,
        day: 10,
        hour: 2,
        minute: 30,
      );

      expect(resolved.resolution, TimeResolution.shiftedForward);
      expect(resolved.utcInstant, utcDate(2024, 3, 10, 7, 30));
    });

    test('01:30 on the 2024 US fall-back day picks the earlier instant', () {
      final resolved = engine.instantFor(
        zoneId: 'America/New_York',
        year: 2024,
        month: 11,
        day: 3,
        hour: 1,
        minute: 30,
      );

      expect(resolved.resolution, TimeResolution.ambiguousFirst);
      // 01:30 happens at 05:30 UTC as EDT and again at 06:30 UTC as EST.
      expect(resolved.utcInstant, utcDate(2024, 11, 3, 5, 30));
      expect(
        resolved.utcInstant.isBefore(utcDate(2024, 11, 3, 6, 30)),
        isTrue,
      );
    });

    test('02:00 on the 2024 US fall-back day is past the repeat and exact', () {
      final resolved = engine.instantFor(
        zoneId: 'America/New_York',
        year: 2024,
        month: 11,
        day: 3,
        hour: 2,
      );

      expect(resolved.resolution, TimeResolution.exact);
      expect(resolved.utcInstant, utcDate(2024, 11, 3, 7));
    });

    test('01:30 on the 2024 London fall-back day picks the BST instant', () {
      // London resolves an ambiguous local time to the later occurrence on
      // its own, so this is the branch New York does not exercise.
      final resolved = engine.instantFor(
        zoneId: 'Europe/London',
        year: 2024,
        month: 10,
        day: 27,
        hour: 1,
        minute: 30,
      );

      expect(resolved.resolution, TimeResolution.ambiguousFirst);
      expect(resolved.utcInstant, utcDate(2024, 10, 27, 0, 30));
    });

    test('01:00 on the 2024 London spring-forward day shifts to 02:00', () {
      final resolved = engine.instantFor(
        zoneId: 'Europe/London',
        year: 2024,
        month: 3,
        day: 31,
        hour: 1,
      );

      expect(resolved.resolution, TimeResolution.shiftedForward);
      expect(resolved.utcInstant, utcDate(2024, 3, 31, 1));
    });

    test('Lord Howe 02:00 on 2024-10-06 shifts by the 30-minute gap', () {
      final resolved = engine.instantFor(
        zoneId: 'Australia/Lord_Howe',
        year: 2024,
        month: 10,
        day: 6,
        hour: 2,
      );

      expect(resolved.resolution, TimeResolution.shiftedForward);
      expect(resolved.utcInstant, utcDate(2024, 10, 5, 15, 30));
      // The clock goes 02:00 -> 02:30, so 02:30 is the first valid local time.
      expect(
        engine.wallTimeAt(
          zoneId: 'Australia/Lord_Howe',
          instant: resolved.utcInstant,
        ),
        utcDate(2024, 10, 6, 2, 30),
      );
    });

    test('Lord Howe 01:45 on 2024-04-07 picks the earlier of two', () {
      // Only 01:30..02:00 repeats there, so a hard-coded one-hour probe would
      // miss this and report the local time as unambiguous.
      final resolved = engine.instantFor(
        zoneId: 'Australia/Lord_Howe',
        year: 2024,
        month: 4,
        day: 7,
        hour: 1,
        minute: 45,
      );

      expect(resolved.resolution, TimeResolution.ambiguousFirst);
      expect(resolved.utcInstant, utcDate(2024, 4, 6, 14, 45));
      expect(resolved.utcInstant.isBefore(utcDate(2024, 4, 6, 15, 15)), isTrue);
    });

    test('an unknown id resolves against UTC rather than throwing', () {
      final resolved = engine.instantFor(
        zoneId: 'Not/AZone',
        year: 2024,
        month: 6,
        day: 15,
        hour: 12,
      );

      expect(resolved.resolution, TimeResolution.exact);
      expect(resolved.utcInstant, utcDate(2024, 6, 15, 12));
    });
  });

  group('relativeOffset', () {
    Duration londonFromNewYork(DateTime instant) => engine.relativeOffset(
      fromZoneId: 'America/New_York',
      toZoneId: 'Europe/London',
      instant: instant,
    );

    test('London is +4h from New York on 2024-03-20, in the spring gap', () {
      // New York moved on 2024-03-10, London not until 2024-03-31, so for
      // those three weeks the pair sits an hour closer than usual.
      expect(londonFromNewYork(utcDate(2024, 3, 20, 12)), _gmt - _edt);
      expect(
        londonFromNewYork(utcDate(2024, 3, 20, 12)),
        const Duration(hours: 4),
      );
    });

    test('London is +4h from New York on 2024-10-30, in the autumn gap', () {
      // London moved back on 2024-10-27, New York not until 2024-11-03.
      expect(
        londonFromNewYork(utcDate(2024, 10, 30, 12)),
        const Duration(hours: 4),
      );
    });

    test('London is +5h from New York on 2024-04-10, outside the gap', () {
      expect(
        londonFromNewYork(utcDate(2024, 4, 10, 12)),
        _bst - _edt,
      );
      expect(
        londonFromNewYork(utcDate(2024, 4, 10, 12)),
        const Duration(hours: 5),
      );
    });

    test('London is +5h from New York on 2024-01-15, both on standard', () {
      expect(londonFromNewYork(utcDate(2024, 1, 15, 12)), _gmt - _est);
    });

    test('the relation is antisymmetric at a single instant', () {
      expect(
        engine.relativeOffset(
          fromZoneId: 'Europe/London',
          toZoneId: 'America/New_York',
          instant: utcDate(2024, 3, 20, 12),
        ),
        const Duration(hours: -4),
      );
    });

    test('a pair with a half-hour zone keeps the minutes', () {
      expect(
        engine.relativeOffset(
          fromZoneId: 'Asia/Kolkata',
          toZoneId: 'America/New_York',
          instant: utcDate(2024, 6, 15, 12),
        ),
        const Duration(hours: -9, minutes: -30),
      );
    });

    test('an unknown id is treated as UTC', () {
      expect(
        engine.relativeOffset(
          fromZoneId: 'Not/AZone',
          toZoneId: 'Asia/Kolkata',
          instant: utcDate(2024, 6, 15, 12),
        ),
        _ist,
      );
    });
  });

  group('dayIn', () {
    test('an ordinary New York day has 24 slots and no transition', () {
      final day = engine.dayIn(
        zoneId: 'America/New_York',
        localDate: utcDate(2024, 6, 15),
      );

      expect(day.hourCount, 24);
      expect(day.hours, hasLength(24));
      expect(day.transition, isNull);
      expect(day.date, utcDate(2024, 6, 15));
      expect(day.hours.first, utcDate(2024, 6, 15, 4));
    });

    test('the 2024 US spring-forward day has 23 slots and skips 02:00', () {
      final day = engine.dayIn(
        zoneId: 'America/New_York',
        localDate: utcDate(2024, 3, 10),
      );

      expect(day.hourCount, 23);
      expect(day.hours, hasLength(23));
      expect(day.hours.first, utcDate(2024, 3, 10, 5));
      expect(_localHoursIn(engine, day), isNot(contains(2)));
      expect(_localHoursIn(engine, day).take(3), <int>[0, 1, 3]);

      final transition = day.transition;
      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 3, 10, 7));
      expect(transition.before, _est);
      expect(transition.after, _edt);
      expect(transition.skippedHour, 2);
      expect(transition.repeatedHour, isNull);
    });

    test('the 2024 US fall-back day has 25 slots and repeats 01:00', () {
      final day = engine.dayIn(
        zoneId: 'America/New_York',
        localDate: utcDate(2024, 11, 3),
      );

      expect(day.hourCount, 25);
      expect(day.hours, hasLength(25));
      expect(day.hours.first, utcDate(2024, 11, 3, 4));
      expect(_localHoursIn(engine, day).take(4), <int>[0, 1, 1, 2]);
      expect(_localHoursIn(engine, day).where((h) => h == 1), hasLength(2));

      final transition = day.transition;
      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 11, 3, 6));
      expect(transition.before, _edt);
      expect(transition.after, _est);
      expect(transition.repeatedHour, 1);
      expect(transition.skippedHour, isNull);
    });

    test('a half-hour zone starts its day on the half hour', () {
      final day = engine.dayIn(
        zoneId: 'Asia/Kolkata',
        localDate: utcDate(2024, 6, 15),
      );

      expect(day.hourCount, 24);
      expect(day.hours.first, utcDate(2024, 6, 14, 18, 30));
      expect(day.transition, isNull);
    });

    test('Lord Howe 2024-10-06 reports 24 slots for a 23.5 hour day', () {
      final day = engine.dayIn(
        zoneId: 'Australia/Lord_Howe',
        localDate: utcDate(2024, 10, 6),
      );

      // hourCount is an int, so the half hour has to come out of the slot
      // instants: this is the one day where the two disagree.
      expect(day.hourCount, 24);
      expect(day.hours.first, utcDate(2024, 10, 5, 13, 30));
      expect(day.hours.last, utcDate(2024, 10, 6, 12, 30));

      final nextMidnight = engine.instantFor(
        zoneId: 'Australia/Lord_Howe',
        year: 2024,
        month: 10,
        day: 7,
      ).utcInstant;
      expect(
        nextMidnight.difference(day.hours.first),
        const Duration(hours: 23, minutes: 30),
      );

      final transition = day.transition;
      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 10, 5, 15, 30));
      expect(transition.before, _lhStandard);
      expect(transition.after, _lhDaylight);
      expect(transition.after - transition.before, _halfHour);
      expect(transition.skippedHour, 2);
    });

    test('Lord Howe 2024-04-07 reports 25 slots for a 24.5 hour day', () {
      final day = engine.dayIn(
        zoneId: 'Australia/Lord_Howe',
        localDate: utcDate(2024, 4, 7),
      );

      expect(day.hourCount, 25);
      expect(day.hours.first, utcDate(2024, 4, 6, 13));

      final nextMidnight = engine.instantFor(
        zoneId: 'Australia/Lord_Howe',
        year: 2024,
        month: 4,
        day: 8,
      ).utcInstant;
      expect(
        nextMidnight.difference(day.hours.first),
        const Duration(hours: 24, minutes: 30),
      );

      final transition = day.transition;
      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 4, 6, 15));
      expect(transition.before, _lhDaylight);
      expect(transition.after, _lhStandard);
      expect(transition.before - transition.after, _halfHour);
      expect(transition.repeatedHour, 1);
    });

    test('Santiago 2024-09-08 begins on the transition that eats 00:00', () {
      final day = engine.dayIn(
        zoneId: 'America/Santiago',
        localDate: utcDate(2024, 9, 8),
      );

      expect(day.hourCount, 23);
      expect(day.hours.first, utcDate(2024, 9, 8, 4));
      expect(
        engine.wallTimeAt(
          zoneId: 'America/Santiago',
          instant: day.hours.first,
        ),
        utcDate(2024, 9, 8, 1),
      );

      // The day's first instant *is* the change, so a scan anchored there and
      // stepping forward would walk straight past it.
      final transition = day.transition;
      expect(transition, isNotNull);
      expect(transition!.atUtc, day.hours.first);
      expect(transition.skippedHour, 0);
    });
  });

  group('nextTransition', () {
    test('New York from 2024-01-01 finds the 2024-03-10 spring forward', () {
      final transition = engine.nextTransition(
        zoneId: 'America/New_York',
        instant: utcDate(2024),
      );

      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 3, 10, 7));
      expect(transition.before, _est);
      expect(transition.after, _edt);
      expect(transition.skippedHour, 2);
      expect(transition.repeatedHour, isNull);
    });

    test('a transition exactly at the queried instant still counts', () {
      final transition = engine.nextTransition(
        zoneId: 'America/New_York',
        instant: utcDate(2024, 3, 10, 7),
      );

      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 3, 10, 7));
    });

    test('London from 2024-07-01 finds the 2024-10-27 fall back', () {
      final transition = engine.nextTransition(
        zoneId: 'Europe/London',
        instant: utcDate(2024, 7),
      );

      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 10, 27, 1));
      expect(transition.before, _bst);
      expect(transition.after, _gmt);
      expect(transition.repeatedHour, 1);
      expect(transition.skippedHour, isNull);
    });

    test('Lord Howe from 2024-06-01 finds a 30-minute jump', () {
      final transition = engine.nextTransition(
        zoneId: 'Australia/Lord_Howe',
        instant: utcDate(2024, 6),
      );

      expect(transition, isNotNull);
      expect(transition!.atUtc, utcDate(2024, 10, 5, 15, 30));
      expect(transition.after - transition.before, _halfHour);
    });

    test('America/Sao_Paulo has none scheduled since DST was abolished', () {
      expect(
        engine.nextTransition(
          zoneId: 'America/Sao_Paulo',
          instant: utcDate(2024, 6),
        ),
        isNull,
      );
    });

    test('Asia/Kolkata has none at all', () {
      expect(
        engine.nextTransition(
          zoneId: 'Asia/Kolkata',
          instant: utcDate(2024, 6),
        ),
        isNull,
      );
    });
  });

  group('deviceZone', () {
    void mockPlatformZone(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_deviceZoneChannel, handler);
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_deviceZoneChannel, null);
    });

    test('adopts a zone the platform reports', () async {
      mockPlatformZone((_) async => 'America/Sao_Paulo');

      expect(
        await engine.deviceZone(),
        const DeviceZone(zoneId: 'America/Sao_Paulo', isFallback: false),
      );
    });

    test('canonicalises a legacy id the platform reports', () async {
      // Android vendors still hand out ids the tzdata renamed years ago.
      mockPlatformZone((_) async => 'Asia/Calcutta');

      expect(
        await engine.deviceZone(),
        const DeviceZone(zoneId: 'Asia/Kolkata', isFallback: false),
      );
    });

    test('falls back to UTC for an id the tzdata rejects', () async {
      mockPlatformZone((_) async => 'Not/AZone');

      expect(
        await engine.deviceZone(),
        const DeviceZone(zoneId: utcZoneId, isFallback: true),
      );
    });

    test('falls back to UTC when the platform channel fails', () async {
      mockPlatformZone((_) async {
        throw PlatformException(code: 'unavailable');
      });

      expect(
        await engine.deviceZone(),
        const DeviceZone(zoneId: utcZoneId, isFallback: true),
      );
    });

    test('falls back to UTC when the plugin is missing entirely', () async {
      // No handler registered: invokeMethod throws MissingPluginException,
      // which must not be allowed to block startup.
      expect(
        await engine.deviceZone(),
        const DeviceZone(zoneId: utcZoneId, isFallback: true),
      );
    });
  });
}

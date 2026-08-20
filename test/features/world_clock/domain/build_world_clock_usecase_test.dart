import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/world_clock/domain/entities/world_clock_view_model.dart';
import 'package:timebuddy/features/world_clock/domain/usecases/build_world_clock_usecase.dart';

import '../../../harness/helpers.dart';

// Every zone and instant below is real, and pinned to its year because an
// offset is a function of an instant and 2024's rules are not 2018's:
//
//   At 2024-06-15 12:30 UTC — mid-June, so both hemispheres are settled and
//   nothing here is one minute from a transition:
//     America/Sao_Paulo  -03:00  09:30 Jun 15  (DST abolished in 2019)
//     America/New_York   -04:00  08:30 Jun 15  (EDT, DST on)
//     Europe/Berlin      +02:00  14:30 Jun 15  (CEST, DST on)
//     Asia/Karachi       +05:00  17:30 Jun 15  (no DST since 2009)
//     Asia/Kolkata       +05:30  18:00 Jun 15
//     Asia/Kathmandu     +05:45  18:15 Jun 15
//     Asia/Tokyo         +09:00  21:30 Jun 15
//     Pacific/Kiritimati +14:00  02:30 Jun 16
//     Pacific/Niue       -11:00  01:30 Jun 15
//
//   Kiritimati and Niue are 25 hours apart, which is why they are the pair
//   every date-line case uses: one instant puts them on either side of a day
//   boundary, and an instant an hour earlier puts them two days apart.

const String _saoPaulo = 'America/Sao_Paulo';
const String _saoPauloLegacy = 'Brazil/East';
const String _newYork = 'America/New_York';
const String _berlin = 'Europe/Berlin';
const String _karachi = 'Asia/Karachi';
const String _kolkata = 'Asia/Kolkata';
const String _kathmandu = 'Asia/Kathmandu';
const String _tokyo = 'Asia/Tokyo';
const String _kiritimati = 'Pacific/Kiritimati';
const String _niue = 'Pacific/Niue';

/// A zone id no tzdata release will ever carry, so `zoneOrNull` returns null
/// and the row takes the unresolved path.
const String _unknownZone = 'Mars/Olympus_Mons';

/// Stands in for `t.locations.homeLabel`, which the cubit supplies in the app.
const String _homeFallbackLabel = 'Home';

/// The reference instant. Mid-June and off the hour, so a use case that
/// hardcoded a whole hour or ignored `nowInstant` could not pass by accident.
final DateTime _nowUtc = utcDate(2024, 6, 15, 12, 30);

/// One hour earlier, which is where Kiritimati and Niue sit two calendar days
/// apart rather than one.
final DateTime _twoDaysApartUtc = utcDate(2024, 6, 15, 10, 30);

/// Mid-January, when the northern hemisphere is off daylight saving.
final DateTime _januaryUtc = utcDate(2024, 1, 15, 12, 30);

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

WorldClockTile _tile(WorldClockViewModel model, String zoneId) =>
    model.tiles.firstWhere((tile) => tile.location.zoneId == zoneId);

void main() {
  final engine = TzTimeZoneEngine();
  final buildWorldClock = BuildWorldClockUseCase(engine: engine);

  setUpAll(() async {
    initTestTimeZones();
    await engine.initialize();
  });

  WorldClockViewModel buildModel({
    required String home,
    List<String> zoneIds = const [],
    DateTime? nowInstant,
    WorkingHours workingHours = WorkingHours.defaultHours,
    String homeFallbackLabel = _homeFallbackLabel,
  }) {
    return buildWorldClock(
      board: _board(home, zoneIds),
      workingHours: workingHours,
      nowInstant: nowInstant ?? _nowUtc,
      homeFallbackLabel: homeFallbackLabel,
    );
  }

  group('local time', () {
    test('is the wall clock each zone reads at the shared instant', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_tokyo, _kathmandu],
      );

      expect(model.nowInstant, _nowUtc);
      expect(model.home.localTime.hour, 9);
      expect(model.home.localTime.minute, 30);
      expect(_tile(model, _tokyo).localTime.hour, 21);
      // A 45-minute zone carries its minutes into the wall clock, which is why
      // no layout here may assume rows share a minute.
      expect(_tile(model, _kathmandu).localTime.hour, 18);
      expect(_tile(model, _kathmandu).localTime.minute, 15);
    });

    test('carries each zone offset from UTC, minutes included', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_kathmandu, _kolkata],
      );

      expect(model.home.offsetFromUtc, const Duration(hours: -3));
      expect(
        _tile(model, _kathmandu).offsetFromUtc,
        const Duration(hours: 5, minutes: 45),
      );
      expect(
        _tile(model, _kolkata).offsetFromUtc,
        const Duration(hours: 5, minutes: 30),
      );
    });
  });

  group('offset from home (rule 5)', () {
    test('keeps the minutes of a non-whole-hour zone', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_kathmandu, _kolkata],
      );

      expect(
        _tile(model, _kathmandu).offsetFromHome,
        const Duration(hours: 8, minutes: 45),
      );
      expect(
        _tile(model, _kolkata).offsetFromHome,
        const Duration(hours: 8, minutes: 30),
      );
    });

    test('is negative for a zone behind home', () {
      final model = buildModel(home: _tokyo, zoneIds: [_newYork]);

      // Tokyo is +09:00 and New York is on EDT (-04:00) in June.
      expect(_tile(model, _newYork).offsetFromHome, const Duration(hours: -13));
    });

    test('is negative and carries minutes when home is a half-hour zone', () {
      final model = buildModel(home: _kolkata, zoneIds: [_saoPaulo]);

      expect(
        _tile(model, _saoPaulo).offsetFromHome,
        const Duration(hours: -8, minutes: -30),
      );
    });

    test('is zero for the home zone itself, hero and row alike', () {
      final model = buildModel(home: _saoPaulo, zoneIds: [_saoPaulo, _tokyo]);

      expect(model.home.offsetFromHome, Duration.zero);
      expect(_tile(model, _saoPaulo).offsetFromHome, Duration.zero);
      expect(_tile(model, _saoPaulo).isHome, isTrue);
      expect(_tile(model, _tokyo).isHome, isFalse);
    });

    test('resolves for the instant, not for a stored offset', () {
      // New York is 1 hour behind Sao Paulo in June and 2 in January: the two
      // zones' DST seasons do not line up, so a difference cached in June is
      // wrong for half the year.
      final june = buildModel(home: _saoPaulo, zoneIds: [_newYork]);
      final january = buildModel(
        home: _saoPaulo,
        zoneIds: [_newYork],
        nowInstant: _januaryUtc,
      );

      expect(_tile(june, _newYork).offsetFromHome, const Duration(hours: -1));
      expect(
        _tile(january, _newYork).offsetFromHome,
        const Duration(hours: -2),
      );
    });
  });

  group('day delta (rule 6)', () {
    test('is zero when the two zones share a calendar date', () {
      final model = buildModel(home: _saoPaulo, zoneIds: [_tokyo]);

      expect(_tile(model, _tokyo).dayDelta, 0);
      expect(model.home.dayDelta, 0);
    });

    test('is +1 for a zone already on the next date', () {
      final model = buildModel(home: _niue, zoneIds: [_kiritimati]);

      // Niue reads 01:30 on 15 June; Kiritimati reads 02:30 on the 16th.
      expect(model.home.localTime.day, 15);
      expect(_tile(model, _kiritimati).localTime.day, 16);
      expect(_tile(model, _kiritimati).dayDelta, 1);
    });

    test('is -1 for a zone still on the previous date', () {
      final model = buildModel(home: _kiritimati, zoneIds: [_niue]);

      expect(model.home.localTime.day, 16);
      expect(_tile(model, _niue).localTime.day, 15);
      expect(_tile(model, _niue).dayDelta, -1);
    });

    test('reports a real two-day gap rather than clamping to -1', () {
      // Kiritimati (+14:00) and Niue (-11:00) are 25 hours apart, so for one
      // hour a day they are two calendar days apart. Clamping would print
      // "Yesterday" for the day before yesterday.
      final model = buildModel(
        home: _kiritimati,
        zoneIds: [_niue],
        nowInstant: _twoDaysApartUtc,
      );

      expect(model.home.localTime.day, 16);
      expect(_tile(model, _niue).localTime.day, 14);
      expect(_tile(model, _niue).dayDelta, -2);
    });
  });

  group('hour band (rule 7)', () {
    test('classifies every band from one instant', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _newYork, _tokyo, _kiritimati],
      );

      // 09:30, inside the 09:00-17:00 window.
      expect(_tile(model, _saoPaulo).band, HourBand.good);
      // 08:30, the hour before it opens.
      expect(_tile(model, _newYork).band, HourBand.fair);
      // 21:30: awake, but well outside working hours.
      expect(_tile(model, _tokyo).band, HourBand.poor);
      // 02:30.
      expect(_tile(model, _kiritimati).band, HourBand.night);
    });

    test('follows the user working window rather than the clock', () {
      // A 22:00-06:00 night shift: 21:30 is the hour before the shift starts
      // and 02:30 is the middle of it, so the two verdicts swap.
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_tokyo, _kiritimati],
        workingHours: const WorkingHours(startHour: 22, endHour: 6),
      );

      expect(_tile(model, _tokyo).band, HourBand.fair);
      expect(_tile(model, _kiritimati).band, HourBand.good);
    });
  });

  group('daylight saving (rule 8)', () {
    test('flags a zone observing DST at the instant shown', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_berlin, _newYork, _tokyo, _karachi],
      );

      expect(_tile(model, _berlin).isDst, isTrue);
      expect(_tile(model, _berlin).abbreviation, 'CEST');
      expect(_tile(model, _newYork).isDst, isTrue);
      // Neither zone has observed DST for over a decade.
      expect(_tile(model, _tokyo).isDst, isFalse);
      expect(_tile(model, _tokyo).abbreviation, 'JST');
      expect(_tile(model, _karachi).isDst, isFalse);
      // Brazil abolished DST in 2019, so the home row never flags it.
      expect(model.home.isDst, isFalse);
    });

    test('clears the flag on the same zone in the other season', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_berlin],
        nowInstant: _januaryUtc,
      );

      expect(_tile(model, _berlin).isDst, isFalse);
      expect(_tile(model, _berlin).abbreviation, 'CET');
    });
  });

  group('the home hero (rules 1 and 11)', () {
    test('an empty board still produces a home clock', () {
      final model = buildModel(home: _saoPaulo);

      expect(model.tiles, isEmpty);
      expect(model.home.isHome, isTrue);
      expect(model.home.localTime.hour, 9);
      expect(model.homeHasBoardRow, isFalse);
      expect(model.homeZoneUnresolved, isFalse);
    });

    test('names a home zone with no row from the fallback label', () {
      final model = buildModel(home: _saoPaulo, homeFallbackLabel: 'Base');

      expect(model.home.location.label, 'Base');
      expect(
        model.home.location.id,
        BuildWorldClockUseCase.homeWithoutRowId,
      );
      expect(model.home.location.zoneId, _saoPaulo);
    });

    test('borrows the board row when the home zone has one', () {
      final model = buildModel(home: _saoPaulo, zoneIds: [_tokyo, _saoPaulo]);

      expect(model.homeHasBoardRow, isTrue);
      expect(model.home.location.label, 'Sao Paulo');
      expect(model.home.location.id, 'row-1-$_saoPaulo');
      // The row keeps its place in the list as well: the hero is a second
      // reading of it, not a move (rule 2).
      expect(model.tiles.map((tile) => tile.location.zoneId), [
        _tokyo,
        _saoPaulo,
      ]);
    });

    test('matches a home row spelled with a legacy alias', () {
      // `Brazil/East` and `America/Sao_Paulo` are one clock under two
      // spellings, so the board row must still be recognised as home.
      final model = buildModel(
        home: _saoPauloLegacy,
        zoneIds: [_saoPaulo],
      );

      expect(model.homeHasBoardRow, isTrue);
      expect(model.home.location.id, 'row-0-$_saoPaulo');
      expect(_tile(model, _saoPaulo).isHome, isTrue);
    });

    test('keeps board order and one tile per saved row', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_tokyo, _berlin, _kolkata],
      );

      expect(model.tiles.map((tile) => tile.location.zoneId), [
        _tokyo,
        _berlin,
        _kolkata,
      ]);
    });
  });

  group('unresolved zones', () {
    test('falls the home zone back to UTC and says so', () {
      final model = buildModel(home: _unknownZone, zoneIds: [_tokyo]);

      expect(model.homeZoneUnresolved, isTrue);
      expect(model.home.isUnresolved, isTrue);
      expect(model.home.offsetFromUtc, Duration.zero);
      expect(model.home.localTime.hour, 12);
      // Every offset on the page is then measured from UTC.
      expect(_tile(model, _tokyo).offsetFromHome, const Duration(hours: 9));
    });

    test('keeps an unresolved row in place instead of dropping it', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_tokyo, _unknownZone],
      );

      expect(model.tiles, hasLength(2));
      final orphan = _tile(model, _unknownZone);
      expect(orphan.isUnresolved, isTrue);
      expect(_tile(model, _tokyo).isUnresolved, isFalse);
      // UTC stands in for the missing zone, which is what the greyed tile
      // exists to warn about.
      expect(orphan.offsetFromUtc, Duration.zero);
      expect(orphan.offsetFromHome, const Duration(hours: 3));
    });
  });
}

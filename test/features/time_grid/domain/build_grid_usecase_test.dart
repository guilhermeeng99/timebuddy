import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/time_grid/domain/entities/grid_view_model.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';

import '../../../harness/helpers.dart';

// Every date below is a real IANA transition, pinned to its year because an
// offset is a function of an instant and 2024's rules are not 2018's:
//
//   America/New_York 2024 - springs forward 10 March, 02:00 EST -> 03:00 EDT
//     (07:00 UTC), so that local day is 23 hours; falls back 3 November,
//     02:00 EDT -> 01:00 EST (06:00 UTC), so that one is 25.
//   America/Sao_Paulo - DST abolished in 2019, so it sits at -03:00 all
//     through 2024 and makes a reference row that never moves.
//   Australia/Lord_Howe 2024 - springs forward 6 October, 02:00 (+10:30) ->
//     02:30 (+11:00), i.e. 15:30 UTC on 5 October. The jump is 30 minutes, so
//     the row's minutes change mid-window.
//   America/Santiago 2024 - springs forward at 00:00 local on 8 September
//     (04:00 UTC), so that local day has no midnight and begins on the change.
//   Asia/Kolkata is +05:30 and Asia/Kathmandu +05:45 all year, no DST.
//   Pacific/Kiritimati is +14:00 and Pacific/Niue -11:00 all year: 25 hours
//     apart, which is how two rows of one grid land on different dates.
//   24 September 2024 is a Tuesday, so an English date label reads 'Tue 24'.

const String _utc = 'UTC';
const String _saoPaulo = 'America/Sao_Paulo';
const String _saoPauloLegacy = 'Brazil/East';
const String _newYork = 'America/New_York';
const String _santiago = 'America/Santiago';
const String _tokyo = 'Asia/Tokyo';
const String _kolkata = 'Asia/Kolkata';
const String _kathmandu = 'Asia/Kathmandu';
const String _kiritimati = 'Pacific/Kiritimati';
const String _niue = 'Pacific/Niue';
const String _lordHowe = 'Australia/Lord_Howe';
const String _brisbane = 'Australia/Brisbane';

/// A zone id no tzdata release will ever carry, so `zoneOrNull` returns null
/// and the row takes the unresolved path (rule 14).
const String _unknownZone = 'Mars/Olympus_Mons';

const Duration _hour = Duration(hours: 1);

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

GridRow _row(GridViewModel model, String zoneId) =>
    model.rows.firstWhere((row) => row.location.zoneId == zoneId);

List<int> _localHours(GridRow row) => [
  for (final cell in row.cells) cell.localTime.hour,
];

/// The reference day's own hour count, with the flanking slots taken back
/// off. Stated separately from the window total because 23 and 25 are the
/// numbers rule 2 is about; a total of 29 or 31 only implies them.
int _dayLength(GridViewModel model) =>
    model.slots.length - 2 * BuildGridUseCase.flankSlots;

List<int> _dayStartIndexes(GridRow row) => [
  for (var i = 0; i < row.cells.length; i++)
    if (row.cells[i].isDayStart) i,
];

/// Whether two neighbouring cells read the same wall-clock hour, which is the
/// fingerprint of a fall-back inside the window and cannot happen on a row
/// built by adding an hour to its predecessor.
bool _repeatsAnHour(GridRow row) {
  for (var i = 1; i < row.cells.length; i++) {
    if (row.cells[i].localTime.hour == row.cells[i - 1].localTime.hour) {
      return true;
    }
  }
  return false;
}

void main() {
  final engine = TzTimeZoneEngine();
  final buildGrid = BuildGridUseCase(engine: engine);

  setUpAll(() async {
    initTestTimeZones();
    // formatDayMonth reads intl's date symbols, which the app gets from
    // flutter_localizations and a test process has to load itself.
    await initializeDateFormatting();
    await engine.initialize();
  });

  GridViewModel buildModel({
    required String home,
    required DateTime referenceDate,
    List<String> zoneIds = const [],
    WorkingHours workingHours = WorkingHours.defaultHours,
    DateTime? nowInstant,
    DateTime? cursorInstant,
    String localeTag = 'en',
  }) {
    return buildGrid(
      board: _board(home, zoneIds),
      workingHours: workingHours,
      referenceDate: referenceDate,
      nowInstant: nowInstant ?? utcDate(2024, 9, 24, 12),
      cursorInstant: cursorInstant,
      localeTag: localeTag,
    );
  }

  group('rule 1: the home zone defines the columns', () {
    test('column n is the same instant in every row on 2024-09-24', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _tokyo],
        referenceDate: utcDate(2024, 9, 24),
      );

      for (var i = 0; i < model.slots.length; i++) {
        expect(_row(model, _saoPaulo).cells[i].instant, model.slots[i]);
        expect(_row(model, _tokyo).cells[i].instant, model.slots[i]);
      }
      // Rows are never aligned to their own midnight: Tokyo opens the window
      // on the following calendar day and still shares column 0.
      expect(_row(model, _tokyo).cells.first.localTime.day, 24);
      expect(_row(model, _saoPaulo).cells.first.localTime.day, 23);
    });

    test('the row whose zone is the home zone is flagged home', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_tokyo, _saoPaulo],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(_row(model, _saoPaulo).isHome, isTrue);
      expect(_row(model, _tokyo).isHome, isFalse);
    });

    test('a legacy alias of the home zone is still the home row', () {
      // Brazil/East canonicalises onto America/Sao_Paulo, so comparing raw
      // stored ids would leave the board with no home row at all.
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPauloLegacy],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(model.rows.single.isHome, isTrue);
    });

    test('rows keep the board order', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_tokyo, _kolkata, _saoPaulo],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(
        model.rows.map((row) => row.location.zoneId),
        [_tokyo, _kolkata, _saoPaulo],
      );
    });
  });

  group('rule 2: the column count comes from the engine', () {
    test('a plain day is 24 slots, 30 with the flanks (2024-09-24)', () {
      final model = buildModel(
        home: _newYork,
        zoneIds: [_newYork],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(_dayLength(model), 24);
      expect(model.slots.length, 30);
      expect(model.rows.single.cells.length, 30);
    });

    test('the 2024-11-03 New York fall-back day is 25 slots, 31 total', () {
      final model = buildModel(
        home: _newYork,
        zoneIds: [_newYork, _tokyo],
        referenceDate: utcDate(2024, 11, 3),
      );

      expect(_dayLength(model), 25);
      expect(model.slots.length, 31);
      for (final row in model.rows) {
        expect(row.cells.length, 31);
      }
    });

    test('the 2024-03-10 New York spring-forward day is 23 slots, 29', () {
      final model = buildModel(
        home: _newYork,
        zoneIds: [_newYork, _tokyo],
        referenceDate: utcDate(2024, 3, 10),
      );

      expect(_dayLength(model), 23);
      expect(model.slots.length, 29);
      for (final row in model.rows) {
        expect(row.cells.length, 29);
      }
    });

    test('the reference row has no 02:00 column on 2024-03-10', () {
      final model = buildModel(
        home: _newYork,
        zoneIds: [_newYork],
        referenceDate: utcDate(2024, 3, 10),
      );
      final cells = model.rows.single.cells;

      // 01:00 is followed straight by 03:00, and the skipped hour simply has
      // no column: an implementation iterating 0..23 would show 02:00 here.
      expect(cells[4].localTime.hour, 1);
      expect(cells[5].localTime.hour, 3);
      expect(cells[5].instant, utcDate(2024, 3, 10, 7));
      expect(cells[5].hasTransition, isTrue);
      expect(cells[4].hasTransition, isFalse);
    });

    test('the reference row shows 01:00 twice on 2024-11-03', () {
      final model = buildModel(
        home: _newYork,
        zoneIds: [_newYork],
        referenceDate: utcDate(2024, 11, 3),
      );
      final cells = model.rows.single.cells;

      expect(cells[4].localTime.hour, 1);
      expect(cells[5].localTime.hour, 1);
      expect(cells[4].instant, utcDate(2024, 11, 3, 5));
      expect(cells[5].instant, utcDate(2024, 11, 3, 6));
      expect(cells[5].hasTransition, isTrue);
    });
  });

  group('rule 3: the window is the day plus three slots either side', () {
    test('it opens three hours before local midnight in the home zone', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo],
        referenceDate: utcDate(2024, 9, 24),
      );
      final cells = model.rows.single.cells;

      // Sao Paulo is -03:00, so its 24 September starts at 03:00 UTC.
      expect(model.slots.first, utcDate(2024, 9, 24));
      expect(model.slots.last, utcDate(2024, 9, 25, 5));
      expect(model.slots.length, 30);
      expect(_localHours(model.rows.single).take(3).toList(), [21, 22, 23]);
      expect(cells.first.localTime.day, 23);
      expect(cells.last.localTime.day, 25);
      expect(cells.last.localTime.hour, 2);
    });

    test('the flanks come from the neighbouring days on a DST day', () {
      // The ends of the window are the neighbouring days' own edge slots, so
      // a 23-hour and a 25-hour reference day both keep exactly three columns
      // on each side and both stay anchored to a real local midnight.
      final springForward = buildModel(
        home: _newYork,
        zoneIds: [_newYork],
        referenceDate: utcDate(2024, 3, 10),
      );
      final fallBack = buildModel(
        home: _newYork,
        zoneIds: [_newYork],
        referenceDate: utcDate(2024, 11, 3),
      );

      expect(springForward.slots.first, utcDate(2024, 3, 10, 2));
      expect(springForward.slots.last, utcDate(2024, 3, 11, 6));
      expect(fallBack.slots.first, utcDate(2024, 11, 3, 1));
      expect(fallBack.slots.last, utcDate(2024, 11, 4, 7));
    });

    test('a day that begins on its own transition still gets its flanks', () {
      // America/Santiago springs forward at 00:00 local on 2024-09-08, so
      // that day has no midnight at all and starts on the change itself.
      final model = buildModel(
        home: _santiago,
        zoneIds: [_santiago],
        referenceDate: utcDate(2024, 9, 8),
      );
      final cells = model.rows.single.cells;

      expect(_dayLength(model), 23);
      expect(model.slots.length, 29);
      expect(model.slots.first, utcDate(2024, 9, 8, 1));
      expect(cells[2].localTime.hour, 23);
      expect(cells[3].instant, utcDate(2024, 9, 8, 4));
      expect(cells[3].localTime.hour, 1);
      expect(cells[3].hasTransition, isTrue);
    });

    test('every slot is exactly one real hour after the previous one', () {
      final model = buildModel(
        home: _newYork,
        zoneIds: [_newYork],
        referenceDate: utcDate(2024, 3, 10),
      );

      // 23 columns are 23 *real* hours: a window built from local arithmetic
      // would leave a two-hour gap where the clocks jumped.
      for (var i = 1; i < model.slots.length; i++) {
        expect(model.slots[i].difference(model.slots[i - 1]), _hour);
      }
    });
  });

  group('rule 4: every cell is derived from its own instant', () {
    test('New York repeats 01:00 on 2024-11-03 while Sao Paulo does not', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _newYork],
        referenceDate: utcDate(2024, 11, 3),
      );
      final home = _row(model, _saoPaulo);
      final newYork = _row(model, _newYork);

      expect(_repeatsAnHour(newYork), isTrue);
      expect(_repeatsAnHour(home), isFalse);
      expect(newYork.cells[5].localTime.hour, 1);
      expect(newYork.cells[6].localTime.hour, 1);
      expect(newYork.cells[5].instant, utcDate(2024, 11, 3, 5));
      expect(newYork.cells[6].instant, utcDate(2024, 11, 3, 6));
      // Same wall clock, two different instants: only a per-cell conversion
      // can produce that.
      expect(
        newYork.cells[6].instant.difference(newYork.cells[5].instant),
        _hour,
      );
    });

    test('the transition is flagged on the row that has it, not the grid', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _newYork],
        referenceDate: utcDate(2024, 11, 3),
      );

      expect(_row(model, _newYork).cells[6].hasTransition, isTrue);
      expect(_row(model, _newYork).cells[5].hasTransition, isFalse);
      expect(
        _row(model, _saoPaulo).cells.every((cell) => !cell.hasTransition),
        isTrue,
      );
    });

    test('the reference row advances one hour per column that day', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo],
        referenceDate: utcDate(2024, 11, 3),
      );
      final cells = model.rows.single.cells;

      expect(cells.first.localTime.hour, 21);
      expect(cells[6].localTime.hour, 3);
    });
  });

  group('rule 5: fractional offsets keep their minutes', () {
    test('Asia/Kolkata reads :30 in every cell against Sao Paulo', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _kolkata],
        referenceDate: utcDate(2024, 9, 24),
      );
      final kolkata = _row(model, _kolkata);

      expect(kolkata.relativeToHome, const Duration(hours: 8, minutes: 30));
      expect(kolkata.cells.first.localTime.hour, 5);
      for (final cell in kolkata.cells) {
        expect(cell.localTime.minute, 30);
        expect(cell.hasOffsetMinutes, isTrue);
      }
      expect(
        _row(model, _saoPaulo).cells.every((cell) => !cell.hasOffsetMinutes),
        isTrue,
      );
    });

    test('Asia/Kathmandu reads :45 in every cell against Sao Paulo', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_kathmandu],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(
        model.rows.single.relativeToHome,
        const Duration(hours: 8, minutes: 45),
      );
      for (final cell in model.rows.single.cells) {
        expect(cell.localTime.minute, 45);
      }
    });

    test('Lord Howe loses its :30 mid-window on 2024-10-06', () {
      final model = buildModel(
        home: _brisbane,
        zoneIds: [_lordHowe],
        referenceDate: utcDate(2024, 10, 6),
      );
      final cells = model.rows.single.cells;

      // +10:30 -> +11:00 at 15:30 UTC on 5 October, inside the slot that
      // opens at 15:00 UTC. A per-row minute would still read :30 afterwards.
      expect(cells[4].instant, utcDate(2024, 10, 5, 15));
      expect(cells[4].hasTransition, isTrue);
      expect(cells[4].localTime.minute, 30);
      expect(cells[4].hasOffsetMinutes, isTrue);
      expect(cells[5].localTime.minute, 0);
      expect(cells[5].hasOffsetMinutes, isFalse);
      expect(cells.first.localTime.minute, 30);
      expect(cells.last.localTime.minute, 0);
    });
  });

  group('rule 6: day boundaries are marked per row', () {
    test('Kiritimati and Niue turn the date on different columns', () {
      final model = buildModel(
        home: _utc,
        zoneIds: [_kiritimati, _niue],
        referenceDate: utcDate(2024, 9, 24),
      );
      final kiritimati = _row(model, _kiritimati);
      final niue = _row(model, _niue);

      // 25 hours apart: at column 13 Kiritimati is already on Wednesday while
      // Niue is still on Monday. One global boundary line would be wrong for
      // one of them.
      expect(_dayStartIndexes(kiritimati), [13]);
      expect(_dayStartIndexes(niue), [14]);
      expect(kiritimati.cells[13].dateLabel, 'Wed 25');
      expect(niue.cells[14].dateLabel, 'Tue 24');
      expect(kiritimati.cells[13].instant, niue.cells[13].instant);
    });

    test('a UTC row marks both midnights inside the window', () {
      final model = buildModel(
        home: _utc,
        zoneIds: [_utc],
        referenceDate: utcDate(2024, 9, 24),
      );
      final cells = model.rows.single.cells;

      expect(_dayStartIndexes(model.rows.single), [3, 27]);
      expect(cells[3].dateLabel, 'Tue 24');
      expect(cells[27].dateLabel, 'Wed 25');
    });

    test('the first cell never opens a day', () {
      final model = buildModel(
        home: _utc,
        zoneIds: [_utc, _kiritimati, _niue],
        referenceDate: utcDate(2024, 9, 24),
      );

      for (final row in model.rows) {
        expect(row.cells.first.isDayStart, isFalse);
        expect(row.cells.first.dateLabel, isNull);
      }
    });

    test('dateLabel is present exactly when isDayStart is set', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _kolkata, _tokyo],
        referenceDate: utcDate(2024, 9, 24),
      );

      for (final row in model.rows) {
        for (final cell in row.cells) {
          expect(cell.dateLabel != null, cell.isDayStart);
        }
      }
    });

    test('date labels are formatted under the locale tag', () {
      final model = buildModel(
        home: _utc,
        zoneIds: [_utc],
        referenceDate: utcDate(2024, 9, 24),
        localeTag: 'pt-BR',
      );

      expect(
        model.rows.single.cells[3].dateLabel!.toLowerCase(),
        startsWith('ter'),
      );
    });
  });

  group('rule 7: bands come from the working window', () {
    test('a night shift makes 23:00 good where the default makes it night', () {
      GridRow rowWith(WorkingHours workingHours) => buildModel(
        home: _utc,
        zoneIds: [_utc],
        referenceDate: utcDate(2024, 9, 24),
        workingHours: workingHours,
      ).rows.single;

      final nightShift = rowWith(
        const WorkingHours(startHour: 22, endHour: 6),
      );
      final office = rowWith(WorkingHours.defaultHours);

      expect(nightShift.cells[26].localTime.hour, 23);
      expect(nightShift.cells[26].band, HourBand.good);
      expect(office.cells[26].band, HourBand.night);
      // The window moved, so midday changed sides too.
      expect(nightShift.cells[15].localTime.hour, 12);
      expect(nightShift.cells[15].band, HourBand.poor);
      expect(office.cells[15].band, HourBand.good);
    });

    test('the default window bands 17:00 fair and 19:00 poor', () {
      final model = buildModel(
        home: _utc,
        zoneIds: [_utc],
        referenceDate: utcDate(2024, 9, 24),
      );
      final cells = model.rows.single.cells;

      expect(cells[20].localTime.hour, 17);
      expect(cells[20].band, HourBand.fair);
      expect(cells[22].localTime.hour, 19);
      expect(cells[22].band, HourBand.poor);
    });

    test('a band follows the row local hour, not the reference hour', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _tokyo],
        referenceDate: utcDate(2024, 9, 24),
      );

      // One instant, 15:00 UTC: noon in Sao Paulo, midnight in Tokyo.
      expect(_row(model, _saoPaulo).cells[15].localTime.hour, 12);
      expect(_row(model, _saoPaulo).cells[15].band, HourBand.good);
      expect(_row(model, _tokyo).cells[15].localTime.hour, 0);
      expect(_row(model, _tokyo).cells[15].band, HourBand.night);
    });
  });

  group('rule 14: an unresolved row keeps its place', () {
    test('it carries no cells, no zone state and no offset', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_unknownZone],
        referenceDate: utcDate(2024, 9, 24),
      );
      final row = model.rows.single;

      expect(row.isUnresolved, isTrue);
      expect(row.cells, isEmpty);
      expect(row.zoneState, isNull);
      expect(row.relativeToHome, Duration.zero);
      expect(row.isHome, isFalse);
      expect(row.location.zoneId, _unknownZone);
    });

    test('the rows around it are unaffected and the order holds', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo, _unknownZone, _tokyo],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(model.rows.map((row) => row.isUnresolved), [false, true, false]);
      expect(model.rows[0].cells.length, model.slots.length);
      expect(model.rows[2].cells.length, model.slots.length);
      expect(model.rows[1].location.sortIndex, 1);
    });
  });

  group('an unresolved home zone falls back to UTC', () {
    test('the flag is set and the columns are UTC hours', () {
      final model = buildModel(
        home: _unknownZone,
        zoneIds: [_tokyo],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(model.homeZoneUnresolved, isTrue);
      expect(model.referenceDate, utcDate(2024, 9, 24));
      expect(model.slots.first, utcDate(2024, 9, 23, 21));
      expect(model.slots.length, 30);
      // The board still renders: the page banners the broken home zone
      // instead of going blank.
      expect(model.rows.single.cells.length, 30);
      expect(model.rows.single.relativeToHome, const Duration(hours: 9));
    });

    test('the flag is clear for a home zone that resolves', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(model.homeZoneUnresolved, isFalse);
    });
  });

  group('zone state and offsets', () {
    test('they answer for the reference day, not for now', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_newYork],
        referenceDate: utcDate(2024, 1, 15),
        nowInstant: utcDate(2024, 7, 15, 12),
      );
      final newYork = model.rows.single;

      // Reading the badge off `nowInstant` would print EDT and -1h here, both
      // of which are wrong for the day on screen.
      expect(newYork.zoneState?.offset, const Duration(hours: -5));
      expect(newYork.zoneState?.abbreviation, 'EST');
      expect(newYork.zoneState?.isDst, isFalse);
      expect(newYork.relativeToHome, const Duration(hours: -2));
    });

    test('the home row carries a zero relative offset', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(model.rows.single.relativeToHome, Duration.zero);
      expect(model.rows.single.zoneState?.zoneId, _saoPaulo);
    });
  });

  group('model plumbing', () {
    test('nowInstant and cursorInstant are carried through untouched', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo],
        referenceDate: utcDate(2024, 9, 24),
        nowInstant: utcDate(2024, 9, 24, 15, 7, 42),
        cursorInstant: utcDate(2024, 9, 24, 18),
      );

      expect(model.nowInstant, utcDate(2024, 9, 24, 15, 7, 42));
      expect(model.cursorInstant, utcDate(2024, 9, 24, 18));
    });

    test('there is no cursor unless one is passed', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo],
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(model.cursorInstant, isNull);
    });

    test('referenceDate is reduced to the local date it names', () {
      final model = buildModel(
        home: _saoPaulo,
        zoneIds: [_saoPaulo],
        referenceDate: utcDate(2024, 9, 24, 17, 42),
      );

      expect(model.referenceDate, utcDate(2024, 9, 24));
      expect(model.slots.first, utcDate(2024, 9, 24));
    });

    test('an empty board still produces the column window', () {
      final model = buildModel(
        home: _saoPaulo,
        referenceDate: utcDate(2024, 9, 24),
      );

      expect(model.rows, isEmpty);
      expect(model.slots.length, 30);
    });
  });
}

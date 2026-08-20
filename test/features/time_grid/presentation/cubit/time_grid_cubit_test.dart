import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/domain/entities/grid_view_model.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_cubit.dart';

import '../../../../harness/factories/preferences_factory.dart';
import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

// Every instant below is either a real IANA transition or a deliberate
// distance from one:
//
//   America/Sao_Paulo abolished DST in 2019, so it sits at -03:00 all through
//     2024 and gives a reference zone whose days are all 24 hours long. At
//     2024-06-15 02:00 UTC it is still 2024-06-14 there, which is how a
//     "today" read off the instant instead of out of the home zone shows up
//     as a wrong reference date rather than as a passing test.
//   America/New_York 2024 falls back on 3 November, 02:00 EDT -> 01:00 EST
//     (06:00 UTC). That local day is 25 hours long, and 14:00 sits at 19:00
//     UTC on it against the 18:00 UTC it occupied the day before. That single
//     hour is the whole of rule 10: a cubit that kept the cursor's *instant*,
//     or that added 24 hours to it, lands the user on 13:00.
const String _saoPaulo = 'America/Sao_Paulo';
const String _tokyo = 'Asia/Tokyo';
const String _kolkata = 'Asia/Kolkata';
const String _newYork = 'America/New_York';
const String _london = 'Europe/London';

/// A zone id no tzdata release will ever carry, so `zoneOrNull` returns null
/// and the home zone takes the unresolved path.
const String _unknownZone = 'Mars/Olympus_Mons';

/// Slots in a window whose reference day is an ordinary 24-hour one (rule 3).
const int _plainWindowSlots = 24 + 2 * BuildGridUseCase.flankSlots;

/// Slots in a window whose reference day is New York's 25-hour 3 November.
const int _fallBackWindowSlots = 25 + 2 * BuildGridUseCase.flankSlots;

/// A board state carrying no board: initial, or a refresh in flight.
const BoardState _boardPending = BoardLoading();

/// The board could not be read at all.
const BoardState _boardFailed = BoardError(failure: StorageFailure());

/// 2024-06-15 02:00 UTC, which is 2024-06-14 23:00 in Sao Paulo.
final DateTime _eveningInSaoPaulo = utcDate(2024, 6, 15, 2);

/// 2024-11-02 18:00 UTC: 14:00 EDT, the day before New York falls back.
final DateTime _afternoonBeforeFallBack = utcDate(2024, 11, 2, 18);

/// The board state a loaded `BoardCubit` publishes.
///
/// Every `BoardState` this file builds goes through this helper and the two
/// constants above, on purpose. `BoardCubit` is being written alongside these
/// tests, and the grid reads exactly two things out of it —
/// `BoardLoaded.board` and `BoardError.failure` — so if the state class lands
/// carrying more than docs/specs/locations.md lists, three lines here absorb
/// it instead of forty call sites.
BoardState _loaded(BoardEntity board) => BoardLoaded(board: board);

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

GridRow _rowOf(GridViewModel model, String zoneId) =>
    model.rows.firstWhere((row) => row.location.zoneId == zoneId);

/// The band the row is painting on its cell for [localHour].
///
/// Read back off the model rather than recomputed: the claim is that a
/// preference change reached the cells, and calling `hourBandFor` here would
/// compare the test's arithmetic against itself.
HourBand _bandAtLocalHour(GridRow row, int localHour) =>
    row.cells.firstWhere((cell) => cell.localTime.hour == localHour).band;

/// The session's `BoardCubit`, which the grid subscribes to and never writes.
///
/// A mock rather than a real cubit with a stubbed repository: this file is
/// about what the grid does *with* a board state, and driving the real one
/// would make every case here depend on the board's own persistence path
/// (CLAUDE.md: mock at boundaries).
class _MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

/// `BuildGridUseCase` with a call counter in front of the real one.
///
/// The state machine's performance claim is about *how often* the model is
/// rebuilt: a tick must not, a board or preference change must
/// (time_grid.md, Performance). A count states that directly. Asserting on the
/// emitted model cannot: a full rebuild that happened to produce equal values
/// is indistinguishable from the cheap `copyWith` the spec asks for.
class _CountingBuildGrid implements BuildGridUseCase {
  _CountingBuildGrid(BuildGridUseCase delegate) : _delegate = delegate;

  final BuildGridUseCase _delegate;

  int calls = 0;

  @override
  GridViewModel call({
    required BoardEntity board,
    required WorkingHours workingHours,
    required DateTime referenceDate,
    required DateTime nowInstant,
    DateTime? cursorInstant,
    String localeTag = 'en',
  }) {
    calls++;
    return _delegate(
      board: board,
      workingHours: workingHours,
      referenceDate: referenceDate,
      nowInstant: nowInstant,
      cursorInstant: cursorInstant,
      localeTag: localeTag,
    );
  }
}

void main() {
  final engine = TzTimeZoneEngine();

  setUpAll(() async {
    initTestTimeZones();
    registerCommonFallbacks();
    // formatDayMonth reads intl's date symbols, which the app gets from
    // flutter_localizations and a test process has to load itself.
    await initializeDateFormatting();
    await engine.initialize();
  });

  final saoPauloBoard = _board(_saoPaulo, [_saoPaulo, _tokyo]);
  final newYorkBoard = _board(_newYork, [_newYork, _london]);

  late StreamController<BoardState> boardStates;
  late _MockBoardCubit boardCubit;
  late MockPreferencesRepository preferencesRepository;
  late PreferencesCubit preferences;
  late FakeClock clock;
  late _CountingBuildGrid buildGrid;

  /// Points the mock at [initial] and at the controller later states arrive
  /// through.
  void seedBoard(BoardState initial) =>
      whenListen(boardCubit, boardStates.stream, initialState: initial);

  TimeGridCubit buildCubit() => TimeGridCubit(
    boardCubit: boardCubit,
    preferencesCubit: preferences,
    buildGrid: buildGrid,
    engine: engine,
    clock: clock,
  );

  /// A started cubit, holding the board and reading the clock a test needs.
  Future<TimeGridCubit> startGrid({
    BoardEntity? board,
    DateTime? nowUtc,
  }) async {
    if (nowUtc != null) clock.setTo(nowUtc);
    if (board != null) seedBoard(_loaded(board));
    final cubit = buildCubit()..start();
    addTearDown(cubit.close);
    await pumpEventQueue();
    return cubit;
  }

  /// Pushes [state] through `BoardCubit.stream` and lets the grid react.
  Future<void> publishBoard(BoardState state) async {
    boardStates.add(state);
    await pumpEventQueue();
  }

  GridViewModel modelOf(TimeGridCubit cubit) {
    final state = cubit.state;
    expect(state, isA<TimeGridReady>(), reason: 'expected a drawable grid');
    return (state as TimeGridReady).model;
  }

  setUp(() async {
    clock = FakeClock(_eveningInSaoPaulo);
    buildGrid = _CountingBuildGrid(BuildGridUseCase(engine: engine));

    boardStates = StreamController<BoardState>.broadcast();
    addTearDown(boardStates.close);
    boardCubit = _MockBoardCubit();

    preferencesRepository = MockPreferencesRepository();
    final document = aPreferences();
    when(
      () => preferencesRepository.load(
        deviceLocale: any(named: 'deviceLocale'),
      ),
    ).thenAnswer((_) async => Right<Failure, PreferencesEntity>(document));
    when(
      () => preferencesRepository.save(any()),
    ).thenAnswer((_) async => Right<Failure, PreferencesEntity>(document));

    preferences = PreferencesCubit(
      repository: preferencesRepository,
      clock: clock,
    );
    addTearDown(preferences.close);
    // Seeded through `load`, so the grid reads the state the real startup path
    // produces rather than one emitted by hand.
    await preferences.load(deviceLocale: const Locale('en'));

    seedBoard(_loaded(saoPauloBoard));
  });

  group('state machine', () {
    test('starts in TimeGridLoading, before start() subscribes', () {
      // bloc_test records emissions, not the initial value, so the one state
      // the page renders on its very first frame has to be asserted here.
      final cubit = buildCubit();
      addTearDown(cubit.close);

      expect(cubit.state, const TimeGridLoading());
    });

    blocTest<TimeGridCubit, TimeGridState>(
      'publishes a grid for the board the session already holds',
      build: buildCubit,
      act: (cubit) async {
        cubit.start();
        await pumpEventQueue();
      },
      expect: () => [
        isA<TimeGridReady>()
            .having((state) => state.model.rows.length, 'rows', 2)
            .having(
              (state) => state.model.slots.length,
              'slots',
              _plainWindowSlots,
            )
            .having(
              (state) => state.model.nowInstant,
              'nowInstant',
              _eveningInSaoPaulo,
            )
            .having(
              (state) => state.model.cursorInstant,
              'cursorInstant',
              isNull,
            )
            .having(
              (state) => state.model.homeZoneUnresolved,
              'homeZoneUnresolved',
              isFalse,
            ),
      ],
    );

    test('opens on today in the HOME zone, not on the device date', () async {
      // 02:00 UTC on the 15th is 23:00 on the 14th in Sao Paulo. A cubit that
      // read the calendar date off the instant would open a day ahead of its
      // user, with nothing on screen saying the columns had moved.
      final cubit = await startGrid();

      expect(cubit.todayInHomeZone, utcDate(2024, 6, 14));
      expect(cubit.referenceZoneId, _saoPaulo);
      expect(modelOf(cubit).referenceDate, utcDate(2024, 6, 14));
    });

    blocTest<TimeGridCubit, TimeGridState>(
      'renders the empty state for a board with no locations',
      build: buildCubit,
      act: (cubit) async {
        seedBoard(_loaded(_board(_saoPaulo, const [])));
        cubit.start();
        await pumpEventQueue();
      },
      // A distinct state, not a ready model with zero rows: the page owes the
      // user an invitation, not a header strip over nothing.
      expect: () => [const TimeGridEmpty()],
    );

    blocTest<TimeGridCubit, TimeGridState>(
      'surfaces the failure when the board cannot be read',
      build: buildCubit,
      act: (cubit) async {
        seedBoard(_boardFailed);
        cubit.start();
        await pumpEventQueue();
      },
      expect: () => [const TimeGridError(failure: StorageFailure())],
    );

    test('stays loading while the board has not resolved', () async {
      seedBoard(_boardPending);
      final cubit = buildCubit()..start();
      addTearDown(cubit.close);
      await pumpEventQueue();

      expect(cubit.state, const TimeGridLoading());
      expect(buildGrid.calls, 0);
    });

    test('holds the last grid through a transient board state', () async {
      // A refresh re-emits BoardLoaded, so the only way back to a board-less
      // state with a grid already on screen is a transient one. Blanking a
      // screen the user is reading is worse than showing it one revision old.
      final cubit = await startGrid();
      final before = modelOf(cubit);

      await publishBoard(_boardPending);

      expect(cubit.state, isA<TimeGridReady>());
      expect(modelOf(cubit), same(before));
    });

    test('stops rebuilding once closed', () async {
      // A leaked subscription is not a quiet leak here: `emit` after `close`
      // throws, so the board's next revision would take the app down.
      final cubit = await startGrid();
      final builds = buildGrid.calls;
      await cubit.close();

      boardStates.add(
        _loaded(_board(_saoPaulo, [_saoPaulo, _tokyo, _kolkata])),
      );
      await pumpEventQueue();

      expect(buildGrid.calls, builds);
    });
  });

  group('a board change rebuilds', () {
    test('a row added to the board becomes a row on the grid', () async {
      final cubit = await startGrid();
      final builds = buildGrid.calls;

      await publishBoard(
        _loaded(_board(_saoPaulo, [_saoPaulo, _tokyo, _kolkata])),
      );

      final model = modelOf(cubit);
      expect(model.rows.length, 3);
      expect(_rowOf(model, _kolkata).cells, hasLength(model.slots.length));
      expect(buildGrid.calls, builds + 1);
    });

    test('a board emptied elsewhere collapses the grid', () async {
      final cubit = await startGrid();

      await publishBoard(_loaded(_board(_saoPaulo, const [])));

      expect(cubit.state, const TimeGridEmpty());
    });

    test('a new home zone re-aligns the columns', () async {
      final cubit = await startGrid();
      final firstSlotBefore = modelOf(cubit).slots.first;

      await publishBoard(_loaded(_board(_tokyo, [_saoPaulo, _tokyo])));

      final model = modelOf(cubit);
      expect(cubit.referenceZoneId, _tokyo);
      expect(_rowOf(model, _tokyo).isHome, isTrue);
      expect(_rowOf(model, _saoPaulo).isHome, isFalse);

      // The columns are the home zone's hours, so they move with it: column 0
      // is 21:00 the previous day in whichever zone is home (rule 3). Sao
      // Paulo and Tokyo are 12 hours apart, so a grid that kept the old
      // alignment would have every row half a day out.
      expect(firstSlotBefore, utcDate(2024, 6, 14));
      expect(
        engine.wallTimeAt(zoneId: _tokyo, instant: model.slots.first),
        utcDate(2024, 6, 13, 21),
      );
      // The day the user is looking at is theirs and does not jump, even
      // though "today" is now a different date in the new home zone.
      expect(model.referenceDate, utcDate(2024, 6, 14));
      expect(cubit.todayInHomeZone, utcDate(2024, 6, 15));
    });

    test('an unresolvable home zone falls back to UTC and says so', () async {
      final cubit = await startGrid(
        board: _board(_unknownZone, [_saoPaulo, _tokyo]),
      );

      final model = modelOf(cubit);
      expect(cubit.referenceZoneId, utcZoneId);
      expect(model.homeZoneUnresolved, isTrue);
      // It degrades, it does not go blank: the rows are still drawable.
      expect(model.rows.length, 2);
      expect(model.slots, hasLength(_plainWindowSlots));
    });
  });

  group('a preference change rebuilds', () {
    test('a new working window repaints the bands', () async {
      final cubit = await startGrid();
      final builds = buildGrid.calls;
      final before = _rowOf(modelOf(cubit), _saoPaulo);

      expect(_bandAtLocalHour(before, 14), HourBand.good);
      expect(_bandAtLocalHour(before, 23), HourBand.night);

      // A night shift inverts both hours: 14:00 leaves the window and 23:00
      // enters it. Asserting both directions is what separates "the bands were
      // recomputed" from "everything went one shade greyer".
      await preferences.setWorkingHours(
        const WorkingHours(startHour: 22, endHour: 6),
      );
      await pumpEventQueue();

      final after = _rowOf(modelOf(cubit), _saoPaulo);
      expect(_bandAtLocalHour(after, 14), HourBand.poor);
      expect(_bandAtLocalHour(after, 23), HourBand.good);
      expect(buildGrid.calls, builds + 1);
    });
  });

  group('the cursor', () {
    test('snaps to the slot holding the instant it was given', () async {
      final cubit = await startGrid();
      expect(modelOf(cubit).cursorInstant, isNull);

      // Twenty minutes past the hour. A cursor stored raw would highlight
      // nothing at all: every row compares its cell instant against this
      // value, and no cell instant is ever off the hour.
      cubit.setCursor(utcDate(2024, 6, 14, 17, 20));

      final model = modelOf(cubit);
      expect(model.cursorInstant, utcDate(2024, 6, 14, 17));
      expect(model.slots, contains(model.cursorInstant));
      expect(
        engine.wallTimeAt(zoneId: _saoPaulo, instant: model.cursorInstant!),
        utcDate(2024, 6, 14, 14),
      );
    });

    test('ignores an instant outside the visible window', () async {
      final cubit = await startGrid();
      final before = modelOf(cubit);

      cubit.setCursor(utcDate(2024, 6, 20, 12));

      expect(modelOf(cubit), same(before));
      expect(modelOf(cubit).cursorInstant, isNull);
    });

    test('clearCursor drops it', () async {
      final cubit = await startGrid();
      expect(modelOf(cubit).cursorInstant, isNull);

      cubit
        ..setCursor(utcDate(2024, 6, 14, 17))
        ..clearCursor();

      expect(modelOf(cubit).cursorInstant, isNull);
    });
  });

  group('rule 10: stepping the date keeps the cursor time of day', () {
    /// A grid on 2 November 2024 in New York, cursor on 14:00 EDT.
    Future<TimeGridCubit> gridWithCursorAtTwo() async {
      final cubit = await startGrid(
        board: newYorkBoard,
        nowUtc: _afternoonBeforeFallBack,
      );
      expect(modelOf(cubit).referenceDate, utcDate(2024, 11, 2));

      cubit.setCursor(_afternoonBeforeFallBack);
      expect(modelOf(cubit).cursorInstant, _afternoonBeforeFallBack);
      return cubit;
    }

    test('14:00 stays 14:00 across the 25-hour fall-back day', () async {
      final cubit = await gridWithCursorAtTwo();
      final naiveNextDay = _afternoonBeforeFallBack.add(
        const Duration(days: 1),
      );

      cubit.stepDate(1);

      final model = modelOf(cubit);
      expect(model.referenceDate, utcDate(2024, 11, 3));
      // The day really is 25 hours long, so the window grew by one column and
      // nothing along the way counted to 24.
      expect(model.slots, hasLength(_fallBackWindowSlots));

      // 14:00 EST. Neither the 18:00 UTC a pinned instant would have kept, nor
      // the 18:00 UTC that adding 24 hours produces — both of which the user
      // reads as 13:00.
      expect(model.cursorInstant, utcDate(2024, 11, 3, 19));
      expect(model.cursorInstant, isNot(naiveNextDay));
      expect(
        engine.wallTimeAt(zoneId: _newYork, instant: model.cursorInstant!),
        utcDate(2024, 11, 3, 14),
      );
    });

    test('stepping back restores the instant it came from', () async {
      final cubit = await gridWithCursorAtTwo();
      expect(modelOf(cubit).referenceDate, utcDate(2024, 11, 2));

      cubit
        ..stepDate(1)
        ..stepDate(-1);

      final model = modelOf(cubit);
      expect(model.referenceDate, utcDate(2024, 11, 2));
      expect(model.cursorInstant, _afternoonBeforeFallBack);
    });

    test('goToToday returns to the home zone day, still on 14:00', () async {
      final cubit = await gridWithCursorAtTwo();
      expect(modelOf(cubit).referenceDate, utcDate(2024, 11, 2));

      cubit
        ..stepDate(4)
        ..goToToday();

      final model = modelOf(cubit);
      expect(model.referenceDate, utcDate(2024, 11, 2));
      expect(model.cursorInstant, _afternoonBeforeFallBack);
    });

    test('a date step with no cursor introduces none', () async {
      final cubit = await startGrid();
      expect(modelOf(cubit).cursorInstant, isNull);

      cubit.stepDate(1);

      final model = modelOf(cubit);
      expect(model.referenceDate, utcDate(2024, 6, 15));
      expect(model.cursorInstant, isNull);
    });

    test('a cleared cursor is not resurrected by a later step', () async {
      // clearCursor drops the time of day as well as the instant. A cubit that
      // kept the intent would put a cursor back on a grid the user cleared.
      final cubit = await gridWithCursorAtTwo();
      expect(modelOf(cubit).cursorInstant, isNotNull);

      cubit
        ..clearCursor()
        ..stepDate(1);

      expect(modelOf(cubit).cursorInstant, isNull);
    });
  });

  group('tick', () {
    test('moves now without rebuilding a single row', () async {
      final cubit = await startGrid();
      final before = modelOf(cubit);
      final builds = buildGrid.calls;
      final later = _eveningInSaoPaulo.add(const Duration(minutes: 5));

      cubit.tick(later);

      final after = modelOf(cubit);
      expect(after.nowInstant, later);
      // Identity, not equality. A rebuild that produced equal rows would still
      // be the per-minute work the marker's CustomPainter exists to avoid.
      expect(after.rows, same(before.rows));
      expect(after.slots, same(before.slots));
      expect(after.referenceDate, before.referenceDate);
      expect(buildGrid.calls, builds);
    });

    test('emits nothing when now has not moved', () async {
      final cubit = await startGrid();
      final before = modelOf(cubit);

      cubit.tick(_eveningInSaoPaulo);

      expect(modelOf(cubit), same(before));
    });

    test('is ignored before the first grid exists', () async {
      seedBoard(_boardPending);
      final cubit = buildCubit()..start();
      addTearDown(cubit.close);
      await pumpEventQueue();

      cubit.tick(_eveningInSaoPaulo.add(const Duration(hours: 1)));

      expect(cubit.state, const TimeGridLoading());
    });
  });
}

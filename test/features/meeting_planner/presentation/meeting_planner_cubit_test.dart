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
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/build_meeting_summary_usecase.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/find_best_slot_usecase.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/format_meeting_text_usecase.dart';
import 'package:timebuddy/features/meeting_planner/presentation/cubit/meeting_planner_cubit.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_cubit.dart';

import '../../../harness/factories/preferences_factory.dart';
import '../../../harness/fake_clock.dart';
import '../../../harness/helpers.dart';
import '../../../harness/mocks.dart';

// The three use cases have their own tests; this file is about the mode the
// grid enters and the transitions of docs/specs/meeting_planner.md's state
// machine. It drives a **real** `TimeGridCubit` rather than a mock of one,
// because the two facts the planner reads off the grid — the column set and
// the reference day — are exactly what the last transition of that machine
// depends on, and a stubbed reference date could never take a selection off
// screen the way a real date step does.
//
// The board is chosen so no range in the day is good for everyone, which is
// what rule 7 exists for:
//
//   America/Sao_Paulo is the home zone. It abolished DST in 2019, so it sits
//     at -03:00 all through 2024 and every column below is a whole hour.
//   Asia/Tokyo is +09:00, i.e. exactly 12 hours from home, so an afternoon in
//     Sao Paulo is the middle of Tokyo's night and vice versa.
const String _saoPaulo = 'America/Sao_Paulo';
const String _tokyo = 'Asia/Tokyo';

/// 2024-09-24 15:00 UTC, which is 12:00 in Sao Paulo, so the grid opens on
/// 2024-09-24 in the home zone rather than on whatever day it is in UTC.
final DateTime _middayInSaoPaulo = utcDate(2024, 9, 24, 15);

/// The reference day the grid opens on at [_middayInSaoPaulo].
final DateTime _referenceDate = utcDate(2024, 9, 24);

/// The board state a loaded `BoardCubit` publishes.
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

/// The session's `BoardCubit`, which the planner reads and never writes
/// (rule 11).
///
/// A mock rather than a real cubit with a stubbed repository: this file is
/// about what the planner does *with* a board, and driving the real one would
/// make every case here depend on the board's persistence path (CLAUDE.md:
/// mock at boundaries).
class _MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

void main() {
  final engine = TzTimeZoneEngine();
  final buildSummary = BuildMeetingSummaryUseCase(engine: engine);
  final findBestSlot = FindBestSlotUseCase(engine: engine);
  const formatText = FormatMeetingTextUseCase();

  setUpAll(() async {
    initTestTimeZones();
    registerCommonFallbacks();
    // BuildGridUseCase labels its rows through intl's date symbols, which the
    // app gets from flutter_localizations and a test process has to load.
    await initializeDateFormatting();
    await engine.initialize();
  });

  final twoZoneBoard = _board(_saoPaulo, [_saoPaulo, _tokyo]);
  final homeOnlyBoard = _board(_saoPaulo, [_saoPaulo]);

  late StreamController<BoardState> boardStates;
  late _MockBoardCubit boardCubit;
  late PreferencesCubit preferences;
  late FakeClock clock;
  late TimeGridCubit gridCubit;

  /// The reference day's column for [localHour] in the home zone.
  ///
  /// Asked of the engine rather than counted off the window's first column:
  /// the grid window carries three flanking columns from the day before, and
  /// an index that forgot them would be silently off by three.
  DateTime daySlot(int localHour) => engine
      .dayIn(zoneId: _saoPaulo, localDate: _referenceDate)
      .hours[localHour];

  MeetingSelection selectingIn(MeetingPlannerCubit cubit) {
    final state = cubit.state;
    expect(state, isA<PlannerSelecting>(), reason: 'a drag is in progress');
    return (state as PlannerSelecting).selection;
  }

  PlannerSelected selectedIn(MeetingPlannerCubit cubit) {
    final state = cubit.state;
    expect(state, isA<PlannerSelected>(), reason: 'a range is settled');
    return state as PlannerSelected;
  }

  /// A planner in the state the grid page puts it in: mode on, both cubits it
  /// reads already holding what the session holds.
  ///
  /// The grid is started first and drained, because the planner adopts the
  /// column set and the reference day on `start()` and a grid still in
  /// `TimeGridLoading` would hand it neither.
  Future<MeetingPlannerCubit> startPlanner() async {
    gridCubit = TimeGridCubit(
      boardCubit: boardCubit,
      preferencesCubit: preferences,
      buildGrid: BuildGridUseCase(engine: engine),
      engine: engine,
      clock: clock,
    )..start();
    addTearDown(gridCubit.close);
    await pumpEventQueue();

    final planner = MeetingPlannerCubit(
      boardCubit: boardCubit,
      preferencesCubit: preferences,
      gridCubit: gridCubit,
      buildSummary: buildSummary,
      findBestSlot: findBestSlot,
      formatText: formatText,
      engine: engine,
      // Injected so no case here reaches for a platform channel; the copy
      // path has its own test surface and is not what this file is about.
      writeToClipboard: (_) async {},
    )..start();
    addTearDown(planner.close);
    await pumpEventQueue();
    return planner;
  }

  /// A settled selection over Sao Paulo's local 16:00 to 18:00.
  ///
  /// Deliberately a range that straddles the end of the working day: 16:00 is
  /// good, 17:00 is fair and 18:00 is poor, so anything but the worst hour
  /// scores it as reachable (rule 6).
  Future<MeetingPlannerCubit> plannerOnLateAfternoon() async {
    final planner = await startPlanner();
    planner
      ..startSelection(daySlot(16))
      ..extendTo(daySlot(18))
      ..endSelection();
    return planner;
  }

  setUp(() async {
    clock = FakeClock(_middayInSaoPaulo);

    boardStates = StreamController<BoardState>.broadcast();
    addTearDown(boardStates.close);
    boardCubit = _MockBoardCubit();
    whenListen(
      boardCubit,
      boardStates.stream,
      initialState: _loaded(twoZoneBoard),
    );

    final preferencesRepository = MockPreferencesRepository();
    // Hoisted, and deliberately: a `when` evaluated inside another `when`'s
    // argument throws and leaves mocktail's global stubbing flag set, which
    // then breaks every later test in the file.
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
    // Seeded through `load`, so the planner reads the state the real startup
    // path produces rather than one emitted by hand.
    await preferences.load(deviceLocale: const Locale('en'));
  });

  group('rule 3: a drag is clamped, never refused', () {
    test('stops at twelve slots and keeps the anchor where it was', () async {
      final planner = await startPlanner();

      planner.startSelection(daySlot(0));
      expect(selectingIn(planner).slotCount, 1, reason: 'one slot is valid');

      planner.extendTo(daySlot(4));
      expect(selectingIn(planner).slotCount, 5);

      // Twenty columns past the anchor. The gesture is not rejected; it stops.
      planner.extendTo(daySlot(20));
      final capped = selectingIn(planner);
      expect(capped.slotCount, MeetingSelection.maxSlots);
      // The cap is measured from the anchor, so the end the user is still
      // holding stays where they put it.
      expect(capped.startInstant, daySlot(0));
      expect(capped.endInstant, daySlot(12));

      planner.endSelection();
      expect(selectedIn(planner).summary.selection.slotCount, 12);
    });
  });

  group('rule 6: the verdict is the worst hour in the range', () {
    test('a range that ends badly is scored by its worst hour', () async {
      final planner = await plannerOnLateAfternoon();
      final summary = selectedIn(planner).summary;

      expect(summary.home.localStart.hour, 16);
      expect(summary.duration, const Duration(hours: 3));
      // 16:00 is inside the working window and 17:00 is its shoulder, so a
      // verdict taken from the first hour would read `good` and one taken
      // from an average would read `fair`. A meeting is only as good as its
      // worst hour for that person.
      expect(summary.home.verdict, HourBand.poor);

      final tokyo = summary.lines.single;
      expect(tokyo.location.zoneId, _tokyo);
      expect(tokyo.localStart.hour, 4);
      // Twelve hours from home, so the same range is the next calendar day
      // there and squarely in the middle of the night.
      expect(tokyo.dayDelta, 1);
      expect(tokyo.verdict, HourBand.night);
    });
  });

  group('rule 7: a better window is offered, and applying it moves', () {
    test('the best window in the day replaces the one selected', () async {
      final planner = await plannerOnLateAfternoon();

      final offered = selectedIn(planner);
      final suggestion = offered.summary.suggestion;
      expect(
        suggestion,
        isNotNull,
        reason: 'a row asleep is what rule 7 searches for',
      );
      // 08:00 in Sao Paulo is 20:00 in Tokyo: nobody is asleep, which beats
      // every other three-column range in the day, and ties break earlier.
      expect(suggestion!.startInstant, daySlot(8));
      expect(suggestion.slotCount, 3);
      // The card names a window, so the cubit resolves the one line it shows
      // rather than asking the user to accept instants they cannot read.
      expect(offered.suggestionHome?.localStart.hour, 8);

      planner.applySuggestion();

      final applied = selectedIn(planner);
      expect(applied.summary.selection, suggestion);
      expect(applied.summary.home.localStart.hour, 8);
      expect(applied.summary.home.verdict, HourBand.fair);
      expect(applied.summary.lines.single.verdict, HourBand.poor);
      // Nothing in the day beats the window just applied, so the offer is
      // withdrawn rather than pointing back at the range already on screen.
      expect(applied.summary.suggestion, isNull);
      expect(applied.suggestionHome, isNull);
    });
  });

  group('the grid owns what a selection is expressed against', () {
    test('a reference-date change clears it; a cursor move does not', () async {
      final planner = await plannerOnLateAfternoon();

      // A cursor move re-emits the grid without moving the day, and the
      // summary on screen is still describing columns the user can see.
      // Clearing here would drop a meeting the user has already picked.
      gridCubit.setCursor(daySlot(10));
      await pumpEventQueue();
      expect(planner.state, isA<PlannerSelected>());

      gridCubit.stepDate(1);
      await pumpEventQueue();

      // The selection's instants are no longer on screen, so it goes rather
      // than staying as a band over columns nobody can see.
      expect(planner.state, const PlannerIdle());
      expect(gridCubit.state, isA<TimeGridReady>());
    });

    test('a row removed while a range is selected drops out of it', () async {
      final planner = await plannerOnLateAfternoon();
      expect(selectedIn(planner).summary.lines, hasLength(1));

      boardStates.add(_loaded(homeOnlyBoard));
      await pumpEventQueue();

      // The range never belonged to a row, so it survives the board change
      // and only the summary recomputes around it (edge case).
      final summary = selectedIn(planner).summary;
      expect(summary.lines, isEmpty);
      expect(summary.selection.startInstant, daySlot(16));
      expect(summary.home.localStart.hour, 16);
    });
  });
}

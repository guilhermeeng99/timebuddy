import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/routes/app_shell.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/feature_empty_state.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/app/widgets/timebuddy_bottom_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_date_pill.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/time_grid/presentation/pages/time_grid_page.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_header_strip.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_now_marker.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_row_view.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

// This file covers the half of docs/specs/time_grid.md that no unit test can
// reach: geometry. `build_grid_usecase_test.dart` already proves the model is
// right, so nothing here re-derives a local hour — every assertion is about
// where a widget landed on screen and which one lit up.
//
// The three zones are chosen so a wrong answer cannot look plausible:
//
//   America/Sao_Paulo is -03:00 all through 2024 (DST abolished in 2019), so
//     it is the home row and its cells sit on whole hours.
//   Asia/Kolkata is +05:30, i.e. 8h30 from home, so its cells must carry ':30'
//     for the whole window (rule 5) while staying in the same columns.
//   Asia/Tokyo is +09:00, i.e. exactly 12 hours from home, so its clock is as
//     far from Sao Paulo's as a clock can get and still be a whole hour.
const String _saoPaulo = 'America/Sao_Paulo';
const String _kolkata = 'Asia/Kolkata';
const String _tokyo = 'Asia/Tokyo';

/// A zone id no tzdata release will ever carry, so the board's home zone
/// resolves against nothing and the grid falls back to UTC.
const String _unknownZone = 'Mars/Olympus_Mons';

/// Kolkata's offset from Sao Paulo is `+08:30`.
const int _kolkataHoursFromHome = 8;

/// Tokyo's offset from Sao Paulo is `+12:00`.
const int _tokyoHoursFromHome = 12;

/// Wide enough for the full pinned column plus fifteen hour columns, and tall
/// enough that all three rows are built.
///
/// Above `ResponsiveLayout.mobileBreakpoint` on purpose: the geometry below is
/// written against the full pinned column (`GridMetrics.labelColumnWidth`),
/// which is the form the grid takes at a desktop width. The dense 128px form
/// is what [_phoneSurface] reaches.
///
/// **How many columns is no longer a constant.** `GridLayout` divides the
/// 720pt track into the most whole columns that clear its floor, so this
/// surface resolves to fifteen at 48pt rather than twelve at 60. Nothing below
/// hardcodes either number — the tests read the width the page resolved, which
/// is the only figure the header, the rows and the painters all agree on.
const Size _wideSurface = Size(900, 700);

/// A phone: below `ResponsiveLayout.mobileBreakpoint`, so the page renders its
/// own date pill, the pinned column goes dense at 96px, and the bottom bar's
/// clearance applies under the list.
///
/// It reads that way in `MediaQuery` and not merely on the render surface,
/// which is what `pumpApp`'s `surfaceSize` used to get wrong: these two tests
/// called themselves phone tests while laying out the 132px desktop column.
const Size _phoneSurface = Size(400, 720);

/// Enough rows to make the vertical list scroll on [_phoneSurface].
///
/// All distinct zones, because locations rule 2 rejects two rows sharing one.
const List<String> _manyZones = <String>[
  _saoPaulo,
  _kolkata,
  _tokyo,
  'Europe/London',
  'Europe/Paris',
  'America/New_York',
  'America/Los_Angeles',
  'Australia/Sydney',
  'Africa/Cairo',
  'Asia/Dubai',
  'Pacific/Auckland',
  'Asia/Kathmandu',
];

/// The last row of a [_manyZones] board.
const String _lastZone = 'Asia/Kathmandu';

/// A board state carrying no board yet.
const BoardState _boardPending = BoardLoading();

/// The board state a loaded `BoardCubit` publishes.
///
/// The one place this file names `BoardLoaded`. `BoardCubit` is being written
/// alongside these tests and the grid reads only `board` out of it, so a state
/// class that lands carrying more than docs/specs/locations.md lists costs one
/// line here.
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

/// The hour track of one row, found by the zone it renders.
///
/// Through `GridRowView.row` rather than by list index: the assertions below
/// compare two named rows against each other, and an index would quietly test
/// the wrong pair the day the board factory changes order.
Finder _trackOf(String zoneId) => find.byWidgetPredicate(
  (widget) => widget is GridRowView && widget.row.location.zoneId == zoneId,
  description: 'hour track of $zoneId',
);

Finder _cellsOf(String zoneId) =>
    find.descendant(of: _trackOf(zoneId), matching: find.byType(HourCell));

/// The cell the shared cursor is sitting on in [zoneId]'s row.
Finder _cursorCellOf(String zoneId) => find.descendant(
  of: _trackOf(zoneId),
  matching: find.byWidgetPredicate(
    (widget) => widget is HourCell && widget.isCursor,
  ),
);

/// Every lit cell on screen, across all rows.
Finder _allCursorCells() => find.byWidgetPredicate(
  (widget) => widget is HourCell && widget.isCursor,
  description: 'cell under the hour cursor',
);

/// The session's `BoardCubit`. The grid reads it and never writes to it, so a
/// mock holding one state is the whole of what the page needs from the board.
class _MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

void main() {
  setUpAll(() async {
    initTestTimeZones();
    registerCommonFallbacks();
    // formatDayMonth reads intl's date symbols, which the app gets from
    // flutter_localizations and a test process has to load itself.
    await initializeDateFormatting();
  });

  final threeZoneBoard = _board(_saoPaulo, [_saoPaulo, _kolkata, _tokyo]);

  /// Mounts [TimeGridPage] the way `AppShell` mounts it.
  ///
  /// `pumpApp` owns the locator, the locale, the fonts and the paused ticker,
  /// so it installs first against a throwaway home. `BuildGridUseCase` is the
  /// one dependency this page resolves that milestone 1's harness never had a
  /// reason to register, and building it needs the engine `pumpApp` has just
  /// made — hence a second `pumpWidget` here rather than a private copy of
  /// the harness.
  Future<_MockBoardCubit> pumpGrid(
    WidgetTester tester, {
    required BoardState boardState,
    Size surfaceSize = _wideSurface,
  }) async {
    final app = await pumpApp(
      tester,
      const SizedBox.shrink(),
      surfaceSize: surfaceSize,
    );
    GetIt.I.registerSingleton<BuildGridUseCase>(
      BuildGridUseCase(engine: app.engine),
    );

    final boardCubit = _MockBoardCubit();
    whenListen(
      boardCubit,
      const Stream<BoardState>.empty(),
      initialState: boardState,
    );
    // Accepted by default: the tests that care about a *refused* write are
    // `board_cubit_test.dart`'s, and this page only has to ask.
    when(
      () => boardCubit.reorder(any(), any()),
    ).thenAnswer((_) async => null);

    // The sidebar's stepper slot is app-scoped, so it would otherwise carry
    // one test's pill into the next.
    addTearDown(shellDatePill.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PreferencesCubit>.value(value: app.cubit),
            BlocProvider<BoardCubit>.value(value: boardCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const TimeGridPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    return boardCubit;
  }

  /// The grid's single horizontal `Scrollable`, which lives in the header.
  Finder hourTrack() => find.descendant(
    of: find.byType(GridHeaderStrip),
    matching: find.byType(Scrollable),
  );

  double trackOffset(WidgetTester tester) =>
      tester.state<ScrollableState>(hourTrack()).position.pixels;

  /// The local hour on the leftmost cell [zoneId]'s row currently renders.
  ///
  /// The rows draw only the slice of columns the viewport can see, so this
  /// value moves with the shared scroll offset and stands still without it.
  int leftmostHour(WidgetTester tester, String zoneId) =>
      tester.widget<HourCell>(_cellsOf(zoneId).first).hour;

  /// The hour column width this surface resolved to.
  ///
  /// Read off the header strip rather than recomputed, because the strip's
  /// `itemExtent` *is* the grid's content extent: a test that derived the
  /// number itself could agree with `GridLayout` and still disagree with what
  /// the page actually laid out.
  double resolvedColumnWidth(WidgetTester tester) => tester
      .widget<GridHeaderStrip>(find.byType(GridHeaderStrip))
      .columnWidth;

  HourCell cursorCell(WidgetTester tester, String zoneId) {
    final finder = _cursorCellOf(zoneId);
    expect(finder, findsOneWidget, reason: 'cursor cell of $zoneId');
    return tester.widget<HourCell>(finder);
  }

  testWidgets('the pinned label column does not move with the hours', (
    tester,
  ) async {
    await pumpGrid(tester, boardState: _loaded(threeZoneBoard));

    final labelBefore = tester.getRect(find.byType(LocationRow).first);
    final columnWidth = resolvedColumnWidth(tester);
    final offsetBefore = trackOffset(tester);
    final homeHourBefore = leftmostHour(tester, _saoPaulo);
    final tokyoHourBefore = leftmostHour(tester, _tokyo);

    // Dragged by the ruler here; the test below drags the cells instead and
    // has to reach the same position, because there is only one.
    await tester.drag(hourTrack(), Offset(-4 * columnWidth, 0));
    await tester.pumpAndSettle();

    final offsetAfter = trackOffset(tester);
    expect(
      offsetAfter,
      greaterThan(offsetBefore),
      reason: 'the drag has to move the track for this to mean anything',
    );

    // Every row followed the one controller by the same number of columns,
    // counted in the width the page resolved rather than in a literal 60 —
    // dividing by a stale constant is how a green test starts describing a
    // grid the app no longer draws.
    final columns =
        (offsetAfter / columnWidth).floor() -
        (offsetBefore / columnWidth).floor();
    expect(columns, greaterThan(0));
    expect(leftmostHour(tester, _saoPaulo), (homeHourBefore + columns) % 24);
    expect(leftmostHour(tester, _tokyo), (tokyoHourBefore + columns) % 24);

    // ...and the identity block did not move by a pixel.
    expect(tester.getRect(find.byType(LocationRow).first), labelBefore);
    expect(labelBefore.left, 0);
    expect(labelBefore.width, GridMetrics.labelColumnWidth);
  });

  testWidgets('the cursor lights the same instant in every row', (
    tester,
  ) async {
    await pumpGrid(tester, boardState: _loaded(threeZoneBoard));
    expect(_allCursorCells(), findsNothing);

    // The ruler is the grid's one pointer path to the cursor (rule 8). A
    // column well inside the rendered window, so its centre is nowhere near
    // the clip edges and the tap cannot land on a neighbour.
    final column = find.byType(GridHeaderColumn).at(3);
    final columnLeft = tester.getRect(column).left;
    await tester.tap(column);
    await tester.pumpAndSettle();

    // One cell per row and not one more: a cursor kept per row would light
    // three unrelated columns and still pass a count of three, which is why
    // the geometry below is the assertion that matters.
    expect(_allCursorCells(), findsNWidgets(3));

    final homeLeft = tester.getRect(_cursorCellOf(_saoPaulo)).left;
    // Under the column that was tapped, and not merely somewhere consistent:
    // a cursor off by one would satisfy every other assertion here.
    expect(homeLeft, moreOrLessEquals(columnLeft, epsilon: 0.5));
    expect(tester.getRect(_cursorCellOf(_kolkata)).left, homeLeft);
    expect(tester.getRect(_cursorCellOf(_tokyo)).left, homeLeft);

    // Same column, different clocks. That difference is the screen's whole
    // reason to exist, and it is what a row aligned to its own midnight loses.
    final home = cursorCell(tester, _saoPaulo);
    final kolkata = cursorCell(tester, _kolkata);
    final tokyo = cursorCell(tester, _tokyo);
    expect(home.minute, 0);
    expect(kolkata.hour, (home.hour + _kolkataHoursFromHome) % 24);
    expect(kolkata.minute, 30);
    expect(tokyo.hour, (home.hour + _tokyoHoursFromHome) % 24);
    expect(tokyo.minute, 0);
  });

  testWidgets('a drag over the cells scrolls the track (rule 16)', (
    tester,
  ) async {
    await pumpGrid(tester, boardState: _loaded(threeZoneBoard));

    final columnWidth = resolvedColumnWidth(tester);
    final offsetBefore = trackOffset(tester);
    final homeHourBefore = leftmostHour(tester, _saoPaulo);
    final tokyoHourBefore = leftmostHour(tester, _tokyo);

    // The gesture the cursor used to own. It reaches the header's
    // `ScrollPosition` even though no row is a `Scrollable`, which is the
    // whole of rule 16.
    await tester.drag(_cellsOf(_saoPaulo).at(2), Offset(-4 * columnWidth, 0));
    await tester.pumpAndSettle();

    final offsetAfter = trackOffset(tester);
    expect(
      offsetAfter,
      greaterThan(offsetBefore),
      reason: 'the drag has to move the track for this to mean anything',
    );

    // Every row followed by the same number of columns, exactly as they do
    // when the ruler is the surface being dragged.
    final columns =
        (offsetAfter / columnWidth).floor() -
        (offsetBefore / columnWidth).floor();
    expect(columns, greaterThan(0));
    expect(leftmostHour(tester, _saoPaulo), (homeHourBefore + columns) % 24);
    expect(leftmostHour(tester, _tokyo), (tokyoHourBefore + columns) % 24);

    // And it stayed a pan: a drag that lit a column would be the old
    // behaviour surviving underneath the new one.
    expect(_allCursorCells(), findsNothing);
  });

  testWidgets('a tap on a cell is not a way to set the cursor', (
    tester,
  ) async {
    await pumpGrid(tester, boardState: _loaded(threeZoneBoard));

    await tester.tap(_cellsOf(_saoPaulo).at(3));
    await tester.pumpAndSettle();

    // Deliberate, not an oversight: the cells are a read surface so the pan
    // can have every pixel of the track (rule 8).
    expect(_allCursorCells(), findsNothing);
  });

  testWidgets('a half-hour zone renders its minutes and home does not', (
    tester,
  ) async {
    await pumpGrid(tester, boardState: _loaded(threeZoneBoard));

    final kolkataCells = tester.widgetList<HourCell>(_cellsOf(_kolkata));
    expect(kolkataCells, isNotEmpty);
    expect(
      kolkataCells.every((cell) => cell.minute == 30),
      isTrue,
      reason: 'Kolkata is +05:30 from a whole-hour home for the whole window',
    );

    // The digits, not just the field: hiding the minutes would claim an
    // alignment with the column that the row does not have (rule 5).
    expect(
      find.descendant(
        of: _trackOf(_kolkata),
        matching: find.textContaining(':30'),
      ),
      findsWidgets,
    );
    // The home row is on the columns' own hours, so it shows none. Without
    // this half, a cell that printed `hh:mm` everywhere would pass.
    expect(
      find.descendant(
        of: _trackOf(_saoPaulo),
        matching: find.textContaining(':'),
      ),
      findsNothing,
    );
  });

  testWidgets('an empty board invites a first city, with no grid behind it', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      boardState: _loaded(_board(_saoPaulo, const [])),
      surfaceSize: _phoneSurface,
    );

    expect(find.byType(FeatureEmptyState), findsOneWidget);
    expect(find.text(t.grid.emptyTitle), findsOneWidget);
    expect(find.text(t.grid.emptyMessage), findsOneWidget);

    // Not a header strip and a date stepper over nothing (time_grid.md, edge
    // cases). This surface is below the breakpoint, so a rendered grid would
    // put its own pill on the page and this assertion would fail.
    expect(find.byType(GridHeaderStrip), findsNothing);
    expect(find.byType(GridRowView), findsNothing);
    expect(find.byType(GridNowMarker), findsNothing);
    expect(find.byType(HourCell), findsNothing);
    expect(find.byType(TimeBuddyDatePill), findsNothing);

    // The way out of the empty state is still on screen.
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('the placeholder holds until the board resolves', (
    tester,
  ) async {
    await pumpGrid(tester, boardState: _boardPending);

    expect(find.byType(LoadingShimmer), findsOneWidget);
    expect(find.byType(GridHeaderStrip), findsNothing);
    expect(find.byType(FeatureEmptyState), findsNothing);
  });

  testWidgets('warns when the home zone did not resolve, and still draws', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      boardState: _loaded(_board(_unknownZone, [_saoPaulo, _kolkata, _tokyo])),
    );

    expect(find.text(t.grid.homeZoneBrokenBanner), findsOneWidget);

    // It degrades to UTC columns rather than going blank: the rows the user
    // saved are all still there and still readable.
    expect(find.byType(GridHeaderStrip), findsOneWidget);
    expect(find.byType(GridRowView), findsNWidgets(3));
    expect(_cellsOf(_tokyo), findsWidgets);
  });

  testWidgets('says nothing about the home zone when it resolved', (
    tester,
  ) async {
    // The other half of the pair. A warning that shows on the happy path is
    // noise, and noise is how a real warning stops being read.
    await pumpGrid(tester, boardState: _loaded(threeZoneBoard));

    expect(find.text(t.grid.homeZoneBrokenBanner), findsNothing);
    expect(find.byType(GridHeaderStrip), findsOneWidget);
    expect(find.byType(GridRowView), findsNWidgets(3));
  });

  testWidgets('the last row scrolls clear of the FAB', (tester) async {
    await pumpGrid(
      tester,
      boardState: _loaded(_board(_saoPaulo, _manyZones)),
      surfaceSize: _phoneSurface,
    );

    final rows = find
        .ancestor(
          of: find.byType(GridRowView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    expect(
      tester.state<ScrollableState>(rows).position.maxScrollExtent,
      greaterThan(0),
      reason: 'the board must out-run the viewport for this to mean anything',
    );

    await tester.drag(find.byType(GridRowView).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    final position = tester.state<ScrollableState>(rows).position;
    expect(
      position.pixels,
      moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
      reason: 'the list has to be scrolled to its end',
    );

    // The bar and the FAB both float over this list, so the last row has to be
    // reachable underneath them, not merely visible (design_system §7).
    expect(_trackOf(_lastZone), findsOneWidget);
    expect(
      tester.getRect(_trackOf(_lastZone)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(FloatingActionButton)).top),
    );
  });

  group('the label column owns the row', () {
    /// Lifts the row at [from] and drops it one row further down.
    ///
    /// Driven as a real gesture rather than by calling `onReorderItem`: what
    /// is under test is precisely that the lift is reachable from the label
    /// column at all, which a direct call would assume.
    Future<void> dragRowDown(
      WidgetTester tester, {
      required int from,
      required bool touch,
    }) async {
      final label = find.byType(LocationRow).at(from);
      final gesture = await tester.startGesture(tester.getCenter(label));
      if (touch) {
        // A finger has to press and hold. An immediate lift here would steal
        // every vertical scroll of the grid that began over a label.
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      }
      // In steps, because one jump can land outside every drop target and the
      // list then has nowhere to put the row.
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, GridMetrics.rowHeight / 3));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a finger long-presses a label to move its row', (
      tester,
    ) async {
      final boardCubit = await pumpGrid(
        tester,
        boardState: _loaded(threeZoneBoard),
      );

      await dragRowDown(tester, from: 0, touch: true);

      // Both indices are final positions: `onReorderItem` has already
      // adjusted the destination for the lifted row (locations.md rule 5).
      verify(() => boardCubit.reorder(0, 1)).called(1);
    });

    testWidgets('a mouse drags it without the hold', (tester) async {
      // Set before the pump: `Theme.platform` is read when the row builds, and
      // it is what picks between the two drag-start listeners. Cleared inside
      // the body rather than in a tear-down, which runs *after* the binding
      // checks that no debug variable outlived the test.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final boardCubit = await pumpGrid(
          tester,
          boardState: _loaded(threeZoneBoard),
        );

        await dragRowDown(tester, from: 0, touch: false);

        // A long-press before a drag on a desktop reads as the app being slow.
        verify(() => boardCubit.reorder(0, 1)).called(1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a drag over the hours pans the track, not the row', (
      tester,
    ) async {
      final boardCubit = await pumpGrid(
        tester,
        boardState: _loaded(threeZoneBoard),
      );

      // The one gesture that would break if the row lift were attached to the
      // whole row instead of to the pinned column.
      await tester.drag(
        _cellsOf(_saoPaulo).first,
        const Offset(3 * GridMetrics.hourColumnWidth, 0),
      );
      await tester.pumpAndSettle();

      verifyNever(() => boardCubit.reorder(any(), any()));
    });

    testWidgets("tapping a label opens that row's actions", (tester) async {
      await pumpGrid(tester, boardState: _loaded(threeZoneBoard));

      // `warnIfMissed: false`: the handle's `HitTestBehavior.opaque` answers
      // the tap and stops the descent, so `LocationRow`'s own render object is
      // deliberately not in the hit-test chain.
      await tester.tap(find.byType(LocationRow).first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // The sheet the board page used to be the only way to reach. Neither
      // drag recognizer claims a pointer that never moved, so the tap
      // survives on both platforms.
      expect(find.text(t.locations.setAsHome), findsOneWidget);
      expect(find.text(t.locations.replaceZone), findsOneWidget);
      expect(find.text(t.common.remove), findsOneWidget);
    });

    testWidgets('the undo snackbar clears the floating bar on a phone', (
      tester,
    ) async {
      final boardCubit = await pumpGrid(
        tester,
        boardState: _loaded(threeZoneBoard),
        surfaceSize: _phoneSurface,
      );
      when(
        () => boardCubit.removeLocation(any()),
      ).thenAnswer((_) async => null);

      await tester.tap(find.byType(LocationRow).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.common.remove));
      await tester.pumpAndSettle();

      // A default snackbar is fixed to the bottom of the *page's* Scaffold,
      // and the bar is not in that Scaffold — it is an Align in `AppShell`'s
      // Stack, painted above it. So an unlifted snackbar puts the Undo button
      // underneath the pill, where it can be read and not pressed
      // (design_system section 9).
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.behavior, SnackBarBehavior.floating);
      expect(
        (snack.margin! as EdgeInsets).bottom,
        greaterThanOrEqualTo(TimeBuddyBottomBar.reservedHeight),
      );
      expect(find.text(t.locations.undo), findsOneWidget);
    });

    testWidgets('and stays put where there is no bar', (tester) async {
      final boardCubit = await pumpGrid(
        tester,
        boardState: _loaded(threeZoneBoard),
      );
      when(
        () => boardCubit.removeLocation(any()),
      ).thenAnswer((_) async => null);

      await tester.tap(find.byType(LocationRow).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.common.remove));
      await tester.pumpAndSettle();

      // At and above 600px the rail replaces the bar, so a snackbar floating
      // 96px off the floor would be hovering over nothing.
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
        SnackBarBehavior.fixed,
      );
    });
  });
}

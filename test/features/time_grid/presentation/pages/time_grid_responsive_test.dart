import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/routes/app_shell.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/app/widgets/timebuddy_bottom_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_date_pill.dart';
import 'package:timebuddy/app/widgets/timebuddy_sidebar.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/time_grid/presentation/grid_layout.dart';
import 'package:timebuddy/features/time_grid/presentation/pages/time_grid_page.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_header_strip.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_row_view.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';
import 'package:uuid/uuid.dart';

import '../../../../harness/factories/board_factory.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

// The grid's half of the responsive contract (design_system section 7,
// time_grid.md "Responsive"), run through the real page inside the real shell
// at the two widths the product is used at.
//
// `time_grid_page_test.dart` already owns the grid's geometry at one width;
// nothing here re-derives an hour. These are the four things that break when
// somebody edits the shell or the page around it: how wide the pinned column
// is, whether it still carries a country line, who is drawing the date
// stepper, and whether the last row can be reached under the floating chrome.
//
// The page is mounted through `AppShell` rather than on its own because half
// of what is under test is a negotiation between the two: the page publishes
// a stepper that the rail may or may not be showing, and a page tested alone
// cannot tell a rail that took the stepper from a rail that never existed.
//
// ---------------------------------------------------------------------------
// WHAT THIS FILE FOUND, and why the mobile half of it is worth keeping.
//
// The three mobile tests here were the first in the suite to lay the dense
// column out at all, and they failed on a `RenderFlex` overflow raised
// inside `LocationRow` rather than on anything they assert: the status line
// put the zone abbreviation and the `Home` chip into a `Row` as two unflexed
// children, so the pair took its natural width and overran the room left
// inside the column (then `96 - 2 * AppSpacing.sm`). In a test it shouts; in
// release it silently painted the chip across the grid's first hour column.
// `_StatusLine` now drops the abbreviation on any dense row that already has
// something more useful in that slot, and these tests pass.
//
// They were the first because the page harness used to widen the viewport
// with `tester.binding.setSurfaceSize`, which moves the render surface and
// leaves `MediaQuery` at 800x600 — so a page handed a 400x720 "phone" still
// answered `ResponsiveLayout.isMobile` with `false` and drew the 132px
// column. This file set `tester.view` directly, which is why it saw the truth
// first. `pumpApp`'s `surfaceSize` does that now (see `pump_app.dart`), so a
// mobile test elsewhere in the suite is genuinely mobile and the assertions
// below are no longer the only ones laying this column out.
// ---------------------------------------------------------------------------

/// A phone: below the 600px breakpoint, so the column goes dense and the page
/// keeps its own stepper.
const Size _mobileSurface = Size(375, 812);

/// A desktop window: the rail is on screen, expanded, and the grid still gets
/// every pixel left over, because it is the one page exempt from
/// `maxContentWidth`.
const Size _desktopSurface = Size(1280, 800);

/// A tablet: the rail is on screen but collapsed to icons.
///
/// This band had no test at all, which is how it came to be the worst place in
/// the app to read the grid — a 240pt rail on a 700pt window left the hours
/// less room than a phone had.
const Size _tabletSurface = Size(768, 1024);

/// One pixel below the breakpoint, and one above it.
///
/// The pair exists to assert the thing the user actually reported: that making
/// the window *bigger* made the grid worse.
const Size _justBelowRail = Size(599, 800);
const Size _justAboveRail = Size(601, 800);

/// Width of the pinned column below `600px` (time_grid.md, Responsive).
///
/// Written out rather than read from the page, which keeps it private: the
/// number is a promise the spec makes, so the test has to state it
/// independently or it would only be comparing the page against itself.
const double _denseLabelColumnWidth = 128;

/// One board row, reduced to the three strings a layout assertion reads.
typedef _City = ({String zoneId, String label, String country});

/// The home row: `Europe/Berlin` observes DST, which nothing here depends on,
/// but a home zone that is *not* the factory default keeps this file honest
/// about which row it made the reference.
const _City _berlin = (
  zoneId: 'Europe/Berlin',
  label: 'Berlin',
  country: 'DE',
);

/// `+05:30`, so its row is the one whose cells carry minutes. Its country
/// line is what the dense column drops.
const _City _kolkata = (
  zoneId: 'Asia/Kolkata',
  label: 'Kolkata',
  country: 'IN',
);

const _City _tokyo = (zoneId: 'Asia/Tokyo', label: 'Tokyo', country: 'JP');

/// Three rows, three distinct country codes: "the country line is gone" and
/// "the country line is there" cannot be told apart if two rows share a code.
const List<_City> _threeCities = <_City>[_berlin, _kolkata, _tokyo];

/// Enough rows to out-run a phone viewport, so the last one has to be
/// scrolled to. All distinct zones, because locations rule 2 rejects two rows
/// sharing one.
const List<String> _manyZoneIds = <String>[
  'Europe/Berlin',
  'Asia/Kolkata',
  'Asia/Tokyo',
  'Europe/London',
  'Europe/Paris',
  'America/New_York',
  'America/Los_Angeles',
  'America/Sao_Paulo',
  'Australia/Sydney',
  'Africa/Cairo',
  'Asia/Dubai',
  'Pacific/Auckland',
  'Asia/Kathmandu',
];

/// The board boundary `AppShell` resolves out of `GetIt` to build the
/// session's `BoardCubit`. The grid reads that cubit and never writes to it.
class _MockBoardRepository extends Mock implements BoardRepository {}

/// `BoardCubit` mints row ids with a `Uuid`. Nothing here adds a city.
class _MockUuid extends Mock implements Uuid {}

/// A board of [cities], in order, with the first one as home.
///
/// The sort index comes from the loop rather than from a literal, so the rows
/// keep the order they are written in without any of them repeating a
/// factory default.
BoardEntity _boardOf(List<_City> cities) => aBoard(
  homeZoneId: cities.first.zoneId,
  locations: [
    for (var index = 0; index < cities.length; index++)
      aSavedLocation(
        id: 'row-$index',
        zoneId: cities[index].zoneId,
        label: cities[index].label,
        countryCode: cities[index].country,
        sortIndex: index,
      ),
  ],
);

/// The many-row board, whose labels and country codes nothing asserts on.
BoardEntity _tallBoard() => _boardOf(<_City>[
  for (final zoneId in _manyZoneIds)
    (
      zoneId: zoneId,
      label: zoneId.split('/').last.replaceAll('_', ' '),
      country: 'ZZ',
    ),
]);

/// A router shaped like `AppRouter`'s shell: one branch per destination, in
/// `TimeBuddyNavDestination` order, which `AppShell` asserts on.
///
/// Only the grid branch is ever visited, and it holds the real page.
GoRouter _shellRouter() {
  return GoRouter(
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.grid,
                builder: (context, state) => const TimeGridPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.clocks,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.converter,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The hour track of one row, found by the zone it renders.
///
/// Through `GridRowView.row` rather than by list index, so an assertion about
/// the last row cannot quietly move to another one.
Finder _trackOf(String zoneId) => find.byWidgetPredicate(
  (widget) => widget is GridRowView && widget.row.location.zoneId == zoneId,
  description: 'hour track of $zoneId',
);

void main() {
  setUpAll(() async {
    initTestTimeZones();
    registerCommonFallbacks();
    // formatDayMonth reads intl's date symbols, which the app gets from
    // flutter_localizations and a test process has to load itself.
    await initializeDateFormatting();
  });

  /// Mounts the real [TimeGridPage] inside the real [AppShell] at [surface].
  ///
  /// `pumpApp` owns the locator, the locale, the fonts and the paused ticker,
  /// so it installs first against a throwaway home. `BuildGridUseCase` needs
  /// the engine it has just made, and the shell builds its own `BoardCubit`
  /// out of `GetIt` — which is why the board arrives as a stubbed repository
  /// rather than as a mocked cubit: the cubit the page reads is the one the
  /// shell creates, and nothing above it can substitute another.
  Future<void> pumpGridShell(
    WidgetTester tester, {
    required Size surface,
    required BoardEntity board,
  }) async {
    // Through the harness rather than by setting `tester.view` here, which is
    // what this file used to do: `surfaceSize` now moves `MediaQuery` as well
    // as the render surface, and owns the reset that stops one test's width
    // reaching the next.
    final app = await pumpApp(
      tester,
      const SizedBox.shrink(),
      surfaceSize: surface,
    );

    // Hoisted out of the stub: building the answer inside `when` is what makes
    // mocktail throw "Cannot call `when` within a stub response".
    final repository = _MockBoardRepository();
    when(
      () => repository.load(
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => Right<Failure, BoardEntity>(board));

    GetIt.I
      ..registerSingleton<BoardRepository>(repository)
      ..registerSingleton<Uuid>(_MockUuid())
      ..registerSingleton<BuildGridUseCase>(
        BuildGridUseCase(engine: app.engine),
      );

    // Both notifiers are app-scoped and outlive the pumped tree, so one test's
    // stepper and sub-page depth would otherwise be the next one's start.
    addTearDown(shellDatePill.reset);
    addTearDown(subPageDepth.reset);

    await tester.pumpWidget(
      TranslationProvider(
        // Both providers, matching `TimeBuddyApp`: the rail's foot is the
        // settings destination wearing the session, so it reads `AuthBloc`.
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PreferencesCubit>.value(value: app.cubit),
            BlocProvider<AuthBloc>.value(value: app.authBloc),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: _shellRouter(),
          ),
        ),
      ),
    );
    // The board load is a real future, and `ShellDatePill` publishes out of a
    // build, so the grid and the rail are both a frame behind the first pump.
    await tester.pumpAndSettle();
  }

  /// The identity blocks of the pinned column, in board order.
  List<LocationRow> pinnedColumn(WidgetTester tester) =>
      tester.widgetList<LocationRow>(find.byType(LocationRow)).toList();

  Finder pillInRail() => find.descendant(
    of: find.byType(TimeBuddySidebar),
    matching: find.byType(TimeBuddyDatePill),
  );

  Finder pillOnPage() => find.descendant(
    of: find.byType(TimeGridPage),
    matching: find.byType(TimeBuddyDatePill),
  );

  testWidgets('below 600px the pinned column is dense and 128px wide', (
    tester,
  ) async {
    await pumpGridShell(
      tester,
      surface: _mobileSurface,
      board: _boardOf(_threeCities),
    );

    final rows = pinnedColumn(tester);
    expect(rows, hasLength(_threeCities.length));
    expect(rows.every((row) => row.dense), isTrue);
    expect(
      tester.getSize(find.byType(LocationRow).first).width,
      _denseLabelColumnWidth,
      reason: 'every pixel spent on the label is an hour column lost',
    );

    // Dense means the country line is gone, not that the type shrank: the
    // city label and the status line are still there to read.
    for (final city in _threeCities) {
      expect(find.text(city.country), findsNothing);
      expect(find.text(city.label), findsOneWidget);
    }
  });

  testWidgets('at 600px and up the pinned column is full and named', (
    tester,
  ) async {
    await pumpGridShell(
      tester,
      surface: _desktopSurface,
      board: _boardOf(_threeCities),
    );

    final rows = pinnedColumn(tester);
    expect(rows, hasLength(_threeCities.length));
    expect(
      rows.any((row) => row.dense),
      isFalse,
      reason: 'there is room for the country line at this width',
    );
    expect(
      tester.getSize(find.byType(LocationRow).first).width,
      GridMetrics.labelColumnWidth,
    );

    for (final city in _threeCities) {
      expect(find.text(city.country), findsOneWidget);
      expect(find.text(city.label), findsOneWidget);
    }
  });

  testWidgets('the grid keeps the whole window width beside the rail', (
    tester,
  ) async {
    await pumpGridShell(
      tester,
      surface: _desktopSurface,
      board: _boardOf(_threeCities),
    );

    final track = tester.getRect(_trackOf(_berlin.zoneId));
    // It starts where the rail and the label column end, and runs to the
    // window edge: the grid is the one page allowed to ignore
    // `maxContentWidth`, because its value is showing as many hours as fit.
    expect(
      track.left,
      TimeBuddySidebar.expandedWidth + GridMetrics.labelColumnWidth,
    );
    expect(track.right, _desktopSurface.width);
    expect(track.width, greaterThan(ResponsiveLayout.maxContentWidth));
  });

  testWidgets('below 600px the grid draws its own stepper, and only it', (
    tester,
  ) async {
    await pumpGridShell(
      tester,
      surface: _mobileSurface,
      board: _boardOf(_threeCities),
    );

    // Exactly one. A page that renders a stepper unconditionally still passes
    // "there is a stepper" at both widths and shows two of them on a tablet.
    expect(find.byType(TimeBuddyDatePill), findsOneWidget);
    expect(pillOnPage(), findsOneWidget);
    expect(pillInRail(), findsNothing);
  });

  testWidgets('at 600px and up the rail takes the stepper off the page', (
    tester,
  ) async {
    await pumpGridShell(
      tester,
      surface: _desktopSurface,
      board: _boardOf(_threeCities),
    );

    expect(find.byType(TimeBuddyDatePill), findsOneWidget);
    expect(pillInRail(), findsOneWidget);
    expect(
      pillOnPage(),
      findsNothing,
      reason: 'the page must take no row of layout for a control the rail has',
    );
    expect(
      tester.getRect(find.byType(TimeBuddyDatePill)).right,
      lessThanOrEqualTo(TimeBuddySidebar.expandedWidth),
    );
  });


  /// The column width the page resolved for this surface.
  double columnWidth(WidgetTester tester) => tester
      .widget<GridHeaderStrip>(find.byType(GridHeaderStrip))
      .columnWidth;

  /// The shared hour track's scroll offset, in pixels.
  ///
  /// Read off the header's `Scrollable`, which is the grid's only horizontal
  /// one and therefore the authority every row is supposed to be following.
  double trackOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(GridHeaderStrip),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  /// The local hour in the first cell one row is currently rendering.
  int firstRenderedHour(WidgetTester tester, String zoneId) => tester
      .widgetList<HourCell>(
        find.descendant(of: _trackOf(zoneId), matching: find.byType(HourCell)),
      )
      .first
      .hour;

  /// Which column index the *controller* says is at the track's left edge.
  int firstColumnIndex(WidgetTester tester) =>
      (trackOffset(tester) / columnWidth(tester)).floor();

  /// How many whole hours one row shows.
  ///
  /// Measured from the track rather than by counting `HourCell` widgets: a row
  /// renders the window that *covers* the viewport, so the widget count runs
  /// one or two ahead of what a user can actually read and would make this
  /// assertion drift with an implementation detail.
  int visibleHours(WidgetTester tester, String zoneId) =>
      tester.getRect(_trackOf(zoneId)).width ~/ columnWidth(tester);

  testWidgets('the hour columns fill the track instead of clipping one', (
    tester,
  ) async {
    // The complaint, stated as geometry: at a fixed 60pt the track's last
    // column was sliced through its digits at almost every window width.
    await pumpGridShell(
      tester,
      surface: _desktopSurface,
      board: _boardOf(_threeCities),
    );

    final track = tester.getRect(_trackOf(_berlin.zoneId));
    final width = columnWidth(tester);
    expect(width, greaterThanOrEqualTo(GridLayout.minColumnWidth));
    expect(
      track.width / width,
      closeTo(track.width ~/ width, 0.001),
      reason: 'a whole number of columns has to tile the track exactly',
    );
  });

  testWidgets('widening the window past the rail never shows fewer hours', (
    tester,
  ) async {
    // THE REGRESSION THIS RELEASE FIXES. Before it, 599px showed nine hour
    // columns and 600px showed three: the rail took 240 of a 600pt window and
    // the pinned column took another 180. The rail now collapses to 80 in this
    // band, and the columns shrink to fit what is left.
    await pumpGridShell(
      tester,
      surface: _justBelowRail,
      board: _boardOf(_threeCities),
    );
    final below = visibleHours(tester, _berlin.zoneId);

    tester.view.physicalSize = _justAboveRail;
    await tester.pumpAndSettle();
    final above = visibleHours(tester, _berlin.zoneId);

    // 599px shows nine hours; 601px shows seven, and the two it lost are the
    // 80pt icon rail that appeared. Before this release the same step went
    // from nine to three, because the rail arrived 240pt wide and the pinned
    // column grew 52pt in the same pixel.
    expect(below, greaterThanOrEqualTo(9));
    expect(
      above,
      greaterThanOrEqualTo(below - 2),
      reason: 'crossing the breakpoint may cost the rail, not the screen',
    );
    expect(
      above,
      greaterThanOrEqualTo(6),
      reason: 'a tablet must never read worse than a phone did',
    );
  });

  testWidgets('a tablet collapses the rail and takes its stepper back', (
    tester,
  ) async {
    await pumpGridShell(
      tester,
      surface: _tabletSurface,
      board: _boardOf(_threeCities),
    );

    expect(
      tester.getSize(find.byType(TimeBuddySidebar)).width,
      TimeBuddySidebar.collapsedWidth,
    );
    // Collapsed, the rail cannot hold a 240pt stepper, so the page draws its
    // own — and there is still exactly one on screen, which is the §7 rule.
    expect(pillInRail(), findsNothing);
    expect(pillOnPage(), findsOneWidget);
    expect(find.byType(TimeBuddyDatePill), findsOneWidget);
    // The bottom bar belongs to phones and must not join the rail here.
    expect(find.byType(TimeBuddyBottomBar), findsOneWidget);
    expect(tester.getSize(find.byType(TimeBuddyBottomBar)).height, 0);
    // The labels are gone but the destinations are not: they are tooltips and
    // semantic labels now, not nothing.
    expect(find.text(t.nav.clocks), findsNothing);
  });

  testWidgets('a resize keeps the grid on the hour it was showing', (
    tester,
  ) async {
    // A ScrollPosition stores pixels, and a pixel stopped meaning a fixed hour
    // when the column width became a function of the viewport. Without the
    // rescale, dragging a window edge scrubs the grid through time (rule 15).
    await pumpGridShell(
      tester,
      surface: _desktopSurface,
      board: _boardOf(_threeCities),
    );

    // Scrolled to a deliberately FRACTIONAL column first, and this is the
    // whole rigour of the test. The grid opens centred on now, which lands on
    // an exact integer column — and an integer column happens to survive a
    // moderate width change even with no rescale at all, so a test that
    // asserted the leftmost hour from the opening position would pass against
    // a reverted implementation. Half a column in, it cannot.
    final widthBefore = columnWidth(tester);
    await tester.drag(
      find.byType(GridHeaderStrip),
      Offset(-3.5 * widthBefore, 0),
    );
    await tester.pumpAndSettle();

    final columnBefore = trackOffset(tester) / widthBefore;
    final visibleBefore = visibleHours(tester, _berlin.zoneId);
    final indexBefore = firstColumnIndex(tester);
    final hourBefore = firstRenderedHour(tester, _berlin.zoneId);
    expect(
      columnBefore - columnBefore.floorToDouble(),
      closeTo(0.5, 0.1),
      reason: 'the test is only sharp from a fractional column',
    );

    tester.view.physicalSize = _tabletSurface;
    await tester.pumpAndSettle();

    expect(
      visibleHours(tester, _berlin.zoneId),
      lessThan(visibleBefore),
      reason: 'the resize has to change the geometry for this to mean anything',
    );
    // Tight on purpose. The rescale lands the offset on `column * newWidth`
    // exactly, so anything beyond rounding is a failure — and the tolerance
    // has to be tight because the drift it is catching is genuinely small:
    // `GridLayout` keeps the column between 48 and ~52 at every width that
    // scrolls at all, so a stale pixel offset misreads the column by
    // hundredths rather than by hours. Correct is correct; a loose tolerance
    // here would pass against no rescale whatsoever.
    expect(
      trackOffset(tester) / columnWidth(tester),
      closeTo(columnBefore, 0.02),
      reason: 'the offset must be carried across in columns, not in pixels',
    );

    // And the rows have to agree with that controller. Berlin is the reference
    // zone, so its cells carry the same hours the ruler does; if the offset
    // the rows draw from ever fell out of step with the one the header
    // scrolled to, this is where it would show.
    //
    // It does NOT cover the `correctPixels` guard in `_syncTrackAfterResize`:
    // deleting that line leaves this test green, because the rescaling
    // `jumpTo` notifies the listener for it. Measured with a mutation run, not
    // assumed — the guard stays because the clamp genuinely notifies nobody,
    // but the suite's teeth are in the `jumpTo`, and a comment claiming
    // otherwise would be the kind of false assurance this file exists to stop.
    final indexAfter = firstColumnIndex(tester);
    final expectedHour = (hourBefore + (indexAfter - indexBefore)) % 24;
    expect(
      firstRenderedHour(tester, _berlin.zoneId),
      expectedHour,
      reason: 'the rows must follow the same offset the header scrolled to',
    );
  });

  testWidgets('the last row scrolls clear of the FAB and the bar', (
    tester,
  ) async {
    await pumpGridShell(
      tester,
      surface: _mobileSurface,
      board: _tallBoard(),
    );

    final rows = find
        .ancestor(
          of: find.byType(GridRowView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(rows).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the board must out-run the viewport for this to mean anything',
    );

    await tester.drag(find.byType(GridRowView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      position.pixels,
      moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
      reason: 'the list has to be scrolled to its end',
    );

    // The bar and the FAB both float *over* this list and reserve no layout
    // space, so the last row has to be reachable underneath them rather than
    // merely visible. `bottomSafeForFab` is what buys the room.
    final fab = tester.getRect(find.byType(FloatingActionButton));
    final bar = tester.getRect(find.byType(TimeBuddyBottomBar));
    expect(bar.height, TimeBuddyBottomBar.reservedHeight);
    expect(
      fab.bottom,
      bar.top,
      reason: 'the FAB is lifted by exactly the bar it has to clear',
    );

    expect(_trackOf(_manyZoneIds.last), findsOneWidget);
    expect(
      tester.getRect(_trackOf(_manyZoneIds.last)).bottom,
      lessThanOrEqualTo(fab.top),
    );
  });
}

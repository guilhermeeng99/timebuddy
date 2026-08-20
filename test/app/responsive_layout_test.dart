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
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/lifted_fab.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/app/widgets/timebuddy_bottom_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_date_pill.dart';
import 'package:timebuddy/app/widgets/timebuddy_sidebar.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/settings/presentation/pages/settings_page.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';
import 'package:uuid/uuid.dart';

import '../harness/factories/board_factory.dart';
import '../harness/helpers.dart';
import '../harness/pump_app.dart';

// The responsive contract of the shell (design_system section 7), pinned at
// the two widths the product is actually used at. A visual check cannot be
// committed; this can.
//
// Every rule here is asserted from *both* sides of the 600px breakpoint on
// purpose. A test that only checks the happy width still passes with the
// comparison inverted, and inverting it is the single most likely edit to
// break this screen: the chrome would simply appear on the other kind of
// device, which nobody running the suite would see.
//
// Nothing below asserts merely that a build did not throw. The questions are
// which chrome exists, how large it is, and where it sits.

/// A phone: the smaller of the two surfaces, and below the breakpoint.
const Size _mobileSurface = Size(375, 812);

/// A desktop window: past both breakpoints, so the rail is on screen.
const Size _desktopSurface = Size(1280, 800);

/// Relative path of the pushed sub-page under the grid branch.
const String _subPageSegment = 'sub';

/// The pushed sub-page as a location, derived rather than retyped.
const String _subPageRoute = '${AppRoutes.grid}$_subPageSegment';

/// The day the stand-in stepper shows.
///
/// Equal to its own "today", so the pill renders without the Today reset and
/// its width does not depend on when the suite runs.
final DateTime _referenceDay = utcDate(2024, 6, 15);

/// The board boundary `AppShell` resolves out of `GetIt` to build the
/// session's `BoardCubit`.
class _MockBoardRepository extends Mock implements BoardRepository {}

/// `BoardCubit` mints row ids with a `Uuid`. Nothing here adds a city, so it
/// is never asked for one.
class _MockUuid extends Mock implements Uuid {}

/// Stands in for the grid: the one destination that owns a reference day, and
/// therefore the only page that hands the shell a stepper.
///
/// A fake rather than the real `TimeGridPage`, because what is under test is
/// where the shell puts a stepper and a FAB, not what the grid computes.
/// `time_grid_responsive_test.dart` runs the same rules through the real page.
class _StepperPage extends StatelessWidget {
  const _StepperPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: const LiftedFab(
        child: FloatingActionButton(
          onPressed: _ignoreTap,
          child: Icon(Icons.add),
        ),
      ),
      body: Column(
        children: [
          // Rendered unconditionally, exactly as the grid renders it:
          // `ShellDatePill` is what decides whether the stepper stays on the
          // page or goes to the rail.
          ShellDatePill(
            pill: TimeBuddyDatePill(
              value: _referenceDay,
              today: _referenceDay,
              todayLabel: t.grid.today,
              onChanged: _ignoreStep,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pushed sub-page, wrapped the way `AppRouter` wraps the add-location
/// route.
///
/// It carries a FAB of its own so the depth half of the `LiftedFab` rule can
/// be read off a page that is actually on screen.
class _PushedSubPage extends StatelessWidget {
  const _PushedSubPage();

  @override
  Widget build(BuildContext context) {
    return const SubPageScope(
      child: Scaffold(
        floatingActionButton: LiftedFab(
          child: FloatingActionButton(
            onPressed: _ignoreTap,
            child: Icon(Icons.check),
          ),
        ),
        body: SizedBox.expand(),
      ),
    );
  }
}

/// The stepper is placed here, never driven: these tests ask where it lands.
void _ignoreStep(DateTime day) {}

/// The FABs exist to be measured, not pressed.
void _ignoreTap() {}

/// A router shaped like `AppRouter`'s shell: one branch per destination, in
/// `TimeBuddyNavDestination` order, which `AppShell` asserts on.
///
/// Built here rather than reused from `AppRouter`, whose router is a
/// `static final` carrying the app's redirect chain: it would send every test
/// through the splash and hand one test's navigation stack to the next.
GoRouter _shellRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.grid,
                builder: (context, state) => const _StepperPage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: _subPageSegment,
                    builder: (context, state) => const _PushedSubPage(),
                  ),
                ],
              ),
            ],
          ),
          // Never visited here: both nav surfaces list the destinations
          // themselves, so this branch only has to exist.
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.locations,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  setUpAll(() async {
    initTestTimeZones();
    registerCommonFallbacks();
    // The date pill formats its label through intl, whose date symbols the app
    // gets from flutter_localizations and a test process has to load itself.
    await initializeDateFormatting();
  });

  /// Mounts [AppShell] at [surface], through a router shaped like the app's.
  ///
  /// `pumpApp` owns the locator, the locale, the fonts and the paused ticker,
  /// so it installs first against a throwaway home. The two dependencies the
  /// shell resolves for its `BoardCubit` are registered after it and before
  /// the real tree is pumped, which is why this is not one `pumpApp` call.
  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    required Size surface,
    String initialLocation = AppRoutes.grid,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = surface;
    // The view is process-wide. Without the reset the next test in this file
    // inherits this width and quietly asserts the wrong side of the
    // breakpoint.
    addTearDown(tester.view.reset);

    final app = await pumpApp(tester, const SizedBox.shrink());

    // Hoisted out of the stub: building the answer inside `when` is what makes
    // mocktail throw "Cannot call `when` within a stub response".
    final board = aBoard(locations: [aSavedLocation()]);
    final repository = _MockBoardRepository();
    when(
      () => repository.load(
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => Right<Failure, BoardEntity>(board));

    GetIt.I
      ..registerSingleton<BoardRepository>(repository)
      ..registerSingleton<Uuid>(_MockUuid());

    // Both notifiers are app-scoped and outlive the pumped tree, so one test's
    // stepper and sub-page depth would otherwise be the next one's start.
    addTearDown(shellDatePill.reset);
    addTearDown(subPageDepth.reset);

    final router = _shellRouter(initialLocation: initialLocation);
    await tester.pumpWidget(
      TranslationProvider(
        child: BlocProvider<PreferencesCubit>.value(
          value: app.cubit,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    // `ShellDatePill` publishes out of its own build, so the rail only has the
    // stepper one frame later.
    await tester.pumpAndSettle();
    return router;
  }

  /// The stepper wherever it ended up, which is the point of half these tests.
  Finder datePill() => find.byType(TimeBuddyDatePill);

  Finder pillInRail() => find.descendant(
    of: find.byType(TimeBuddySidebar),
    matching: datePill(),
  );

  Finder pillOnPage() => find.descendant(
    of: find.byType(_StepperPage),
    matching: datePill(),
  );

  /// The licenses row of the settings page: the last thing in that list, and
  /// the row a missing bottom inset leaves visible and untappable.
  Finder licensesRow() => find.ancestor(
    of: find.text(t.settings.licenses),
    matching: find.byType(InkWell),
  );

  /// Drags [page]'s scroll view to its end, having checked there was something
  /// to scroll.
  Future<void> scrollToEnd(WidgetTester tester, Finder page) async {
    final scrollable = find
        .descendant(of: page, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the page must out-run the viewport for this to mean anything',
    );

    await tester.drag(page, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(
      position.pixels,
      moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
      reason: 'the list has to be scrolled to its end',
    );
  }

  testWidgets('below 600px the shell hangs a bar and builds no rail', (
    tester,
  ) async {
    await pumpShell(tester, surface: _mobileSurface);

    // The rail is not merely invisible below the breakpoint: it builds nothing
    // at all, so none of its contents is on screen to be read out, tabbed into
    // or measured.
    expect(tester.getSize(find.byType(TimeBuddySidebar)), Size.zero);
    expect(find.text(t.app.name), findsNothing);

    final bar = tester.getRect(find.byType(TimeBuddyBottomBar));
    expect(bar.height, TimeBuddyBottomBar.reservedHeight);
    expect(
      bar.bottom,
      _mobileSurface.height,
      reason: 'the bar floats on the window edge, over the page',
    );
    expect(bar.left, 0);
    expect(bar.right, _mobileSurface.width);

    // Only the active destination names itself on a phone-width pill.
    expect(find.text(t.nav.grid), findsOneWidget);
    expect(find.text(t.nav.locations), findsNothing);
    expect(find.text(t.nav.settings), findsNothing);
  });

  testWidgets('at 600px and up the rail replaces the bar', (tester) async {
    await pumpShell(tester, surface: _desktopSurface);

    expect(
      tester.getSize(find.byType(TimeBuddyBottomBar)),
      Size.zero,
      reason: 'a bar beside a rail would be two navigations for one app',
    );

    final rail = tester.getRect(find.byType(TimeBuddySidebar));
    expect(rail.left, 0);
    expect(rail.top, 0);
    expect(rail.width, TimeBuddySidebar.width);
    expect(rail.height, _desktopSurface.height);
    expect(find.text(t.app.name), findsOneWidget);

    // The rail takes its own column rather than floating over the content.
    expect(
      tester.getRect(find.byType(_StepperPage)).left,
      TimeBuddySidebar.width,
    );

    // Every destination is legible at this width, not just the active one.
    for (final destination in TimeBuddyNavDestination.values) {
      expect(find.text(destination.label), findsOneWidget);
    }
  });

  testWidgets('below 600px the page owns the stepper, and only the page', (
    tester,
  ) async {
    await pumpShell(tester, surface: _mobileSurface);

    // Exactly one is the whole rule. The failure design_system section 7 names
    // is a page that draws its own stepper while the rail is showing one, and
    // a "renders a stepper" assertion passes that with flying colours.
    expect(datePill(), findsOneWidget);
    expect(pillOnPage(), findsOneWidget);
    expect(pillInRail(), findsNothing);
  });

  testWidgets('at 600px and up the rail owns the stepper, and only the rail', (
    tester,
  ) async {
    await pumpShell(tester, surface: _desktopSurface);

    expect(datePill(), findsOneWidget);
    expect(pillInRail(), findsOneWidget);
    expect(
      pillOnPage(),
      findsNothing,
      reason: 'the page must take no space for a control the rail is showing',
    );

    // Parented to the rail *and* drawn inside its column.
    expect(
      tester.getRect(datePill()).right,
      lessThanOrEqualTo(TimeBuddySidebar.width),
    );
  });

  testWidgets('a sub-page takes the bar and the stepper off a phone', (
    tester,
  ) async {
    final router = await pumpShell(tester, surface: _mobileSurface);

    // The baseline: without it, a shell that never drew chrome at all would
    // pass every assertion below.
    expect(
      tester.getRect(find.byType(TimeBuddyBottomBar)).height,
      TimeBuddyBottomBar.reservedHeight,
    );
    expect(datePill(), findsOneWidget);

    router.go(_subPageRoute);
    await tester.pumpAndSettle();

    expect(find.byType(SubPageScope), findsOneWidget);
    expect(subPageDepth.value, 1);
    expect(tester.getSize(find.byType(TimeBuddyBottomBar)), Size.zero);
    // No stepper anywhere: the rail has none to show at this width, and the
    // page that owned one went under the route pushed over it.
    expect(datePill(), findsNothing);

    // Depth 1, so the FAB drops back to the Scaffold's own margin: there is no
    // bar left to clear, and a lift here would strand it in empty space.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(_mobileSurface.height - fab.bottom, kFloatingActionButtonMargin);
  });

  testWidgets('a sub-page empties the rail slot and leaves the nav', (
    tester,
  ) async {
    final router = await pumpShell(tester, surface: _desktopSurface);
    expect(pillInRail(), findsOneWidget);

    router.go(_subPageRoute);
    await tester.pumpAndSettle();

    expect(subPageDepth.value, 1);
    expect(
      datePill(),
      findsNothing,
      reason: 'a pushed form has no reference day to step',
    );

    // The stepper goes; the way to another destination does not.
    expect(
      tester.getRect(find.byType(TimeBuddySidebar)).width,
      TimeBuddySidebar.width,
    );
    for (final destination in TimeBuddyNavDestination.values) {
      expect(find.text(destination.label), findsOneWidget);
    }

    // A FAB on a sub-page is unlifted at every width, and the bar stays gone.
    expect(tester.getSize(find.byType(TimeBuddyBottomBar)), Size.zero);
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(_desktopSurface.height - fab.bottom, kFloatingActionButtonMargin);
  });

  testWidgets('the FAB rises exactly onto the bar on a phone', (tester) async {
    await pumpShell(tester, surface: _mobileSurface);

    final fab = tester.getRect(find.byType(FloatingActionButton));
    final bar = tester.getRect(find.byType(TimeBuddyBottomBar));

    // The lift is derived from the bar's own height, so the two meet: the
    // FAB's bottom edge is the bar's top edge. Retuning the bar has to move
    // the FAB with it, and this is the assertion that says so.
    expect(fab.bottom, bar.top);
    expect(
      _mobileSurface.height - fab.bottom,
      kFloatingActionButtonMargin + LiftedFab.mobileLift,
    );
    expect(
      kFloatingActionButtonMargin + LiftedFab.mobileLift,
      TimeBuddyBottomBar.reservedHeight,
    );
  });

  testWidgets('the FAB sits at the plain margin at 600px and up', (
    tester,
  ) async {
    await pumpShell(tester, surface: _desktopSurface);

    // Nothing floats along the bottom of a window this wide, so a lift would
    // park the FAB in the middle of nowhere.
    expect(tester.getSize(find.byType(TimeBuddyBottomBar)), Size.zero);
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(_desktopSurface.height - fab.bottom, kFloatingActionButtonMargin);
  });

  testWidgets('a primary destination clears the bar with its last row', (
    tester,
  ) async {
    await pumpShell(
      tester,
      surface: _mobileSurface,
      initialLocation: AppRoutes.settings,
    );
    await scrollToEnd(tester, find.byType(SettingsPage));

    final row = tester.getRect(licensesRow());
    final bar = tester.getRect(find.byType(TimeBuddyBottomBar));
    expect(bar.top, _mobileSurface.height - TimeBuddyBottomBar.reservedHeight);

    // This is the bug that shipped once. The bar floats over the list and
    // reserves no layout space, so a list padded to its own last pixel ends on
    // a row the user can see and cannot tap; `bottomSafeForBar` is what buys
    // the room, and scrolling to the end is the only way to prove it did.
    expect(
      row.bottom,
      lessThanOrEqualTo(bar.top),
      reason: 'the last row has to be tappable, not merely visible',
    );
  });

  testWidgets('the same list may reach the window edge at 600px and up', (
    tester,
  ) async {
    await pumpShell(
      tester,
      surface: _desktopSurface,
      initialLocation: AppRoutes.settings,
    );
    await scrollToEnd(tester, find.byType(SettingsPage));

    // The other half of the rule. At this width the rail takes its own column
    // and nothing floats along the bottom, so the inset collapses; a mobile
    // inset left switched on would show up here as a band of dead space under
    // the last row.
    expect(tester.getSize(find.byType(TimeBuddyBottomBar)), Size.zero);
    expect(
      tester.getRect(licensesRow()).bottom,
      greaterThan(_desktopSurface.height - TimeBuddyBottomBar.reservedHeight),
    );
  });
}

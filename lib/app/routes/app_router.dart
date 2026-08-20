import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/routes/app_shell.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/features/locations/presentation/pages/add_location_sheet.dart';
import 'package:timebuddy/features/locations/presentation/pages/locations_page.dart';
import 'package:timebuddy/features/settings/presentation/pages/settings_page.dart';
import 'package:timebuddy/features/time_grid/presentation/pages/time_grid_page.dart';

/// How dark the add-location route dims the page it was opened from.
///
/// Matches the weight of a Material modal barrier: enough to push the page
/// behind the sheet, not so much that the user loses the row they were
/// looking at when they decided to add a city.
const double _sheetScrimAlpha = 0.4;

/// Enter and exit duration of the add-location route.
const Duration _sheetTransition = Duration(milliseconds: 250);

/// The app's single [GoRouter].
///
/// Held as a `static final` and built exactly once. Every theme, palette and
/// locale change rebuilds `MaterialApp`, and a router constructed inside that
/// build would reset the navigation stack under the user each time.
///
/// **The URL strategy is deliberately left at go_router's default hash form**
/// (`/#/settings`), so nothing here or in `main` may call
/// `usePathUrlStrategy()`. The web build is served from a GitHub Pages
/// *project* sub-path, a static host with no rewrite rule: under the path
/// strategy a reload of `/settings` asks the host for a file that does not
/// exist and gets a 404 instead of `index.html`.
///
/// ```dart
/// MaterialApp.router(routerConfig: AppRouter.router);
/// ```
abstract class AppRouter {
  static final StatefulShellBranch _gridBranch = StatefulShellBranch(
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.grid,
        builder: (context, state) => const TimeGridPage(),
      ),
    ],
  );

  static final StatefulShellBranch _locationsBranch = StatefulShellBranch(
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.locations,
        builder: (context, state) => const LocationsPage(),
        routes: <RouteBase>[
          // Nested for the URL: `/locations/add` reads as what it is and is
          // reachable as a deep link, which a modal opened from a button
          // never is.
          //
          // Deliberately *without* a `parentNavigatorKey`. A route pushed on
          // the root navigator is a sibling of `AppShell`, not a descendant,
          // and the board it writes to is the `BoardCubit` the shell
          // provides — so it could not read the cubit at all. Left inside the
          // branch, go_router grafts the push onto whichever branch navigator
          // is showing (`RouteMatchList.push` keeps the current shell match
          // and appends the imperative one), so the grid's FAB and a deep
          // link both land on top of the page the user is actually looking
          // at, under the shell's providers.
          GoRoute(
            path: AppRoutes.addLocationSegment,
            pageBuilder: _addLocationPage,
          ),
        ],
      ),
    ],
  );

  static final StatefulShellBranch _settingsBranch = StatefulShellBranch(
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );

  /// One branch per primary destination, **in `TimeBuddyNavDestination`
  /// order**.
  ///
  /// `AppShell` reads the highlighted destination out of the shell's
  /// `currentIndex` and switches branches with `goBranch(destination.index)`,
  /// so the two orders are one fact written down twice; `AppShell` asserts on
  /// the count, so a fourth destination added to only one of them fails
  /// loudly in debug instead of quietly selecting the wrong tab.
  ///
  /// Each branch keeps its own `Navigator`, which is what makes a trip to
  /// settings and back leave the grid's horizontal scroll where it was.
  static final List<StatefulShellBranch> _branches = <StatefulShellBranch>[
    _gridBranch,
    _locationsBranch,
    _settingsBranch,
  ];

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.grid,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: _branches,
      ),
    ],
  );

  /// The add-location route: the city picker, wearing a modal's clothes.
  ///
  /// `AddLocationSheet` is the same widget the board page opens with
  /// `showAddLocationSheet`, and it draws a `DraggableScrollableSheet`. A
  /// route that rendered it opaquely would show a sheet floating over a blank
  /// scaffold, and the same action would look like two different things
  /// depending on which screen it was started from. `opaque: false` plus a
  /// scrim keeps the page underneath painted, so the pushed route and the
  /// modal are indistinguishable — except that this one has a URL and a back
  /// button.
  ///
  /// [SubPageScope] is applied here rather than inside the sheet because the
  /// modal path must *not* have it: a modal barrier already covers the bottom
  /// bar, while this route only covers the branch's content area.
  static Page<void> _addLocationPage(
    BuildContext context,
    GoRouterState state,
  ) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      opaque: false,
      barrierDismissible: true,
      barrierColor: context.appColors.scrim.withValues(alpha: _sheetScrimAlpha),
      // The platform's own "dismiss" label, so the barrier reads correctly to
      // a screen reader in every locale the app is translated into.
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: _sheetTransition,
      reverseTransitionDuration: _sheetTransition,
      transitionsBuilder: _slideUp,
      child: const SubPageScope(child: AddLocationSheet()),
    );
  }

  /// Slides a page up from the bottom edge, the way a bottom sheet arrives.
  static Widget _slideUp(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // A chained tween rather than a `CurvedAnimation`: this builder runs on
    // every frame of the transition, and the chain form allocates nothing that
    // would then be owed a `dispose`.
    final slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    return SlideTransition(position: animation.drive(slide), child: child);
  }
}

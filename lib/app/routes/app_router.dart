import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/routes/app_shell.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/auth/presentation/pages/onboarding_page.dart';
import 'package:timebuddy/features/locations/presentation/pages/add_location_sheet.dart';
import 'package:timebuddy/features/profile/presentation/pages/profile_page.dart';
import 'package:timebuddy/features/settings/presentation/pages/settings_page.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';
import 'package:timebuddy/features/startup/presentation/pages/startup_page.dart';
import 'package:timebuddy/features/time_converter/presentation/pages/time_converter_page.dart';
import 'package:timebuddy/features/time_grid/presentation/pages/time_grid_page.dart';
import 'package:timebuddy/features/world_clock/presentation/pages/world_clock_page.dart';

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
        routes: <RouteBase>[
          // Nested under the grid, which is the screen that owns the board
          // now that the Cities destination is gone. `/add` reads as what it
          // is and is reachable as a deep link, which a modal opened from a
          // button never is.
          //
          // Deliberately *without* a `parentNavigatorKey`. A route pushed on
          // the root navigator is a sibling of `AppShell`, not a descendant,
          // and the board it writes to is the `BoardCubit` the shell
          // provides — so it could not read the cubit at all. Left inside the
          // branch, go_router grafts the push onto whichever branch navigator
          // is showing, so the grid's FAB, the world clock's FAB and a deep
          // link all land on top of the page the user is actually looking at,
          // under the shell's providers.
          GoRoute(
            path: AppRoutes.addLocationSegment,
            pageBuilder: _addLocationPage,
          ),
        ],
      ),
    ],
  );

  static final StatefulShellBranch _clocksBranch = StatefulShellBranch(
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.clocks,
        builder: (context, state) => const WorldClockPage(),
      ),
    ],
  );

  static final StatefulShellBranch _converterBranch = StatefulShellBranch(
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.converter,
        builder: (context, state) => const TimeConverterPage(),
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
  /// the count, so a destination added to only one of them fails loudly in
  /// debug instead of quietly selecting the wrong tab.
  ///
  /// Each branch keeps its own `Navigator`, which is what makes a trip to
  /// settings and back leave the grid's horizontal scroll where it was — and,
  /// from M4 on, leave the converter's half-filled form alone while the user
  /// checks a city on the world clock.
  ///
  /// The meeting planner has no branch: it is a mode of `_gridBranch`
  /// (docs/specs/meeting_planner.md), so entering it keeps the grid's own
  /// navigator and its scroll position.
  static final List<StatefulShellBranch> _branches = <StatefulShellBranch>[
    _gridBranch,
    _clocksBranch,
    _converterBranch,
    _settingsBranch,
  ];

  static final GoRouter router = GoRouter(
    // Every launch, and every deep link, starts on the splash: it is where
    // tzdata is loaded and where the account's documents are reconciled
    // (docs/specs/startup.md), and [_redirect] holds anything that tries to
    // skip it.
    initialLocation: AppRoutes.startup,
    refreshListenable: _authRefresh,
    redirect: _redirect,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.startup,
        builder: (context, state) => const StartupPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      // Root level rather than a sixth branch: the account page is not one of
      // the nav destinations, and it is the one screen that can end the
      // session that the shell's chrome and board are built on.
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfilePage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: _branches,
      ),
    ],
  );

  /// What every navigation is allowed to do, in four rules.
  ///
  /// 1. Until startup resolves, nothing but the splash renders. A deep link
  ///    that skipped it would build a grid against uninitialized tzdata, and
  ///    `StartupError` holds here too, because its recovery is the page's
  ///    retry rather than a route out (startup.md, responsibility 6).
  /// 2. No session **and no guest marker**: the landing is onboarding. Sign-in
  ///    is an offer rather than a gate (guest_mode.md rule 5), so what this
  ///    rule now catches is only the visitor who has not chosen either way.
  ///    The broad `is! Authenticated` is kept deliberately: `AuthInitial` and
  ///    `AuthError` both belong on onboarding for a non-guest.
  /// 3. A guest whose sign-in landed goes back through the splash, so
  ///    `StartupCubit` can run the adopting sync (guest_mode.md rule 6).
  ///    Keyed on `adoptionAttempted` rather than on the marker alone, because
  ///    an adoption that fails leaves the marker set and a marker-only rule
  ///    would loop `/startup` → grid → `/startup` forever.
  /// 4. A session that lands while onboarding is showing goes back through the
  ///    splash, not straight to the grid. That sign-in may be a *different*
  ///    account, whose board and preferences have not been pulled yet. Rule 3
  ///    cannot cover it: a visitor signing in from onboarding is not a guest.
  ///
  /// Leaving the splash on success is deliberately *not* here: that is
  /// `StartupPage`'s own `context.go`, so the one place that knows startup
  /// finished is the one place that acts on it.
  static String? _redirect(BuildContext context, GoRouterState state) {
    final location = state.matchedLocation;
    if (!_startupResolved(sl<StartupCubit>().state)) {
      return location == AppRoutes.startup ? null : AppRoutes.startup;
    }

    final guest = sl<GuestSession>();
    final authState = sl<AuthBloc>().state;
    if (authState is! Authenticated && !guest.isGuest) {
      return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
    }

    if (guest.isGuest &&
        authState is Authenticated &&
        !guest.adoptionAttempted) {
      return location == AppRoutes.startup ? null : AppRoutes.startup;
    }

    // Spelled out as `is Authenticated` rather than left as the fall-through
    // it used to be, so a *guest* who opens `/onboarding` — by URL, or to
    // reach the Google button — is allowed to stay and read it. Bouncing them
    // to the splash would send them straight back to the grid and make the
    // tour unreachable for the one person still deciding.
    if (authState is Authenticated && location == AppRoutes.onboarding) {
      return AppRoutes.startup;
    }
    return null;
  }

  /// Whether startup has produced a route decision.
  ///
  /// `StartupInitial`, `StartupLoading` and `StartupError` all mean "not yet",
  /// which is why this asks for the two states that are answers rather than
  /// excluding the three that are not: a fourth non-terminal state added later
  /// would otherwise open the app by default.
  static bool _startupResolved(StartupState state) =>
      state is StartupAuthenticated || state is StartupUnauthenticated;

  /// Re-runs [_redirect] whenever the session **or the guest marker** changes.
  ///
  /// Without it the rules above would only be applied on a navigation, so a
  /// sign-out performed on the profile page would leave the user sitting on a
  /// screen they are no longer allowed to see until they tapped something.
  ///
  /// `GuestSession` is merged in rather than left to the navigation that
  /// follows it, because "continue without an account" changes what rule 2
  /// answers *before* anything navigates: without this the onboarding page
  /// would have to know which route to send a new guest to, which is the
  /// redirect's job.
  static final Listenable _authRefresh = Listenable.merge(<Listenable>[
    _BlocRefreshListenable(sl<AuthBloc>().stream),
    sl<GuestSession>(),
  ]);

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

/// A bloc's state stream, wearing the `Listenable` go_router wants.
///
/// go_router only re-evaluates `redirect` on a navigation or when its
/// `refreshListenable` notifies, and the session changes without either: a
/// revoked token or a sign-out in another browser tab arrives on this stream
/// and nowhere else.
///
/// Never disposed, deliberately. It is owned by the `static final` router and
/// lives exactly as long as the process; a `dispose` that could be called
/// would be a way to leave the app with a redirect that has stopped listening.
class _BlocRefreshListenable extends ChangeNotifier {
  _BlocRefreshListenable(Stream<Object?> states) {
    _subscription = states.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// Every route path in the app, in one place.
///
/// These strings are also the web URLs, so a rename breaks somebody's
/// bookmark: add a constant here before adding a `GoRoute`, and never inline
/// a path literal at a `context.go` / `context.push` call site.
///
/// ```dart
/// context.push(AppRoutes.addLocation);
/// ```
abstract class AppRoutes {
  /// The splash, and the app's entry route (docs/specs/startup.md).
  ///
  /// Everything passes through here, including a deep link: tzdata is loaded
  /// on this route, and a grid built before it lands renders plausible hours
  /// that are simply wrong (CLAUDE.md, Time & Timezone Rules). It is also
  /// where a fresh sign-in comes back to, so the new account's documents are
  /// reconciled before any page reads them.
  static const String startup = '/startup';

  /// The unauthenticated landing: the three-slide tour whose last slide holds
  /// the Google button (docs/specs/auth.md).
  ///
  /// Not `/sign-in`, and there is no page by that name: the app is
  /// Google-only, so a screen whose whole content is one button would be a
  /// second stop on the way to the same tap.
  static const String onboarding = '/onboarding';

  /// The account page: who is signed in, the sync status, sign out, delete
  /// account (docs/specs/auth.md).
  ///
  /// A root-level route rather than a sixth shell branch. It is reached from
  /// the sidebar's profile slot and from settings, it is not one of the
  /// destinations the nav offers, and it is the one screen that can end the
  /// session under the chrome that would otherwise be drawn around it.
  static const String profile = '/profile';

  /// The comparison grid: where a signed-in launch lands
  /// (docs/specs/time_grid.md).
  ///
  /// It replaced milestone 1's placeholder home page rather than sitting
  /// behind it: the grid is the answer the user opened the app for, and a
  /// landing screen in front of it is a tap that buys nothing. [startup] is
  /// not such a screen — it is work the user would otherwise wait through on
  /// a half-drawn grid.
  ///
  /// **The meeting planner has no route of its own on purpose.** It is a mode
  /// of this page (docs/specs/meeting_planner.md): same rows, same columns,
  /// same engine, with the cursor turned into a range. A `/planner` URL would
  /// promise a second screen and then render the first one.
  static const String grid = '/';

  /// The world clock: one live tile per saved city
  /// (docs/specs/world_clock.md).
  ///
  /// A destination of its own rather than a tab inside [grid], because it
  /// answers a different question — "what time is it there *now*" against the
  /// grid's "what does this hour look like everywhere" — and because a shell
  /// branch is what lets each keep its own scroll position.
  ///
  /// Plural, and `/clocks` rather than `/world-clock`: it is the URL of a list
  /// of clocks, and the shorter spelling is the one a user retypes correctly.
  static const String clocks = '/clocks';

  /// The one-instant converter (docs/specs/time_converter.md).
  ///
  /// A primary destination, not a sub-page of the grid: it is reached cold
  /// ("what is 14:00 Tokyo here"), so putting it behind another screen would
  /// charge a tap for the app's second most common question.
  static const String converter = '/converter';

  /// The saved board: add, reorder, remove (docs/specs/locations.md).
  static const String locations = '/locations';

  /// The `add` segment on its own.
  ///
  /// go_router wants a *relative* path on a child route, so the nested
  /// `GoRoute` under [locations] is declared with this instead of with the
  /// full path. Deriving [addLocation] from it is what stops the two
  /// spellings from drifting apart when either one is renamed.
  static const String addLocationSegment = 'add';

  /// The add-location sub-page: the city picker, as a URL.
  ///
  /// Nested under the board because that is where it reads as what it is, and
  /// because `TimeBuddyNavDestination.matches` counts sub-routes. The route
  /// renders the same `AddLocationSheet` the board page opens as a modal, over
  /// a scrim rather than opaquely, so the two entry points look alike; see
  /// `app_router.dart`. The router wraps it in a `SubPageScope`, which is what
  /// stops `LiftedFab` lifting a FAB over a bar that is no longer on screen
  /// (design_system §7).
  static const String addLocation = '$locations/$addLocationSegment';

  /// Preferences (docs/specs/preferences.md).
  ///
  /// A primary destination from M2 on, not a pushed sub-page: it is one of
  /// the things the nav offers, so it owns a shell branch and keeps its own
  /// scroll position across a trip to the grid and back.
  static const String settings = '/settings';
}

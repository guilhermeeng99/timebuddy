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
  /// The comparison grid, and the app's start route
  /// (docs/specs/time_grid.md).
  ///
  /// It replaced milestone 1's placeholder home page rather than sitting
  /// behind it: the grid is the answer the user opened the app for, and a
  /// landing screen in front of it is a tap that buys nothing.
  static const String grid = '/';

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
  /// the three things the nav offers, so it owns a shell branch and keeps its
  /// own scroll position across a trip to the grid and back.
  static const String settings = '/settings';
}

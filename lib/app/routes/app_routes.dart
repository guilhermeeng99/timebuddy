/// Every route path in the app, in one place.
///
/// These strings are also the web URLs, so a rename breaks somebody's
/// bookmark: add a constant here before adding a `GoRoute`, and never inline
/// a path literal at a `context.go` / `context.push` call site.
///
/// ```dart
/// context.push(AppRoutes.settings);
/// ```
abstract class AppRoutes {
  /// The board. A device-clock placeholder in M1, the comparison grid from M2
  /// on (docs/specs/time_grid.md).
  static const String home = '/';

  /// Preferences. Pushed as a sub-page, and URL-reachable on web, which is
  /// why every page that leaves it uses `context.popOrGo`.
  static const String settings = '/settings';
}

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Navigation helpers that survive a deep link.
extension ContextNavigationExtensions on BuildContext {
  /// Closes the current sub-page, falling back to [fallbackRoute] when there
  /// is nothing to close.
  ///
  /// Every sub-page in TimeBuddy is URL-addressable on web (`/profile`,
  /// `/add`). When the user opens one of those URLs directly — a
  /// pasted link, a bookmark, a page reload — the router builds that page as
  /// the *first* entry of the stack, so `pop()` has nothing beneath it: on web
  /// it strands the user on a dead page, and on Android it closes the app.
  ///
  /// The same widget is reached both ways, so the close action cannot assume
  /// either. It asks the router and then either pops the push or navigates to
  /// the route the page belongs under.
  ///
  /// ```dart
  /// // The profile page: pushed from settings, or opened cold at /profile.
  /// context.popOrGo(AppRoutes.grid);
  ///
  /// // A picker handing a value back to the page that pushed it.
  /// context.popOrGo(AppRoutes.grid, result: selectedCity);
  /// ```
  ///
  /// Most sub-pages reach this through `TimeBuddyLargeAppBar`'s
  /// `fallbackRoute` rather than calling it directly, because the back chevron
  /// is where the close action lives.
  void popOrGo(String fallbackRoute, {Object? result}) {
    // Resolved once and used through the router rather than through go_router's
    // own BuildContext extension: unqualified extension members do not resolve
    // against `this` inside another extension's body.
    final router = GoRouter.of(this);
    if (router.canPop()) {
      router.pop(result);
      return;
    }
    router.go(fallbackRoute);
  }
}

import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/features/home/presentation/pages/home_page.dart';
import 'package:timebuddy/features/settings/presentation/pages/settings_page.dart';

/// The app's single [GoRouter].
///
/// Held as a `static final` and built exactly once. Every theme, palette and
/// locale change rebuilds `MaterialApp`, and a router constructed inside that
/// build would reset the navigation stack under the user each time.
///
/// **The URL strategy is deliberately left at go_router's default hash form**
/// (`/#/settings`). The web build is served from a GitHub Pages *project*
/// sub-path, a static host with no rewrite rule: with `usePathUrlStrategy` a
/// reload of `/settings` asks the host for a file that does not exist and
/// returns a 404 instead of `index.html`.
///
/// ```dart
/// MaterialApp.router(routerConfig: AppRouter.router);
/// ```
abstract class AppRouter {
  // TODO(m2): wrap the tabbed pages in a ShellRoute once the grid, world clock
  // and planner exist, so the sidebar and the floating bottom bar survive
  // navigation instead of being rebuilt per page. The shell also owns the
  // reference-day date pill. See docs/specs/time_grid.md.
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
}

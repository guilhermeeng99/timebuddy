import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';

// The back chevron, and specifically the case that had no answer before:
// a page that is reachable by URL, is not one of the nav destinations, and is
// opened cold. `/profile` is that page — a root-level route outside the shell,
// so on a page reload it has neither a navigator stack to pop nor a bottom bar
// or rail to leave by. The bar hid its chevron (correctly, since `pop()` would
// have done nothing) and left the user with no way off the screen at all.
//
// `context.popOrGo` existed for exactly this and had zero call sites in `lib/`.
// `fallbackRoute` is the wiring.
void main() {
  Finder chevron() => find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.icon.codePoint == 0xf053,
    description: 'the back chevron',
  );

  /// A router whose start route is [start], so a page opened at it has an
  /// empty stack — the cold-open case, not a push.
  Widget coldAt(String start, Widget page) {
    return MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: GoRouter(
        initialLocation: start,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('grid'))),
          GoRoute(path: start, builder: (_, _) => page),
        ],
      ),
    );
  }

  testWidgets('a cold sub-page with a fallback keeps its way out', (
    tester,
  ) async {
    await tester.pumpWidget(
      coldAt(
        '/profile',
        const Scaffold(
          appBar: TimeBuddyLargeAppBar(title: 'Profile', fallbackRoute: '/'),
          body: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(chevron(), findsOneWidget);

    await tester.tap(chevron());
    await tester.pumpAndSettle();

    // Went to the fallback rather than doing nothing. `popOrGo` asks the
    // router, which is the only thing that knows there is no push to unwind.
    expect(find.text('grid'), findsOneWidget);
  });

  testWidgets('a cold sub-page without a fallback still hides the chevron', (
    tester,
  ) async {
    await tester.pumpWidget(
      coldAt(
        '/sheet',
        const Scaffold(
          appBar: TimeBuddyLargeAppBar(title: 'Sheet'),
          body: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Unchanged, and deliberately so: a chevron that is visible, tappable and
    // inert is worse than none. Only a page that names somewhere to go gets to
    // keep it (design_system §7).
    expect(chevron(), findsNothing);
  });

  testWidgets('a pushed page pops, fallback or not', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      appBar: TimeBuddyLargeAppBar(title: 'Pushed'),
                      body: SizedBox.shrink(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(chevron(), findsOneWidget);

    await tester.tap(chevron());
    await tester.pumpAndSettle();

    // With no `fallbackRoute` the bar stays on a plain `Navigator.pop`, which
    // is what lets it work inside a pushed route that has no router above it —
    // dialogs and widget tests included.
    expect(find.text('open'), findsOneWidget);
  });
}

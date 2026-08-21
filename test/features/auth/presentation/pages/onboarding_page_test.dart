import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/auth/presentation/pages/onboarding_page.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

/// A viewport tall enough to hold a slide plus the fixed action block.
const Size _surface = Size(500, 900);

/// Stands in for the grid, so "it left onboarding" is a visible fact rather
/// than an assertion about a router's internal location.
const String _gridMarker = 'the app';

void main() {
  setUpAll(() {
    initTestTimeZones();
    registerCommonFallbacks();
  });

  testWidgets('offers a way past the account on the first slide', (
    tester,
  ) async {
    await pumpApp(tester, const OnboardingPage(), surfaceSize: _surface);

    // docs/specs/guest_mode.md rule 3. Skipping the tour and declining an
    // account are two different intentions and get two different controls,
    // so both are on screen at once here.
    expect(find.text(t.auth.onboardingNext), findsOneWidget);
    expect(find.text(t.auth.onboardingSkip), findsOneWidget);
    expect(find.text(t.auth.continueAsGuest), findsOneWidget);
  });

  testWidgets('offers it on the sign-in slide too', (tester) async {
    final app = await pumpApp(
      tester,
      const OnboardingPage(),
      surfaceSize: _surface,
    );

    await tester.tap(find.text(t.auth.onboardingSkip));
    await tester.pumpAndSettle();

    // The slide a blocked sign-in opens straight onto. A control that only
    // appeared on slides 1 and 2 would leave the one person who cannot sign in
    // three swipes behind the way out.
    expect(find.text(t.auth.signInWithGoogle), findsOneWidget);
    expect(find.text(t.auth.continueAsGuest), findsOneWidget);
    expect(app.guestSession.isGuest, isFalse);
  });

  testWidgets('the action block does not grow the page past its box', (
    tester,
  ) async {
    await pumpApp(tester, const OnboardingPage(), surfaceSize: _surface);

    // `_actionsHeight` was raised from 112 when the third control landed. A
    // constant left at the two-control height clips it, and an overflow in
    // the app's very first screen is the worst place to find one.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signing-in state replaces every control with a spinner', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const OnboardingPage(),
      surfaceSize: _surface,
      authState: const AuthLoading(),
    );

    // The guest control goes too. The Google flow leaves the app, and a
    // visitor who tapped "continue without an account" mid-redirect would come
    // back to a session the router then has two answers for.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t.auth.continueAsGuest), findsNothing);
    expect(find.text(t.auth.signInWithGoogle), findsNothing);
  });

  testWidgets('entering guest mode leaves onboarding for the grid', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.onboarding,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: AppRoutes.grid,
          builder: (context, state) => const Text(_gridMarker),
        ),
      ],
    );
    final app = await pumpAppRouter(tester, router, surfaceSize: _surface);

    await tester.tap(find.text(t.auth.continueAsGuest));
    await tester.pumpAndSettle();

    // The page navigates, and it has to: the redirect is a guard, and a guest
    // is *allowed* on `/onboarding`, so writing the marker alone would leave
    // them looking at the button they just pressed
    // (docs/specs/guest_mode.md rule 3).
    expect(app.guestSession.isGuest, isTrue);
    expect(find.text(_gridMarker), findsOneWidget);
    expect(find.text(t.auth.continueAsGuest), findsNothing);
  });
}

/// Mounts a page the way the running app mounts it.
///
/// Milestone 1's pages only render when four things are wired at once: the
/// service locator, an already-loaded `PreferencesCubit`, slang's top-level
/// `t` and the theme. Standing that up inline in every `testWidgets` body
/// would be thirty lines of ceremony per test and, worse, thirty chances to
/// stand it up slightly differently — which is how a widget suite ends up
/// asserting confidently on a tree the app itself never builds.
///
/// It also owns the two pieces of global state a widget test leaks by default.
/// `GetIt` is process-wide, so without a reset a page mounted here would
/// cheerfully resolve the previous test's clock and engine. And
/// `TickerService` starts a `Timer` in its constructor, which `flutter_test`
/// fails the test for if it is still pending when the body returns.
///
/// The third global it pins is the platform, through [_deviceZoneChannel]:
/// see the comment on it for why a real page mounted here hangs without that.
///
/// ```dart
/// final app = await pumpApp(tester, const SettingsPage());
/// await tester.tap(find.text(t.settings.themeLight));
/// await tester.pumpAndSettle();
/// final state = app.cubit.state as PreferencesReady;
/// expect(state.preferences.themeMode, ThemeMode.light);
/// ```
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import 'factories/preferences_factory.dart';
import 'fake_clock.dart';
import 'helpers.dart';
import 'mocks.dart';

/// The handles a pumped page hands back to its test.
///
/// A record rather than a class: five references with no behaviour, and
/// `app.cubit` / `app.repository` at the call site reads better than five
/// positional locals unpacked from a tuple.
typedef PumpedApp = ({
  PreferencesCubit cubit,
  MockPreferencesRepository repository,
  FakeClock clock,
  TickerService ticker,
  TimeZoneEngine engine,
  MockAuthBloc authBloc,
  GuestSession guestSession,
});

/// `flutter_timezone`'s channel, the one platform call the app makes.
///
/// `TzTimeZoneEngine.deviceZone` invokes it, and under `flutter_test` nothing
/// ever answers: a real platform message is replied to on the host event loop,
/// which a `testWidgets` body driving fake time never reaches. The call does
/// not throw and does not time out — its future simply never completes, so
/// `BoardCubit.load` never leaves `BoardLoading`, every page waiting on the
/// board holds a `LoadingShimmer`, and that shimmer's repeating animation
/// keeps a frame scheduled forever. The visible symptom is `pumpAndSettle`
/// timing out in a test that never mentioned the platform at all.
const MethodChannel _deviceZoneChannel = MethodChannel('flutter_timezone');

/// Answers [_deviceZoneChannel] with [handler]; `null` unregisters it again.
void _stubDeviceZone(Future<Object?> Function(MethodCall call)? handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_deviceZoneChannel, handler);

/// The instant every pumped page reads as "now" unless a test pins its own.
///
/// Mid-June, mid-month and off the hour on purpose: it sits far from any DST
/// transition in either hemisphere, so a page test cannot be broken by one it
/// never meant to exercise, and a widget that renders a hardcoded `12:00`
/// cannot pass by accident.
final DateTime harnessNowUtc = utcDate(2024, 6, 15, 12, 30);

/// Lays the next `pumpWidget` out in a [size]-logical-pixel window.
///
/// Through the view and not `tester.binding.setSurfaceSize`, which is the
/// distinction this harness got wrong for a milestone. `setSurfaceSize`
/// overrides the *render surface* only; `MediaQuery` is derived from the view,
/// whose `physicalSize` stays at the default 2400x1800 at dpr 3 — 800x600
/// logical — no matter what the surface says. Pages asked for a 400x720
/// "phone" were therefore laid out 400px wide while every
/// `MediaQuery.sizeOf(context).width` in them read 800, so
/// `ResponsiveLayout.isMobile` answered `false` and the mobile form of the
/// grid's pinned column was never laid out by any test. A `RenderFlex`
/// overflow shipped through that hole.
///
/// `devicePixelRatio` is pinned to 1 so [size] is read literally: the view
/// takes physical pixels, and leaving the default 3 in place would ask for a
/// window a third of the size written at the call site.
///
/// The view is process-wide and survives the test that set it, so the reset is
/// not optional — without it the next test in the file silently inherits this
/// width and asserts the wrong side of the breakpoint.
///
/// `responsive_layout_test.dart` and `time_grid_responsive_test.dart` wrote
/// this by hand, which is how they became the first tests in the suite to see
/// a real width; both now go through here instead, so there is one place that
/// decides what a viewport is and one place to get it wrong.
/// `pump_app_test.dart` is what keeps it honest.
void _setViewport(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}

/// Mounts [child] under the app's real shell: translations, the preferences
/// cubit and the light theme.
///
/// [preferences] seeds the cubit through `load`, so the page sees exactly the
/// document a test names. [engine] defaults to the real `TzTimeZoneEngine`;
/// pass a stub only for answers real tzdata cannot be made to give, such as
/// which zone the device reports. [surfaceSize] replaces the default 800x600
/// viewport, for a page whose lazy list is taller than it or whose layout
/// depends on how wide the window is.
///
/// **[surfaceSize] is the whole viewport, `MediaQuery` included.** It is
/// applied through [_setViewport], for the reason spelled out there.
Future<PumpedApp> pumpApp(
  WidgetTester tester,
  Widget child, {
  PreferencesEntity? preferences,
  TimeZoneEngine? engine,
  DateTime? nowUtc,
  Size? surfaceSize,
  AuthState? authState,
}) async {
  final app = await _install(
    tester,
    preferences: preferences,
    engine: engine,
    nowUtc: nowUtc,
    surfaceSize: surfaceSize,
    authState: authState,
  );
  await tester.pumpWidget(
    _shell(app, MaterialApp(theme: AppTheme.light(), home: child)),
  );
  return app;
}

/// [pumpApp] for a page that navigates.
///
/// `context.push` resolves its router off the element tree, so a page that
/// pushes has to be mounted *through* a `GoRouter` rather than dropped into a
/// bare `home:`. Tests build a throwaway router with a marker destination
/// instead of reusing `AppRouter.router`, which is a `static final` and would
/// carry one test's navigation stack into the next.
Future<PumpedApp> pumpAppRouter(
  WidgetTester tester,
  GoRouter router, {
  PreferencesEntity? preferences,
  TimeZoneEngine? engine,
  DateTime? nowUtc,
  Size? surfaceSize,
  AuthState? authState,
}) async {
  final app = await _install(
    tester,
    preferences: preferences,
    engine: engine,
    nowUtc: nowUtc,
    surfaceSize: surfaceSize,
    authState: authState,
  );
  await tester.pumpWidget(
    _shell(
      app,
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  return app;
}

/// `TranslationProvider` above everything, so the top-level `t` resolves the
/// same way it does under `runApp`, and `BlocProvider` above `MaterialApp`, so
/// a pushed route and a modal sheet read the same cubit the page does.
/// The providers `TimeBuddyApp` puts above every route, and only those.
///
/// `AuthBloc` is here because it is there (`app_widget.dart`): a page that
/// mentions the session — settings' Account row, the profile page — reads it
/// off the tree, and a harness that only provided preferences would make those
/// pages untestable while the app itself works.
Widget _shell(PumpedApp app, Widget child) => TranslationProvider(
  child: MultiBlocProvider(
    providers: [
      BlocProvider<PreferencesCubit>.value(value: app.cubit),
      BlocProvider<AuthBloc>.value(value: app.authBloc),
    ],
    child: child,
  ),
);

Future<PumpedApp> _install(
  WidgetTester tester, {
  required PreferencesEntity? preferences,
  required TimeZoneEngine? engine,
  required DateTime? nowUtc,
  required Size? surfaceSize,
  required AuthState? authState,
}) async {
  registerCommonFallbacks();

  // slang and intl are both process-wide, so pin them rather than inherit
  // whatever ran first: `t` must resolve to the English bundle, and
  // `formatClock`'s am/pm marker must resolve at all, which it only does for
  // a locale whose date symbols are loaded (`en_US` is the only one there is
  // until `initializeDateFormatting` runs).
  LocaleSettings.setLocaleSync(AppLocale.en);
  Intl.defaultLocale = 'en_US';
  addTearDown(() => Intl.defaultLocale = null);

  // AppTypography asks Google Fonts for Poppins and Inter. A test has no
  // network and the app bundles no copy, so this turns a doomed HTTP round
  // trip into an immediate fallback to the default font.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Answered rather than left hanging, for the reason [_deviceZoneChannel]
  // spells out. `UTC` and not a real zone: the device zone is only a *fallback*
  // for a first-run board, so a page test that has an opinion about the home
  // zone states it in the board it passes, and one that has none should not
  // silently inherit a city from the harness. A test that is about what the
  // platform reports registers its own handler, the way
  // `timezone_engine_test.dart` does.
  _stubDeviceZone((_) async => utcZoneId);
  addTearDown(() => _stubDeviceZone(null));

  if (surfaceSize != null) {
    _setViewport(tester, surfaceSize);
  }

  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);

  final clock = FakeClock(nowUtc ?? harnessNowUtc);

  // Paused immediately, and deliberately. The constructor starts a Timer, and
  // flutter_test fails any test whose body returns with one still pending —
  // that check runs before tear-downs, so disposing later would be too late.
  // Pausing cancels the timer without closing the stream, so every ClockText
  // still renders from its `initialData`, which is this clock's pinned
  // instant rather than a tick landing at an unpredictable point in the test.
  final ticker = TickerService(clock: clock)..pause();
  addTearDown(ticker.dispose);

  final repository = MockPreferencesRepository();
  final document = preferences ?? aPreferences();
  when(
    () => repository.load(deviceLocale: any(named: 'deviceLocale')),
  ).thenAnswer((_) async => Right<Failure, PreferencesEntity>(document));
  when(
    () => repository.save(any()),
  ).thenAnswer((_) async => Right<Failure, PreferencesEntity>(document));

  final cubit = PreferencesCubit(repository: repository, clock: clock);
  addTearDown(cubit.close);
  // Seeded through `load` rather than by emitting directly, so the page is
  // handed the state the real startup path produces.
  await cubit.load(deviceLocale: const Locale('en'));

  final resolvedEngine = engine ?? TzTimeZoneEngine();

  // Signed out and quiet unless a test says otherwise, which is the state
  // every page has to render correctly anyway now that sign-in is optional
  // (docs/specs/guest_mode.md).
  final authBloc = MockAuthBloc();
  whenListen(
    authBloc,
    const Stream<AuthState>.empty(),
    initialState: authState ?? const Unauthenticated(),
  );
  addTearDown(authBloc.close);

  // The real `GuestSession` over a mocked store: it is a plain notifier with
  // no logic worth faking, and `LocalStore` is the boundary (CLAUDE.md). Not a
  // guest by default, so a test that wants one calls `enter()`.
  final guestStore = MockLocalStore();
  when(() => guestStore.readRaw(any())).thenAnswer((_) async => null);
  when(() => guestStore.writeRaw(any(), any())).thenAnswer((_) async {});
  when(() => guestStore.remove(any())).thenAnswer((_) async {});
  final guestSession = GuestSession(localStore: guestStore);
  addTearDown(guestSession.dispose);

  GetIt.I
    ..registerSingleton<Clock>(clock)
    ..registerSingleton<TickerService>(ticker)
    ..registerSingleton<TimeZoneEngine>(resolvedEngine)
    ..registerSingleton<PreferencesCubit>(cubit)
    ..registerSingleton<AuthBloc>(authBloc)
    ..registerSingleton<GuestSession>(guestSession);

  return (
    cubit: cubit,
    repository: repository,
    clock: clock,
    ticker: ticker,
    engine: resolvedEngine,
    authBloc: authBloc,
    guestSession: guestSession,
  );
}

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
/// ```dart
/// final app = await pumpApp(tester, const SettingsPage());
/// await tester.tap(find.text(t.settings.themeLight));
/// await tester.pumpAndSettle();
/// final state = app.cubit.state as PreferencesReady;
/// expect(state.preferences.themeMode, ThemeMode.light);
/// ```
library;

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
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
});

/// The instant every pumped page reads as "now" unless a test pins its own.
///
/// Mid-June, mid-month and off the hour on purpose: it sits far from any DST
/// transition in either hemisphere, so a page test cannot be broken by one it
/// never meant to exercise, and a widget that renders a hardcoded `12:00`
/// cannot pass by accident.
final DateTime harnessNowUtc = utcDate(2024, 6, 15, 12, 30);

/// Mounts [child] under the app's real shell: translations, the preferences
/// cubit and the light theme.
///
/// [preferences] seeds the cubit through `load`, so the page sees exactly the
/// document a test names. [engine] defaults to the real `TzTimeZoneEngine`;
/// pass a stub only for answers real tzdata cannot be made to give, such as
/// which zone the device reports. [surfaceSize] widens the default 800x600
/// viewport for a page whose lazy list is taller than it.
Future<PumpedApp> pumpApp(
  WidgetTester tester,
  Widget child, {
  PreferencesEntity? preferences,
  TimeZoneEngine? engine,
  DateTime? nowUtc,
  Size? surfaceSize,
}) async {
  final app = await _install(
    tester,
    preferences: preferences,
    engine: engine,
    nowUtc: nowUtc,
    surfaceSize: surfaceSize,
  );
  await tester.pumpWidget(
    _shell(app.cubit, MaterialApp(theme: AppTheme.light(), home: child)),
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
}) async {
  final app = await _install(
    tester,
    preferences: preferences,
    engine: engine,
    nowUtc: nowUtc,
    surfaceSize: surfaceSize,
  );
  await tester.pumpWidget(
    _shell(
      app.cubit,
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  return app;
}

/// `TranslationProvider` above everything, so the top-level `t` resolves the
/// same way it does under `runApp`, and `BlocProvider` above `MaterialApp`, so
/// a pushed route and a modal sheet read the same cubit the page does.
Widget _shell(PreferencesCubit cubit, Widget app) => TranslationProvider(
  child: BlocProvider<PreferencesCubit>.value(value: cubit, child: app),
);

Future<PumpedApp> _install(
  WidgetTester tester, {
  required PreferencesEntity? preferences,
  required TimeZoneEngine? engine,
  required DateTime? nowUtc,
  required Size? surfaceSize,
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

  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

  GetIt.I
    ..registerSingleton<Clock>(clock)
    ..registerSingleton<TickerService>(ticker)
    ..registerSingleton<TimeZoneEngine>(resolvedEngine)
    ..registerSingleton<PreferencesCubit>(cubit);

  return (
    cubit: cubit,
    repository: repository,
    clock: clock,
    ticker: ticker,
    engine: resolvedEngine,
  );
}

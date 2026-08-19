import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/widgets/clock_text.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/home/presentation/pages/home_page.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';
import '../../../../harness/pump_app.dart';

/// The zone the page is told the device sits in.
///
/// Kolkata rather than a whole-hour zone on purpose: `+05:30` is the offset a
/// clock built on `instant.hour + offsetHours` gets visibly wrong, and it is
/// also the label a hand-rolled `'${d.inHours}h'` drops the minutes from
/// (CLAUDE.md, Time rule 6).
const String _deviceZoneId = 'Asia/Kolkata';

/// [harnessNowUtc] (12:30 UTC) as a person in [_deviceZoneId] reads it.
const String _deviceWallClock = '18:00';

/// The same instant read from UTC.
///
/// Asserted *absent* on the device-zone page: it is what a clock that
/// formatted the raw instant would show, and `12:30` looks every bit as much
/// like a working clock as `18:00` does.
const String _utcWallClock = '12:30';

/// Text of the throwaway page the settings route resolves to.
const String _settingsMarker = 'settings-route-reached';

void main() {
  setUpAll(() {
    initTestTimeZones();
    registerCommonFallbacks();
  });

  // A TimeZoneEngine that reports `zone` as the device's, and hands every
  // other question to real tzdata.
  //
  // Only the platform call is stubbed. There is no platform to ask in a test
  // and the fallback shape cannot be produced on demand, so that one answer
  // has to be dictated; every conversion the page renders stays real, so the
  // digits below are checked against actual IANA rules rather than against the
  // test's own arithmetic (CLAUDE.md, Harness Engineering).
  MockTimeZoneEngine engineReporting(DeviceZone zone) {
    final real = TzTimeZoneEngine();
    final engine = MockTimeZoneEngine();
    when(engine.deviceZone).thenAnswer((_) async => zone);
    when(
      () => engine.wallTimeAt(
        zoneId: any(named: 'zoneId'),
        instant: any(named: 'instant'),
      ),
    ).thenAnswer(
      (invocation) => real.wallTimeAt(
        zoneId: invocation.namedArguments[#zoneId] as String,
        instant: invocation.namedArguments[#instant] as DateTime,
      ),
    );
    when(
      () => engine.stateAt(
        zoneId: any(named: 'zoneId'),
        instant: any(named: 'instant'),
      ),
    ).thenAnswer(
      (invocation) => real.stateAt(
        zoneId: invocation.namedArguments[#zoneId] as String,
        instant: invocation.namedArguments[#instant] as DateTime,
      ),
    );
    return engine;
  }

  Future<PumpedApp> pumpHome(WidgetTester tester, DeviceZone zone) =>
      pumpApp(tester, const HomePage(), engine: engineReporting(zone));

  const kolkata = DeviceZone(zoneId: _deviceZoneId, isFallback: false);
  const fallback = DeviceZone(zoneId: utcZoneId, isFallback: true);

  testWidgets('renders the device clock, zone id and offset', (tester) async {
    await pumpHome(tester, kolkata);
    await tester.pump();

    expect(find.text(t.home.title), findsOneWidget);
    expect(find.text(t.home.deviceClockLabel.toUpperCase()), findsOneWidget);
    expect(find.text(t.home.milestoneNotice), findsOneWidget);

    // The whole point of the page: 12:30 UTC is 18:00 in Kolkata, so digits
    // alone prove the ticker instant went through the engine on the way out.
    expect(find.text(_deviceWallClock), findsOneWidget);
    expect(find.text(_utcWallClock), findsNothing);

    // The raw IANA id until the city catalog lands in M2, and the offset for
    // this instant rather than a whole-hour approximation of it.
    expect(find.text(_deviceZoneId), findsOneWidget);
    expect(find.text('+05:30'), findsOneWidget);

    expect(find.byType(LoadingShimmer), findsNothing);
  });

  testWidgets('holds the placeholder until the device zone resolves', (
    tester,
  ) async {
    // `deviceZone()` crosses a platform channel, so the first frame is always
    // this one. It must be shaped like the block it replaces, not blank
    // (design_system, State screens).
    await pumpHome(tester, kolkata);

    expect(find.byType(LoadingShimmer), findsOneWidget);
    expect(find.byType(ClockText), findsNothing);

    await tester.pump();

    expect(find.byType(LoadingShimmer), findsNothing);
    expect(find.byType(ClockText), findsOneWidget);
  });

  testWidgets('still renders when the device zone falls back to UTC', (
    tester,
  ) async {
    // Rule 11 of the engine spec: a refused or unknown platform zone lands on
    // UTC. The page must not go blank, and it must not pass the fallback off
    // as a detected zone either: an unlabelled UTC clock under "your device"
    // is indistinguishable from a correct one, which is the silent failure
    // CLAUDE.md Time rule 8 singles out.
    await pumpHome(tester, fallback);
    await tester.pump();

    expect(find.byType(ClockText), findsOneWidget);
    expect(find.text(_utcWallClock), findsOneWidget);
    expect(find.text(utcZoneId), findsOneWidget);
    expect(find.text('+00:00'), findsOneWidget);
    expect(find.text(t.home.milestoneNotice), findsOneWidget);
    expect(find.byType(LoadingShimmer), findsNothing);
    expect(find.text(t.home.deviceZoneUnknownTitle), findsOneWidget);
    expect(find.text(t.home.deviceZoneUnknownBody), findsOneWidget);
  });

  testWidgets('says nothing about detection when the zone WAS detected', (
    tester,
  ) async {
    // The other half of the pair: a warning that shows on the happy path is
    // noise, and noise is how a real warning stops being read.
    await pumpHome(tester, kolkata);
    await tester.pump();

    expect(find.text(t.home.deviceZoneUnknownTitle), findsNothing);
    expect(find.text(t.home.deviceZoneUnknownBody), findsNothing);
  });

  testWidgets('the settings action pushes the settings route', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) =>
              const Scaffold(body: Text(_settingsMarker)),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpAppRouter(tester, router, engine: engineReporting(kolkata));
    await tester.pump();

    expect(find.byTooltip(t.home.settingsAction), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text(_settingsMarker), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });
}

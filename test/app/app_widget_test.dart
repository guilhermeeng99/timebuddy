import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/app_widget.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../harness/factories/preferences_factory.dart';
import '../harness/factories/user_factory.dart';
import '../harness/fake_clock.dart';
import '../harness/helpers.dart';
import '../harness/mocks.dart';

/// The sync boundary. Mocked: these tests are about *who calls what on a
/// resume*, and a real service would answer that two network hops away.
class _MockSyncService extends Mock implements SyncService {}

/// The startup gate, held in `StartupLoading` throughout.
///
/// That is what keeps `AppRouter`'s redirect pinned to the splash: this file
/// is about the app widget's three side effects, not about the router's four
/// rules, which `app_router_gate_test.dart` owns.
class _MockStartupCubit extends MockCubit<StartupState>
    implements StartupCubit {}

/// `flutter_timezone`'s channel, the one platform call the app makes.
///
/// Under `flutter_test` nothing ever answers it, and an unanswered platform
/// call neither throws nor times out — its future simply never completes. The
/// splash asks it for the device zone, so an unstubbed channel leaves the
/// first route waiting forever.
const MethodChannel _deviceZoneChannel = MethodChannel('flutter_timezone');

/// Answers [_deviceZoneChannel] with [handler]; `null` unregisters it again.
void _stubDeviceZone(Future<Object?> Function(MethodCall call)? handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_deviceZoneChannel, handler);

void main() {
  setUpAll(() {
    initTestTimeZones();
    registerCommonFallbacks();
  });

  // Built once for the whole file and re-registered by every mount.
  //
  // `AppRouter.router` is a `static final` whose refresh listenable resolves
  // `AuthBloc` and `GuestSession` out of `GetIt` the first time anything
  // touches it — and holds those two references for the rest of the process.
  // Fresh instances per test would leave that listenable pointing at a closed
  // bloc from whichever test happened to run first.
  final authBloc = MockAuthBloc();
  final startupCubit = _MockStartupCubit();
  final guestSession = GuestSession(localStore: MockLocalStore());

  late FakeClock clock;
  late RecordingTickerService ticker;
  late PreferencesCubit preferencesCubit;
  late _MockSyncService syncService;
  late Completer<Either<Failure, PreferencesEntity>> preferencesLoad;

  /// Stands the app's dependencies up **inside the test body**, and mounts it.
  ///
  /// Everything is built here rather than in a `setUp` on purpose: a
  /// `Completer` created outside `testWidgets` belongs to the root zone, so
  /// its continuations are scheduled somewhere `tester.pump()` cannot reach.
  /// The symptom is a preferences load that completes and never arrives — a
  /// state change the widget under test simply never sees, and no error
  /// anywhere.
  ///
  /// The preferences future is deliberately left open: `TimeBuddyApp` starts
  /// the load in `initState`, so holding it is what lets a test observe the
  /// widget before and after the document resolves.
  Future<void> pumpBootstrapping(
    WidgetTester tester, {
    AuthState session = const Unauthenticated(),
  }) async {
    clock = FakeClock(utcDate(2024, 6, 15, 12, 30));

    // Paused before anything can subscribe: the constructor starts a `Timer`,
    // and `flutter_test` fails a test whose body returns with one pending. The
    // counters are zeroed after, so every number a test reads is one the
    // widget put there rather than one this setup did.
    ticker = RecordingTickerService(clock: clock)
      ..pause()
      ..pauses = 0
      ..resumes = 0;

    preferencesLoad = Completer<Either<Failure, PreferencesEntity>>();
    final preferencesRepository = MockPreferencesRepository();
    when(
      () =>
          preferencesRepository.load(deviceLocale: any(named: 'deviceLocale')),
    ).thenAnswer((_) => preferencesLoad.future);
    when(() => preferencesRepository.save(any())).thenAnswer(
      (invocation) async => Right<Failure, PreferencesEntity>(
        invocation.positionalArguments.first as PreferencesEntity,
      ),
    );
    preferencesCubit = PreferencesCubit(
      repository: preferencesRepository,
      clock: clock,
    );

    syncService = _MockSyncService();
    when(
      () => syncService.flushDirty(userId: any(named: 'userId')),
    ).thenAnswer((_) async {});

    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: session,
    );
    whenListen(
      startupCubit,
      const Stream<StartupState>.empty(),
      initialState: const StartupLoading(),
    );
    when(startupCubit.initialize).thenAnswer((_) async {});
    // The three collaborators above outlive the test, so the calls recorded
    // against them do too. Cleared here rather than after `whenListen`, which
    // re-stubs but does not forget: without this, "asked exactly once" would
    // read the running total for the whole file.
    clearInteractions(authBloc);

    LocaleSettings.setLocaleSync(AppLocale.en);
    // No network in a test and no bundled copy of Poppins or Inter, so this
    // turns a doomed HTTP round trip into an immediate fallback.
    GoogleFonts.config.allowRuntimeFetching = false;
    _stubDeviceZone((_) async => utcZoneId);
    addTearDown(() => _stubDeviceZone(null));

    await GetIt.I.reset();
    GetIt.I
      ..registerSingleton<Clock>(clock)
      ..registerSingleton<TickerService>(ticker)
      ..registerSingleton<TimeZoneEngine>(TzTimeZoneEngine())
      ..registerSingleton<PreferencesCubit>(preferencesCubit)
      ..registerSingleton<AuthBloc>(authBloc)
      ..registerSingleton<StartupCubit>(startupCubit)
      ..registerSingleton<GuestSession>(guestSession)
      ..registerSingleton<SyncService>(syncService);
    addTearDown(GetIt.I.reset);
    addTearDown(preferencesCubit.close);
    addTearDown(ticker.dispose);

    await tester.pumpWidget(TranslationProvider(child: const TimeBuddyApp()));
    await tester.pump();
  }

  /// Resolves the preferences document, which promotes the widget out of its
  /// bootstrap frame and runs the side effects.
  Future<void> resolvePreferences(
    WidgetTester tester, {
    required bool showSeconds,
  }) async {
    preferencesLoad.complete(
      Right<Failure, PreferencesEntity>(aPreferences(showSeconds: showSeconds)),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Stops a ticker a test left running.
  ///
  /// `resume()` restarts the periodic timer, and `flutter_test` asserts on a
  /// pending timer *before* tear-downs run — so this has to be the last line
  /// of the test body rather than an `addTearDown`.
  void quietTicker() => ticker.pause();

  group('the app-wide lifecycle hook', () {
    testWidgets('stops the ticker when the app is backgrounded', (
      tester,
    ) async {
      await pumpBootstrapping(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // CLAUDE.md, Performance: a backgrounded app that keeps ticking burns a
      // wakeup per second to repaint pixels nobody can see. This widget is the
      // app's only `WidgetsBindingObserver`, so nothing else can make the call.
      expect(ticker.pauses, 1);
      expect(ticker.resumes, 0);
    });

    testWidgets('restarts it on the way back', (tester) async {
      await pumpBootstrapping(tester);

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // `resume` re-emits immediately, so a phone unlocked an hour later does
      // not show the minute it was locked at until the next tick lands.
      expect(ticker.resumes, 1);
      quietTicker();
    });

    testWidgets('ignores the transient states on the way there', (
      tester,
    ) async {
      await pumpBootstrapping(tester);

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();

      // inactive / hidden / detached are stops on the way to paused or
      // resumed. Reacting to them would cancel and restart the timer every
      // time the notification shade is pulled down.
      expect(ticker.pauses, 0);
      expect(ticker.resumes, 0);
    });

    testWidgets('stops observing once it is disposed', (tester) async {
      await pumpBootstrapping(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // The observer is registered against a process-wide binding, so one that
      // is never removed outlives its widget and keeps pausing a ticker whose
      // app is gone.
      expect(ticker.pauses, 0);
    });
  });

  group('the dirty-flag retry on resume', () {
    testWidgets('flushes the pending writes of the signed-in account', (
      tester,
    ) async {
      await pumpBootstrapping(tester, session: Authenticated(aUser()));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // docs/specs/sync.md rule 4: a resume is the moment most likely to have
      // a working radio, and `flushDirty` costs zero reads when nothing is
      // dirty — so it runs on every resume, for that account and no other.
      verify(() => syncService.flushDirty(userId: aUser().id)).called(1);
      quietTicker();
    });

    testWidgets('asks for nothing while nobody is signed in', (tester) async {
      await pumpBootstrapping(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // A guest owes the server nothing, because they have no documents on it.
      // A flush here would be a call with no account to make it for.
      verifyNever(() => syncService.flushDirty(userId: any(named: 'userId')));
      quietTicker();
    });

    testWidgets('does not flush on the way to the background', (tester) async {
      await pumpBootstrapping(tester, session: Authenticated(aUser()));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // Pausing is the moment the radio is *least* likely to survive a write,
      // and the flag it would leave behind is the same flag the next resume
      // reads anyway.
      verifyNever(() => syncService.flushDirty(userId: any(named: 'userId')));
    });
  });

  group('the ticker rate follows the seconds preference', () {
    testWidgets('seconds off asks for the minute rate', (tester) async {
      await pumpBootstrapping(tester);
      // Nothing is applied before the document resolves: the bootstrap frame
      // has no preferences to apply.
      expect(ticker.secondsRequests, isEmpty);

      await resolvePreferences(tester, showSeconds: false);

      // docs/specs/preferences.md rule 10. `ticker_service_test.dart` proves
      // the ticker obeys this call; what is pinned here is that somebody makes
      // it, which is the half nothing covered.
      expect(ticker.secondsRequests, [false]);
      expect(ticker.needsSeconds, isFalse);
      quietTicker();
    });

    testWidgets('seconds on asks for 1 Hz', (tester) async {
      await pumpBootstrapping(tester);

      await resolvePreferences(tester, showSeconds: true);

      expect(ticker.secondsRequests, [true]);
      expect(ticker.needsSeconds, isTrue);
      quietTicker();
    });

    testWidgets('a later change to the preference is applied too', (
      tester,
    ) async {
      await pumpBootstrapping(tester);
      await resolvePreferences(tester, showSeconds: false);

      await preferencesCubit.setShowSeconds(value: true);
      await tester.pump();

      // Turning seconds on is the only thing that puts the ticker at 1 Hz, and
      // it is a live preference: the switch in settings has to reach the
      // heartbeat without a restart.
      expect(ticker.secondsRequests, [false, true]);
      expect(ticker.needsSeconds, isTrue);
      quietTicker();
    });
  });

  group('the bootstrap frame', () {
    testWidgets('shows a bare spinner until preferences resolve', (
      tester,
    ) async {
      await pumpBootstrapping(tester);

      // Not the splash. `StartupPage` runs *inside* the router, in the user's
      // own colors; this frame cannot use the selected palette, because that
      // is exactly what it is waiting for.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('starts the session check exactly once', (tester) async {
      await pumpBootstrapping(tester);
      // A rebuild must not repeat it: `initState` is the one place in the app
      // that runs once per process and sits above the router, which is why the
      // check is asked for here rather than by `StartupCubit`.
      await tester.pump();

      verify(() => authBloc.add(const AuthCheckRequested())).called(1);
    });
  });
}

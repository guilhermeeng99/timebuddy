import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/world_clock/domain/usecases/build_world_clock_usecase.dart';
import 'package:timebuddy/features/world_clock/presentation/cubit/world_clock_cubit.dart';

import '../../../../harness/factories/board_factory.dart';
import '../../../../harness/factories/preferences_factory.dart';
import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

/// Mid-June and off the hour, far from any DST transition in either
/// hemisphere: a test about the lifecycle must not be able to fail because of
/// a boundary it never meant to cross.
final DateTime _nowInstant = utcDate(2024, 6, 15, 12, 30, 20);

void main() {
  setUpAll(() {
    // The real engine and real tzdata: every field this cubit emits is a
    // conversion, and a mocked engine could only confirm the assumptions the
    // test already made (CLAUDE.md, Testing Rules).
    initTestTimeZones();
    registerCommonFallbacks();
  });

  late MockBoardCubit boardCubit;
  late PreferencesCubit preferencesCubit;
  late MockPreferencesRepository preferencesRepository;
  late RecordingTickerService ticker;
  late FakeClock clock;

  // Home is left at the factory default, so the Sao Paulo row below is the
  // hero and Tokyo is the one tile measured against it.
  final board = aBoard(
    locations: [
      aSavedLocation(),
      aSavedLocation(
        id: 'row-tokyo',
        zoneId: 'Asia/Tokyo',
        label: 'Tokyo',
        countryCode: 'JP',
        sortIndex: 1,
      ),
    ],
  );
  final loadedBoard = BoardLoaded(board: board);

  setUp(() async {
    clock = FakeClock(_nowInstant);

    boardCubit = MockBoardCubit();
    whenListen(
      boardCubit,
      const Stream<BoardState>.empty(),
      initialState: loadedBoard,
    );

    // The real preferences cubit over a mocked repository: the repository is
    // the boundary (CLAUDE.md), and this cubit reads the *working window* out
    // of whatever state the real one publishes.
    preferencesRepository = MockPreferencesRepository();
    when(
      () =>
          preferencesRepository.load(deviceLocale: any(named: 'deviceLocale')),
    ).thenAnswer(
      (_) async => Right<Failure, PreferencesEntity>(aPreferences()),
    );
    when(() => preferencesRepository.save(any())).thenAnswer(
      (invocation) async => Right<Failure, PreferencesEntity>(
        invocation.positionalArguments.first as PreferencesEntity,
      ),
    );
    preferencesCubit = PreferencesCubit(
      repository: preferencesRepository,
      clock: clock,
    );
    await preferencesCubit.load(deviceLocale: const Locale('en'));

    // A real ticker, paused: its constructor starts a `Timer`, and a test that
    // let it run would depend on how long the test itself took. The counters
    // are zeroed afterwards, so every number a test reads is one the cubit
    // put there rather than one this setup did.
    ticker = RecordingTickerService(clock: clock)
      ..pause()
      ..pauses = 0
      ..resumes = 0;
  });

  /// Lets a `Stream.multi` subscription actually register.
  ///
  /// `RecordingTickerService` counts through `Stream.multi`, whose `onListen`
  /// runs in a microtask rather than inside `listen()`, so a count read in the
  /// same synchronous run as `start()` is always one short.
  Future<void> settleSubscriptions() => Future<void>.delayed(Duration.zero);

  tearDown(() async {
    await preferencesCubit.close();
    await ticker.dispose();
  });

  WorldClockCubit buildCubit() => WorldClockCubit(
    boardCubit: boardCubit,
    preferencesCubit: preferencesCubit,
    buildWorldClock: BuildWorldClockUseCase(engine: TzTimeZoneEngine()),
    engine: TzTimeZoneEngine(),
    clock: clock,
    ticker: ticker,
  );

  /// The instant the model on screen was built for.
  DateTime nowInstantOf(WorldClockCubit cubit) =>
      (cubit.state as WorldClockReady).model.nowInstant;

  group('start', () {
    blocTest<WorldClockCubit, WorldClockState>(
      'builds the first model from the board already in hand',
      build: buildCubit,
      act: (cubit) => cubit.start(),
      verify: (cubit) {
        // Seeded from `BoardCubit.state` and not from its stream: the shell
        // loads the board before the page mounts, so a cubit that only
        // listened would sit on `WorldClockLoading` forever on a revisit.
        expect(cubit.state, isA<WorldClockReady>());
        expect(nowInstantOf(cubit), _nowInstant);
      },
    );

    // A plain test rather than a `blocTest`: `blocTest` closes the cubit
    // before `verify` runs, and a closed cubit has already let its
    // subscription go, so the count would read zero however this behaved.
    test('subscribes to the one shared ticker', () async {
      final cubit = buildCubit()..start();
      addTearDown(cubit.close);
      await settleSubscriptions();

      // Rule 3, and the reason `TickerService` is a singleton: a cubit that
      // grew its own `Timer.periodic` would leave this at zero while still
      // updating, and a 20-city board would then be 20 timers.
      expect(ticker.liveSubscriptions, 1);
    });
  });

  group('onAppPaused', () {
    blocTest<WorldClockCubit, WorldClockState>(
      'stops the shared ticker',
      build: buildCubit,
      act: (cubit) => cubit
        ..start()
        ..onAppPaused(),
      verify: (_) {
        // CLAUDE.md, Performance: a backgrounded app must not wake the CPU
        // once a second to repaint pixels nobody can see.
        expect(ticker.pauses, 1);
      },
    );

    blocTest<WorldClockCubit, WorldClockState>(
      'emits nothing of its own',
      build: buildCubit,
      act: (cubit) {
        cubit.start();
        return cubit.onAppPaused();
      },
      // Exactly one state, the model `start` built. Rebuilding on the way to
      // the background would be a full board recomputed for a screen that is
      // already off.
      expect: () => [isA<WorldClockReady>()],
    );
  });

  group('onAppResumed', () {
    blocTest<WorldClockCubit, WorldClockState>(
      'restarts the ticker',
      build: buildCubit,
      act: (cubit) {
        cubit
          ..start()
          ..onAppPaused();
        return cubit.onAppResumed();
      },
      verify: (_) {
        expect(ticker.pauses, 1);
        expect(ticker.resumes, 1);
      },
    );

    blocTest<WorldClockCubit, WorldClockState>(
      'catches the clock up to the instant the phone was unlocked at',
      build: buildCubit,
      act: (cubit) {
        cubit
          ..start()
          ..onAppPaused();
        // An hour and a half in a pocket, which crosses both a minute and an
        // hour boundary: every date label, day delta and band on the page is
        // stale by the time the screen comes back.
        clock.advance(const Duration(hours: 1, minutes: 30));
        return cubit.onAppResumed();
      },
      verify: (cubit) {
        // Rule 10: a phone unlocked an hour after it was locked must not keep
        // showing the minute it was locked at until the next tick lands. The
        // ticker's own immediate emission covers the digits; this covers
        // everything around them.
        expect(
          nowInstantOf(cubit),
          _nowInstant.add(const Duration(hours: 1, minutes: 30)),
        );
      },
    );

    blocTest<WorldClockCubit, WorldClockState>(
      'rebuilds even when the resume lands inside the same minute',
      build: buildCubit,
      act: (cubit) {
        cubit
          ..start()
          ..onAppPaused();
        // A glance at the screen, not a night in a pocket. This is the case
        // that separates the explicit `tick` from the ticker's own immediate
        // emission: `_onTick` drops anything inside the minute already on
        // screen, so without the explicit call a short resume would leave the
        // model built for the instant the app went away at.
        clock.advance(const Duration(seconds: 20));
        return cubit.onAppResumed();
      },
      verify: (cubit) {
        expect(
          nowInstantOf(cubit),
          _nowInstant.add(const Duration(seconds: 20)),
        );
      },
    );

    blocTest<WorldClockCubit, WorldClockState>(
      'is safe to call without a preceding pause',
      build: buildCubit,
      act: (cubit) {
        cubit.start();
        clock.advance(const Duration(minutes: 5));
        return cubit.onAppResumed();
      },
      verify: (cubit) {
        expect(
          nowInstantOf(cubit),
          _nowInstant.add(const Duration(minutes: 5)),
        );
        expect(ticker.resumes, 1);
      },
    );
  });

  group('tick', () {
    blocTest<WorldClockCubit, WorldClockState>(
      'rebuilds the board for the instant it was handed',
      build: buildCubit,
      act: (cubit) {
        cubit.start();
        return cubit.tick(_nowInstant.add(const Duration(minutes: 3)));
      },
      verify: (cubit) {
        expect(
          nowInstantOf(cubit),
          _nowInstant.add(const Duration(minutes: 3)),
        );
      },
    );

    blocTest<WorldClockCubit, WorldClockState>(
      'a tick inside the minute already on screen is dropped',
      build: buildCubit,
      act: (cubit) async {
        cubit.start();
        // With `showSeconds` on the shared ticker runs at 1 Hz, and every
        // field this model carries — the date, the day delta, the offset, the
        // band, the DST flag — is constant across a minute. Re-emitting a
        // whole board 60 times a minute is the rebuild storm the shared ticker
        // exists to prevent.
        clock.advance(const Duration(seconds: 20));
        ticker.resume();
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => [isA<WorldClockReady>()],
    );

    blocTest<WorldClockCubit, WorldClockState>(
      'a tick that begins a new minute is not',
      build: buildCubit,
      act: (cubit) async {
        cubit.start();
        // 12:30:20 -> 12:31:00, one second past the boundary rather than a
        // round minute, so the filter has to be comparing the minute a tick
        // belongs to and not the seconds field.
        clock.advance(const Duration(seconds: 41));
        ticker.resume();
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => [isA<WorldClockReady>(), isA<WorldClockReady>()],
    );
  });

  group('the board and the preferences it reads', () {
    blocTest<WorldClockCubit, WorldClockState>(
      'a board that fails to load is an error, not an empty page',
      build: buildCubit,
      seed: () => const WorldClockLoading(),
      setUp: () {
        whenListen(
          boardCubit,
          const Stream<BoardState>.empty(),
          initialState: const BoardError(failure: StorageFailure()),
        );
      },
      act: (cubit) => cubit.start(),
      expect: () => [const WorldClockError(failure: StorageFailure())],
    );

    blocTest<WorldClockCubit, WorldClockState>(
      'a preference change repaints the page',
      build: buildCubit,
      act: (cubit) async {
        cubit.start();
        // The working window decides every band (rule 7), so a change to it
        // has to reach a page that is already built.
        await preferencesCubit.setWorkingHours(
          const WorkingHours(startHour: 22, endHour: 6),
        );
      },
      expect: () => [isA<WorldClockReady>(), isA<WorldClockReady>()],
      verify: (cubit) {
        final home = (cubit.state as WorldClockReady).model.home;
        // Midday in Sao Paulo is outside a 22:00-06:00 night shift, so the
        // band it lands in is not the working one.
        expect(home.band.name, isNot('working'));
      },
    );
  });

  group('close', () {
    test('releases the ticker subscription', () async {
      final cubit = buildCubit()..start();
      await settleSubscriptions();
      expect(ticker.liveSubscriptions, 1);

      await cubit.close();

      // A leaked subscription keeps calling `emit` on a closed cubit, which
      // surfaces as an unhandled error in a later, unrelated test rather than
      // here — which is exactly why the count is asserted and not the silence.
      expect(ticker.liveSubscriptions, 0);
    });

    test('a tick after close reaches nothing', () async {
      final cubit = buildCubit()..start();
      final lastInstant = nowInstantOf(cubit);

      await cubit.close();
      clock.advance(const Duration(minutes: 10));
      ticker.resume();
      await Future<void>.delayed(Duration.zero);

      // The page was disposed; the shared ticker keeps running for whatever
      // replaced it, and this cubit must simply not be listening any more.
      expect((cubit.state as WorldClockReady).model.nowInstant, lastInstant);
    });

    test('stops following the board too', () async {
      final boardStates = StreamController<BoardState>.broadcast();
      addTearDown(boardStates.close);
      whenListen(
        boardCubit,
        boardStates.stream,
        initialState: loadedBoard,
      );
      final cubit = buildCubit()..start();

      await cubit.close();
      boardStates.add(const BoardError(failure: StorageFailure()));
      await Future<void>.delayed(Duration.zero);

      // Three subscriptions are opened by `start` and all three have to be
      // released; asserting only the ticker would leave two ways to leak.
      expect(cubit.state, isA<WorldClockReady>());
    });
  });
}

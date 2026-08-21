import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';

import '../../../../harness/factories/board_factory.dart';
import '../../../../harness/factories/preferences_factory.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

/// The session, as the cubit sees it: read-only, and never dispatched to.
///
/// `MockBloc` rather than a hand-built fake so `whenListen` can hand the cubit
/// a state stream that has not settled yet, which is the only way to reach the
/// slow path (docs/specs/startup.md rule 5).
class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

/// The 500-row asset, mocked away: this file is about the *order* things are
/// loaded in, not about what the catalog holds.
class _MockCityCatalogRepository extends Mock
    implements CityCatalogRepository {}

/// The first sync. Mocked so "it failed" and "it never answered" are two
/// stubs, which is the only way to reach rules 7 and 8 deterministically.
class _MockSyncService extends Mock implements SyncService {}

const String _userId = 'firebase-uid';

/// The signed-in account every authenticated case resolves to.
final UserEntity _user = UserEntity(
  id: _userId,
  name: 'Ada Lovelace',
  email: 'ada@example.com',
  createdAt: utcDate(2024),
);

/// What a sync that landed hands back. Both documents already agreed, so
/// nothing here depends on which side won.
final SyncOutcome _reconciled = SyncOutcome(
  board: aBoard(),
  preferences: aPreferences(),
  boardWinner: ConflictWinner.none,
  preferencesWinner: ConflictWinner.none,
);

void main() {
  late _MockAuthBloc authBloc;
  late MockTimeZoneEngine engine;
  late _MockCityCatalogRepository catalog;
  late _MockSyncService syncService;
  late MockLocalStore localStore;
  late GuestSession guestSession;

  /// What was reached for, in the order it was reached for.
  ///
  /// The engine and the catalog are started *before* auth is read (rule 2),
  /// and only an ordered record can tell that apart from "all three were
  /// called", which is what a bare `verify` would prove.
  late List<String> reachedFor;

  void authBlocHolds(AuthState state) {
    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: state,
    );
  }

  setUp(() {
    authBloc = _MockAuthBloc();
    engine = MockTimeZoneEngine();
    catalog = _MockCityCatalogRepository();
    syncService = _MockSyncService();
    localStore = MockLocalStore();
    guestSession = GuestSession(localStore: localStore);
    reachedFor = <String>[];

    // Not a guest unless a case says so. Stubbed rather than left to
    // mocktail's null, so `restore()` has something to read on every path.
    when(
      () => localStore.readRaw(StorageKeys.guest),
    ).thenAnswer((_) async => null);

    when(engine.initialize).thenAnswer((_) async {
      reachedFor.add('engine');
    });
    when(catalog.load).thenAnswer((_) async {
      reachedFor.add('catalog');
      return const Right<Failure, List<CityEntity>>([]);
    });
    when(
      () => syncService.sync(
        userId: any(named: 'userId'),
        adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
      ),
    ).thenAnswer(
      (_) async => Right<Failure, SyncOutcome>(_reconciled),
    );

    authBlocHolds(const Unauthenticated());
  });

  StartupCubit buildCubit() => StartupCubit(
    authBloc: authBloc,
    engine: engine,
    catalog: catalog,
    syncService: syncService,
    guestSession: guestSession,
  );

  /// Turns the device into a guest, the way onboarding would.
  ///
  /// The real [GuestSession] over a mocked store rather than a mocked session:
  /// `LocalStore` is the boundary (CLAUDE.md), and the thing under test here
  /// is partly *whether the cubit clears the marker*, which a mock would
  /// happily report either way.
  Future<void> becomeGuest() async {
    when(
      () => localStore.readRaw(StorageKeys.guest),
    ).thenAnswer((_) async => 'true');
    when(() => localStore.remove(StorageKeys.guest)).thenAnswer((_) async {});
    await guestSession.restore();
  }

  /// Every state the cubit emits while [body] runs.
  ///
  /// The cubit is built inside so a case that never calls `initialize()` still
  /// gets a closed cubit, and the collected list is the whole assertion
  /// surface: this feature's side effect is a route decision, which the page
  /// reads off exactly these states.
  Future<List<StartupState>> statesDuring(
    Future<void> Function(StartupCubit cubit) body,
  ) async {
    final cubit = buildCubit();
    final seen = <StartupState>[];
    final subscription = cubit.stream.listen(seen.add);

    await body(cubit);
    await pumpEventQueue();
    await subscription.cancel();
    await cubit.close();
    return seen;
  }

  void expectSyncWasNotRun() {
    verifyNever(
      () => syncService.sync(
        userId: any(named: 'userId'),
        adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
      ),
    );
  }

  test('starts before initialize has attempted anything', () {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    // The one frame between the route building the page and its `initState`
    // sees this, and the cubit never returns to it: a retry re-emits
    // `StartupLoading` directly.
    expect(cubit.state, const StartupInitial());
  });

  group('ordering', () {
    test('starts the engine and the catalog before it reads auth', () async {
      when(() => authBloc.state).thenAnswer((_) {
        reachedFor.add('auth');
        return const Unauthenticated();
      });

      await statesDuring((cubit) => cubit.initialize());

      // Rule 2: tzdata is unconditional and nothing waits on a user for it.
      // An engine started after the auth answer would let an unauthenticated
      // user reach onboarding, which shows a live clock, before there is a
      // database to read one from.
      expect(reachedFor, <String>['engine', 'catalog', 'auth']);
    });

    test('the progress sentinels are 0.0, 0.3 and 0.6, in order', () async {
      authBlocHolds(Authenticated(_user));

      final states = await statesDuring((cubit) => cubit.initialize());

      // Written out rather than read back off `StartupLoading`: the page picks
      // its localized step label by comparing against these three numbers, so
      // a constant that quietly moved would relabel the splash without failing
      // anything (rule 9).
      expect(
        states.whereType<StartupLoading>().map((state) => state.progress),
        <double>[0, 0.3, 0.6],
      );
    });
  });

  group('the fast path', () {
    blocTest<StartupCubit, StartupState>(
      'syncs and lands authenticated when the session already resolved',
      setUp: () {
        authBlocHolds(Authenticated(_user));
      },
      build: buildCubit,
      act: (cubit) => cubit.initialize(),
      expect: () => <StartupState>[
        const StartupLoading(),
        const StartupLoading(progress: StartupLoading.preparedProgress),
        const StartupLoading(progress: StartupLoading.syncingProgress),
        const StartupAuthenticated(userId: _userId, syncFailed: false),
      ],
      verify: (_) {
        verify(
          () => syncService.sync(
            userId: _userId,
            adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
          ),
        ).called(1);
        // Rule 4: a bloc that already holds the answer is not worth a
        // subscription opened to close a moment later.
        verifyNever(() => authBloc.stream);
      },
    );

    blocTest<StartupCubit, StartupState>(
      'sends a signed-out user on without syncing',
      build: buildCubit,
      act: (cubit) => cubit.initialize(),
      expect: () => <StartupState>[
        const StartupLoading(),
        const StartupLoading(progress: StartupLoading.preparedProgress),
        const StartupUnauthenticated(),
      ],
      verify: (_) {
        // Rule 6: there is no account to reconcile against, so the sync is
        // skipped outright rather than run against an empty user id.
        expectSyncWasNotRun();
        verifyNever(() => authBloc.stream);
      },
    );

    blocTest<StartupCubit, StartupState>(
      'reads a failed session check as signed out',
      setUp: () {
        authBlocHolds(const AuthError(AuthFailure()));
      },
      build: buildCubit,
      act: (cubit) => cubit.initialize(),
      // An error screen in front of a sign-in button the user could simply
      // press is a dead end; onboarding is one tap from a retry.
      expect: () => <StartupState>[
        const StartupLoading(),
        const StartupLoading(progress: StartupLoading.preparedProgress),
        const StartupUnauthenticated(),
      ],
      verify: (_) {
        expectSyncWasNotRun();
      },
    );
  });

  group('the slow path', () {
    test('holds at loading until the auth stream settles', () async {
      final auth = StreamController<AuthState>.broadcast();
      addTearDown(auth.close);
      whenListen(authBloc, auth.stream, initialState: const AuthInitial());

      final cubit = buildCubit();
      addTearDown(cubit.close);
      final seen = <StartupState>[];
      final subscription = cubit.stream.listen(seen.add);
      addTearDown(subscription.cancel);

      final running = cubit.initialize();
      await pumpEventQueue();

      // The engine and the catalog are done, and nothing terminal may show
      // while the bloc still says `AuthInitial` (rule 5).
      expect(
        seen.last,
        const StartupLoading(progress: StartupLoading.preparedProgress),
      );

      auth.add(Authenticated(_user));
      await running;
      await pumpEventQueue();

      expect(
        seen.last,
        const StartupAuthenticated(userId: _userId, syncFailed: false),
      );
      verify(() => authBloc.stream).called(1);
    });

    test('a second terminal auth event does not throw', () async {
      final auth = StreamController<AuthState>.broadcast();
      addTearDown(auth.close);
      whenListen(authBloc, auth.stream, initialState: const AuthInitial());

      final cubit = buildCubit();
      addTearDown(cubit.close);
      final seen = <StartupState>[];
      final subscription = cubit.stream.listen(seen.add);
      addTearDown(subscription.cancel);

      final running = cubit.initialize();
      await pumpEventQueue();

      // Back to back, the way a sign-in landing on top of a session check
      // arrives. Cancelling the subscription usually swallows the second, and
      // `_settleAuth` guards the completer for the times it does not: a second
      // `complete()` throws, and it would throw inside a stream callback where
      // nothing is left to catch it.
      auth
        ..add(Authenticated(_user))
        ..add(const Unauthenticated());

      await running;
      await pumpEventQueue();

      expect(
        seen.whereType<StartupAuthenticated>(),
        <StartupState>[
          const StartupAuthenticated(userId: _userId, syncFailed: false),
        ],
      );
      expect(seen.whereType<StartupUnauthenticated>(), isEmpty);
    });
  });

  group('the first sync', () {
    blocTest<StartupCubit, StartupState>(
      'opens on local data when the sync fails outright',
      setUp: () {
        authBlocHolds(Authenticated(_user));
        when(
          () => syncService.sync(
            userId: any(named: 'userId'),
            adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
          ),
        ).thenAnswer(
          (_) async => const Left<Failure, SyncOutcome>(ServerFailure()),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.initialize(),
      // Rule 7, and the difference from the project this pattern came from:
      // TimeBuddy has a usable local board, so a failed sync is a flag on a
      // terminal state and never `StartupError`. The passive indicator
      // explains the rest (sync.md rule 4).
      expect: () => <StartupState>[
        const StartupLoading(),
        const StartupLoading(progress: StartupLoading.preparedProgress),
        const StartupLoading(progress: StartupLoading.syncingProgress),
        const StartupAuthenticated(userId: _userId, syncFailed: true),
      ],
    );

    testWidgets('gives up on a sync that outruns its time box', (
      tester,
    ) async {
      authBlocHolds(Authenticated(_user));
      final pending = Completer<Either<Failure, SyncOutcome>>();
      when(
        () => syncService.sync(
          userId: any(named: 'userId'),
          adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
        ),
      ).thenAnswer((_) => pending.future);

      final cubit = buildCubit();
      final seen = <StartupState>[];
      final subscription = cubit.stream.listen(seen.add);

      // The fake async that `testWidgets` runs its body in owns the budget's
      // timer, so the five seconds cost nothing and cannot flake.
      unawaited(cubit.initialize());
      await tester.pump();
      expect(
        seen.last,
        const StartupLoading(progress: StartupLoading.syncingProgress),
      );

      await tester.pump(
        StartupCubit.syncTimeBox - const Duration(milliseconds: 1),
      );
      expect(
        seen.last,
        const StartupLoading(progress: StartupLoading.syncingProgress),
      );

      await tester.pump(const Duration(milliseconds: 1));
      expect(
        seen.last,
        const StartupAuthenticated(userId: _userId, syncFailed: true),
      );

      // Rule 8's other half: the sync was not cancelled, it was left running,
      // and the decision it lands on afterwards must not move the app a
      // second time.
      pending.complete(Right<Failure, SyncOutcome>(_reconciled));
      await tester.pump();
      expect(
        seen.last,
        const StartupAuthenticated(userId: _userId, syncFailed: true),
      );

      // Not awaited, and that is the whole trick. Cancelling a broadcast
      // subscription answers with `Future._nullFuture`, a future that lives in
      // the *root* zone; awaiting it here would resume this body from the real
      // event loop, outside the fake async that owns every other microtask in
      // this test. Everything queued after that point — the cubit's own
      // `close()`, and the frame `testWidgets` pumps once the body returns —
      // would then sit in a queue nobody drains, and the test would never
      // complete. The cancel itself is synchronous, so dropping the future
      // costs nothing.
      unawaited(subscription.cancel());
      await cubit.close();
    });
  });

  group('the unrecoverable case', () {
    blocTest<StartupCubit, StartupState>(
      'stops at the error state when tzdata will not load',
      setUp: () {
        when(engine.initialize).thenAnswer((_) async {
          throw const FormatException('corrupt tzdata');
        });
      },
      build: buildCubit,
      act: (cubit) => cubit.initialize(),
      // Rule 10: the raw exception is a developer's breadcrumb and the page
      // owns the localized copy, so the state carries no field to leak it.
      expect: () => <StartupState>[
        const StartupLoading(),
        const StartupError(),
      ],
      verify: (_) {
        expectSyncWasNotRun();
      },
    );

    blocTest<StartupCubit, StartupState>(
      'stops at the error state when the catalog will not load',
      setUp: () {
        when(catalog.load).thenAnswer(
          (_) async => const Left<Failure, List<CityEntity>>(StorageFailure()),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.initialize(),
      // Fatal although the board would technically render: a first run where
      // no city can be added is a dead end, not a degraded app.
      expect: () => <StartupState>[
        const StartupLoading(),
        const StartupError(),
      ],
    );

    test('a retry after an error starts the sequence over', () async {
      when(engine.initialize).thenAnswer((_) async {
        throw const FormatException('corrupt tzdata');
      });
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.initialize();
      expect(cubit.state, const StartupError());

      when(engine.initialize).thenAnswer((_) async {});
      await cubit.initialize();

      // Rule 1: re-entry is the error state's retry and nothing else, and it
      // re-announces loading rather than returning to `StartupInitial`.
      expect(cubit.state, const StartupUnauthenticated());
    });
  });

  group('adopting a guest who signed in', () {
    test(
      'asks the sync to adopt, and clears the marker once it lands',
      () async {
        await becomeGuest();
        authBlocHolds(Authenticated(_user));

        final cubit = buildCubit();
        addTearDown(cubit.close);
        await cubit.initialize();

        // The flag is the whole difference between "your account replaces this
        // board" and "this board replaces your account"
        // (docs/specs/guest_mode.md rule 6).
        verify(
          () => syncService.sync(userId: _userId, adoptGuestDocuments: true),
        ).called(1);
        expect(guestSession.isGuest, isFalse);
        expect(
          cubit.state,
          const StartupAuthenticated(userId: _userId, syncFailed: false),
        );
      },
    );

    test('leaves the marker set when the adopting sync failed', () async {
      await becomeGuest();
      authBlocHolds(Authenticated(_user));
      when(
        () => syncService.sync(
          userId: any(named: 'userId'),
          adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
        ),
      ).thenAnswer(
        (_) async => const Left<Failure, SyncOutcome>(
          ServerFailure('the account could not be read'),
        ),
      );

      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.initialize();

      // Rule 8. Clearing it here would strand a board that never reached the
      // account: the next launch would sync as an ordinary signed-in user and
      // the guest's cities would lose the ladder to a remote that has them
      // beaten on nothing but existing.
      expect(guestSession.isGuest, isTrue);
      expect(
        cubit.state,
        const StartupAuthenticated(userId: _userId, syncFailed: true),
      );
    });

    test('marks the attempt before awaiting, so the router cannot loop',
        () async {
      await becomeGuest();
      authBlocHolds(Authenticated(_user));
      final held = Completer<Either<Failure, SyncOutcome>>();
      when(
        () => syncService.sync(
          userId: any(named: 'userId'),
          adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
        ),
      ).thenAnswer((_) => held.future);

      final cubit = buildCubit();
      addTearDown(cubit.close);
      unawaited(cubit.initialize());
      await pumpEventQueue();

      // While the sync is still in flight the marker is necessarily still set,
      // so `AppRouter`'s guest rule would send this same session back to the
      // splash forever if it keyed on the marker alone.
      expect(guestSession.isGuest, isTrue);
      expect(guestSession.adoptionAttempted, isTrue);

      held.complete(Right<Failure, SyncOutcome>(_reconciled));
      await pumpEventQueue();
      expect(guestSession.isGuest, isFalse);
    });

    testWidgets('an adopting sync is not cut off by the time box', (
      tester,
    ) async {
      await becomeGuest();
      authBlocHolds(Authenticated(_user));
      final slow = Completer<Either<Failure, SyncOutcome>>();
      when(
        () => syncService.sync(
          userId: any(named: 'userId'),
          adoptGuestDocuments: any(named: 'adoptGuestDocuments'),
        ),
      ).thenAnswer((_) => slow.future);

      final cubit = buildCubit();
      addTearDown(cubit.close);
      unawaited(cubit.initialize());
      // Well past rule 8's budget, which an ordinary first sync would have
      // abandoned by now — spent inside `testWidgets`' fake async rather than
      // on the wall clock. It used to be a real `Future.delayed`, which made
      // one test more than half the suite's total runtime and left the
      // assertion below dependent on how loaded the machine was. The sibling
      // test above already made this trade; this one had not.
      await tester.pump(StartupCubit.syncTimeBox * 2);
      await tester.pump();

      // Rule 7: `AppShell` builds `BoardCubit` the moment the router leaves
      // `/startup`, so opening early would load the guest's document a
      // heartbeat before the account's replaced it.
      expect(cubit.state, isA<StartupLoading>());

      slow.complete(Right<Failure, SyncOutcome>(_reconciled));
      await tester.pump();
      expect(
        cubit.state,
        const StartupAuthenticated(userId: _userId, syncFailed: false),
      );
    });

    test('a signed-in user who was never a guest syncs normally', () async {
      authBlocHolds(Authenticated(_user));

      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.initialize();

      // The ladder still owns every ordinary sync. Adoption is one call on one
      // transition, not a mode the app stays in.
      verify(
        () => syncService.sync(userId: _userId),
      ).called(1);
      verifyNever(() => localStore.remove(StorageKeys.guest));
    });
  });
}

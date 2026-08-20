import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/domain/repositories/auth_repository.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';

import '../../../../harness/factories/user_factory.dart';

/// The repository boundary for these tests.
///
/// Declared here rather than in `test/harness/mocks.dart` on purpose: several
/// M3 files are landing at once, and a shared edit for a mock only this file
/// needs is a merge conflict for nothing. Promote it the moment a second test
/// file wants the same boundary.
class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  final ada = aUser();
  final grace = aUser(
    id: 'uid-grace',
    name: 'Grace Hopper',
    email: 'grace@example.com',
    photoUrl: null,
  );

  const networkFailure = ServerFailure('the network went away');
  const signOutFailure = AuthFailure('firebase refused the sign-out');

  late _MockAuthRepository repository;
  late StreamController<UserEntity?> sessions;
  late Completer<Either<Failure, UserEntity>> pendingSignIn;

  setUp(() {
    repository = _MockAuthRepository();
    sessions = StreamController<UserEntity?>();
    // Stubbed before any bloc exists: the constructor subscribes immediately,
    // so a bloc built against an unstubbed getter never listens at all.
    when(() => repository.authStateChanges).thenAnswer((_) => sessions.stream);
  });

  tearDown(() async {
    await sessions.close();
  });

  AuthBloc buildBloc() => AuthBloc(repository: repository);

  void sessionCheckAnswers(Either<Failure, UserEntity?> result) {
    when(repository.getCurrentUser).thenAnswer((_) async => result);
  }

  void signInAnswers(Either<Failure, UserEntity> result) {
    when(repository.signInWithGoogle).thenAnswer((_) async => result);
  }

  void signOutAnswers(Either<Failure, void> result) {
    when(repository.signOut).thenAnswer((_) async => result);
  }

  /// Lets the event loop drain, so an event posted on the line above has been
  /// handled before the next line runs.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('starts in AuthInitial, before anything has been asked', () {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    // Not covered by any blocTest below: bloc_test records emissions, and the
    // initial state was never emitted.
    expect(bloc.state, const AuthInitial());
  });

  test('subscribes to the session stream and cancels it on close', () async {
    final bloc = buildBloc();

    // Subscribed from the constructor, so the app cannot forget to listen.
    expect(sessions.hasListener, isTrue);

    await bloc.close();

    // A live subscription after close would keep emitting into a bloc whose
    // `emit` throws.
    expect(sessions.hasListener, isFalse);
  });

  group('AuthCheckRequested', () {
    blocTest<AuthBloc, AuthState>(
      'reports the session it found, with no loading state on the way',
      setUp: () => sessionCheckAnswers(Right<Failure, UserEntity?>(ada)),
      build: buildBloc,
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      // The splash is already on screen while this runs (auth.md, State
      // Machine), so an AuthLoading here would only ever be a flicker.
      expect: () => [Authenticated(ada)],
      verify: (_) => verify(repository.getCurrentUser).called(1),
    );

    blocTest<AuthBloc, AuthState>(
      'reports no session as Unauthenticated',
      setUp: () => sessionCheckAnswers(const Right<Failure, UserEntity?>(null)),
      build: buildBloc,
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [const Unauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'treats a failed check as no session rather than as an error',
      // An error screen in front of a sign-in button the user could simply
      // press is a dead end (auth.md, State Machine).
      setUp: () => sessionCheckAnswers(
        const Left<Failure, UserEntity?>(networkFailure),
      ),
      build: buildBloc,
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [const Unauthenticated()],
    );
  });

  group('AuthGoogleSignInRequested', () {
    blocTest<AuthBloc, AuthState>(
      'shows the spinner and lands on the new session',
      setUp: () => signInAnswers(Right<Failure, UserEntity>(ada)),
      build: buildBloc,
      act: (bloc) => bloc.add(const AuthGoogleSignInRequested()),
      expect: () => [const AuthLoading(), Authenticated(ada)],
    );

    blocTest<AuthBloc, AuthState>(
      'returns to onboarding in silence when the dialog was dismissed',
      // Rule 5: cancellation is a decision, not a failure. Unauthenticated
      // puts the user back on onboarding with no red banner.
      setUp: () => signInAnswers(
        const Left<Failure, UserEntity>(signInCancelledFailure),
      ),
      build: buildBloc,
      act: (bloc) => bloc.add(const AuthGoogleSignInRequested()),
      expect: () => [const AuthLoading(), const Unauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'surfaces a genuine sign-in failure as AuthError',
      setUp: () => signInAnswers(
        const Left<Failure, UserEntity>(networkFailure),
      ),
      build: buildBloc,
      act: (bloc) => bloc.add(const AuthGoogleSignInRequested()),
      expect: () => [const AuthLoading(), const AuthError(networkFailure)],
    );

    blocTest<AuthBloc, AuthState>(
      'an AuthFailure without the cancelled marker is still an error',
      // Guards the read: `failure is AuthFailure` alone would swallow every
      // real authentication error into a silent return to onboarding.
      setUp: () => signInAnswers(
        const Left<Failure, UserEntity>(AuthFailure('google said no')),
      ),
      build: buildBloc,
      act: (bloc) => bloc.add(const AuthGoogleSignInRequested()),
      expect: () => [
        const AuthLoading(),
        const AuthError(AuthFailure('google said no')),
      ],
    );
  });

  group('AuthSignOutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'ends the session, with no loading state',
      setUp: () => signOutAnswers(const Right<Failure, void>(null)),
      build: buildBloc,
      seed: () => Authenticated(ada),
      act: (bloc) => bloc.add(const AuthSignOutRequested()),
      expect: () => [const Unauthenticated()],
      verify: (_) => verify(repository.signOut).called(1),
    );

    blocTest<AuthBloc, AuthState>(
      'reports a failed sign-out, because the user is still signed in',
      // The local board is deliberately not cleared when the remote call
      // fails (auth.md, Edge Cases), so the user has to be told.
      setUp: () => signOutAnswers(const Left<Failure, void>(signOutFailure)),
      build: buildBloc,
      seed: () => Authenticated(ada),
      act: (bloc) => bloc.add(const AuthSignOutRequested()),
      expect: () => [const AuthError(signOutFailure)],
    );
  });

  group('AuthUserChanged, from the repository stream', () {
    blocTest<AuthBloc, AuthState>(
      'adopts a session Firebase published on its own',
      build: buildBloc,
      act: (bloc) async {
        sessions.add(grace);
        await settle();
      },
      expect: () => [Authenticated(grace)],
    );

    blocTest<AuthBloc, AuthState>(
      'signs the user out when the session is revoked remotely',
      build: buildBloc,
      seed: () => Authenticated(ada),
      act: (bloc) async {
        sessions.add(null);
        await settle();
      },
      expect: () => [const Unauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'ignores the null published while a sign-in is in flight',
      // Firebase tears the old session down *while* the Google dialog is
      // open. Honouring that null would bounce the user back to onboarding a
      // frame before their own sign-in lands.
      setUp: () {
        pendingSignIn = Completer<Either<Failure, UserEntity>>();
        when(
          repository.signInWithGoogle,
        ).thenAnswer((_) => pendingSignIn.future);
      },
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const AuthGoogleSignInRequested());
        await settle();
        sessions.add(null);
        await settle();
        pendingSignIn.complete(Right<Failure, UserEntity>(ada));
        await settle();
      },
      expect: () => [const AuthLoading(), Authenticated(ada)],
    );

    blocTest<AuthBloc, AuthState>(
      'a session swap emits the new user',
      build: buildBloc,
      seed: () => Authenticated(ada),
      act: (bloc) async {
        sessions.add(grace);
        await settle();
      },
      expect: () => [Authenticated(grace)],
    );
  });
}

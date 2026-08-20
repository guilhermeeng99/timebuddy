import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:timebuddy/features/auth/data/models/user_model.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/domain/repositories/auth_repository.dart';

/// Composes the Firebase data source with the local cache, and translates
/// every transport error into a `Failure` (auth.md rule 10).
///
/// The rules that shape this class all say the same thing in different words:
/// an authentication that *worked* must not be turned into an error screen by
/// something downstream of it. Firestore being unreachable degrades to a
/// credentials-only profile (rule 4), a missing document is written rather
/// than reported (rule 8), and a stream error becomes "signed out" instead of
/// an unhandled error (rule 9).
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required LocalStore localStore,
  }) : _remoteDataSource = remoteDataSource,
       _localStore = localStore;

  final AuthRemoteDataSource _remoteDataSource;
  final LocalStore _localStore;

  @override
  Future<Either<Failure, UserEntity>> signInWithGoogle() async {
    try {
      final session = await _remoteDataSource.signInWithGoogle();
      // No session and no exception means the user closed the dialog, or the
      // web redirect left without producing one. Neither is an error, so it
      // travels as the cancellation marker the bloc reads to return to
      // onboarding in silence (rule 5).
      if (session == null) return const Left(signInCancelledFailure);
      return Right(await _profileOrMinimal(session));
    } on Object catch (error) {
      return Left(_failureFrom(error));
    }
  }

  @override
  Future<Either<Failure, void>> signOut() async {
    try {
      await _remoteDataSource.signOut();
    } on Object catch (error) {
      // The local cache is deliberately left alone here (auth.md, Edge
      // Cases): a user whose sign-out failed is still signed in, and wiping
      // their board would hand them an empty app they did not ask for.
      return Left(_failureFrom(error));
    }
    await _clearLocalData();
    return const Right<Failure, void>(null);
  }

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUser() async {
    try {
      final session = await _remoteDataSource.currentAuthUser();
      if (session == null) return const Right(null);
      // Self-heals rule 8: an authenticated user whose profile document never
      // landed gets one written now, instead of being bounced to onboarding
      // by a document that is missing for reasons they cannot act on.
      return Right(await _profileOrMinimal(session));
    } on Object catch (error) {
      return Left(_failureFrom(error));
    }
  }

  @override
  Stream<UserEntity?> get authStateChanges {
    // Rule 9. An error escaping this stream reaches the zone guard and takes
    // the app down; folded into `null` it costs the user one sign-in tap, so
    // the transformer converts rather than forwards.
    //
    // `handleData` is spelled out rather than left to the default, which
    // would forward each event through an implicit `as UserEntity?` cast.
    return _remoteDataSource.authStateChanges.transform(
      StreamTransformer<UserModel?, UserEntity?>.fromHandlers(
        handleData: (session, sink) => sink.add(session),
        handleError: (error, stackTrace, sink) => sink.add(null),
      ),
    );
  }

  /// The stored profile, or the credentials themselves when Firestore will
  /// not answer.
  ///
  /// Rule 4: an authentication that succeeded must not end on an error screen
  /// because a profile document could not be read. The user reaches the app
  /// with their local board, and the next sync reconciles the rest — an auth
  /// success followed by an error screen would be the worst of both.
  Future<UserEntity> _profileOrMinimal(UserModel session) async {
    try {
      return await _remoteDataSource.ensureProfile(session);
    } on Object catch (_) {
      return session;
    }
  }

  /// Wipes every local key on sign-out (rule 7).
  ///
  /// Everything, not just the two documents: the dirty flags go with them, so
  /// a write still pending for the account that just signed out cannot be
  /// flushed into the next one (docs/specs/sync.md rule 10). Leaving another
  /// account's cities on a shared browser is a privacy leak, however mild.
  Future<void> _clearLocalData() async {
    try {
      await _localStore.clearAll();
    } on Object catch (_) {
      // Swallowed on purpose, and only here. The remote session is already
      // gone by this point, so failing the sign-out would strand the UI as
      // signed in against a Firebase that has signed out — worse than a stale
      // local board, which the next sign-in reconciles anyway.
    }
  }

  /// Rule 10's uniform mapping, in one place so three methods cannot drift.
  ///
  /// The catch-all answers `ServerFailure` rather than rethrowing, because a
  /// repository that lets a transport type escape has leaked its data layer
  /// (`exceptions.dart`). It is reached by `Error`s too, which matters: an
  /// uninitialised `google_sign_in` throws `StateError`, and `on Exception`
  /// would let exactly the failure rule 6 guards against through.
  Failure _failureFrom(Object error) {
    if (error is AuthException) return AuthFailure(error.message);
    if (error is ServerException) return ServerFailure(error.message);
    return ServerFailure(error.toString());
  }
}

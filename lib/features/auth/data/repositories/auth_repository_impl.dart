import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:timebuddy/features/auth/data/models/user_model.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/domain/repositories/auth_repository.dart';

/// The exact [AuthFailure.message] a sign-in carries when the browser refused
/// Firebase the storage it needs to finish (docs/specs/auth.md rule 2).
///
/// Same mechanism as [signInCancelledMarker], and for the same reason:
/// `Failure` is a sealed family and `AuthFailure` is `final`, so a subtype
/// cannot be declared for it. The marker travels in the developer-facing
/// `message`, which is never rendered.
///
/// This one exists because the failure it names is otherwise **silent**. A
/// redirect that came back empty and a user who never signed in produce the
/// identical "signed out" screen, and only this marker separates "your browser
/// dropped the sign-in" from "you have not signed in yet".
///
/// Read it through [isSignInStorageBlocked], never by comparing strings.
const String signInStorageBlockedMarker = 'auth.signIn.storageBlocked';

/// The value the repository answers with when the browser will not carry a
/// sign-in through: a redirect that returned with nothing, or a popup Firebase
/// could not open storage for.
const AuthFailure signInStorageBlockedFailure = AuthFailure(
  signInStorageBlockedMarker,
);

/// Whether [failure] means the browser dropped the sign-in, rather than the
/// user never having started one.
///
/// ```dart
/// result.fold(
///   (failure) => isSignInStorageBlocked(failure)
///       ? showSnack(t.auth.signInStorageBlocked) // "allow pop-ups, or …"
///       : showSnack(t.auth.signInFailed),
///   (user) => openApp(user),
/// );
/// ```
bool isSignInStorageBlocked(Failure failure) =>
    failure is AuthFailure && failure.message == signInStorageBlockedMarker;

/// The exact [AuthFailure.message] a sign-in carries when the popup was
/// blocked and the redirect fallback is already known not to work here.
const String signInPopupBlockedMarker = 'auth.signIn.popupBlocked';

/// The value the repository answers with when the only remaining flow is one
/// the browser refuses to open.
///
/// Deliberately distinct from [signInStorageBlockedFailure] and from a generic
/// failure: this one has an exact remedy the user can carry out, which is to
/// allow pop-ups for this site and press the button again.
const AuthFailure signInPopupBlockedFailure = AuthFailure(
  signInPopupBlockedMarker,
);

/// Whether [failure] is a pop-up blocker rather than anything about the
/// account, the network or Firebase.
bool isSignInPopupBlocked(Failure failure) =>
    failure is AuthFailure && failure.message == signInPopupBlockedMarker;

/// Composes the Firebase data source with the local cache, and translates
/// every transport error into a `Failure` (auth.md rule 10).
///
/// The rules that shape this class all say the same thing in different words:
/// an authentication that *worked* must not be turned into an error screen by
/// something downstream of it. Firestore being unreachable degrades to a
/// credentials-only profile (rule 4), a missing document is written rather
/// than reported (rule 8), and a stream error becomes "signed out" instead of
/// an unhandled error (rule 9).
///
/// It also owns the one web policy the data source cannot: whether a blocked
/// popup is worth answering with a redirect. That decision needs to remember
/// what happened *before the page was unloaded*, so it lives in [LocalStore]
/// rather than in a field — see [_redirectNoteKey].
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required LocalStore localStore,
  }) : _remoteDataSource = remoteDataSource,
       _localStore = localStore;

  /// Where a web redirect leaves a note for the page that comes back.
  ///
  /// It has to be storage rather than a field because `signInWithRedirect`
  /// unloads the page: the object that started the flow is gone by the time
  /// the answer arrives. It is first-party to the app's own origin, which is
  /// precisely the storage a partitioning browser leaves alone — the state
  /// Firebase loses is the one it wrote on the auth domain (rule 2).
  ///
  /// `StorageKeys` is where the other keys live and where this one belongs;
  /// it is declared here so the note and the only code that reads it land
  /// together, and moving it is a one-line change. It carries the same `.v1`
  /// suffix so it can be versioned like the rest (sync.md rule 11), and
  /// `clearAll()` on sign-out drops it with everything else, so the diagnosis
  /// below is re-learned per session rather than outliving the browser it was
  /// made about.
  static const String _redirectNoteKey = 'timebuddy.auth.webRedirect.v1';

  /// A redirect left this page and has not been answered for yet.
  static const String _redirectPending = 'pending';

  /// A redirect came back with nothing: this browser does not carry one.
  static const String _redirectUnusable = 'unusable';

  final AuthRemoteDataSource _remoteDataSource;
  final LocalStore _localStore;

  @override
  Future<Either<Failure, UserEntity>> signInWithGoogle() async {
    try {
      final outcome = await _remoteDataSource.signInWithGoogle();
      return switch (outcome) {
        GoogleSignInSucceeded(:final session) => Right(
          await _completeSignIn(session),
        ),
        // Rule 5: a dismissed dialog or a closed popup is a decision, not an
        // error, so it travels as the marker the bloc reads to return to
        // onboarding in silence.
        GoogleSignInCancelled() => const Left(signInCancelledFailure),
        // Said out loud rather than retried: the browser has already refused
        // the storage, and a redirect would only lose it again quietly.
        GoogleSignInStorageBlocked() => Left(await _rememberBlockedStorage()),
        GoogleSignInPopupUnavailable() => await _redirectInstead(),
      };
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
    // Read *before* the session check, because the check is what consumes the
    // redirect: afterwards, "was a redirect in flight" has no answer left.
    final wasRedirecting = await _redirectNote() == _redirectPending;
    try {
      // The only call below that can throw. Everything else in this block is
      // a private method of this class that swallows its own errors, which is
      // what lets the catch attribute a throw to the session check.
      final session = await _remoteDataSource.currentAuthUser();

      if (session == null) {
        // This is the silent failure, and the only place it can be seen. The
        // redirect went out from this page and came back with no user and no
        // session, so the state Firebase parked on the auth domain did not
        // survive the round trip: partitioned third-party storage, not a
        // user who changed their mind (rule 2). Reported as a failure,
        // because "signed out" is indistinguishable from never having tried.
        if (wasRedirecting) return Left(await _rememberBlockedStorage());
        return const Right(null);
      }

      // The redirect worked after all; the note has nothing left to say.
      if (wasRedirecting) await _clearRedirectNote();
      // Self-heals rule 8: an authenticated user whose profile document never
      // landed gets one written now, instead of being bounced to onboarding
      // by a document that is missing for reasons they cannot act on.
      return Right(await _profileOrMinimal(session));
    } on Object catch (error) {
      // A redirect that came back throwing lost the same state as one that
      // came back empty — a mismatched nonce, an auth event the browser would
      // not hand over. The browser is merely being louder about it.
      if (wasRedirecting) return Left(await _rememberBlockedStorage());
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

  /// Answers a popup the browser would not open (rule 2).
  ///
  /// A full-page redirect is not a popup, so a blocker cannot stop it, and on
  /// a browser that keeps third-party storage it simply works — which is why
  /// this is a fallback and not an error message. What it cannot survive is
  /// storage partitioning: the flow parks its state on the Firebase auth
  /// domain and reads it back from the app's origin, and Safari, Firefox and
  /// Chrome-without-third-party-cookies drop it in between.
  ///
  /// So it is tried exactly once per session. After this page has watched a
  /// redirect come back empty, a second one would only spend another full
  /// page load to fail the same silent way; the user is told about the pop-up
  /// blocker instead, which is the one thing left that they can act on.
  Future<Either<Failure, UserEntity>> _redirectInstead() async {
    if (await _redirectNote() == _redirectUnusable) {
      return const Left(signInPopupBlockedFailure);
    }
    await _writeRedirectNote(_redirectPending);
    try {
      await _remoteDataSource.startGoogleRedirect();
    } on Object {
      // The page is staying put, so the note would be read by the next boot
      // as a redirect that came back empty — a verdict about a browser that
      // never got the chance to prove anything.
      await _clearRedirectNote();
      rethrow;
    }
    // The browser is navigating away. Nothing has happened *yet*, and this is
    // the marker for exactly that: any banner raised now would be shown for a
    // few milliseconds to a user who is already looking at Google's page.
    return const Left(signInCancelledFailure);
  }

  /// Records that this browser will not carry a redirect, and names the
  /// failure that says so.
  ///
  /// One write covers both notes: a pending redirect that came back empty is
  /// the very evidence that makes it unusable, so the pending state is
  /// consumed in the same breath and cannot be read twice.
  Future<Failure> _rememberBlockedStorage() async {
    await _writeRedirectNote(_redirectUnusable);
    return signInStorageBlockedFailure;
  }

  /// A session in hand ends whatever story the note was telling, including a
  /// verdict about this browser that a working sign-in has just outdated.
  Future<UserEntity> _completeSignIn(UserModel session) async {
    await _clearRedirectNote();
    return _profileOrMinimal(session);
  }

  /// The note the last redirect left, or `null` when there is none.
  ///
  /// A store that will not answer is not evidence of anything, so a read
  /// failure reads as "no note". The alternative is telling a user that their
  /// browser blocked a sign-in because `localStorage` hiccuped.
  Future<String?> _redirectNote() async {
    try {
      return await _localStore.readRaw(_redirectNoteKey);
    } on Object catch (_) {
      return null;
    }
  }

  Future<void> _writeRedirectNote(String note) async {
    try {
      await _localStore.writeRaw(_redirectNoteKey, note);
    } on Object catch (_) {
      // Swallowed: a diagnosis that cannot be persisted costs the diagnosis,
      // never the sign-in. The flow carries on exactly as it would have.
    }
  }

  Future<void> _clearRedirectNote() async {
    try {
      await _localStore.remove(_redirectNoteKey);
    } on Object catch (_) {
      // Same trade as the write above. A note that outlives its answer only
      // costs one wasted redirect on the next blocked popup.
    }
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

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/platform/app_platform.dart';
import 'package:timebuddy/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:timebuddy/features/auth/data/models/user_model.dart';
import 'package:timebuddy/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:timebuddy/features/auth/domain/repositories/auth_repository.dart';

import '../../../../harness/factories/user_factory.dart';
import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

/// The one collection the profile document lives in (CLAUDE.md, Firestore
/// Collections). Spelled out here so a rename inside the data source cannot
/// quietly leave these tests exercising a document nobody reads.
const String _usersCollection = 'users';

/// The local-store key the repository leaves its web-redirect note under, and
/// the two values it can hold.
///
/// Spelled out rather than imported, on purpose. This is a *persisted* key: a
/// rename is a storage change that strands the note a redirect already wrote,
/// so it has to be a visible, deliberate edit on this side too rather than
/// something a refactor carries along silently.
const String _redirectNoteKey = 'timebuddy.auth.webRedirect.v1';
const String _redirectPending = 'pending';
const String _redirectUnusable = 'unusable';

// Boundary mocks. Declared in this file rather than in test/harness/mocks.dart
// because several M3 files are landing at once and a shared edit for mocks
// only this file needs is a merge conflict for nothing; promote any of them
// the moment a second test file wants the same boundary.
//
// Firestore is deliberately absent from this list: `FirebaseFirestore`'s
// document, collection and snapshot types are `@sealed`, so hand-mocking the
// reference chain both warns (`subtype_of_sealed_class`) and only ever
// replays the semantics the test already assumed. `FakeFirebaseFirestore`
// below is a real in-memory Firestore instead.
class _MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockFirebaseUser extends Mock implements User {}

class _MockUserMetadata extends Mock implements UserMetadata {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

/// The in-memory Firestore these tests run against, counting how often the
/// `users` collection was looked up at all.
///
/// The count exists for the one assertion a fake with real semantics cannot
/// make by inspecting its own contents: *Firestore was never consulted*. Every
/// other question ("was it written?", "with what?") is answered by reading the
/// documents back, which is stronger than replaying a recorded call.
class _CountingFirestore extends FakeFirebaseFirestore {
  int collectionLookups = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    collectionLookups++;
    return super.collection(path);
  }
}

/// The same Firestore with the backend unreachable (rule 4).
///
/// The outage is raised at the collection lookup rather than at the document
/// read because `CollectionReference` and `DocumentReference` are sealed and
/// cannot be wrapped. It makes no difference to what is under test: the lookup
/// happens inside `ensureProfile`'s `try`, so the `FirebaseException` travels
/// exactly the path a failed `get()` would.
class _UnreachableFirestore extends _CountingFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }
}

/// The browser build. Injected rather than read from `kIsWeb`, which is the
/// entire reason `AppPlatform` exists: a test binary is never a browser, so
/// the web half of rules 2 and 6 would otherwise be unreachable code.
class _WebPlatform extends AppPlatform {
  const _WebPlatform();

  @override
  bool get isWeb => true;
}

/// The Android build, the other half of the same two rules.
class _MobilePlatform extends AppPlatform {
  const _MobilePlatform();

  @override
  bool get isWeb => false;
}

void main() {
  setUpAll(() {
    registerCommonFallbacks();
    // Only this file passes these through `any()`: the credential the data
    // source builds from the Google ID token, the provider it hands the popup
    // and the redirect, and the profile it forwards. mocktail matches a
    // fallback by `is T`, so the concrete Google types below cover the
    // `AuthCredential` and `AuthProvider` parameters they are passed as.
    registerFallbackValue(
      GoogleAuthProvider.credential(idToken: 'fallback-id-token'),
    );
    registerFallbackValue(GoogleAuthProvider());
    registerFallbackValue(UserModel.fromEntity(aUser()));
  });

  /// What the injected clock reads. Distinct from every fixture instant, so a
  /// value that came from the clock cannot be mistaken for one that did not.
  final bootInstant = utcDate(2024, 6, 1, 8);

  /// Firebase Auth's own account metadata: the true first-sign-in instant,
  /// identical on every device the user signs in from.
  final accountCreatedAt = utcDate(2023, 6, 1, 9, 30);

  final ada = aUser(createdAt: accountCreatedAt);

  /// The credentials-only profile a data source hands back.
  final session = UserModel.fromEntity(ada);

  /// The name the user set from the profile page, which a re-provisioning
  /// must not overwrite with the Google display name.
  const renamed = 'Ada, renamed in the profile page';

  group('over a mocked data source', () {
    late _MockAuthRemoteDataSource remote;
    late MockLocalStore store;
    late AuthRepositoryImpl repository;

    setUp(() {
      remote = _MockAuthRemoteDataSource();
      store = MockLocalStore();
      repository = AuthRepositoryImpl(
        remoteDataSource: remote,
        localStore: store,
      );
      when(store.clearAll).thenAnswer((_) async {});
      // The default browser: nothing was ever redirected here. Tests about
      // the redirect note re-stub `readRaw` with the state they need, and
      // mocktail answers with the most recently registered match.
      when(() => store.readRaw(any())).thenAnswer((_) async => null);
      when(() => store.writeRaw(any(), any())).thenAnswer((_) async {});
      when(() => store.remove(any())).thenAnswer((_) async {});
      when(remote.startGoogleRedirect).thenAnswer((_) async {});
    });

    T valueOf<T>(Either<Failure, T> result) =>
        result.getOrElse(() => fail('expected a Right, got $result'));

    Failure failureOf<T>(Either<Failure, T> result) =>
        result.fold((failure) => failure, (_) => fail('expected a Left'));

    /// The note the last redirect left behind on this browser.
    void redirectNoteReads(String? note) {
      when(
        () => store.readRaw(_redirectNoteKey),
      ).thenAnswer((_) async => note);
    }

    group('signInWithGoogle', () {
      test('answers the provisioned profile', () async {
        final stored = UserModel.fromEntity(ada.copyWith(name: renamed));
        when(
          remote.signInWithGoogle,
        ).thenAnswer((_) async => GoogleSignInSucceeded(session));
        when(
          () => remote.ensureProfile(session),
        ).thenAnswer((_) async => stored);

        final result = await repository.signInWithGoogle();

        expect(valueOf(result), stored);
        verify(() => remote.ensureProfile(session)).called(1);
      });

      test('answers the cancellation marker when nothing happened', () async {
        // Rule 5. A dismissed dialog and a closed popup are decisions, not
        // errors, and they say so with their own outcome rather than sharing
        // one with every other "no session".
        when(
          remote.signInWithGoogle,
        ).thenAnswer((_) async => const GoogleSignInCancelled());

        final result = await repository.signInWithGoogle();

        expect(failureOf(result), signInCancelledFailure);
        expect(isSignInCancelled(failureOf(result)), isTrue);
        verifyNever(() => remote.ensureProfile(any()));
      });

      test('degrades to the credentials when Firestore refuses', () async {
        // Rule 4: the authentication itself succeeded, so the user reaches
        // the app with their local board and the next sync reconciles.
        when(
          remote.signInWithGoogle,
        ).thenAnswer((_) async => GoogleSignInSucceeded(session));
        when(
          () => remote.ensureProfile(session),
        ).thenThrow(const ServerException('firestore is unreachable'));

        final result = await repository.signInWithGoogle();

        expect(valueOf(result), session);
      });

      test('maps an AuthException to an AuthFailure', () async {
        when(
          remote.signInWithGoogle,
        ).thenThrow(const AuthException('google said no'));

        final result = await repository.signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        expect(isSignInCancelled(failureOf(result)), isFalse);
      });

      test('maps an Error to a ServerFailure', () async {
        // Rule 10's catch-all has to reach `Error`s too: an uninitialised
        // `google_sign_in` throws StateError, and `on Exception` would let
        // exactly that escape the data layer.
        when(remote.signInWithGoogle).thenThrow(StateError('not initialised'));

        final result = await repository.signInWithGoogle();

        expect(failureOf(result), isA<ServerFailure>());
      });

      test('never clears the local cache', () async {
        when(
          remote.signInWithGoogle,
        ).thenAnswer((_) async => GoogleSignInSucceeded(session));
        when(
          () => remote.ensureProfile(session),
        ).thenAnswer((_) async => session);

        await repository.signInWithGoogle();

        verifyNever(store.clearAll);
      });
    });

    group('the web redirect fallback (rule 2)', () {
      /// The browser refused to open the popup.
      void popupWasBlocked() {
        when(
          remote.signInWithGoogle,
        ).thenAnswer((_) async => const GoogleSignInPopupUnavailable());
      }

      test('a blocked popup falls back to the full-page redirect', () async {
        // A redirect is not a popup, so a blocker cannot stop it, and on a
        // browser that keeps third-party storage it simply works. The user
        // is told nothing, because nothing has gone wrong yet.
        popupWasBlocked();

        final result = await repository.signInWithGoogle();

        verify(remote.startGoogleRedirect).called(1);
        // Written *before* the redirect leaves, because after it there is no
        // page left to write from: this note is the only thing that will
        // distinguish "came back empty" from "never went".
        verify(
          () => store.writeRaw(_redirectNoteKey, _redirectPending),
        ).called(1);
        expect(isSignInCancelled(failureOf(result)), isTrue);
      });

      test('a redirect known to be dropped here is not tried twice', () async {
        // The second round trip would spend a whole page load to fail the
        // same silent way. The pop-up blocker is what is left to say, and it
        // is something the user can actually act on.
        redirectNoteReads(_redirectUnusable);
        popupWasBlocked();

        final result = await repository.signInWithGoogle();

        expect(isSignInPopupBlocked(failureOf(result)), isTrue);
        expect(isSignInCancelled(failureOf(result)), isFalse);
        verifyNever(remote.startGoogleRedirect);
      });

      test('a browser refusing storage is told so, with no redirect', () async {
        // The loud form of the same failure: Firebase could not even open the
        // storage the popup needs, so a redirect would only lose it again,
        // and this time without saying anything at all.
        when(
          remote.signInWithGoogle,
        ).thenAnswer((_) async => const GoogleSignInStorageBlocked());

        final result = await repository.signInWithGoogle();

        expect(isSignInStorageBlocked(failureOf(result)), isTrue);
        verifyNever(remote.startGoogleRedirect);
        verify(
          () => store.writeRaw(_redirectNoteKey, _redirectUnusable),
        ).called(1);
      });

      test('a redirect that never started leaves no note behind', () async {
        // Otherwise the next boot reads a verdict about a browser that never
        // got the chance to prove anything, and blames it for a failure that
        // happened before the page even moved.
        popupWasBlocked();
        when(remote.startGoogleRedirect).thenThrow(
          const AuthException('the browser refused the navigation'),
        );

        final result = await repository.signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        expect(isSignInCancelled(failureOf(result)), isFalse);
        verify(() => store.remove(_redirectNoteKey)).called(1);
      });

      test('a note that cannot be written still starts the redirect', () async {
        // The note buys a diagnosis, not the sign-in. A store that refuses it
        // costs the explanation, and nothing else.
        popupWasBlocked();
        when(
          () => store.writeRaw(any(), any()),
        ).thenThrow(const StorageException());

        final result = await repository.signInWithGoogle();

        verify(remote.startGoogleRedirect).called(1);
        expect(isSignInCancelled(failureOf(result)), isTrue);
      });

      test('a session in hand clears the note', () async {
        // A verdict about this browser that a working sign-in has outdated.
        redirectNoteReads(_redirectUnusable);
        when(
          remote.signInWithGoogle,
        ).thenAnswer((_) async => GoogleSignInSucceeded(session));
        when(
          () => remote.ensureProfile(session),
        ).thenAnswer((_) async => session);

        await repository.signInWithGoogle();

        verify(() => store.remove(_redirectNoteKey)).called(1);
      });

      test('the three sign-in markers are distinguishable', () {
        // The whole point of the markers: the UI picks one string per case,
        // and two cases that compare equal are one case with two names.
        expect(isSignInCancelled(signInStorageBlockedFailure), isFalse);
        expect(isSignInCancelled(signInPopupBlockedFailure), isFalse);
        expect(isSignInStorageBlocked(signInCancelledFailure), isFalse);
        expect(isSignInStorageBlocked(signInPopupBlockedFailure), isFalse);
        expect(isSignInPopupBlocked(signInStorageBlockedFailure), isFalse);
        expect(isSignInStorageBlocked(const ServerFailure()), isFalse);
      });
    });

    group('signOut', () {
      test('clears every local key after a successful sign-out', () async {
        // Rule 7: another account's cities left on a shared browser is a
        // privacy leak, however mild. Everything goes, dirty flags included.
        when(remote.signOut).thenAnswer((_) async {});

        final result = await repository.signOut();

        expect(result.isRight(), isTrue);
        verify(store.clearAll).called(1);
      });

      test('keeps the local board when the remote sign-out failed', () async {
        // A user whose sign-out failed is still signed in; wiping their board
        // would hand them an empty app they did not ask for (Edge Cases).
        when(remote.signOut).thenThrow(const AuthException('no network'));

        final result = await repository.signOut();

        expect(failureOf(result), isA<AuthFailure>());
        verifyNever(store.clearAll);
      });

      test('still succeeds when the local wipe fails', () async {
        // The remote session is already gone by then, so failing here would
        // strand the UI as signed in against a Firebase that signed out.
        when(remote.signOut).thenAnswer((_) async {});
        when(store.clearAll).thenThrow(const StorageException());

        final result = await repository.signOut();

        expect(result.isRight(), isTrue);
      });
    });

    group('getCurrentUser', () {
      test('answers null when nobody is signed in', () async {
        when(remote.currentAuthUser).thenAnswer((_) async => null);

        final result = await repository.getCurrentUser();

        expect(valueOf(result), isNull);
        verifyNever(() => remote.ensureProfile(any()));
      });

      test('writes a missing profile instead of bouncing the user', () async {
        // Rule 8, the classic web-redirect race: the document never landed,
        // which is not something the user can act on.
        when(remote.currentAuthUser).thenAnswer((_) async => session);
        when(
          () => remote.ensureProfile(session),
        ).thenAnswer((_) async => session);

        final result = await repository.getCurrentUser();

        expect(valueOf(result), session);
        verify(() => remote.ensureProfile(session)).called(1);
      });

      test('degrades to the credentials when the profile read fails', () async {
        when(remote.currentAuthUser).thenAnswer((_) async => session);
        when(
          () => remote.ensureProfile(session),
        ).thenThrow(const ServerException());

        final result = await repository.getCurrentUser();

        expect(valueOf(result), session);
      });

      test('maps a failed session check to a failure', () async {
        when(remote.currentAuthUser).thenThrow(const AuthException('expired'));

        final result = await repository.getCurrentUser();

        expect(failureOf(result), isA<AuthFailure>());
      });
    });

    group('a redirect coming back (rule 2)', () {
      test('an empty return is diagnosed, not passed off as silence', () async {
        // THE failure this whole design is about. The redirect went out from
        // this page and came back with no user and no session, so the state
        // Firebase parked on the auth domain did not survive the round trip.
        // Reported, because "signed out" is indistinguishable from never
        // having tried, and the user did try.
        redirectNoteReads(_redirectPending);
        when(remote.currentAuthUser).thenAnswer((_) async => null);

        final result = await repository.getCurrentUser();

        expect(isSignInStorageBlocked(failureOf(result)), isTrue);
        expect(isSignInCancelled(failureOf(result)), isFalse);
        // And the verdict is kept, so the next blocked popup does not spend
        // another page load discovering the same thing.
        verify(
          () => store.writeRaw(_redirectNoteKey, _redirectUnusable),
        ).called(1);
      });

      test('a return that threw is the same lost state', () async {
        // A mismatched nonce, an auth event the browser would not hand back:
        // the same partitioned storage, merely louder about it.
        redirectNoteReads(_redirectPending);
        when(
          remote.currentAuthUser,
        ).thenThrow(const AuthException('missing or invalid nonce'));

        final result = await repository.getCurrentUser();

        expect(isSignInStorageBlocked(failureOf(result)), isTrue);
      });

      test('a return carrying a session clears the note', () async {
        redirectNoteReads(_redirectPending);
        when(remote.currentAuthUser).thenAnswer((_) async => session);
        when(
          () => remote.ensureProfile(session),
        ).thenAnswer((_) async => session);

        final result = await repository.getCurrentUser();

        expect(valueOf(result), session);
        verify(() => store.remove(_redirectNoteKey)).called(1);
        verifyNever(() => store.writeRaw(_redirectNoteKey, any()));
      });

      test('no redirect and no session is still plain signed out', () async {
        // The boot every signed-out user gets. Nothing was attempted, so
        // there is nothing to explain and no failure to raise.
        when(remote.currentAuthUser).thenAnswer((_) async => null);

        final result = await repository.getCurrentUser();

        expect(valueOf(result), isNull);
        verifyNever(() => store.writeRaw(_redirectNoteKey, any()));
      });

      test('a store that will not answer invents no diagnosis', () async {
        // A `localStorage` hiccup is not evidence that the browser blocked a
        // sign-in, and telling the user it was would be worse than silence.
        when(() => store.readRaw(any())).thenThrow(const StorageException());
        when(remote.currentAuthUser).thenAnswer((_) async => null);

        final result = await repository.getCurrentUser();

        expect(valueOf(result), isNull);
      });
    });

    group('authStateChanges', () {
      test('forwards each session and folds an error into null', () async {
        // Rule 9. An error escaping this stream reaches the zone guard and
        // takes the app down; folded into null it costs one sign-in tap.
        final published = StreamController<UserModel?>();
        addTearDown(published.close);
        when(
          () => remote.authStateChanges,
        ).thenAnswer((_) => published.stream);

        final observed = expectLater(
          repository.authStateChanges,
          emitsInOrder(<Object?>[session, null, null, emitsDone]),
        );

        published
          ..add(session)
          ..addError(const ServerException('firestore blew up'))
          ..add(null);
        await published.close();
        await observed;
      });
    });
  });

  // Everything below drives the real Firebase data source, because the
  // platform fork lives there: these are the only tests that can reach the
  // web half of rules 2 and 6 (docs/specs/auth.md, Testing).
  group('through the real Firebase data source', () {
    late _MockFirebaseAuth firebaseAuth;
    late _MockGoogleSignIn googleSignIn;
    late _CountingFirestore firestore;
    late MockLocalStore store;
    late FakeClock clock;

    setUp(() {
      firebaseAuth = _MockFirebaseAuth();
      googleSignIn = _MockGoogleSignIn();
      firestore = _CountingFirestore();
      store = MockLocalStore();
      clock = FakeClock(bootInstant);

      when(store.clearAll).thenAnswer((_) async {});
      when(() => store.readRaw(any())).thenAnswer((_) async => null);
      when(() => store.writeRaw(any(), any())).thenAnswer((_) async {});
      when(() => store.remove(any())).thenAnswer((_) async {});
      when(firebaseAuth.signOut).thenAnswer((_) async {});
      when(
        () => firebaseAuth.signInWithRedirect(any()),
      ).thenAnswer((_) async {});
      when(googleSignIn.initialize).thenAnswer((_) async {});
      when(googleSignIn.signOut).thenAnswer((_) async {});
    });

    AuthRepositoryImpl repositoryOn(AppPlatform platform) {
      return AuthRepositoryImpl(
        remoteDataSource: AuthRemoteDataSourceImpl(
          firebaseAuth: firebaseAuth,
          firestore: firestore,
          googleSignIn: googleSignIn,
          platform: platform,
          clock: clock,
        ),
        localStore: store,
      );
    }

    T valueOf<T>(Either<Failure, T> result) =>
        result.getOrElse(() => fail('expected a Right, got $result'));

    Failure failureOf<T>(Either<Failure, T> result) =>
        result.fold((failure) => failure, (_) => fail('expected a Left'));

    /// The document the data source provisions, addressed the same way it is.
    DocumentReference<Map<String, dynamic>> profileDocument() =>
        firestore.collection(_usersCollection).doc(ada.id);

    /// The stored profile, read back out of the in-memory Firestore.
    ///
    /// Fails rather than returning null, so a test asserting on the written
    /// fields reports "nothing was written" instead of a null dereference.
    Future<Map<String, dynamic>> storedProfile() async {
      final snapshot = await profileDocument().get();
      final data = snapshot.data();
      if (data == null) {
        fail('expected a profile document at ${snapshot.reference.path}');
      }
      return data;
    }

    /// Whether `users/{ada}` exists at all.
    Future<bool> profileExists() async =>
        (await profileDocument().get()).exists;

    /// A Firebase session for [ada]. [creationTime] is required rather than
    /// defaulted, because "Auth reported no creation time" is a case one of
    /// these tests is specifically about.
    _MockFirebaseUser aFirebaseSession({required DateTime? creationTime}) {
      final metadata = _MockUserMetadata();
      when(() => metadata.creationTime).thenReturn(creationTime);
      final user = _MockFirebaseUser();
      when(() => user.uid).thenReturn(ada.id);
      when(() => user.displayName).thenReturn(ada.name);
      when(() => user.email).thenReturn(ada.email);
      when(() => user.photoURL).thenReturn(ada.photoUrl);
      when(() => user.metadata).thenReturn(metadata);
      return user;
    }

    /// The Google plugin completes with an account carrying [idToken], which
    /// is the whole point of the exchange: it is what Firebase verifies.
    void googleReturns({required String? idToken}) {
      final account = _MockGoogleSignInAccount();
      when(
        () => account.authentication,
      ).thenReturn(GoogleSignInAuthentication(idToken: idToken));
      when(googleSignIn.authenticate).thenAnswer((_) async => account);
    }

    /// Firebase adopts whatever credential it is handed and reports [user].
    void firebaseAdopts(User? user) {
      final credential = _MockUserCredential();
      when(() => credential.user).thenReturn(user);
      when(
        () => firebaseAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => credential);
    }

    /// The Google dialog raised [code] instead of completing.
    void googleThrows(GoogleSignInExceptionCode code) {
      when(googleSignIn.authenticate).thenThrow(
        GoogleSignInException(code: code, description: 'from the test'),
      );
    }

    /// The browser popup completes and Firebase reports [user].
    void popupReturns(User? user) {
      final credential = _MockUserCredential();
      when(() => credential.user).thenReturn(user);
      when(
        () => firebaseAuth.signInWithPopup(any()),
      ).thenAnswer((_) async => credential);
    }

    /// The popup was refused with [code].
    ///
    /// A plain `FirebaseException` rather than a `FirebaseAuthException`,
    /// whose constructor is `@protected` and cannot be built here. It makes no
    /// difference to what is under test: the data source discriminates on
    /// `code`, which is what `firebase_auth_web` fills in after stripping the
    /// `auth/` prefix off the JS SDK's error.
    void popupThrows(String code) {
      when(() => firebaseAuth.signInWithPopup(any())).thenThrow(
        FirebaseException(plugin: 'firebase_auth', code: code),
      );
    }

    /// The redirect a previous page load started came back with [user].
    void redirectReturns(User? user) {
      final credential = _MockUserCredential();
      when(() => credential.user).thenReturn(user);
      when(firebaseAuth.getRedirectResult).thenAnswer((_) async => credential);
    }

    /// Firestore already holds a profile, under a name the user edited.
    ///
    /// Returns the document exactly as it was written, so a test can assert
    /// that provisioning left every field of it alone.
    Future<Map<String, dynamic>> firestoreHoldsProfile() async {
      final stored = <String, dynamic>{
        'name': renamed,
        'email': ada.email,
        'photoUrl': ada.photoUrl,
        'createdAt': Timestamp.fromDate(accountCreatedAt),
      };
      await profileDocument().set(stored);
      return stored;
    }

    group('sign-out is platform-specific (rule 6)', () {
      test('skips the Google plugin in a browser', () async {
        // The plugin is never initialised on web — Firebase owns the GSI
        // lifecycle there — so calling into it throws StateError, which is
        // why this branch exists at all.
        final result = await repositoryOn(const _WebPlatform()).signOut();

        expect(result.isRight(), isTrue);
        verifyNever(googleSignIn.initialize);
        verifyNever(googleSignIn.signOut);
        verify(firebaseAuth.signOut).called(1);
        verify(store.clearAll).called(1);
      });

      test('signs out of Google as well on Android', () async {
        final result = await repositoryOn(const _MobilePlatform()).signOut();

        expect(result.isRight(), isTrue);
        verify(googleSignIn.initialize).called(1);
        verify(googleSignIn.signOut).called(1);
        verify(firebaseAuth.signOut).called(1);
      });

      test('signs out of Firebase even when Google refuses', () async {
        // Swallowed on purpose: otherwise the user taps sign out, is shown an
        // error, and stays signed in to the app itself.
        when(googleSignIn.signOut).thenThrow(StateError('not initialised'));

        final result = await repositoryOn(const _MobilePlatform()).signOut();

        expect(result.isRight(), isTrue);
        verify(firebaseAuth.signOut).called(1);
        verify(store.clearAll).called(1);
      });

      test('signs out of Firebase when Google never initialised', () async {
        when(googleSignIn.initialize).thenThrow(StateError('no play services'));

        final result = await repositoryOn(const _MobilePlatform()).signOut();

        expect(result.isRight(), isTrue);
        verify(firebaseAuth.signOut).called(1);
      });

      test('a failed Firebase sign-out keeps the local data', () async {
        when(firebaseAuth.signOut).thenThrow(
          FirebaseException(plugin: 'firebase_auth', code: 'network-error'),
        );

        final result = await repositoryOn(const _MobilePlatform()).signOut();

        expect(failureOf(result), isA<AuthFailure>());
        verifyNever(store.clearAll);
      });
    });

    group('sign-in is platform-specific (rule 2)', () {
      test('the browser tries the popup and never leaves the page', () async {
        // The popup hands the credential back to this page, so the session is
        // written first-party and nothing has to survive a cross-site
        // navigation. That is the whole reason it goes first.
        popupReturns(aFirebaseSession(creationTime: accountCreatedAt));
        await firestoreHoldsProfile();

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        expect(valueOf(result).name, renamed);
        verify(() => firebaseAuth.signInWithPopup(any())).called(1);
        verifyNever(() => firebaseAuth.signInWithRedirect(any()));
        verifyNever(googleSignIn.authenticate);
      });

      test('a closed popup is a cancellation, not a failure', () async {
        // Rule 5, and it must not become a redirect either: the user closed
        // the window on purpose, and sending them to Google anyway would
        // override a decision they just made.
        popupThrows('popup-closed-by-user');

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        expect(isSignInCancelled(failureOf(result)), isTrue);
        verifyNever(() => firebaseAuth.signInWithRedirect(any()));
      });

      test('a superseded popup request is a cancellation too', () async {
        // What a double tap produces: the second request cancels the first.
        popupThrows('cancelled-popup-request');

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        expect(isSignInCancelled(failureOf(result)), isTrue);
      });

      test('a blocked popup falls back to the redirect', () async {
        popupThrows('popup-blocked');

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        verify(() => firebaseAuth.signInWithRedirect(any())).called(1);
        verify(
          () => store.writeRaw(_redirectNoteKey, _redirectPending),
        ).called(1);
        // The page is on its way to Google; a banner now would be shown for a
        // few milliseconds to a user who is already gone.
        expect(isSignInCancelled(failureOf(result)), isTrue);
      });

      test('an environment with no popup falls back too', () async {
        // A WebView, or a non-http origin. From here it is the same dead end
        // as a blocker: the popup is not available, so try the other flow.
        popupThrows('operation-not-supported-in-this-environment');

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        verify(() => firebaseAuth.signInWithRedirect(any())).called(1);
        expect(isSignInCancelled(failureOf(result)), isTrue);
      });

      test('a browser refusing storage never gets a redirect', () async {
        // `web-storage-unsupported` is the same browser policy that drops a
        // redirect's state, caught before the page is spent on it.
        popupThrows('web-storage-unsupported');

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        expect(isSignInStorageBlocked(failureOf(result)), isTrue);
        verifyNever(() => firebaseAuth.signInWithRedirect(any()));
      });

      test('an unauthorised domain is a real failure', () async {
        // Not a cancellation and not a browser policy: a misconfiguration
        // nobody signs in past, and no other flow would help.
        popupThrows('unauthorized-domain');

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        expect(isSignInCancelled(failureOf(result)), isFalse);
        expect(isSignInStorageBlocked(failureOf(result)), isFalse);
        verifyNever(() => firebaseAuth.signInWithRedirect(any()));
      });

      test('a popup that returns no user is a failure', () async {
        popupReturns(null);

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        expect(isSignInCancelled(failureOf(result)), isFalse);
      });

      test('a rejected redirect is a failure, not a cancellation', () async {
        popupThrows('popup-blocked');
        when(() => firebaseAuth.signInWithRedirect(any())).thenThrow(
          FirebaseException(plugin: 'firebase_auth', code: 'network-error'),
        );

        final result =
            await repositoryOn(const _WebPlatform()).signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        expect(isSignInCancelled(failureOf(result)), isFalse);
        // The page did not move, so the note it would have left must go.
        verify(() => store.remove(_redirectNoteKey)).called(1);
      });

      test('the redirect that came back empty is reported', () async {
        // End to end, on the deployed origin: a redirect left this page, and
        // `getRedirectResult` came back with nothing while no session exists.
        // Silence here is what sends a user who just signed in back to
        // onboarding with no explanation at all.
        when(
          () => store.readRaw(_redirectNoteKey),
        ).thenAnswer((_) async => _redirectPending);
        redirectReturns(null);
        when(() => firebaseAuth.currentUser).thenReturn(null);

        final result =
            await repositoryOn(const _WebPlatform()).getCurrentUser();

        expect(isSignInStorageBlocked(failureOf(result)), isTrue);
        verify(
          () => store.writeRaw(_redirectNoteKey, _redirectUnusable),
        ).called(1);
      });

      test('Android never opens a popup', () async {
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(aFirebaseSession(creationTime: accountCreatedAt));

        await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        verifyNever(() => firebaseAuth.signInWithPopup(any()));
        verifyNever(() => firebaseAuth.signInWithRedirect(any()));
      });

      test('Android exchanges the Google ID token for a session', () async {
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(aFirebaseSession(creationTime: accountCreatedAt));
        await firestoreHoldsProfile();

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(valueOf(result).id, ada.id);
        expect(valueOf(result).name, renamed);
        verify(googleSignIn.initialize).called(1);
        final credential = verify(
          () => firebaseAuth.signInWithCredential(captureAny()),
        ).captured.single as OAuthCredential;
        expect(credential.idToken, 'the-id-token');
      });

      test('a dismissed dialog is a cancellation (rule 5)', () async {
        googleThrows(GoogleSignInExceptionCode.canceled);

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(isSignInCancelled(failureOf(result)), isTrue);
        verifyNever(() => firebaseAuth.signInWithCredential(any()));
      });

      test('an interrupted dialog is a cancellation too', () async {
        // Same outcome reached by a rotation, or by the app being
        // backgrounded under the sheet.
        googleThrows(GoogleSignInExceptionCode.interrupted);

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(isSignInCancelled(failureOf(result)), isTrue);
      });

      test('a missing Activity is an error, not a silent return', () async {
        // `uiUnavailable` is a wiring bug: returning to onboarding in silence
        // would hide it from every user and every bug report.
        googleThrows(GoogleSignInExceptionCode.uiUnavailable);

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        expect(isSignInCancelled(failureOf(result)), isFalse);
      });

      test('an account with no ID token is a failure', () async {
        googleReturns(idToken: null);

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        verifyNever(() => firebaseAuth.signInWithCredential(any()));
      });

      test('a failed plugin initialisation is not memoised', () async {
        // Otherwise every retry after a transient Play Services hiccup
        // replays the same stale failure and the user can never sign in
        // again without restarting the app.
        var attempts = 0;
        when(googleSignIn.initialize).thenAnswer((_) async {
          attempts++;
          if (attempts == 1) throw StateError('play services not ready');
        });
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(aFirebaseSession(creationTime: accountCreatedAt));
        await firestoreHoldsProfile();
        final repository = repositoryOn(const _MobilePlatform());

        final first = await repository.signInWithGoogle();
        final second = await repository.signInWithGoogle();

        expect(failureOf(first), isA<ServerFailure>());
        expect(valueOf(second).id, ada.id);
        verify(googleSignIn.initialize).called(2);
      });
    });

    group('provisioning the profile document (rules 3, 4 and 8)', () {
      test('writes the document when there is none, merged', () async {
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(aFirebaseSession(creationTime: accountCreatedAt));
        // Stages the race the merge is there for: a second device created the
        // document between this one's read and its write. Un-saving the
        // document leaves the other device's field in the store while the
        // read still finds nothing, which is the one state a merged write and
        // an overwriting one disagree about.
        await profileDocument().set(<String, dynamic>{'fromAnotherDevice': 1});
        firestore.removeSavedDocument(profileDocument().path);
        expect(await profileExists(), isFalse);

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(valueOf(result).name, ada.name);
        final document = await storedProfile();
        expect(document['name'], ada.name);
        expect(document['email'], ada.email);
        // Written even when null, because every write here is a merge: an
        // omitted field would keep a photo the user removed.
        expect(document.containsKey('photoUrl'), isTrue);
        expect(document['photoUrl'], ada.photoUrl);
        expect(
          (document['createdAt'] as Timestamp).toDate().toUtc(),
          accountCreatedAt,
        );
        // Merged, so two devices signing in at once cannot blank each other:
        // an overwriting write would have dropped the field below.
        expect(document['fromAnotherDevice'], 1);
      });

      test('a removed Google picture is stored as an explicit null', () async {
        // The other half of `toJson`'s "written even when null": the document
        // has to carry the key, or the merge leaves the URL of a picture the
        // user removed in Firestore forever. Only a Firestore that really
        // stores documents can tell an explicit null from an absent field.
        final withoutPicture = aFirebaseSession(
          creationTime: accountCreatedAt,
        );
        when(() => withoutPicture.photoURL).thenReturn(null);
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(withoutPicture);

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(valueOf(result).photoUrl, isNull);
        final document = await storedProfile();
        expect(document.containsKey('photoUrl'), isTrue);
        expect(document['photoUrl'], isNull);
      });

      test('is idempotent: an existing document is untouched', () async {
        // Rule 3. A retry after a partial failure completes rather than
        // duplicating, and a refresh from the Google display name here would
        // silently undo a rename on every single sign-in.
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(aFirebaseSession(creationTime: accountCreatedAt));
        final untouched = await firestoreHoldsProfile();

        final repository = repositoryOn(const _MobilePlatform());
        final first = await repository.signInWithGoogle();
        final second = await repository.signInWithGoogle();

        expect(valueOf(first).name, renamed);
        expect(valueOf(second).name, renamed);
        // Field for field what it was: a provisioning write would have put
        // the Google display name back over the rename.
        expect(await storedProfile(), untouched);
      });

      test('a Firestore outage yields the credentials profile', () async {
        // Rule 4: an auth success followed by an error screen would be the
        // worst of both.
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(aFirebaseSession(creationTime: accountCreatedAt));
        firestore = _UnreachableFirestore();

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        final profile = valueOf(result);
        expect(profile.id, ada.id);
        expect(profile.name, ada.name);
        expect(profile.email, ada.email);
        expect(profile.createdAt, accountCreatedAt);
      });

      test('getCurrentUser self-heals a missing document', () async {
        // Rule 8: an authenticated user whose document never landed gets one
        // written now instead of being bounced back to onboarding.
        final signedIn = aFirebaseSession(creationTime: accountCreatedAt);
        when(() => firebaseAuth.currentUser).thenReturn(signedIn);
        expect(await profileExists(), isFalse);

        final result =
            await repositoryOn(const _MobilePlatform()).getCurrentUser();

        expect(valueOf(result)?.id, ada.id);
        // Healed for good: the document is really in Firestore now, carrying
        // the Auth credentials, so the next read finds it.
        final document = await storedProfile();
        expect(document['name'], ada.name);
        expect(document['email'], ada.email);
        expect(
          (document['createdAt'] as Timestamp).toDate().toUtc(),
          accountCreatedAt,
        );
      });

      test('getCurrentUser answers null when nobody is signed in', () async {
        when(() => firebaseAuth.currentUser).thenReturn(null);

        final result =
            await repositoryOn(const _MobilePlatform()).getCurrentUser();

        expect(valueOf(result), isNull);
        // Firestore was never consulted at all: no read to fail, and nothing
        // provisioned for a user who is not there.
        expect(firestore.collectionLookups, isZero);
      });

      test('the web session comes from the pending redirect', () async {
        // Reading `currentUser` first races the SDK and bounces a user who
        // just signed in straight back to onboarding: rule 8's redirect race.
        // This is also the only place the redirect is ever consumed.
        redirectReturns(aFirebaseSession(creationTime: accountCreatedAt));
        await firestoreHoldsProfile();

        final result =
            await repositoryOn(const _WebPlatform()).getCurrentUser();

        expect(valueOf(result)?.name, renamed);
        verifyNever(() => firebaseAuth.currentUser);
      });

      test('createdAt falls back to the injected clock', () async {
        // The only sanctioned "now" in the app: a provider that reported no
        // account metadata must not send the code to DateTime.now().
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(aFirebaseSession(creationTime: null));

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(valueOf(result).createdAt, bootInstant);
        // And that is the instant that reached Firestore, rather than a
        // second, later reading taken at write time.
        final document = await storedProfile();
        expect(
          (document['createdAt'] as Timestamp).toDate().toUtc(),
          bootInstant,
        );
      });

      test('a Firebase session with no user is a failure', () async {
        googleReturns(idToken: 'the-id-token');
        firebaseAdopts(null);

        final result =
            await repositoryOn(const _MobilePlatform()).signInWithGoogle();

        expect(failureOf(result), isA<AuthFailure>());
        expect(isSignInCancelled(failureOf(result)), isFalse);
        // The failure lands before provisioning, so nothing was written for a
        // session that does not exist.
        expect(firestore.collectionLookups, isZero);
      });
    });
  });
}

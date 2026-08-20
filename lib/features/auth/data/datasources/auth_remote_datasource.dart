import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/platform/app_platform.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/features/auth/data/models/user_model.dart';

/// Firebase's half of authentication: the Google flow, the live session, and
/// the `users/{userId}` profile document.
///
/// Everything here throws (`AuthException`, `ServerException`) and returns
/// models; turning that into `Either<Failure, T>` is the repository's job
/// (see `exceptions.dart`).
///
/// The one nullable return worth naming is [signInWithGoogle]'s: `null` means
/// *nothing happened* — no session, no error — which is what a dismissed
/// dialog and a page that is navigating away have in common.
abstract class AuthRemoteDataSource {
  /// Runs the platform's Google flow and returns the resulting session as a
  /// credentials-only profile, or `null` when the user did not complete it.
  ///
  /// Throws [AuthException] when the flow genuinely failed.
  Future<UserModel?> signInWithGoogle();

  /// The current session as a credentials-only profile, or `null` when signed
  /// out. On web this is also where a pending redirect is consumed.
  Future<UserModel?> currentAuthUser();

  /// Returns the stored profile for [authUser], writing it first when the
  /// document does not exist yet. Idempotent (rule 3).
  ///
  /// Throws [ServerException] when Firestore refuses the read or the write.
  Future<UserModel> ensureProfile(UserModel authUser);

  /// Ends the session on Google (where applicable) and on Firebase.
  Future<void> signOut();

  /// Session changes as credentials-only profiles. Emits `null` on sign-out.
  Stream<UserModel?> get authStateChanges;
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  AuthRemoteDataSourceImpl({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
    required GoogleSignIn googleSignIn,
    required AppPlatform platform,
    required Clock clock,
  }) : _firebaseAuth = firebaseAuth,
       _firestore = firestore,
       _googleSignIn = googleSignIn,
       _platform = platform,
       _clock = clock;

  /// The one collection this app reads by id and never queries (CLAUDE.md,
  /// Firestore Rules).
  static const String _usersCollection = 'users';

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;
  final AppPlatform _platform;
  final Clock _clock;

  /// The memoised `GoogleSignIn.initialize()` future; see
  /// [_ensureGoogleSignInReady].
  Future<void>? _googleSignInReady;

  @override
  Future<UserModel?> signInWithGoogle() {
    // One method, two flows (rule 2). The browser cannot use a popup without
    // tripping COOP in several browsers, and Android has no redirect to come
    // back from, so neither flow can serve both.
    return _platform.isWeb ? _startWebRedirect() : _authenticateWithPlugin();
  }

  @override
  Future<UserModel?> currentAuthUser() async {
    final user = await _resolveSession();
    return user == null ? null : _profileFromSession(user);
  }

  @override
  Future<UserModel> ensureProfile(UserModel authUser) async {
    // Only the profile document is written here. The board and the
    // preferences documents are `SyncService`'s to provision: it already
    // treats a missing remote document as `revision: -1` and uploads the
    // local one (docs/specs/sync.md, Provisioning), and a second writer with
    // its own idea of the defaults is how two devices end up disagreeing
    // about an empty board.
    try {
      final reference =
          _firestore.collection(_usersCollection).doc(authUser.id);
      final snapshot = await reference.get();

      // Read, then create only when absent. That is what makes provisioning
      // idempotent (rule 3): a retry after a partial failure finds the
      // document and stops, instead of writing a second one. An existing
      // profile is returned untouched rather than refreshed from the Auth
      // credentials, because `ProfileRepository.updateProfile` owns `name`
      // and a refresh here would silently undo a rename on every sign-in.
      if (snapshot.exists) return UserModel.fromFirestore(snapshot);

      // Merged rather than overwritten so two devices signing in at the same
      // moment cannot blank each other's write.
      await reference.set(authUser.toJson(), SetOptions(merge: true));
      return authUser;
    } on FirebaseException catch (error) {
      throw ServerException(_describe(error));
    }
  }

  @override
  Future<void> signOut() async {
    await _signOutOfGoogle();
    try {
      await _firebaseAuth.signOut();
    } on FirebaseException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  @override
  Stream<UserModel?> get authStateChanges {
    // Credentials only, with no Firestore read per event. The stream answers
    // "who is signed in"; the stored profile is `ProfileCubit`'s to load. A
    // read here would put a network round trip, and a second failure mode, on
    // every session change.
    return _firebaseAuth.authStateChanges().map(
      (user) => user == null ? null : _profileFromSession(user),
    );
  }

  /// Web: hand the page to Google and let it come back (rule 2).
  Future<UserModel?> _startWebRedirect() async {
    try {
      await _firebaseAuth.signInWithRedirect(GoogleAuthProvider());
    } on FirebaseException catch (error) {
      throw AuthException(_describe(error));
    }
    // Unreachable in a real browser: the call above navigates away, and the
    // session is picked up by [currentAuthUser] on the way back. A browser
    // that blocked the navigation lands here, and "nothing happened" is
    // exactly the cancelled outcome (rule 5), not an error worth a banner.
    return null;
  }

  /// Android: the plugin authenticates, Firebase adopts the credential.
  Future<UserModel?> _authenticateWithPlugin() async {
    try {
      await _ensureGoogleSignInReady();
      final account = await _googleSignIn.authenticate();

      // The ID token is the whole point of the exchange: it is what Firebase
      // verifies. `google_sign_in` 7.x keeps access tokens behind
      // `authorizationClient`, and this app asks for no OAuth scopes, so the
      // credential is built from the ID token alone.
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthException('Google returned no ID token.');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final session = await _firebaseAuth.signInWithCredential(credential);
      final user = session.user;
      if (user == null) {
        throw const AuthException('Firebase returned no user.');
      }
      return _profileFromSession(user);
    } on GoogleSignInException catch (error) {
      if (_isDialogDismissal(error.code)) return null;
      throw AuthException('Google sign-in failed (${error.code.name}).');
    } on FirebaseException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  /// Whether [code] means the user simply never answered the dialog (rule 5).
  ///
  /// `canceled` is the dismissal itself; `interrupted` is the same outcome
  /// reached by the sheet being torn down under the user, by a rotation or by
  /// the app being backgrounded. `uiUnavailable` is deliberately absent: no
  /// Activity to show the dialog on is a wiring bug, and returning to
  /// onboarding in silence would hide it from every user and every bug report.
  ///
  /// Compared rather than switched because the plugin documents this enum as
  /// open: new codes are explicitly not a breaking change.
  bool _isDialogDismissal(GoogleSignInExceptionCode code) {
    return code == GoogleSignInExceptionCode.canceled ||
        code == GoogleSignInExceptionCode.interrupted;
  }

  /// The Firebase session, resolving a pending web redirect first.
  Future<User?> _resolveSession() async {
    if (!_platform.isWeb) return _firebaseAuth.currentUser;

    // On web the session a redirect just produced only becomes observable
    // once `getRedirectResult` has resolved, so reading `currentUser` first
    // races the SDK and bounces a user who just signed in straight back to
    // onboarding — auth.md rule 8's "classic web-redirect race". This is also
    // the only place the redirect opened by [_startWebRedirect] is consumed.
    // The call is web-only because the platform interface leaves it
    // unimplemented everywhere else.
    try {
      final redirected = await _firebaseAuth.getRedirectResult();
      return redirected.user ?? _firebaseAuth.currentUser;
    } on FirebaseException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  /// Initialises `google_sign_in` once, on the Android path only.
  ///
  /// The plugin requires `initialize()` to have completed before any other
  /// call and documents a second call as undefined behaviour, so the future is
  /// memoised instead of the call being repeated. Web never reaches this:
  /// there, Firebase's redirect flow owns the GSI lifecycle and the plugin is
  /// left uninitialised on purpose (rule 6).
  Future<void> _ensureGoogleSignInReady() async {
    final pending = _googleSignInReady ??= _googleSignIn.initialize();
    try {
      await pending;
    } on Object {
      // A failed initialisation must not stay memoised, or every retry after
      // a transient Play Services hiccup replays the same stale failure and
      // the user can never sign in again without restarting the app.
      _googleSignInReady = null;
      rethrow;
    }
  }

  /// Google's half of signing out, which must never block Firebase's half.
  Future<void> _signOutOfGoogle() async {
    // Skipped entirely on web: the plugin was never initialised there, and
    // calling into an uninitialised plugin throws `StateError` (rule 6).
    if (_platform.isWeb) return;
    try {
      await _ensureGoogleSignInReady();
      await _googleSignIn.signOut();
    } on Object catch (_) {
      // Swallowed on purpose. Whatever Google's SDK thinks, `signOut` below
      // must still run, or the user taps "sign out", is shown an error, and
      // stays signed in to the app itself.
    }
  }

  /// The Auth credentials as a profile, with no Firestore involved.
  UserModel _profileFromSession(User user) {
    return UserModel.fromAuth(
      id: user.uid,
      name: user.displayName,
      email: user.email,
      photoUrl: user.photoURL,
      // Auth's own account metadata is the true "first sign-in" instant and
      // is the same on every device; the injected clock only covers a
      // provider that reported none.
      createdAt: user.metadata.creationTime?.toUtc() ?? _clock.nowUtc(),
    );
  }

  /// Developer-facing text for a Firebase error.
  ///
  /// The code travels because it is what makes a log actionable. It never
  /// reaches a user: the UI picks its string from the failure *type*
  /// (`failures.dart`).
  String _describe(FirebaseException error) {
    return '${error.plugin} rejected the request (${error.code}).';
  }
}

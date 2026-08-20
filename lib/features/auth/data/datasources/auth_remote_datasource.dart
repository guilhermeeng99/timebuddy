import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/platform/app_platform.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/features/auth/data/models/user_model.dart';

/// What one attempt at the platform's Google flow produced, short of an
/// outright error.
///
/// This used to be a nullable [UserModel], where `null` stood for "nothing
/// happened". Three different nothings hid behind it once the browser stopped
/// redirecting unconditionally (docs/specs/auth.md rule 2), and the one that
/// matters — the browser refusing to keep the state the flow needs — is
/// invisible if it shares a value with a dismissed dialog. A sealed family
/// makes the compiler ask the repository about each of them.
sealed class GoogleSignInOutcome {
  const GoogleSignInOutcome();
}

/// The flow completed. [session] is the credentials-only profile it produced.
final class GoogleSignInSucceeded extends GoogleSignInOutcome {
  const GoogleSignInSucceeded(this.session);

  final UserModel session;
}

/// The user walked away: the Android dialog was dismissed, or the browser
/// popup was closed (rule 5). Not an error, and never a banner.
final class GoogleSignInCancelled extends GoogleSignInOutcome {
  const GoogleSignInCancelled();
}

/// The browser refused to open the popup at all.
///
/// Web only, and recoverable: a full-page redirect is not a popup, so the
/// repository can fall back to one. The user did nothing wrong and, in the
/// common case, has nothing to do about it either.
final class GoogleSignInPopupUnavailable extends GoogleSignInOutcome {
  const GoogleSignInPopupUnavailable();
}

/// The browser refused Firebase the storage the flow needs to finish.
///
/// Web only. This is the *loud* form of the failure rule 2 is about: the same
/// browser policy that silently drops a redirect's state on the way back can
/// also reject the popup up front, and when it does there is no point
/// redirecting — the round trip would only lose the state again, in silence.
final class GoogleSignInStorageBlocked extends GoogleSignInOutcome {
  const GoogleSignInStorageBlocked();
}

/// Firebase's half of authentication: the Google flow, the live session, and
/// the `users/{userId}` profile document.
///
/// Everything here throws (`AuthException`, `ServerException`) and returns
/// models; turning that into `Either<Failure, T>` is the repository's job
/// (see `exceptions.dart`).
///
/// Which browser flow runs is *not* decided here beyond the first attempt:
/// this class reports what the browser did and the repository owns the policy,
/// because deciding whether a redirect is still worth trying needs a memory
/// that outlives the page, and only the repository has one.
abstract class AuthRemoteDataSource {
  /// Runs the platform's Google flow without leaving the page: the popup in a
  /// browser, the `google_sign_in` plugin on Android (rule 2).
  ///
  /// Throws [AuthException] when the flow genuinely failed. Everything the
  /// caller is expected to react to comes back as a [GoogleSignInOutcome].
  Future<GoogleSignInOutcome> signInWithGoogle();

  /// Web only: hands the whole page to Google's redirect flow.
  ///
  /// Returns while the browser is still unloading the page, so a caller gets
  /// no session out of it; the result arrives on the next boot, through
  /// [currentAuthUser]. Called only after [signInWithGoogle] reported
  /// [GoogleSignInPopupUnavailable], which no non-web platform can produce.
  ///
  /// Throws [AuthException] when the browser rejected the navigation itself.
  Future<void> startGoogleRedirect();

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

  /// Codes that mean the user closed the popup rather than finishing in it.
  ///
  /// `cancelled-popup-request` is a second sign-in superseding the first,
  /// which a double tap produces routinely; `user-cancelled` is the consent
  /// screen being declined. All three are decisions, not errors (rule 5).
  static const Set<String> _popupDismissalCodes = {
    'popup-closed-by-user',
    'cancelled-popup-request',
    'user-cancelled',
  };

  /// Codes that mean the popup never opened.
  ///
  /// `operation-not-supported-in-this-environment` is what a WebView or a
  /// non-http origin answers, which is the same dead end as a popup blocker
  /// from the caller's side: the popup is not available, try the other flow.
  static const Set<String> _popupUnavailableCodes = {
    'popup-blocked',
    'operation-not-supported-in-this-environment',
  };

  /// The code Firebase raises when the browser denies it session storage.
  ///
  /// Matched on the code rather than on `FirebaseAuthException`, whose
  /// constructor is `@protected` and so cannot be built by a test. The code is
  /// the stable contract anyway: `firebase_auth_web` strips the `auth/` prefix
  /// off the JS SDK's error and hands the rest through untouched.
  static const String _storageUnsupportedCode = 'web-storage-unsupported';

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;
  final AppPlatform _platform;
  final Clock _clock;

  /// The memoised `GoogleSignIn.initialize()` future; see
  /// [_ensureGoogleSignInReady].
  Future<void>? _googleSignInReady;

  @override
  Future<GoogleSignInOutcome> signInWithGoogle() {
    // One method, two flows (rule 2). The browser opens a popup because that
    // is the only web flow whose result lands in the app origin's own
    // storage; Android has no popup and drives the plugin instead.
    return _platform.isWeb
        ? _authenticateWithPopup()
        : _authenticateWithPlugin();
  }

  @override
  Future<void> startGoogleRedirect() async {
    try {
      await _firebaseAuth.signInWithRedirect(GoogleAuthProvider());
    } on FirebaseException catch (error) {
      throw AuthException(_describe(error));
    }
    // Nothing follows in a real browser: the call above unloads the page, and
    // the session is picked up by [currentAuthUser] on the way back.
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

  /// Web: sign in inside a popup, so the session is written first-party.
  ///
  /// The popup hands the credential back to this page and the session is
  /// stored on the app's own origin. Nothing has to survive a cross-site
  /// navigation, which is the whole reason this is tried first (rule 2).
  Future<GoogleSignInOutcome> _authenticateWithPopup() async {
    try {
      final session = await _firebaseAuth.signInWithPopup(GoogleAuthProvider());
      final user = session.user;
      if (user == null) {
        throw const AuthException('Firebase returned no user.');
      }
      return GoogleSignInSucceeded(_profileFromSession(user));
    } on FirebaseException catch (error) {
      return _readPopupRefusal(error);
    }
  }

  /// Why the popup did not produce a session, in the caller's vocabulary.
  ///
  /// Three refusals, three different answers, and the difference is the whole
  /// point: a closed popup must be silent, a blocked one must be retried
  /// another way, and a browser withholding storage must be *said out loud*,
  /// because no amount of retrying will change it.
  GoogleSignInOutcome _readPopupRefusal(FirebaseException error) {
    final code = _bareCode(error.code);
    if (_popupDismissalCodes.contains(code)) {
      return const GoogleSignInCancelled();
    }
    if (code == _storageUnsupportedCode) {
      return const GoogleSignInStorageBlocked();
    }
    if (_popupUnavailableCodes.contains(code)) {
      return const GoogleSignInPopupUnavailable();
    }
    // Everything else — `unauthorized-domain`, `network-request-failed`,
    // `account-exists-with-different-credential` — is a real failure, and one
    // the user cannot fix by tapping the button again in a different browser.
    throw AuthException(_describe(error));
  }

  /// The error code without the `auth/` namespace the web SDK keeps.
  ///
  /// On Android and iOS the plugin hands over a bare `popup-blocked`, but
  /// `firebase_auth_web` forwards the JavaScript SDK's code verbatim, and
  /// there it reads `auth/popup-blocked`. Matching the bare form only meant
  /// that on the web every branch below missed, a blocked pop-up fell through
  /// to "a real failure the user cannot fix", and the redirect fallback that
  /// exists for exactly this case never ran. Verified against the deployed
  /// build: the browser raised `auth/popup-blocked` and sign-in was
  /// impossible on the web.
  ///
  /// Stripping rather than listing both spellings, so a code added later
  /// cannot reintroduce the same asymmetry.
  static String _bareCode(String code) {
    const namespace = 'auth/';
    return code.startsWith(namespace) ? code.substring(namespace.length) : code;
  }

  /// Android: the plugin authenticates, Firebase adopts the credential.
  Future<GoogleSignInOutcome> _authenticateWithPlugin() async {
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
      return GoogleSignInSucceeded(_profileFromSession(user));
    } on GoogleSignInException catch (error) {
      if (_isDialogDismissal(error.code)) {
        return const GoogleSignInCancelled();
      }
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
    // the only place the redirect opened by [startGoogleRedirect] is
    // consumed. It runs on every web boot, not only after a redirect: a page
    // that skipped it would read `currentUser` before the SDK had finished
    // restoring one. The call is web-only because the platform interface
    // leaves it unimplemented everywhere else.
    //
    // A null user here is *not* proof that nothing happened. It is also what
    // a browser that dropped the redirect's state answers, and the repository
    // is the only layer that can tell those apart (rule 2).
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
  /// there, Firebase owns the GSI lifecycle and the plugin is left
  /// uninitialised on purpose (rule 6).
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
    return '${error.plugin} rejected the request (${_bareCode(error.code)}).';
  }
}

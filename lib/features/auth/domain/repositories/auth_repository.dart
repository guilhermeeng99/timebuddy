import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';

/// The exact [AuthFailure.message] a sign-in nobody completed carries.
///
/// Rule 5 needs "the user closed the dialog" to be distinguishable from "the
/// sign-in failed", because the first must return to onboarding in silence and
/// the second must show a banner. `Failure` is a sealed family and
/// `AuthFailure` is `final`, so a `CancelledAuthFailure` subtype cannot be
/// declared outside `failures.dart`; the marker therefore travels in the one
/// field the family already has. That field is developer-facing and never
/// rendered (see `failures.dart`), so a sentinel there costs the user nothing.
///
/// Read it through [isSignInCancelled], never by comparing strings at a call
/// site.
const String signInCancelledMarker = 'auth.signIn.cancelled';

/// The value [AuthRepository.signInWithGoogle] answers with when the user
/// walked away from the Google dialog, or when the web redirect left without
/// producing a session.
const AuthFailure signInCancelledFailure = AuthFailure(signInCancelledMarker);

/// Whether [failure] is a cancellation rather than a real error.
///
/// ```dart
/// result.fold(
///   (failure) => isSignInCancelled(failure)
///       ? emit(const Unauthenticated())   // back to onboarding, no banner
///       : emit(AuthError(failure)),
///   (user) => emit(Authenticated(user)),
/// );
/// ```
bool isSignInCancelled(Failure failure) =>
    failure is AuthFailure && failure.message == signInCancelledMarker;

/// Everything the app is allowed to ask about the current session.
///
/// Google-only, by design: there is no email/password sign-in and no sign-up
/// form, so the unauthenticated landing is the onboarding page rather than a
/// `SignInPage` (docs/specs/auth.md). There is likewise no `signUp`, because
/// the first successful Google sign-in *is* the sign-up (rule 3).
///
/// ```dart
/// final result = await repository.signInWithGoogle();
/// result.fold(
///   (failure) => isSignInCancelled(failure) ? goBack() : showError(failure),
///   (user) => openApp(user),
/// );
/// ```
abstract class AuthRepository {
  /// Runs the platform's Google flow and provisions the profile document on a
  /// first sign-in.
  ///
  /// Which flow runs is a platform question (rule 2): the browser redirects,
  /// because a popup trips COOP in several browsers, and Android drives the
  /// `google_sign_in` plugin. Both land here, so no caller branches on it.
  ///
  /// Degrades rather than fails when Firestore is unreachable: a session that
  /// authenticated successfully comes back as a profile built from the Auth
  /// credentials alone (rule 4), and the next sync reconciles the rest.
  ///
  /// Answers [signInCancelledFailure] when nothing happened — the dialog was
  /// dismissed, or the redirect is navigating away (rule 5).
  Future<Either<Failure, UserEntity>> signInWithGoogle();

  /// Ends the session and wipes the local cache (rule 7).
  ///
  /// The order is load-bearing: local data is cleared only *after* the remote
  /// sign-out succeeded, so a failed sign-out never leaves the user signed in
  /// with an empty board (auth.md, Edge Cases).
  Future<Either<Failure, void>> signOut();

  /// The session as it stands, or `Right(null)` when nobody is signed in.
  ///
  /// Self-heals a missing profile document (rule 8): an authenticated user
  /// whose Firestore document never landed, which is the classic web-redirect
  /// race, gets one written instead of being bounced back to onboarding.
  Future<Either<Failure, UserEntity?>> getCurrentUser();

  /// Session changes. Emits `null` when signed out.
  ///
  /// Never surfaces a stream error (rule 9): a failure while mapping an event
  /// is folded into `null`, because an unhandled error on this stream reaches
  /// the zone guard and takes the whole app down, while a spurious "signed
  /// out" costs one tap.
  Stream<UserEntity?> get authStateChanges;
}

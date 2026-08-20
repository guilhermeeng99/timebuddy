import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';

/// State of `AuthBloc`: who the app believes is signed in.
///
/// There is deliberately no `AccessDenied` state. TimeBuddy has no allowlist,
/// so every Google account is welcome and there is nothing to deny
/// (docs/specs/auth.md rule 11).
///
/// ```dart
/// switch (state) {
///   Authenticated(:final user) => ProfileHeader(user: user),
///   AuthLoading() => const CircularProgressIndicator(),
///   _ => const OnboardingPage(),
/// }
/// ```
sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => const [];
}

/// What stopped a sign-in, when the answer is something the user can act on.
///
/// An enum rather than the `Failure` itself, because the two failures behind
/// it are told apart by markers that live in the data layer
/// (`auth_repository_impl.dart`, docs/specs/auth.md rule 2). Translating them
/// once, inside the bloc, keeps every page off the marker strings and makes
/// the copy a `switch` with no default: a third obstacle added later is a
/// compile error on the page instead of a silent fall through to the generic
/// "sign-in didn't go through", which is the message these exist not to be.
enum SignInBlock {
  /// The browser would not give Firebase the storage the sign-in needs: a
  /// redirect that came back empty, or a popup refused for want of storage.
  ///
  /// There is no in-app remedy — the flow needs storage this browser
  /// partitions away — so the advice is to try another browser or to allow
  /// cross-site cookies for this site.
  storage,

  /// The pop-up was blocked, and the redirect fallback is already known not
  /// to survive this browser.
  ///
  /// The one obstacle with an exact remedy the user can carry out: allow
  /// pop-ups for this site and press the button again.
  popup,
}

/// Nothing has been asked yet. Only the frames between `main` and the startup
/// flow's `AuthCheckRequested` see this.
final class AuthInitial extends AuthState {
  const AuthInitial();
}

/// A sign-in the user started is running.
///
/// Reserved for that one operation. The session *check* does not pass through
/// here — the splash is already covering it — and neither does sign-out, whose
/// answer arrives in a frame or two (docs/specs/auth.md, State Machine).
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// There is a session, and this is who it belongs to.
final class Authenticated extends AuthState {
  const Authenticated(this.user);

  final UserEntity user;

  @override
  List<Object?> get props => [user];
}

/// Nobody is signed in. The landing for this state is the onboarding page:
/// there is no `SignInPage` and no guest mode (docs/specs/auth.md rule 1).
///
/// [blockedBy] is the difference between "you have not signed in yet" and "a
/// sign-in was attempted here and the browser would not carry it through"
/// (rule 2). Both leave the user on this exact page in front of that exact
/// button; only one of them has something to say.
///
/// **Why a field and not a sixth state**, since the alternative was tried:
///
/// * The app *is* in the state this class names. `AuthError` means an
///   operation failed while the session stayed as it was — the failed
///   sign-out that shaped it leaves the user very much signed in — and
///   `startup_cubit` and `profile_page` both already re-read `AuthError` as
///   "signed out" precisely because that is not what it means.
/// * The diagnosis has to survive a router redirect and several frames: it is
///   produced by the boot-leg check on the splash and read on the onboarding
///   page that replaces it. A state meaning "signed out" travels that route
///   untouched; an error state has to be mapped back to signed out by
///   everything on the way, which is exactly the folding that swallowed this
///   diagnosis before.
/// * `AuthState` is sealed, and `ProfilePage` switches over it with all five
///   cases spelled out and no wildcard. A sixth state is a compile error in a
///   file that has nothing to do with browser storage.
final class Unauthenticated extends AuthState {
  const Unauthenticated({this.blockedBy});

  /// Why the last attempt left the user here, or `null` for an ordinary
  /// signed-out session — a first launch, a cancelled dialog (rule 5), or a
  /// sign-out.
  final SignInBlock? blockedBy;

  // Part of the props, so the plain signed-out state and the one carrying
  // advice are different values. Were it left out, `emit` would see the two
  // as equal and drop the diagnosis as a no-op change.
  @override
  List<Object?> get props => [blockedBy];
}

/// An operation failed for a reason worth showing.
///
/// A *cancelled* sign-in never lands here: dismissing the Google dialog is not
/// an error, so it resolves to [Unauthenticated] and the user is back on
/// onboarding with no red banner (docs/specs/auth.md rule 5). Neither does a
/// browser that blocked the sign-in: that is a signed-out session with advice
/// attached, and it travels as [Unauthenticated.blockedBy].
///
/// [failure] steers the icon and the localized copy; its `message` is a
/// developer string and is never rendered (see `failures.dart`).
final class AuthError extends AuthState {
  const AuthError(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

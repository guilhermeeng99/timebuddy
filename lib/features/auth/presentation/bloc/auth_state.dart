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
final class Unauthenticated extends AuthState {
  const Unauthenticated();
}

/// An operation failed for a reason worth showing.
///
/// A *cancelled* sign-in never lands here: dismissing the Google dialog is not
/// an error, so it resolves to [Unauthenticated] and the user is back on
/// onboarding with no red banner (docs/specs/auth.md rule 5).
///
/// [failure] steers the icon and the localized copy; its `message` is a
/// developer string and is never rendered (see `failures.dart`).
final class AuthError extends AuthState {
  const AuthError(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

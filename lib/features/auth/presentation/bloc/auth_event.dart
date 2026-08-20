import 'package:equatable/equatable.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';

/// Everything that can move `AuthBloc`.
///
/// A `Bloc` and not a `Cubit` because the session changes from two directions
/// at once (CLAUDE.md, State Management): the user taps sign in or sign out,
/// and Firebase publishes a session change nobody on this device asked for.
/// Both arrive here as events, so the transition table in docs/specs/auth.md
/// is one queue with one handler per row, rather than two code paths racing to
/// emit over each other.
///
/// ```dart
/// context.read<AuthBloc>().add(const AuthGoogleSignInRequested());
/// ```
sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => const [];
}

/// Is there already a session? Asked once, by the startup flow.
final class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

/// The Google button on the onboarding page's last slide.
///
/// It carries nothing: the app is Google-only, so there is no credential to
/// pass and no second provider to name (docs/specs/auth.md).
final class AuthGoogleSignInRequested extends AuthEvent {
  const AuthGoogleSignInRequested();
}

/// The confirmed sign-out from the profile page.
///
/// Dispatched only after the user answered the confirmation dialog, because
/// signing out clears the local board (rule 7) and an accidental tap would
/// look like data loss.
final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Internal: one event from `AuthRepository.authStateChanges`.
///
/// An event rather than a direct emit, so a session change that arrives from
/// the server queues behind whatever the user just started instead of
/// overtaking it halfway through.
final class AuthUserChanged extends AuthEvent {
  const AuthUserChanged(this.user);

  /// The session Firebase now reports, or `null` for "signed out": an expired
  /// token, a revoked account, or a sign-out performed in another browser tab.
  final UserEntity? user;

  @override
  List<Object?> get props => [user];
}

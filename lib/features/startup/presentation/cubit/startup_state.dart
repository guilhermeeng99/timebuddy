import 'package:equatable/equatable.dart';

/// State of `StartupCubit`: the gate between "the app process exists" and "a
/// screen the user can trust" (docs/specs/startup.md).
///
/// Deliberately free of user-facing strings. [StartupError] carries no field
/// at all and [StartupLoading] carries only a number, so every visible label
/// is localized by `StartupPage` and the cubit stays testable without slang.
sealed class StartupState extends Equatable {
  const StartupState();

  @override
  List<Object?> get props => const [];
}

/// Before `initialize()` runs. Only the frame between the route building the
/// page and its `initState` sees this.
final class StartupInitial extends StartupState {
  const StartupInitial();
}

/// Work is in flight; [progress] says how much of it is behind us.
///
/// The three sentinels below are the cubit's whole vocabulary (rule 9), and
/// they live here rather than inside the cubit because the page picks its step
/// label by comparing against them: two copies of `0.6` in two files is one
/// edit away from a label that lies.
final class StartupLoading extends StartupState {
  const StartupLoading({this.progress = startedProgress});

  /// Emitted on entry, before anything has been attempted. Always emitted,
  /// whatever `AuthBloc` already holds, so the splash animates in the same way
  /// on a cold start and on a retry (rule 3).
  static const double startedProgress = 0;

  /// The timezone engine and the city catalog are both ready; auth is next.
  static const double preparedProgress = 0.3;

  /// Auth resolved to a signed-in user; the first sync is running.
  static const double syncingProgress = 0.6;

  /// How far along startup is, from 0 to 1.
  ///
  /// A number rather than a step enum because the page renders a progress
  /// bar from it *and* derives the step label from it; an enum would need a
  /// second mapping back to a fraction.
  final double progress;

  @override
  List<Object?> get props => [progress];
}

/// Terminal: a session exists and the first sync has been attempted.
///
/// [syncFailed] is `true` when the sync failed outright or ran past its time
/// box (rules 7 and 8). It is **not** an error state: TimeBuddy has a usable
/// local board, so the app opens either way and the passive sync indicator
/// explains the rest (docs/specs/sync.md rule 4).
final class StartupAuthenticated extends StartupState {
  const StartupAuthenticated({required this.userId, required this.syncFailed});

  /// Firebase Auth UID of the session that resolved.
  final String userId;

  /// Whether the first sync came back empty-handed.
  final bool syncFailed;

  @override
  List<Object?> get props => [userId, syncFailed];
}

/// Terminal: nobody is signed in, so the router sends the user to onboarding.
///
/// `AuthError` lands here too (rule 5): a failed session check reads as
/// "signed out", and onboarding is where the user can retry the Google flow.
final class StartupUnauthenticated extends StartupState {
  const StartupUnauthenticated();
}

/// The engine or the catalog failed, which is the one unrecoverable case
/// (rule 10).
///
/// Field-less on purpose: the raw exception is logged for a developer and the
/// page owns the localized copy, because a user cannot act on
/// `PlatformException(channel-error)` and should never read it.
final class StartupError extends StartupState {
  const StartupError();
}

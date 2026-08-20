import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/sync/sync_coordinator.dart';
// Imported for the two predicates only, and named so that is visible. The
// markers they read belong beside the repository contract and are documented
// as living in the implementation "for now" (docs/specs/auth.md, Failure
// markers); when they move, this line follows them and nothing else here
// changes. Reading them here rather than on a page is the point: one
// translation into `SignInBlock`, and no widget ever sees a marker string.
import 'package:timebuddy/features/auth/data/repositories/auth_repository_impl.dart'
    show isSignInPopupBlocked, isSignInStorageBlocked;
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/domain/repositories/auth_repository.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_event.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_state.dart';

// Re-exported so a widget that imports the bloc also gets its events and
// states, the way a `part`-based bloc would, without giving up the standalone
// files.
export 'package:timebuddy/features/auth/presentation/bloc/auth_event.dart';
export 'package:timebuddy/features/auth/presentation/bloc/auth_state.dart';

/// The session, as one state machine (docs/specs/auth.md, State Machine).
///
/// Registered as a singleton and provided app-wide: the router redirect, the
/// startup cubit and the profile page all have to agree on who is signed in,
/// and a second instance is a second answer to that question.
///
/// It subscribes to `AuthRepository.authStateChanges` in its constructor, so a
/// session revoked on the server, or ended in another browser tab, arrives as
/// an [AuthUserChanged] event rather than being noticed on the next API call.
///
/// **A cancelled sign-in is not an error.** Dismissing the Google dialog
/// resolves to [Unauthenticated], which puts the user back on onboarding with
/// no banner (rule 5). Only a genuine failure reaches [AuthError].
///
/// **A blocked sign-in is not an error either, and not silence.** A browser
/// that dropped the sign-in state, or blocked the popup once the redirect is
/// known not to work here, leaves the user signed out with something they can
/// act on. That travels as [Unauthenticated.blockedBy] from *both* legs — the
/// boot-leg check a redirect lands on, and the sign-in the user started — so
/// onboarding draws one answer for one situation (rule 2).
///
/// ```dart
/// BlocProvider.value(
///   value: sl<AuthBloc>()..add(const AuthCheckRequested()),
///   child: const OnboardingPage(),
/// );
/// ```
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthRepository repository,
    required SyncCoordinator syncCoordinator,
  }) : _repository = repository,
       _syncCoordinator = syncCoordinator,
       super(const AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthGoogleSignInRequested>(_onGoogleSignInRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthUserChanged>(_onUserChanged);

    // Subscribed here rather than from an event, so the app cannot forget to
    // start listening: the stream never errors (rule 9), so there is nothing
    // to handle and nothing that can take the app down.
    _sessionSubscription = _repository.authStateChanges.listen(
      (user) => add(AuthUserChanged(user)),
    );
  }

  /// Attaches and detaches the account the background pushes write to.
  ///
  /// Here rather than in a listener somewhere in the widget tree, because this
  /// is the one place that sees every terminal auth state, including the one a
  /// warm start produces before any widget has mounted. A listener would have
  /// to seed itself from the current state as well, and forgetting that is a
  /// silently signed-out coordinator: edits keep working, they just stop
  /// reaching the server (docs/specs/sync.md rules 2 and 3).
  ///
  /// Every [Unauthenticated] ends the session, diagnosis or not: a sign-in the
  /// browser blocked is still nobody signed in.
  ///
  /// Two states deliberately do NOT end the session:
  ///
  /// * `AuthError`, because a failed sign-out means the user is still signed
  ///   in (auth.md Edge Cases). Detaching there would strand their pending
  ///   writes while the account is very much alive.
  /// * `AuthLoading`, because Firebase publishes a null user while the Google
  ///   dialog is open, and treating that as a sign-out would drop the session
  ///   in the middle of signing in.
  @override
  void onChange(Change<AuthState> change) {
    super.onChange(change);
    final next = change.nextState;
    if (next is Authenticated) {
      _syncCoordinator.startSession(userId: next.user.id);
    } else if (next is Unauthenticated) {
      _syncCoordinator.endSession();
    }
  }

  final AuthRepository _repository;
  final SyncCoordinator _syncCoordinator;

  late final StreamSubscription<UserEntity?> _sessionSubscription;

  /// Startup's question. Answers [Unauthenticated] for *both* "no session" and
  /// "the check itself failed": the app cannot be entered either way, and an
  /// error screen in front of a sign-in button the user could simply press is
  /// a dead end (docs/specs/auth.md, State Machine).
  ///
  /// The one thing no longer folded away is [SignInBlock]. This is the leg a
  /// web redirect comes back on, and a redirect that came back empty is
  /// indistinguishable from a user who never signed in unless the repository's
  /// verdict is carried to the page (rule 2). Still [Unauthenticated], because
  /// that is the truth of it; only now it says why.
  ///
  /// No [AuthLoading] on the way: the splash is already on screen while this
  /// runs, and a loading state under it would only be visible as a flicker if
  /// the check resolved after the splash left.
  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final result = await _repository.getCurrentUser();
    // The repository call outlives a bloc closed mid-flight — which a widget
    // test does routinely — and `emit` on a closed bloc throws.
    if (isClosed) return;
    emit(
      result.fold<AuthState>(
        (failure) => Unauthenticated(blockedBy: _blockFor(failure)),
        (user) => user == null ? const Unauthenticated() : Authenticated(user),
      ),
    );
  }

  /// The one operation that shows a spinner, because the Google flow leaves
  /// the app: on Android the plugin's dialog covers it, and on web the
  /// redirect navigates away and comes back.
  Future<void> _onGoogleSignInRequested(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _repository.signInWithGoogle();
    if (isClosed) return;
    emit(result.fold<AuthState>(_afterFailedSignIn, Authenticated.new));
  }

  /// Sign-out has no loading state either: it resolves in a frame or two, and
  /// a spinner over the profile page would outlive the operation it announces.
  ///
  /// A failed sign-out is a real error (unlike a failed sign-in cancellation):
  /// the local board is deliberately *not* cleared when the remote call fails,
  /// so the user must be told they are still signed in (auth.md, Edge Cases).
  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final result = await _repository.signOut();
    if (isClosed) return;
    emit(result.fold<AuthState>(AuthError.new, (_) => const Unauthenticated()));
  }

  /// A session change published by Firebase.
  void _onUserChanged(AuthUserChanged event, Emitter<AuthState> emit) {
    final user = event.user;
    if (user != null) {
      emit(Authenticated(user));
      return;
    }
    // A `null` while a sign-in is in flight is the *old* session being torn
    // down, not a sign-out: Firebase publishes it while the Google dialog is
    // still open, and honouring it would bounce the user back to onboarding a
    // frame before their own sign-in lands. Every other state takes it.
    if (state is AuthLoading) return;

    // The same null is what Firebase publishes moments after startup on any
    // signed-out boot — including the boot a dropped redirect lands on. It
    // says nothing this state does not already say, so letting it overwrite a
    // diagnosis would erase the answer a few frames before the onboarding page
    // mounts to read it, which is the silent failure all over again. The next
    // attempt clears it instead: [AuthLoading] is a sign-in's first emission.
    final current = state;
    if (current is Unauthenticated && current.blockedBy != null) return;

    emit(const Unauthenticated());
  }

  /// Where a sign-in that produced no session lands.
  ///
  /// Three answers, because they are three different situations for the person
  /// holding the phone (auth.md rule 2): a decision they made, a browser they
  /// can talk into working, and everything else.
  static AuthState _afterFailedSignIn(Failure failure) {
    // Rule 5: a dismissed dialog is a decision, not a failure, so it goes back
    // to onboarding silently — and with no diagnosis, which would explain a
    // problem the user does not have. Read through `isSignInCancelled`, never
    // by comparing the marker string here.
    if (isSignInCancelled(failure)) return const Unauthenticated();
    final block = _blockFor(failure);
    if (block != null) return Unauthenticated(blockedBy: block);
    return AuthError(failure);
  }

  /// The obstacle [failure] names, or `null` when it names none.
  ///
  /// The one place in the app that reads the repository's markers, so a rename
  /// there is a compile error here rather than a page quietly falling back to
  /// the generic message.
  static SignInBlock? _blockFor(Failure failure) {
    if (isSignInStorageBlocked(failure)) return SignInBlock.storage;
    if (isSignInPopupBlocked(failure)) return SignInBlock.popup;
    return null;
  }

  @override
  Future<void> close() async {
    await _sessionSubscription.cancel();
    return super.close();
  }
}

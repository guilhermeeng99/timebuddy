import 'dart:async';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_state.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/startup/presentation/cubit/startup_state.dart';

/// The gate between "the app process exists" and "a screen the user can
/// trust" (docs/specs/startup.md).
///
/// It has no domain and no data layer: it composes four collaborators, in one
/// order, once per launch. Loading tzdata first is not a preference — every
/// other feature assumes it (timezone_engine.md rule 1), and a grid built
/// before it reads plausible hours that are simply wrong.
///
/// **Where the board picks up what sync reconciled.** `SyncService` writes the
/// winning document to the side that lost, so by the time this cubit reaches a
/// terminal state the *local* board document is already the reconciled one.
/// `AppShell` still owns `BoardCubit` and still loads it (CLAUDE.md,
/// Lifecycle), and because the shell is only built after the router leaves
/// `/startup`, that load reads the reconciled document rather than the stale
/// one. No second board owner, no adoption call, no write loop.
/// `PreferencesCubit` is the exception and needs `adoptFromSync`: it is a
/// singleton loaded by `TimeBuddyApp` *before* the router exists, so its
/// in-memory copy would otherwise outlive the document sync replaced.
///
/// ```dart
/// // StartupPage.initState
/// unawaited(context.read<StartupCubit>().initialize());
/// ```
class StartupCubit extends Cubit<StartupState> {
  StartupCubit({
    required AuthBloc authBloc,
    required TimeZoneEngine engine,
    required CityCatalogRepository catalog,
    required SyncService syncService,
    required GuestSession guestSession,
    PreferencesCubit? preferencesCubit,
  }) : _authBloc = authBloc,
       _engine = engine,
       _catalog = catalog,
       _syncService = syncService,
       _guestSession = guestSession,
       _preferencesCubit = preferencesCubit,
       super(const StartupInitial());

  /// Rule 8's budget for the first sync.
  ///
  /// Past it the app opens on local data and the sync finishes in the
  /// background: a splash screen that can hang on a bad network is a broken
  /// app, and unlike the project this pattern came from, TimeBuddy has a
  /// perfectly usable local board to open on.
  static const Duration syncTimeBox = Duration(seconds: 5);

  /// Read-only. The cubit reads `.state` and listens to `.stream`; it never
  /// dispatches an event, because deciding *when* to check a session belongs
  /// to whoever owns the bloc, not to the screen waiting on the answer.
  final AuthBloc _authBloc;

  final TimeZoneEngine _engine;
  final CityCatalogRepository _catalog;
  final SyncService _syncService;

  /// The device's guest marker (docs/specs/guest_mode.md).
  ///
  /// Required rather than optional, unlike [_preferencesCubit]: without it the
  /// adopting sync would silently not happen, and a guest who signed in would
  /// quietly keep a local-only board while the app told them they were synced.
  final GuestSession _guestSession;

  /// The sink for the reconciled preferences document.
  ///
  /// Optional because the four collaborators in the spec are what the state
  /// machine needs; this fifth one only exists so an already-loaded singleton
  /// does not keep serving the copy sync just replaced. The app always passes
  /// it (`injection_container.dart`); a test that asserts on states alone can
  /// leave it out.
  final PreferencesCubit? _preferencesCubit;

  /// Live only while auth has not settled, which on a warm start is never
  /// (rule 4).
  StreamSubscription<AuthState>? _authWatch;
  Completer<String?>? _authSettled;

  /// Runs the whole startup sequence and emits the route decision.
  ///
  /// Invoked exactly once by `StartupPage.initState`; re-entry happens only
  /// through the error state's retry (rule 1), which is why it re-announces
  /// the loading state and releases whatever the previous attempt left behind
  /// before starting anything.
  Future<void> initialize() async {
    if (isClosed) return;
    // Rule 3: loading first and synchronously, whatever `AuthBloc` already
    // holds, so the splash animates in the same way on a cold start as on a
    // retry and nothing can observe the previous run's terminal state.
    emit(const StartupLoading());
    // Releasing the previous attempt's wait unwinds it and drops the
    // subscription feeding it, so two runs cannot both be listening for the
    // same answer.
    _settleAuth(null);

    // Started together, awaited in order. Neither the engine nor the catalog
    // depends on a user, so the auth wait must not queue behind them; the
    // engine is still *started* first, because rule 2 makes tzdata
    // unconditional and every other answer in the app depends on it.
    final prepared = _prepare();
    final signedInUserId = _resolveSignedInUserId();

    if (!await prepared) {
      // Releases the auth wait nobody will read now, and with it the
      // subscription that feeds it.
      _settleAuth(null);
      if (!isClosed) emit(const StartupError());
      return;
    }
    if (isClosed) return;
    emit(const StartupLoading(progress: StartupLoading.preparedProgress));

    final userId = await signedInUserId;
    if (isClosed) return;
    if (userId == null) {
      // Rule 6: the unauthenticated branch skips the sync entirely. There is
      // no account to reconcile against.
      emit(const StartupUnauthenticated());
      return;
    }

    emit(const StartupLoading(progress: StartupLoading.syncingProgress));
    // Read before the sync, because a landed adoption clears it: the flag has
    // to survive long enough to decide whether to call `leave()` below.
    final adopting = _guestSession.isGuest;
    // Set before the await, not after. It is what stops `AppRouter`'s guest
    // rule bouncing this same session back to the splash while the sync it
    // asked for is still in flight (guest_mode.md rule 8).
    if (adopting) _guestSession.adoptionAttempted = true;

    final reconciled = await _firstSync(userId, adopting: adopting);
    if (isClosed) return;
    // Only on a sync that landed (rule 8). A failed adoption leaves the marker
    // in place so the next launch retries it, rather than stranding a board
    // that never reached the account.
    if (adopting && reconciled) await _guestSession.leave();
    if (isClosed) return;
    emit(StartupAuthenticated(userId: userId, syncFailed: !reconciled));
  }

  @override
  Future<void> close() async {
    // Both, and in this order: cancelling alone would leave an `initialize()`
    // suspended on a completer nobody can finish (Edge Cases, "page torn down
    // mid-load").
    await _cancelAuthWatch();
    _settleAuth(null);
    return super.close();
  }

  /// Loads tzdata and the city catalog, and says whether the app may open.
  ///
  /// Only the engine can answer `false` (rule 10). Every reading in the app is
  /// a function of tzdata, so a board built without it shows plausible hours
  /// that are simply wrong — there is nothing honest to render.
  ///
  /// **The catalog is awaited but not gated on, and that is a correction.**
  /// It used to be fatal on the argument that a first run where no city can be
  /// added is a dead end. It is not the only run: on web this asset is an HTTP
  /// request, and one blip on it was taking down a returning user whose board
  /// renders perfectly from the labels it denormalized at add time
  /// ([docs/specs/locations.md](docs/specs/locations.md) rule 12). Startup is
  /// where the read is *warmed*, so the add-location sheet opens against a
  /// parsed index instead of a 500-row decode; when the warming fails, the
  /// sheet reads again and reports its own error with its own retry, which is
  /// what that spec's edge case has always said should happen.
  Future<bool> _prepare() async {
    final engineReady = _engine.initialize();
    final catalogReady = _catalog.load();
    try {
      await engineReady;
    } on Object catch (error, stackTrace) {
      // Claimed even here: a rejected future with no listener reaches the zone
      // guard, so an engine failure would be followed by a crash.
      catalogReady.ignore();
      _logFailure('the timezone engine did not initialize', error, stackTrace);
      return false;
    }

    // Still awaited rather than left running: the point of loading it here is
    // that it is already in memory by the time a page can ask, and a fire and
    // forget read would hand the first keystroke a cold catalog anyway.
    //
    // The catalog answers with an `Either` rather than throwing, so its
    // failure arrives as a value and has to be unwrapped rather than caught.
    final loaded = await catalogReady;
    final catalogFailure = loaded.fold<Failure?>((left) => left, (_) => null);
    if (catalogFailure != null) {
      _logFailure('the city catalog did not load', catalogFailure);
    }
    return true;
  }

  /// The signed-in user's id, or `null` once auth settles on "signed out".
  Future<String?> _resolveSignedInUserId() {
    final settled = _terminalReading(_authBloc.state);
    // Rule 4's fast path. A bloc that already holds a terminal state has the
    // answer, and subscribing for it would open a stream to close a moment
    // later.
    if (settled != null) return Future<String?>.value(settled.userId);

    final completer = _authSettled = Completer<String?>();
    _authWatch = _authBloc.stream.listen(
      _onAuthState,
      onError: _onAuthWatchError,
    );
    return completer.future;
  }

  void _onAuthState(AuthState state) {
    final reading = _terminalReading(state);
    if (reading == null) return;
    _settleAuth(reading.userId);
  }

  /// A bloc's state stream does not normally fail, but a splash held forever
  /// by one that did would be unrecoverable; "signed out" costs one tap.
  void _onAuthWatchError(Object error, StackTrace stackTrace) {
    _logFailure(
      'the auth stream failed while startup waited',
      error,
      stackTrace,
    );
    _settleAuth(null);
  }

  /// Completes the pending wait once, and drops the subscription feeding it.
  ///
  /// Guarded on both sides (rule 5): a bloc can emit two terminal states in a
  /// row — a sign-in landing while the session check is still running — and a
  /// second `complete()` throws.
  void _settleAuth(String? userId) {
    final completer = _authSettled;
    _authSettled = null;
    unawaited(_cancelAuthWatch());
    if (completer == null || completer.isCompleted) return;
    completer.complete(userId);
  }

  Future<void> _cancelAuthWatch() async {
    await _authWatch?.cancel();
    _authWatch = null;
  }

  /// Runs the first sync inside rule 8's time box, and says whether it landed.
  ///
  /// A `false` is not an error: the local board is already usable, so the app
  /// opens either way and `SyncService.status` carries the news to the passive
  /// indicator (rule 7, sync.md rule 4).
  Future<bool> _firstSync(String userId, {required bool adopting}) async {
    final pending = _syncService.sync(
      userId: userId,
      adoptGuestDocuments: adopting,
    );
    // Adoption hangs off the sync itself rather than off the timed-out view of
    // it, so a sync that lands after the budget still reaches the cubits
    // instead of quietly replacing the stored document underneath them.
    unawaited(_adoptWhenReconciled(pending));
    try {
      // An adopting sync is exempt from rule 8's budget (guest_mode.md
      // rule 7). `AppShell` builds `BoardCubit` the moment the router leaves
      // `/startup`, so opening early here would load the guest's document a
      // heartbeat before the account's replaced it — the user would watch
      // their own cities flash up and then vanish.
      final result = adopting
          ? await pending
          : await pending.timeout(syncTimeBox);
      return result.isRight();
    } on TimeoutException {
      // Rule 8: the app opens on local data and the sync finishes behind it.
      return false;
    } on Object catch (_) {
      // `sync` is contracted to answer with an `Either`, so a throw is a bug
      // in the sync layer — but one that must not take the splash down with
      // it. It is logged by the listener above, which is on the same future.
      return false;
    }
  }

  /// Hands the reconciled preferences to the singleton holding the stale copy.
  ///
  /// Adopted, never re-saved: the sync layer already wrote both sides, so
  /// persisting here would bump the revision and bounce a fresh write straight
  /// back at the document it just adopted.
  Future<void> _adoptWhenReconciled(
    Future<Either<Failure, SyncOutcome>> pending,
  ) async {
    final Either<Failure, SyncOutcome> result;
    try {
      result = await pending;
    } on Object catch (error, stackTrace) {
      _logFailure('the first sync threw', error, stackTrace);
      return;
    }

    final outcome = result.fold<SyncOutcome?>((_) => null, (value) => value);
    final preferences = _preferencesCubit;
    if (outcome == null || preferences == null || preferences.isClosed) return;
    preferences.adoptFromSync(outcome.preferences);
  }

  /// The terminal reading of [state], or `null` while auth has not settled.
  ///
  /// `AuthError` is terminal and reads as signed out (Edge Cases): the user
  /// lands on onboarding, where retrying the Google flow is one tap. The
  /// wildcard is rule 5's "any non-terminal state" — `AuthInitial` and
  /// `AuthLoading` both mean the answer has not arrived yet.
  static ({String? userId})? _terminalReading(AuthState state) =>
      switch (state) {
        Authenticated(:final user) => (userId: user.id),
        Unauthenticated() || AuthError() => (userId: null),
        _ => null,
      };

  /// The developer's half of a failure the user is shown localized copy for
  /// (rule 10). `dart:developer`, never `print`: this is a breadcrumb, not
  /// output.
  void _logFailure(String what, Object error, [StackTrace? stackTrace]) {
    developer.log(
      'Startup: $what.',
      name: 'StartupCubit',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_keys.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

/// Holds the signed-in account and performs the *background* half of an
/// ordinary write: the push to Firestore that docs/specs/sync.md rule 2 says
/// follows a successful local write.
///
/// **Why this exists instead of a `userId` on the repository contracts.** The
/// push needs an account id; the repositories do not. Threading one through
/// `BoardRepository.save` would put it in the signature of every caller —
/// `BoardCubit`, the settings page, `SyncServiceImpl`'s own reconciling
/// re-save — and each of them would then have to resolve a session from
/// `AuthBloc`, which is auth knowledge in layers that have no business
/// holding it. The account is session state, so exactly one session-scoped
/// object holds it: set when auth resolves, cleared on sign-out, read only
/// here.
///
/// **A failed push is never a `Left`** (rule 4). The user reordered two
/// cities; Firestore being unreachable is not their problem. The failure
/// becomes a dirty flag instead, and `SyncService.flushDirty` retries it on
/// the next resume, start or sync (rule 3) rather than spinning against a
/// radio that is off.
///
/// **Pushes are not queued behind each other.** Two quick edits fire two
/// overwrites and the network may land them out of order, leaving the server
/// briefly holding the older document. That is repaired, not lost: the newer
/// copy carries the higher `revision`, so the next sync's ladder uploads it
/// (rule 5). A per-document write queue would buy a shorter window at the
/// price of an ordering mechanism this app has no other use for.
///
/// ```dart
/// final coordinator = SyncCoordinator(
///   remoteDataSource: sl<RemoteSettingsDataSource>(),
///   localStore: sl<LocalStore>(),
/// )..startSession(userId: user.id);
/// // Fired, never awaited, by BoardRepositoryImpl.save.
/// await coordinator.pushBoard(board);
/// ```
class SyncCoordinator {
  SyncCoordinator({
    required RemoteSettingsDataSource remoteDataSource,
    required LocalStore localStore,
  }) : _remote = remoteDataSource,
       _dirtyFlags = SyncDirtyFlags(localStore);

  final RemoteSettingsDataSource _remote;

  /// Reused rather than reimplemented: the two flag keys and the rule that a
  /// refused flag write is swallowed already live in one place
  /// (`sync_keys.dart`). A second copy would be a second answer to the
  /// question of what a dirty document is.
  final SyncDirtyFlags _dirtyFlags;

  /// The account every push writes to, or `null` while nobody is signed in.
  ///
  /// Deliberately mutable state on a singleton, which is what a session is:
  /// the alternative is rebuilding the repository graph on every sign-in.
  String? _userId;

  /// Whether a push would reach an account at all.
  ///
  /// Nothing in the write path asks — [pushBoard] and [pushPreferences]
  /// already answer "no session" by doing nothing — so this exists for the
  /// caller that wants to assert the session was attached, rather than to
  /// hand out the id itself.
  bool get hasSession => _userId != null;

  /// Attaches [userId]. Every push from here on writes to that account.
  ///
  /// Called wherever the session resolves — `AuthBloc` reaching
  /// `Authenticated`, on a warm start as much as after a sign-in. Repeating
  /// it with the same id is free, which is what lets the caller be a state
  /// listener rather than a one-shot.
  ///
  /// Named rather than positional, to match `SyncService.sync` and
  /// `flushDirty`: an account id at a call site should say whose it is.
  // A setter would drop the named argument, and an account id at a call
  // site should say whose it is. It also pairs with endSession().
  // ignore: use_setters_to_change_properties
  void startSession({required String userId}) {
    _userId = userId;
  }

  /// Detaches the account, on sign-out and on account deletion (rule 10).
  ///
  /// Nothing is flushed on the way out and nothing is marked: what the
  /// departing account still owed the server is dropped with its local
  /// documents by `SyncService.clearLocalData`, because a pending write must
  /// never be flushed into the *next* session, which would hand one user's
  /// cities to another.
  void endSession() {
    _userId = null;
  }

  /// Uploads [board] to the signed-in account, or marks it dirty if that
  /// fails. Never throws.
  Future<void> pushBoard(BoardEntity board) {
    return _push(
      dirtyKey: StorageKeys.boardDirty,
      write: (userId) => _remote.writeBoard(
        userId: userId,
        board: BoardModel.fromEntity(board),
      ),
    );
  }

  /// Uploads [preferences] to the signed-in account, or marks them dirty if
  /// that fails. Never throws.
  Future<void> pushPreferences(PreferencesEntity preferences) {
    return _push(
      dirtyKey: StorageKeys.preferencesDirty,
      write: (userId) => _remote.writePreferences(
        userId: userId,
        preferences: PreferencesModel.fromEntity(preferences),
      ),
    );
  }

  /// Runs one remote write and keeps [dirtyKey] in step with what the server
  /// is still owed.
  ///
  /// Rule 4 lives here: a remote failure must not be able to travel out of
  /// this method as an exception. Everything above it — a repository that has
  /// already answered `Right`, a caller that never awaited the future — would
  /// otherwise be handed an error it cannot act on, and an unawaited one
  /// would surface as an unhandled async error instead of as a flag.
  Future<void> _push({
    required String dirtyKey,
    required Future<void> Function(String userId) write,
  }) async {
    final userId = _userId;
    // Signed out is not dirty. A document with no account to go to is not a
    // write the server is owed, and a flag set now would be found by the
    // *next* account's flush, which would push the previous user's data into
    // it (rule 10).
    if (userId == null) return;

    try {
      await write(userId);
      // Cleared, not merely left alone: this document is now on the server, so
      // a flag an earlier failed push left behind describes a debt that has
      // just been paid, and flushing it later would re-upload nothing useful.
      await _dirtyFlags.clear(dirtyKey);
    } on ServerException catch (_) {
      await _dirtyFlags.mark(dirtyKey);
    }
  }
}

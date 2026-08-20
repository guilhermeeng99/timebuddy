import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_keys.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';

/// The pair of remote documents. Either may be absent, which is a value on
/// the ladder ([SyncKeys.missingRevision]) rather than a special case.
typedef _RemoteDocuments = ({
  BoardModel? board,
  PreferencesModel? preferences,
});

/// What writing one reconciled document produced.
///
/// The two failures are deliberately different shapes because the app treats
/// them differently: `localFailure` ends the sync and is shown, `remoteError`
/// never is (docs/specs/sync.md rule 4) and only steers the status stream.
typedef _WriteOutcome = ({
  Failure? localFailure,
  ServerException? remoteError,
});

/// Reconciles the device's two documents with the account's, per sync.md.
///
/// **The document is the unit, and there is no field-level merge (rule 6).**
/// Merging two divergent boards would need per-row identity, tombstones for
/// deletions, and an ordering rule for concurrent inserts — that is a
/// synchronisation engine, and this app is a world clock. The trade the
/// project accepted: a user who edits the board on two devices while offline
/// loses one set of edits wholesale, and is told which side won through
/// [SyncOutcome] rather than being left to notice. For two documents under
/// 10 KB that are always read whole, the merge would cost more code than the
/// feature it protects.
///
/// **Nothing here runs on a timer or a snapshot listener (rule 9).** Sync is
/// called at startup, on an explicit refresh, and on resume. A live listener
/// on two settings documents is a subscription per session for data that only
/// this user changes.
///
/// **A successful sync *is* the flush (rule 3).** There is deliberately no
/// second pass over the dirty flags at the end of [sync]: each flag is
/// rewritten while its document's winner is written, so what stays dirty is
/// exactly what the server was not given. A pass after that could only
/// re-upload a document the ladder had already retired, undoing the copy that
/// just won. [flushDirty] exists for the resume path, where there is no
/// reconciliation to piggyback on.
///
/// There is deliberately no `Clock` in this class: reconciliation never
/// stamps a new `updatedAt` and never bumps a `revision`. The winner is
/// written to the losing side exactly as it was, so a sync cannot inflate the
/// numbers it just compared — which would make the next sync see a conflict
/// this one invented.
///
/// ```dart
/// final service = SyncServiceImpl(
///   remoteDataSource: sl<RemoteSettingsDataSource>(),
///   boardRepository: sl<BoardRepository>(),
///   preferencesRepository: sl<PreferencesRepository>(),
///   localStore: sl<LocalStore>(),
///   engine: sl<TimeZoneEngine>(),
///   deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
/// );
/// ```
class SyncServiceImpl implements SyncService {
  SyncServiceImpl({
    required RemoteSettingsDataSource remoteDataSource,
    required BoardRepository boardRepository,
    required PreferencesRepository preferencesRepository,
    required LocalStore localStore,
    required TimeZoneEngine engine,
    required Locale deviceLocale,
  }) : _remote = remoteDataSource,
       _boardRepository = boardRepository,
       _preferencesRepository = preferencesRepository,
       _store = localStore,
       _engine = engine,
       _deviceLocale = deviceLocale,
       _dirtyFlags = SyncDirtyFlags(localStore);

  /// What an absent or unreadable timestamp is worth.
  ///
  /// The epoch, never "now", for the same reason the models use it: a
  /// timestamp nobody can read must lose every tie it enters instead of
  /// winning them by looking freshly written.
  static final DateTime _epochUtc = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  final RemoteSettingsDataSource _remote;
  final BoardRepository _boardRepository;
  final PreferencesRepository _preferencesRepository;
  final LocalStore _store;
  final SyncDirtyFlags _dirtyFlags;

  /// Asked one question only: which zone a board falls back to when nothing
  /// has been stored yet.
  final TimeZoneEngine _engine;

  /// Consulted only when the preferences document has to be seeded, which is
  /// the one moment `hourFormat` and `weekStartsOn` are derived from the
  /// device (preferences.md rule 2).
  final Locale _deviceLocale;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  SyncStatus _lastStatus = SyncStatus.idle;

  @override
  Stream<SyncStatus> get status async* {
    // The current value is replayed before the live events: a broadcast
    // controller drops everything emitted before `listen`, and the sidebar
    // indicator mounts long after the startup sync that found the app
    // offline. Without this it would show "idle" over a failed session.
    yield _lastStatus;
    yield* _statusController.stream;
  }

  @override
  Future<Either<Failure, SyncOutcome>> sync({required String userId}) async {
    _publish(SyncStatus.syncing);

    final deviceZone = await _engine.deviceZone();
    final boardResult = await _boardRepository.load(
      homeZoneIdFallback: deviceZone.zoneId,
    );
    final preferencesResult = await _preferencesRepository.load(
      deviceLocale: _deviceLocale,
    );

    // Both loads seed and persist defaults when nothing is stored, so the
    // ladder below always has a local document to compare against. That is
    // what turns first sign-in provisioning into an ordinary reconciliation
    // instead of a second code path (sync.md, Provisioning).
    return boardResult.fold<Future<Either<Failure, SyncOutcome>>>(
      (failure) => _failed(failure, SyncStatus.error),
      (localBoard) => preferencesResult.fold(
        (failure) => _failed(failure, SyncStatus.error),
        (localPreferences) => _reconcile(
          userId: userId,
          localBoard: localBoard,
          localPreferences: localPreferences,
        ),
      ),
    );
  }

  @override
  Future<void> flushDirty({required String userId}) async {
    final boardDirty = await _dirtyFlags.isDirty(StorageKeys.boardDirty);
    final preferencesDirty = await _dirtyFlags.isDirty(
      StorageKeys.preferencesDirty,
    );
    // Zero reads and no status churn when nothing is pending, which is what
    // makes calling this on every resume free (sync.md, Sync flow). It is also
    // why a second call after a successful flush does nothing at all.
    if (!boardDirty && !preferencesDirty) return;

    _publish(SyncStatus.syncing);
    final boardError = boardDirty ? await _flushBoard(userId) : null;
    final preferencesError = preferencesDirty
        ? await _flushPreferences(userId)
        : null;
    _publish(_statusFor(boardError ?? preferencesError));
  }

  @override
  Future<void> clearLocalData() async {
    // Named removes rather than `LocalStore.clearAll()`: what sign-out has to
    // take with it is this account's documents and its pending writes (rule
    // 10), not every key the app may ever keep. A "has seen the onboarding"
    // marker belongs to the device, not to the user who just left.
    await Future.wait([
      _store.remove(StorageKeys.board),
      _store.remove(StorageKeys.preferences),
      _dirtyFlags.clear(StorageKeys.boardDirty),
      _dirtyFlags.clear(StorageKeys.preferencesDirty),
    ]);
    _publish(SyncStatus.idle);
  }

  /// Closes the status stream.
  ///
  /// The app never calls this: the service lives as long as the process. It
  /// exists so a test that subscribes does not leave a controller open.
  Future<void> dispose() => _statusController.close();

  /// Pulls both documents, decides each winner, and writes it to the side
  /// that lost.
  Future<Either<Failure, SyncOutcome>> _reconcile({
    required String userId,
    required BoardEntity localBoard,
    required PreferencesEntity localPreferences,
  }) async {
    final _RemoteDocuments remote;
    try {
      remote = await _readRemote(
        userId: userId,
        homeZoneIdFallback: localBoard.homeZoneId,
      );
    } on ServerException catch (error) {
      // A failed pull leaves nothing to reconcile against. Local is untouched
      // and still the read path, so the app keeps working (rule 1).
      return _failed(ServerFailure(error.message), _statusFor(error));
    }

    final boardWinner = _boardWinner(localBoard, remote.board);
    final preferencesWinner = _preferencesWinner(
      localPreferences,
      remote.preferences,
    );

    return _writeWinners(
      userId: userId,
      board: _chosen(boardWinner, localBoard, remote.board),
      preferences: _chosen(
        preferencesWinner,
        localPreferences,
        remote.preferences,
      ),
      boardWinner: boardWinner,
      preferencesWinner: preferencesWinner,
    );
  }

  /// The copy the ladder picked.
  ///
  /// The `??` branch is unreachable: an absent remote document is revision -1
  /// and cannot win. It falls back to the copy the user is already looking at
  /// rather than asserting, because a sync is not worth a crash.
  static T _chosen<T>(ConflictWinner winner, T local, T? remote) =>
      winner == ConflictWinner.remote ? remote ?? local : local;

  /// Two document reads, and the whole remote cost of a sync.
  ///
  /// Sequential rather than concurrent on purpose: if the first future throws
  /// while the second is still in flight, nobody awaits the second and its
  /// error becomes an unhandled async error. Two round trips is a price this
  /// app can pay; a crash on a flaky network is not.
  Future<_RemoteDocuments> _readRemote({
    required String userId,
    required String homeZoneIdFallback,
  }) async {
    final board = await _remote.readBoard(
      userId: userId,
      homeZoneIdFallback: homeZoneIdFallback,
    );
    final preferences = await _remote.readPreferences(userId: userId);
    return (board: board, preferences: preferences);
  }

  Future<Either<Failure, SyncOutcome>> _writeWinners({
    required String userId,
    required BoardEntity board,
    required PreferencesEntity preferences,
    required ConflictWinner boardWinner,
    required ConflictWinner preferencesWinner,
  }) async {
    final boardWrite = await _apply(
      winner: boardWinner,
      dirtyKey: StorageKeys.boardDirty,
      document: board,
      saveLocally: _boardRepository.save,
      pushRemotely: (value) => _pushBoard(userId: userId, board: value),
    );
    final boardFailure = boardWrite.localFailure;
    if (boardFailure != null) return _failed(boardFailure, SyncStatus.error);

    final preferencesWrite = await _apply(
      winner: preferencesWinner,
      dirtyKey: StorageKeys.preferencesDirty,
      document: preferences,
      saveLocally: _preferencesRepository.save,
      pushRemotely: (value) =>
          _pushPreferences(userId: userId, preferences: value),
    );
    final preferencesFailure = preferencesWrite.localFailure;
    if (preferencesFailure != null) {
      return _failed(preferencesFailure, SyncStatus.error);
    }

    _publish(
      _statusFor(boardWrite.remoteError ?? preferencesWrite.remoteError),
    );
    return Right(
      SyncOutcome(
        board: board,
        preferences: preferences,
        boardWinner: boardWinner,
        preferencesWinner: preferencesWinner,
      ),
    );
  }

  /// Writes the reconciled [document] to whichever side lost, and keeps
  /// [dirtyKey] in step with what the server is still owed.
  ///
  /// Local first, remote after (rule 2). A refused local write ends the sync,
  /// because it breaks the read path every screen depends on (sync.md, Edge
  /// Cases); a refused remote write does not, because durability is the one
  /// thing the user cannot see going wrong (rule 4).
  Future<_WriteOutcome> _apply<T>({
    required ConflictWinner winner,
    required String dirtyKey,
    required T document,
    required Future<Either<Failure, T>> Function(T document) saveLocally,
    required Future<void> Function(T document) pushRemotely,
  }) async {
    if (winner == ConflictWinner.remote) {
      final failure = _failureIn(await saveLocally(document));
      if (failure != null) {
        return (localFailure: failure, remoteError: null);
      }
    }
    if (winner != ConflictWinner.local) {
      // The server already holds this content, so nothing is owed to it. This
      // also retires a flag left by an older failed push: flushing that later
      // would re-upload the document that lost and undo the one that won.
      await _dirtyFlags.clear(dirtyKey);
      return (localFailure: null, remoteError: null);
    }

    final error = await _push(document, pushRemotely);
    if (error == null) {
      await _dirtyFlags.clear(dirtyKey);
    } else {
      // Rule 3: mark it and move on. Retrying in a loop spins against a radio
      // that is off; the next start, sync or resume flushes it instead.
      await _dirtyFlags.mark(dirtyKey);
    }
    return (localFailure: null, remoteError: error);
  }

  /// Uploads the stored board and clears its flag when that lands.
  Future<ServerException?> _flushBoard(String userId) async {
    final deviceZone = await _engine.deviceZone();
    final stored = await _boardRepository.load(
      homeZoneIdFallback: deviceZone.zoneId,
    );
    final board = stored.fold<BoardEntity?>((_) => null, (value) => value);
    // A document that cannot be read cannot be flushed. The flag stays set, so
    // the attempt costs nothing and repeats once storage recovers.
    if (board == null) return null;

    final error = await _push(
      board,
      (value) => _pushBoard(userId: userId, board: value),
    );
    if (error == null) await _dirtyFlags.clear(StorageKeys.boardDirty);
    return error;
  }

  /// Uploads the stored preferences and clears their flag when that lands.
  Future<ServerException?> _flushPreferences(String userId) async {
    final stored = await _preferencesRepository.load(
      deviceLocale: _deviceLocale,
    );
    final preferences = stored.fold<PreferencesEntity?>(
      (_) => null,
      (value) => value,
    );
    if (preferences == null) return null;

    final error = await _push(
      preferences,
      (value) => _pushPreferences(userId: userId, preferences: value),
    );
    if (error == null) {
      await _dirtyFlags.clear(StorageKeys.preferencesDirty);
    }
    return error;
  }

  Future<void> _pushBoard({
    required String userId,
    required BoardEntity board,
  }) {
    return _remote.writeBoard(
      userId: userId,
      board: BoardModel.fromEntity(board),
    );
  }

  Future<void> _pushPreferences({
    required String userId,
    required PreferencesEntity preferences,
  }) {
    return _remote.writePreferences(
      userId: userId,
      preferences: PreferencesModel.fromEntity(preferences),
    );
  }

  /// Runs a remote write, turning its failure into a value.
  ///
  /// Rule 4 lives here: a failed remote write must not be able to travel as
  /// an exception past this point, because everything above would then have
  /// to decide whether to show it, and one of them eventually would.
  Future<ServerException?> _push<T>(
    T document,
    Future<void> Function(T document) write,
  ) async {
    try {
      await write(document);
      return null;
    } on ServerException catch (error) {
      return error;
    }
  }

  ConflictWinner _boardWinner(BoardEntity local, BoardModel? remote) {
    return _winnerFor(
      localRevision: local.revision,
      remoteRevision: remote?.revision ?? SyncKeys.missingRevision,
      localUpdatedAt: local.updatedAt,
      remoteUpdatedAt: remote?.updatedAt ?? _epochUtc,
      contentMatches: remote != null && _boardsMatch(local, remote),
    );
  }

  ConflictWinner _preferencesWinner(
    PreferencesEntity local,
    PreferencesModel? remote,
  ) {
    return _winnerFor(
      localRevision: local.revision,
      remoteRevision: remote?.revision ?? SyncKeys.missingRevision,
      localUpdatedAt: local.updatedAt,
      remoteUpdatedAt: remote?.updatedAt ?? _epochUtc,
      contentMatches: remote != null && _preferencesMatch(local, remote),
    );
  }

  /// The conflict ladder of sync.md rule 5, in the one order it may run in.
  ///
  /// `revision` is compared **before** `updatedAt`, and that ordering is the
  /// entire safety property (rule 8). `revision` counts writes, which is a
  /// fact about the document; `updatedAt` is a wall clock, which is a claim
  /// by the device that wrote it. A phone whose clock is a day fast would win
  /// every comparison it entered and overwrite edits actually made after its
  /// own. Checking revision first means such a device can only win when it
  /// genuinely wrote more times, and `updatedAt` is left to break ties
  /// between documents written the same number of times — where the remote
  /// side of the tie is a server timestamp.
  ///
  /// [contentMatches] keeps a pointless round trip off both sides: equal
  /// revisions and equal content is agreement, not a conflict.
  ///
  /// The last rung goes to the remote. It is arbitrary, but it is *stable*:
  /// two devices reading the same pair of documents reach the same answer,
  /// where an arbitrary-but-local rule would have them push their own copy at
  /// each other forever.
  static ConflictWinner _winnerFor({
    required int localRevision,
    required int remoteRevision,
    required DateTime localUpdatedAt,
    required DateTime remoteUpdatedAt,
    required bool contentMatches,
  }) {
    if (remoteRevision > localRevision) return ConflictWinner.remote;
    if (localRevision > remoteRevision) return ConflictWinner.local;
    if (contentMatches) return ConflictWinner.none;
    if (localUpdatedAt.isAfter(remoteUpdatedAt)) return ConflictWinner.local;
    return ConflictWinner.remote;
  }

  /// Whether two boards say the same thing, ignoring when they said it.
  ///
  /// `updatedAt` is normalised away because rule 5's third rung asks about
  /// *content*: two documents that agree are not a conflict, whichever was
  /// stamped later.
  ///
  /// The comparison goes through `toJson` rather than `==`, and that is not
  /// paranoia. `Equatable` compares `runtimeType`, while these values arrive
  /// as whatever built them: a `BoardModel` off a store, a plain
  /// `BoardEntity` straight from a seed, rows that are `SavedLocationModel`
  /// on one side and `SavedLocationEntity` on the other. `==` would answer
  /// "different" for two identical boards and manufacture a conflict out of a
  /// class name. Content here means exactly what either store would be
  /// handed, which is what `toJson` produces.
  static bool _boardsMatch(BoardEntity local, BoardEntity remote) =>
      _encodedBoard(local) == _encodedBoard(remote);

  static String _encodedBoard(BoardEntity board) => jsonEncode(
    BoardModel.fromEntity(board.copyWith(updatedAt: _epochUtc)).toJson(),
  );

  /// The preferences half of [_boardsMatch], and for the same two reasons.
  static bool _preferencesMatch(
    PreferencesEntity local,
    PreferencesEntity remote,
  ) => _encodedPreferences(local) == _encodedPreferences(remote);

  static String _encodedPreferences(PreferencesEntity preferences) {
    return jsonEncode(
      PreferencesModel.fromEntity(
        preferences.copyWith(updatedAt: _epochUtc),
      ).toJson(),
    );
  }

  /// The status a remote error leaves behind.
  ///
  /// Offline is recoverable by waiting and needs no explanation; anything
  /// else — permission denied on a misconfigured rule set, a revoked
  /// account — needs a human, which is why the profile page tells them apart.
  static SyncStatus _statusFor(ServerException? error) {
    if (error == null) return SyncStatus.idle;
    if (error is RemoteUnavailableException) return SyncStatus.offline;
    return SyncStatus.error;
  }

  static Failure? _failureIn<T>(Either<Failure, T> result) =>
      result.fold((failure) => failure, (_) => null);

  Future<Either<Failure, SyncOutcome>> _failed(
    Failure failure,
    SyncStatus status,
  ) async {
    _publish(status);
    return Left(failure);
  }

  void _publish(SyncStatus status) {
    // Repeats are dropped so a resume that finds nothing to do cannot make the
    // indicator blink.
    if (status == _lastStatus || _statusController.isClosed) return;
    _lastStatus = status;
    _statusController.add(status);
  }
}

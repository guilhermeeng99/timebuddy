import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_keys.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/core/sync/sync_service_impl.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

import '../../harness/factories/board_factory.dart';
import '../../harness/factories/preferences_factory.dart';
import '../../harness/helpers.dart';
import '../../harness/mocks.dart';

/// The Firestore boundary. Mocked, so "the document is absent", "the document
/// is malformed" and "the radio is off" are three stubs rather than three
/// emulator setups.
class _MockRemoteSettingsDataSource extends Mock
    implements RemoteSettingsDataSource {}

/// The local board document's owner. Mocked so a device holding an older or a
/// clock-skewed copy is one stubbed answer.
class _MockBoardRepository extends Mock implements BoardRepository {}

const String _userId = 'firebase-uid';

/// The only thing the engine is asked for here: what a board falls back to
/// when nothing has been stored yet.
const String _deviceZoneId = 'America/Sao_Paulo';

/// The home zone only the *remote* board carries.
///
/// Content divergence is expressed through one readable field rather than
/// through a row diff, so a failed expectation names the difference instead of
/// printing two lists.
const String _remoteHomeZoneId = 'Europe/Berlin';

const Locale _deviceLocale = Locale('en');

/// The instants the `updatedAt` tie-break is written against.
///
/// Months apart and far from any DST transition: a comparison that comes out
/// wrong here is an ordering bug, not a boundary this file never meant to
/// cover.
final DateTime _earlierInstant = utcDate(2024, 5);
final DateTime _localInstant = utcDate(2024, 6);
final DateTime _laterInstant = utcDate(2024, 7);

/// What an absent timestamp is worth, and the value a fresh local seed carries
/// before anything has stamped it.
final DateTime _epochInstant = utcDate(1970);

/// A device whose wall clock is decades fast (docs/specs/sync.md rule 8).
final DateTime _skewedInstant = utcDate(2099);

/// The stored board every case starts from: three writes deep and stamped in
/// June.
final BoardEntity _localBoard = aBoard(
  locations: [aSavedLocation()],
  revision: 3,
  updatedAt: _localInstant,
);

final PreferencesEntity _localPreferences = aPreferences(
  revision: 2,
  updatedAt: _localInstant,
);

/// A remote board that disagrees with [_localBoard] about its home zone, so
/// the ladder has a real conflict to resolve rather than an agreement.
BoardModel _remoteBoard({
  required int revision,
  required DateTime updatedAt,
}) {
  return BoardModel.fromEntity(
    aBoard(
      homeZoneId: _remoteHomeZoneId,
      locations: [aSavedLocation()],
      revision: revision,
      updatedAt: updatedAt,
    ),
  );
}

/// A remote board saying exactly what [_localBoard] says, down to the rows.
BoardModel _remoteBoardAgreeingWithLocal() =>
    BoardModel.fromEntity(_localBoard);

void main() {
  setUpAll(() {
    // Real tzdata: `BoardEntity` canonicalises zone ids through `zoneOrNull`,
    // so a file that ran against an empty database would compare boards
    // differently depending on which test file happened to run first.
    initTestTimeZones();
    registerCommonFallbacks();
    registerFallbackValue(aBoard());
    registerFallbackValue(BoardModel.fromEntity(aBoard()));
    registerFallbackValue(PreferencesModel.fromEntity(aPreferences()));
  });

  late _MockRemoteSettingsDataSource remote;
  late _MockBoardRepository boardRepository;
  late MockPreferencesRepository preferencesRepository;
  late MockLocalStore store;
  late MockTimeZoneEngine engine;
  late SyncServiceImpl service;

  /// The device store, backed by a real map.
  ///
  /// The dirty flags are read back as often as they are written — "the flag
  /// is set", "the second flush finds nothing" — and a `verify` on `writeRaw`
  /// cannot answer the second question. The map can answer both.
  late Map<String, String> storedKeys;

  setUp(() {
    remote = _MockRemoteSettingsDataSource();
    boardRepository = _MockBoardRepository();
    preferencesRepository = MockPreferencesRepository();
    store = MockLocalStore();
    engine = MockTimeZoneEngine();
    storedKeys = <String, String>{};

    when(() => store.readRaw(any())).thenAnswer(
      (invocation) async =>
          storedKeys[invocation.positionalArguments.first as String],
    );
    when(() => store.writeRaw(any(), any())).thenAnswer((invocation) async {
      storedKeys[invocation.positionalArguments.first as String] =
          invocation.positionalArguments[1] as String;
    });
    when(() => store.remove(any())).thenAnswer((invocation) async {
      storedKeys.remove(invocation.positionalArguments.first as String);
    });

    when(engine.deviceZone).thenAnswer(
      (_) async => const DeviceZone(zoneId: _deviceZoneId, isFallback: false),
    );

    when(
      () => boardRepository.load(
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => Right<Failure, BoardEntity>(_localBoard));
    when(() => boardRepository.save(any())).thenAnswer(
      (invocation) async => Right<Failure, BoardEntity>(
        invocation.positionalArguments.first as BoardEntity,
      ),
    );

    when(
      () => preferencesRepository.load(
        deviceLocale: any(named: 'deviceLocale'),
      ),
    ).thenAnswer(
      (_) async => Right<Failure, PreferencesEntity>(_localPreferences),
    );
    when(() => preferencesRepository.save(any())).thenAnswer(
      (invocation) async => Right<Failure, PreferencesEntity>(
        invocation.positionalArguments.first as PreferencesEntity,
      ),
    );

    when(
      () => remote.readBoard(
        userId: any(named: 'userId'),
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => null);
    // Preferences agree by default, so a board case writes exactly the calls
    // it is about and a stray `writePreferences` cannot pass for one.
    when(() => remote.readPreferences(userId: any(named: 'userId'))).thenAnswer(
      (_) async => PreferencesModel.fromEntity(_localPreferences),
    );
    when(
      () => remote.writeBoard(
        userId: any(named: 'userId'),
        board: any(named: 'board'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => remote.writePreferences(
        userId: any(named: 'userId'),
        preferences: any(named: 'preferences'),
      ),
    ).thenAnswer((_) async {});

    service = SyncServiceImpl(
      remoteDataSource: remote,
      boardRepository: boardRepository,
      preferencesRepository: preferencesRepository,
      localStore: store,
      engine: engine,
      deviceLocale: _deviceLocale,
    );
  });

  tearDown(() => service.dispose());

  void boardRepositoryHolds(BoardEntity board) {
    when(
      () => boardRepository.load(
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => Right<Failure, BoardEntity>(board));
  }

  void remoteHoldsBoard(BoardModel? board) {
    when(
      () => remote.readBoard(
        userId: any(named: 'userId'),
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => board);
  }

  void remoteRejectsBoardWrite(ServerException error) {
    when(
      () => remote.writeBoard(
        userId: any(named: 'userId'),
        board: any(named: 'board'),
      ),
    ).thenThrow(error);
  }

  /// Runs a sync the ladder is expected to resolve.
  ///
  /// A `Left` is always a bug in the case rather than a result to assert on,
  /// so it fails here instead of becoming a null every expectation below would
  /// have to guard.
  Future<SyncOutcome> syncedOutcome() async {
    final result = await service.sync(userId: _userId);
    return result.fold<SyncOutcome>(
      (failure) => fail('sync answered Left($failure)'),
      (outcome) => outcome,
    );
  }

  void expectBoardWasUploaded(BoardEntity board) {
    verify(
      () => remote.writeBoard(
        userId: _userId,
        board: BoardModel.fromEntity(board),
      ),
    ).called(1);
  }

  void expectBoardWasNotUploaded() {
    verifyNever(
      () => remote.writeBoard(
        userId: any(named: 'userId'),
        board: any(named: 'board'),
      ),
    );
  }

  /// Collects what the passive indicator would show, from the replayed current
  /// value onward.
  ///
  /// `status` is an `async*` generator that replays before subscribing to the
  /// live controller, so the event queue has to be pumped once before anything
  /// is published; otherwise the first real transition lands in the gap.
  Future<List<SyncStatus>> statusesDuring(Future<void> Function() run) async {
    final seen = <SyncStatus>[];
    final subscription = service.status.listen(seen.add);
    await pumpEventQueue();
    await run();
    await pumpEventQueue();
    await subscription.cancel();
    return seen;
  }

  group('the conflict ladder', () {
    test('a higher remote revision wins and overwrites local', () async {
      final remoteBoard = _remoteBoard(
        revision: 5,
        updatedAt: _earlierInstant,
      );
      remoteHoldsBoard(remoteBoard);

      final outcome = await syncedOutcome();

      // Stamped two months before local and it still wins: rung 1 never
      // reaches the timestamps.
      expect(outcome.boardWinner, ConflictWinner.remote);
      expect(outcome.board, same(remoteBoard));
      verify(() => boardRepository.save(remoteBoard)).called(1);
      expectBoardWasNotUploaded();
    });

    test('a higher local revision wins and is uploaded', () async {
      remoteHoldsBoard(_remoteBoard(revision: 1, updatedAt: _laterInstant));

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.local);
      expect(outcome.board, _localBoard);
      expectBoardWasUploaded(_localBoard);
      verifyNever(() => boardRepository.save(any()));
    });

    test('equal revisions are broken by the later updatedAt', () async {
      remoteHoldsBoard(_remoteBoard(revision: 3, updatedAt: _earlierInstant));

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.local);
      expectBoardWasUploaded(_localBoard);
    });

    test('equal revisions let a later remote win', () async {
      final remoteBoard = _remoteBoard(revision: 3, updatedAt: _laterInstant);
      remoteHoldsBoard(remoteBoard);

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.remote);
      expect(outcome.board, same(remoteBoard));
      expectBoardWasNotUploaded();
    });

    test('a full tie goes to the remote', () async {
      final remoteBoard = _remoteBoard(revision: 3, updatedAt: _localInstant);
      remoteHoldsBoard(remoteBoard);

      final outcome = await syncedOutcome();

      // Arbitrary but stable: two devices reading this pair have to reach the
      // same answer, or they push their own copy at each other forever.
      expect(outcome.boardWinner, ConflictWinner.remote);
      expect(outcome.board, same(remoteBoard));
    });

    test('two sides that already agree write nothing', () async {
      remoteHoldsBoard(_remoteBoardAgreeingWithLocal());

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.none);
      expect(outcome.board, _localBoard);
      verifyNever(() => boardRepository.save(any()));
      expectBoardWasNotUploaded();
    });

    test('a clock-skewed device loses on revision (rule 8)', () async {
      // The whole reason rung 1 compares revisions: this device's wall clock
      // reads 2099, so on `updatedAt` alone it would win every conflict it
      // ever entered and overwrite edits genuinely made after its own.
      boardRepositoryHolds(
        _localBoard.copyWith(revision: 2, updatedAt: _skewedInstant),
      );
      final remoteBoard = _remoteBoard(revision: 3, updatedAt: _earlierInstant);
      remoteHoldsBoard(remoteBoard);

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.remote);
      expect(outcome.board, same(remoteBoard));
      expectBoardWasNotUploaded();
    });

    test('the two documents are reconciled independently', () async {
      // Rule 7: `revision` is monotonic per document, not global, so a board
      // adopted from the server must not drag the preferences with it.
      final remoteBoard = _remoteBoard(revision: 9, updatedAt: _earlierInstant);
      remoteHoldsBoard(remoteBoard);
      when(() => remote.readPreferences(userId: any(named: 'userId')))
          .thenAnswer((_) async => null);

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.remote);
      expect(outcome.preferencesWinner, ConflictWinner.local);
      expect(outcome.preferences, _localPreferences);
      verify(
        () => remote.writePreferences(
          userId: _userId,
          preferences: PreferencesModel.fromEntity(_localPreferences),
        ),
      ).called(1);
    });
  });

  group('provisioning', () {
    test('a missing remote document counts as revision -1', () async {
      // Both sides at the epoch and the local seed at revision 0: if a missing
      // remote were worth 0 the revisions would tie, the timestamps would tie,
      // and rung 4 would hand the account's first board to a document that
      // does not exist.
      final seededBoard = aBoard(revision: 0, updatedAt: _epochInstant);
      boardRepositoryHolds(seededBoard);
      remoteHoldsBoard(null);

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.local);
      expect(outcome.board, seededBoard);
      expectBoardWasUploaded(seededBoard);
      verifyNever(() => boardRepository.save(any()));
    });

    test('a malformed remote document counts as revision -1', () async {
      // The datasource is what maps an unreadable `revision` to -1; the
      // service's half of that contract is making the value lose, even when
      // the broken document carries the fresher timestamp.
      final seededBoard = aBoard(revision: 0, updatedAt: _earlierInstant);
      boardRepositoryHolds(seededBoard);
      remoteHoldsBoard(
        _remoteBoard(
          revision: SyncKeys.missingRevision,
          updatedAt: _laterInstant,
        ),
      );

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.local);
      expectBoardWasUploaded(seededBoard);
    });
  });

  group('adopting a guest into an account', () {
    /// The adopting sync, which is the one call that bypasses the ladder
    /// (docs/specs/guest_mode.md rule 6).
    Future<SyncOutcome> adoptedOutcome() async {
      final result = await service.sync(
        userId: _userId,
        adoptGuestDocuments: true,
      );
      return result.fold<SyncOutcome>(
        (failure) => fail('sync answered Left($failure)'),
        (outcome) => outcome,
      );
    }

    test('an account with no board takes the guest board', () async {
      remoteHoldsBoard(null);

      final outcome = await adoptedOutcome();

      // The only direction that is safe unconditionally: nothing on the
      // server is being replaced, so this is ordinary provisioning wearing a
      // different name.
      expect(outcome.boardWinner, ConflictWinner.local);
      expect(outcome.board, _localBoard);
      expectBoardWasUploaded(_localBoard);
      verifyNever(() => boardRepository.save(any()));
    });

    test('an account that has a board keeps it', () async {
      final remoteBoard = _remoteBoard(
        revision: 1,
        updatedAt: _earlierInstant,
      );
      remoteHoldsBoard(remoteBoard);

      // Lower revision, older timestamp: it loses every rung of the ladder and
      // still wins here. That is the whole rule — the guest's board never left
      // this device, and the account's is on other devices too.
      expect(_localBoard.revision, greaterThan(remoteBoard.revision));
      expect(_localBoard.updatedAt.isAfter(remoteBoard.updatedAt), isTrue);

      final outcome = await adoptedOutcome();

      expect(outcome.boardWinner, ConflictWinner.remote);
      expect(outcome.board, same(remoteBoard));
      verify(() => boardRepository.save(remoteBoard)).called(1);
      expectBoardWasNotUploaded();
    });

    test('the same pair without the flag goes the other way', () async {
      // The control for the test above: this is exactly what the ladder does
      // with these two documents, and exactly what would silently destroy an
      // account's board if adoption were left to it.
      remoteHoldsBoard(_remoteBoard(revision: 1, updatedAt: _earlierInstant));

      final outcome = await syncedOutcome();

      expect(outcome.boardWinner, ConflictWinner.local);
      expectBoardWasUploaded(_localBoard);
    });

    test('each document is decided on its own', () async {
      // Rule 7 of sync.md survives adoption: an account that has preferences
      // but has never saved a board still gets the guest's board pushed up.
      remoteHoldsBoard(null);

      final outcome = await adoptedOutcome();

      expect(outcome.boardWinner, ConflictWinner.local);
      expect(outcome.preferencesWinner, ConflictWinner.remote);
    });

    test('leaves no dirty flag behind when both writes landed', () async {
      remoteHoldsBoard(null);

      await adoptedOutcome();

      expect(storedKeys.containsKey(StorageKeys.boardDirty), isFalse);
      expect(storedKeys.containsKey(StorageKeys.preferencesDirty), isFalse);
    });
  });

  group('dirty flags', () {
    test('a failed remote write succeeds and marks the document', () async {
      remoteHoldsBoard(null);
      remoteRejectsBoardWrite(const ServerException('permission-denied'));

      final result = await service.sync(userId: _userId);

      // Rules 2 and 4: the user reordered two cities and durability is the one
      // thing they must not be shown going wrong.
      expect(result.isRight(), isTrue);
      expect(storedKeys[StorageKeys.boardDirty], SyncKeys.dirtyMarker);
    });

    test('a landed write retires a stale dirty flag', () async {
      storedKeys[StorageKeys.boardDirty] = SyncKeys.dirtyMarker;
      remoteHoldsBoard(_remoteBoard(revision: 9, updatedAt: _earlierInstant));

      await syncedOutcome();

      // The remote copy won, so the device owes the server nothing. Flushing
      // the stale flag later would re-upload the board that lost.
      expect(storedKeys.containsKey(StorageKeys.boardDirty), isFalse);
    });

    test('flushDirty uploads the marked document and clears it', () async {
      storedKeys[StorageKeys.boardDirty] = SyncKeys.dirtyMarker;

      await service.flushDirty(userId: _userId);

      expect(storedKeys.containsKey(StorageKeys.boardDirty), isFalse);
      expectBoardWasUploaded(_localBoard);
      verifyNever(
        () => remote.writePreferences(
          userId: any(named: 'userId'),
          preferences: any(named: 'preferences'),
        ),
      );
    });

    test('a second flushDirty is a no-op', () async {
      storedKeys[StorageKeys.boardDirty] = SyncKeys.dirtyMarker;

      await service.flushDirty(userId: _userId);
      await service.flushDirty(userId: _userId);

      // Zero reads and zero writes when nothing is pending is what makes this
      // free to call on every resume: the second call returns before it even
      // reads the document it would have pushed.
      expectBoardWasUploaded(_localBoard);
      verify(
        () => boardRepository.load(
          homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
        ),
      ).called(1);
    });

    test('flushDirty keeps the flag when the upload fails again', () async {
      storedKeys[StorageKeys.boardDirty] = SyncKeys.dirtyMarker;
      remoteRejectsBoardWrite(const RemoteUnavailableException());

      await service.flushDirty(userId: _userId);

      // Rule 3: no retry loop against a radio that is off, just a flag that
      // waits for a moment likely to work.
      expect(storedKeys[StorageKeys.boardDirty], SyncKeys.dirtyMarker);
    });
  });

  group('clearLocalData', () {
    test('removes both documents and both dirty flags', () async {
      storedKeys
        ..[StorageKeys.board] = '{}'
        ..[StorageKeys.preferences] = '{}'
        ..[StorageKeys.boardDirty] = SyncKeys.dirtyMarker
        ..[StorageKeys.preferencesDirty] = SyncKeys.dirtyMarker;

      await service.clearLocalData();

      // Rule 10: a pending write belonging to the account that just signed out
      // must not be flushed into the next session.
      expect(storedKeys, isEmpty);
      verify(() => store.remove(StorageKeys.board)).called(1);
      verify(() => store.remove(StorageKeys.preferences)).called(1);
      verify(() => store.remove(StorageKeys.boardDirty)).called(1);
      verify(() => store.remove(StorageKeys.preferencesDirty)).called(1);
    });

    test('leaves keys that belong to the device, not the account', () async {
      const deviceKey = 'timebuddy.hasSeenOnboarding';
      storedKeys[deviceKey] = 'true';

      await service.clearLocalData();

      expect(storedKeys, containsPair(deviceKey, 'true'));
      verifyNever(() => store.clearAll());
    });
  });

  group('the status stream', () {
    test('goes idle, syncing, idle around a sync that lands', () async {
      final seen = await statusesDuring(() => service.sync(userId: _userId));

      expect(seen, <SyncStatus>[
        SyncStatus.idle,
        SyncStatus.syncing,
        SyncStatus.idle,
      ]);
    });

    test('ends on offline when the pull cannot reach Firestore', () async {
      when(
        () => remote.readBoard(
          userId: any(named: 'userId'),
          homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
        ),
      ).thenThrow(const RemoteUnavailableException());

      late Either<Failure, SyncOutcome> result;
      final seen = await statusesDuring(() async {
        result = await service.sync(userId: _userId);
      });

      // Offline rather than error: waiting fixes it, so the indicator says so
      // and the profile page owes the user no explanation.
      expect(seen, <SyncStatus>[
        SyncStatus.idle,
        SyncStatus.syncing,
        SyncStatus.offline,
      ]);
      expect(result.isLeft(), isTrue);
    });

    test('ends on error when the remote refuses for good', () async {
      when(
        () => remote.readBoard(
          userId: any(named: 'userId'),
          homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
        ),
      ).thenThrow(const ServerException('permission-denied'));

      final seen = await statusesDuring(() => service.sync(userId: _userId));

      expect(seen.last, SyncStatus.error);
    });

    test('replays the last status to a listener that mounts later', () async {
      when(
        () => remote.readBoard(
          userId: any(named: 'userId'),
          homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
        ),
      ).thenThrow(const RemoteUnavailableException());
      await service.sync(userId: _userId);

      final seen = <SyncStatus>[];
      final subscription = service.status.listen(seen.add);
      await pumpEventQueue();
      await subscription.cancel();

      // The sidebar indicator mounts long after the startup sync, and a
      // broadcast controller drops everything emitted before `listen`.
      expect(seen, <SyncStatus>[SyncStatus.offline]);
    });
  });
}

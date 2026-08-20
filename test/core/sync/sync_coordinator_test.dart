import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_coordinator.dart';
import 'package:timebuddy/core/sync/sync_keys.dart';
import 'package:timebuddy/features/locations/data/datasources/board_local_datasource.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/data/repositories/board_repository_impl.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/preferences/data/datasources/preferences_local_datasource.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/data/repositories/preferences_repository_impl.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

import '../../harness/factories/board_factory.dart';
import '../../harness/factories/preferences_factory.dart';
import '../../harness/fake_clock.dart';
import '../../harness/helpers.dart';
import '../../harness/mocks.dart';

/// The Firestore boundary. Mocked, so "the write lands" and "the radio is
/// off" are two stubs rather than two emulator setups.
class _MockRemoteSettingsDataSource extends Mock
    implements RemoteSettingsDataSource {}

const String _userId = 'firebase-uid';

/// The launch instant the repositories seed against. Fixed and mid-January,
/// so it sits far from any DST transition.
final DateTime _launchInstant = utcDate(2024, 1, 15, 12);

/// The documents an ordinary edit produces: one revision past what the
/// factories hand out, so a document that reached the mock can be told apart
/// from a default one at a glance.
final BoardEntity _editedBoard = aBoard(
  locations: [aSavedLocation()],
  revision: 4,
);

final PreferencesEntity _editedPreferences = aPreferences(revision: 3);

void main() {
  setUpAll(() {
    // Real tzdata: the board model canonicalises zone ids through
    // `zoneOrNull`, so a file running against an empty database would encode a
    // board differently depending on which test file happened to run first.
    initTestTimeZones();
    registerCommonFallbacks();
    registerFallbackValue(BoardModel.fromEntity(aBoard()));
    registerFallbackValue(PreferencesModel.fromEntity(aPreferences()));
  });

  late _MockRemoteSettingsDataSource remote;
  late MockLocalStore store;
  late SyncCoordinator coordinator;
  late BoardRepositoryImpl boardRepository;
  late PreferencesRepositoryImpl preferencesRepository;

  /// The device store, backed by a real map.
  ///
  /// A dirty flag is asked about as often as it is written — "the flag is
  /// set", "the flag the push retired is gone" — and a `verify` on `writeRaw`
  /// cannot answer the second question. The map can answer both.
  late Map<String, String> storedKeys;

  BoardRepositoryImpl buildBoardRepository() {
    // The real datasource over a mocked store, not a mocked datasource: this
    // file is about the whole local-then-remote path of a save, and a stubbed
    // encoder would let a document reach Firestore that the disk never took.
    return BoardRepositoryImpl(
      localDataSource: BoardLocalDataSourceImpl(store),
      clock: FakeClock(_launchInstant),
      syncCoordinator: coordinator,
    );
  }

  PreferencesRepositoryImpl buildPreferencesRepository() {
    return PreferencesRepositoryImpl(
      localDataSource: PreferencesLocalDataSourceImpl(store),
      clock: FakeClock(_launchInstant),
      syncCoordinator: coordinator,
    );
  }

  setUp(() {
    remote = _MockRemoteSettingsDataSource();
    store = MockLocalStore();
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

    coordinator = SyncCoordinator(remoteDataSource: remote, localStore: store)
      ..startSession(userId: _userId);
    boardRepository = buildBoardRepository();
    preferencesRepository = buildPreferencesRepository();
  });

  /// Lets the push the repository fired finish.
  ///
  /// `save` deliberately does not await it (docs/specs/sync.md rule 2): the
  /// answer is decided by the local write, and a reorder must not wait on a
  /// round trip. Every assertion about the *remote* therefore has to let the
  /// event queue drain first.
  Future<void> settlePush() async {
    await pumpEventQueue();
  }

  /// The value of a `Right`, failing the test on a `Left` rather than handing
  /// back a null every expectation below would have to guard.
  T valueOf<T>(Either<Failure, T> result) =>
      result.getOrElse(() => fail('expected a Right, got $result'));

  void remoteRejectsBoardWrite() {
    when(
      () => remote.writeBoard(
        userId: any(named: 'userId'),
        board: any(named: 'board'),
      ),
    ).thenThrow(const RemoteUnavailableException());
  }

  void remoteRejectsPreferencesWrite() {
    when(
      () => remote.writePreferences(
        userId: any(named: 'userId'),
        preferences: any(named: 'preferences'),
      ),
    ).thenThrow(const RemoteUnavailableException());
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

  void expectPreferencesWereNotUploaded() {
    verifyNever(
      () => remote.writePreferences(
        userId: any(named: 'userId'),
        preferences: any(named: 'preferences'),
      ),
    );
  }

  void expectNothingIsDirty() {
    expect(storedKeys.containsKey(StorageKeys.boardDirty), isFalse);
    expect(storedKeys.containsKey(StorageKeys.preferencesDirty), isFalse);
  }

  group('an ordinary board edit', () {
    test('answers success and pushes the document (rules 1 and 2)', () async {
      final result = await boardRepository.save(_editedBoard);
      await settlePush();

      expect(valueOf(result), _editedBoard);
      expect(storedKeys[StorageKeys.board], isNotNull);
      expectBoardWasUploaded(_editedBoard);
      expectNothingIsDirty();
    });

    test('still answers success when the push fails (rules 3 and 4)', () async {
      remoteRejectsBoardWrite();

      final result = await boardRepository.save(_editedBoard);
      await settlePush();

      // The whole point of rule 4: the user reordered two cities, and a dead
      // radio is not something they did wrong.
      expect(valueOf(result), _editedBoard);
      expect(storedKeys[StorageKeys.board], isNotNull);
      expect(storedKeys[StorageKeys.boardDirty], SyncKeys.dirtyMarker);
    });

    test('retires a flag an earlier failed push left behind', () async {
      storedKeys[StorageKeys.boardDirty] = SyncKeys.dirtyMarker;

      await boardRepository.save(_editedBoard);
      await settlePush();

      // The server now holds this document, so the debt the flag described is
      // paid. Leaving it set would cost the next resume a pointless flush.
      expect(storedKeys.containsKey(StorageKeys.boardDirty), isFalse);
    });
  });

  group('an ordinary preferences edit', () {
    test('answers success and pushes the document (rules 1 and 2)', () async {
      final result = await preferencesRepository.save(_editedPreferences);
      await settlePush();

      expect(valueOf(result), _editedPreferences);
      expect(storedKeys[StorageKeys.preferences], isNotNull);
      verify(
        () => remote.writePreferences(
          userId: _userId,
          preferences: PreferencesModel.fromEntity(_editedPreferences),
        ),
      ).called(1);
      expectNothingIsDirty();
    });

    test('still answers success when the push fails (rules 3 and 4)', () async {
      remoteRejectsPreferencesWrite();

      final result = await preferencesRepository.save(_editedPreferences);
      await settlePush();

      expect(valueOf(result), _editedPreferences);
      expect(storedKeys[StorageKeys.preferencesDirty], SyncKeys.dirtyMarker);
      // Revisions are per document (rule 7): a failed preferences push says
      // nothing about the board.
      expect(storedKeys.containsKey(StorageKeys.boardDirty), isFalse);
    });
  });

  group('with no signed-in account', () {
    setUp(() {
      // Built without `startSession`, which is what a launch before auth has
      // resolved, and every signed-out session, actually looks like.
      coordinator = SyncCoordinator(
        remoteDataSource: remote,
        localStore: store,
      );
      boardRepository = buildBoardRepository();
      preferencesRepository = buildPreferencesRepository();
      // Stubbed to fail, so "nothing is dirty" below can only be explained by
      // the push never being attempted at all.
      remoteRejectsBoardWrite();
      remoteRejectsPreferencesWrite();
    });

    test('a save still lands locally and answers success', () async {
      final result = await boardRepository.save(_editedBoard);
      await settlePush();

      expect(valueOf(result), _editedBoard);
      expect(storedKeys[StorageKeys.board], isNotNull);
    });

    test('nothing is pushed and nothing is marked dirty', () async {
      await boardRepository.save(_editedBoard);
      await preferencesRepository.save(_editedPreferences);
      await settlePush();

      expect(coordinator.hasSession, isFalse);
      expectBoardWasNotUploaded();
      expectPreferencesWereNotUploaded();
      // Signed out is not dirty (rule 10): a flag set with no account behind
      // it would be found by the *next* user's flush and would push this
      // device's documents into their account.
      expectNothingIsDirty();
    });
  });

  group('when the session ends', () {
    test('further saves push nothing and mark nothing', () async {
      await boardRepository.save(_editedBoard);
      await settlePush();
      expectBoardWasUploaded(_editedBoard);

      coordinator.endSession();
      remoteRejectsBoardWrite();

      final result = await boardRepository.save(
        _editedBoard.copyWith(revision: 5),
      );
      await settlePush();

      expect(coordinator.hasSession, isFalse);
      expect(valueOf(result).revision, 5);
      // The stub that would have thrown was never reached, so a signed-out
      // save is silent on both sides.
      expectBoardWasNotUploaded();
      expectNothingIsDirty();
    });
  });
}

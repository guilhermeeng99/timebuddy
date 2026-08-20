import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/features/locations/data/datasources/board_local_datasource.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/data/repositories/board_repository_impl.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';

import '../../../../harness/factories/board_factory.dart';
import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

/// The zone the cubit would have read off the device.
const String _deviceZoneId = 'America/Sao_Paulo';

void main() {
  setUpAll(registerCommonFallbacks);

  final launchInstant = utcDate(2024, 1, 15, 12);

  // Mocked at the store, not at the datasource: the datasource is a thin
  // encode/decode wrapper, and letting the real one run keeps these tests
  // honest about the JSON that actually reaches the disk.
  late MockLocalStore store;
  late FakeClock clock;
  late BoardRepositoryImpl repository;

  setUp(() {
    store = MockLocalStore();
    clock = FakeClock(launchInstant);
    repository = BoardRepositoryImpl(
      localDataSource: BoardLocalDataSourceImpl(store),
      clock: clock,
    );
    when(() => store.writeRaw(any(), any())).thenAnswer((_) async {});
  });

  void storeHolds(String? document) {
    when(
      () => store.readRaw(StorageKeys.board),
    ).thenAnswer((_) async => document);
  }

  String encoded(BoardEntity board) =>
      jsonEncode(BoardModel.fromEntity(board).toJson());

  /// Reads back what the repository actually put on disk.
  ///
  /// Call once per test: mocktail only matches calls it has not verified yet,
  /// so a second call finds nothing.
  BoardModel lastWrittenDocument() {
    final captured = verify(
      () => store.writeRaw(StorageKeys.board, captureAny()),
    ).captured;
    return BoardModel.fromJson(
      jsonDecode(captured.last as String) as Map<String, dynamic>,
      homeZoneIdFallback: _deviceZoneId,
    );
  }

  BoardEntity valueOf(Either<Failure, BoardEntity> result) =>
      result.getOrElse(() => fail('expected a Right, got $result'));

  Failure failureOf(Either<Failure, BoardEntity> result) =>
      result.fold((failure) => failure, (_) => fail('expected a Left'));

  Future<Either<Failure, BoardEntity>> load() =>
      repository.load(homeZoneIdFallback: _deviceZoneId);

  group('load', () {
    test('returns the stored board without rewriting it', () async {
      final stored = aBoard(
        homeZoneId: 'Europe/Berlin',
        locations: [aSavedLocation()],
        revision: 4,
      );
      storeHolds(encoded(stored));

      final result = await load();

      expect(valueOf(result).props, stored.props);
      // The device zone loses to a stored home zone: seeding is a first-launch
      // event only (docs/specs/locations.md rule 3).
      expect(valueOf(result).homeZoneId, 'Europe/Berlin');
      verifyNever(() => store.writeRaw(any(), any()));
    });

    test('seeds an empty board from the fallback zone', () async {
      storeHolds(null);

      final board = valueOf(await load());

      expect(board.homeZoneId, _deviceZoneId);
      expect(board.locations, isEmpty);
      // Zero, so a missing remote document (revision -1) still loses the
      // first reconciliation to this seed (docs/specs/sync.md, Provisioning).
      expect(board.revision, 0);
      expect(board.updatedAt, launchInstant);
    });

    // Written on the spot rather than on the first mutation: an unwritten seed
    // would be re-derived from whatever zone the device reports next launch,
    // moving the reference every offset on the board is measured against.
    test('persists the seeded board immediately', () async {
      storeHolds(null);

      final board = valueOf(await load());

      expect(lastWrittenDocument().props, board.props);
    });

    test('writes under the versioned board key', () async {
      storeHolds(null);

      await load();

      verify(() => store.writeRaw(StorageKeys.board, any())).called(1);
    });

    // A row nobody can parse costs the user that row, never the board.
    test('keeps the readable rows of a partly malformed document', () async {
      storeHolds(
        jsonEncode(<String, dynamic>{
          'homeZoneId': 'Europe/Berlin',
          'locations': [
            {
              'id': 'row-tokyo',
              'zoneId': 'Asia/Tokyo',
              'label': 'Tokyo',
              'countryCode': 'JP',
              'sortIndex': 0,
              'addedAt': '2024-01-15T12:00:00.000Z',
            },
            'not a row',
          ],
          'revision': 2,
          'updatedAt': '2024-01-15T12:00:00.000Z',
        }),
      );

      final board = valueOf(await load());

      expect(board.locations.map((row) => row.id), ['row-tokyo']);
    });

    test('maps an unreadable document to a StorageFailure', () async {
      storeHolds('}{ not json at all');

      expect(failureOf(await load()), isA<StorageFailure>());
    });

    test('maps a refused write during seeding to a StorageFailure', () async {
      storeHolds(null);
      when(
        () => store.writeRaw(any(), any()),
      ).thenThrow(const StorageException('disk full'));

      final failure = failureOf(await load());

      expect(failure, isA<StorageFailure>());
      // The message rides along for the log only; the UI localises by type
      // (failures.dart) and never renders it.
      expect(failure.message, 'disk full');
    });
  });

  group('save', () {
    test('writes through and echoes the board back', () async {
      final board = aBoard(locations: [aSavedLocation()], revision: 9);

      final result = await repository.save(board);

      expect(result, Right<Failure, BoardEntity>(board));
      expect(lastWrittenDocument().props, board.props);
    });

    // Bumping the revision is deliberately the caller's job: a re-save during
    // sync reconciliation would inflate the very revision it is reconciling.
    test('persists the revision and stamp it was given, unchanged', () async {
      final board = aBoard(revision: 9, updatedAt: utcDate(2024, 6, 1, 8, 30));

      await repository.save(board);

      // The stamp differs from the clock's instant here precisely so a
      // restamp would show up as a failure.
      final persisted = lastWrittenDocument();
      expect(persisted.revision, 9);
      expect(persisted.updatedAt, board.updatedAt);
    });

    test('maps a refused write to a StorageFailure', () async {
      when(
        () => store.writeRaw(any(), any()),
      ).thenThrow(const StorageException());

      expect(failureOf(await repository.save(aBoard())), isA<StorageFailure>());
    });

    test('a saved board reloads identically', () async {
      final board = aBoard(
        homeZoneId: 'Asia/Tokyo',
        locations: [
          aSavedLocation(),
          aSavedLocation(
            id: 'row-berlin',
            zoneId: 'Europe/Berlin',
            label: 'Berlin',
            countryCode: 'DE',
            sortIndex: 1,
          ),
        ],
        revision: 3,
      );

      await repository.save(board);
      storeHolds(encoded(board));

      expect(valueOf(await load()).props, board.props);
    });
  });
}

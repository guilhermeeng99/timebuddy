import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/sync/sync_coordinator.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/features/locations/data/datasources/board_local_datasource.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';

/// Local-first implementation of the board document: `shared_preferences` is
/// the read path and decides the answer, Firestore is the durability path and
/// runs behind it (docs/specs/sync.md rules 1 and 2).
///
/// The reconciling *read* is not here. It belongs to `SyncServiceImpl`, which
/// is the one owner of the conflict ladder (rule 5) for both documents; a
/// `load` that pulled the remote copy would be a second owner of it, and two
/// owners of a merge rule are one disagreement away from losing a board.
class BoardRepositoryImpl implements BoardRepository {
  const BoardRepositoryImpl({
    required BoardLocalDataSource localDataSource,
    required Clock clock,
    required SyncCoordinator syncCoordinator,
  }) : _localDataSource = localDataSource,
       _clock = clock,
       _syncCoordinator = syncCoordinator;

  final BoardLocalDataSource _localDataSource;
  final Clock _clock;

  /// The signed-in account's write path, or `null` in a build that has no
  /// remote half — which is also what every repository-level test runs as.
  /// A missing coordinator behaves exactly like a signed-out one: the local
  /// write still lands and nothing is marked dirty.
  final SyncCoordinator _syncCoordinator;

  @override
  Future<Either<Failure, BoardEntity>> load({
    required String homeZoneIdFallback,
  }) async {
    try {
      final stored = await _localDataSource.read(
        homeZoneIdFallback: homeZoneIdFallback,
      );
      if (stored != null) return Right(stored);

      final seeded = BoardEntity.empty(
        homeZoneId: homeZoneIdFallback,
        now: _clock.nowUtc(),
      );
      // Persisted at once so the home zone is frozen on this first launch:
      // an unwritten seed would be re-derived from whatever zone the device
      // reports next time, silently moving the reference every offset on the
      // board is measured against when the user travels
      // (docs/specs/locations.md rule 3).
      await _localDataSource.write(BoardModel.fromEntity(seeded));
      return Right(seeded);
    } on CacheException catch (error) {
      return Left(StorageFailure(error.message));
    } on StorageException catch (error) {
      return Left(StorageFailure(error.message));
    }
  }

  @override
  Future<Either<Failure, BoardEntity>> save(BoardEntity board) async {
    try {
      await _localDataSource.write(BoardModel.fromEntity(board));
    } on CacheException catch (error) {
      return Left(StorageFailure(error.message));
    } on StorageException catch (error) {
      return Left(StorageFailure(error.message));
    }

    // Rule 2, and the reason this is not awaited: the local write already
    // decided the answer, and a reorder that waited on a Firestore round trip
    // would freeze the list for as long as the network felt like taking. The
    // coordinator swallows the failure and marks the document dirty (rules 3
    // and 4), so nothing here can turn a bad radio into a Left.
    unawaited(_syncCoordinator.pushBoard(board));
    return Right(board);
  }
}

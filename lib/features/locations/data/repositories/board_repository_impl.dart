import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/features/locations/data/datasources/board_local_datasource.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';

// TODO(sync): M3 attaches the Firestore mirror described in docs/specs/sync.md
// here: `save` keeps writing locally and returning success first, then pushes
// to `users/{userId}/settings/board` and sets `StorageKeys.boardDirty` when
// that push fails (rules 2 and 3), and `load` grows the reconciling read that
// compares `revision` before `updatedAt` (rule 5). No remote datasource is
// stubbed now, because an empty one would have to guess that contract.

/// Local-only implementation for M2: `shared_preferences` is both the read
/// path and the durability path until the sync layer lands.
class BoardRepositoryImpl implements BoardRepository {
  const BoardRepositoryImpl({
    required BoardLocalDataSource localDataSource,
    required Clock clock,
  }) : _localDataSource = localDataSource,
       _clock = clock;

  final BoardLocalDataSource _localDataSource;
  final Clock _clock;

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
      return Right(board);
    } on CacheException catch (error) {
      return Left(StorageFailure(error.message));
    } on StorageException catch (error) {
      return Left(StorageFailure(error.message));
    }
  }
}

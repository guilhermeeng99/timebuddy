import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/features/preferences/data/datasources/preferences_local_datasource.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';

// TODO(sync): M3 adds the Firestore mirror described in docs/specs/sync.md:
// write locally, return success, then push to
// `users/{userId}/settings/preferences` and set `StorageKeys.preferencesDirty`
// when that push fails (rules 2 and 3). No remote datasource is stubbed here
// because an empty one would have to guess the reconciliation contract.

/// Local-only implementation for M1: `shared_preferences` is both the read
/// path and the durability path until the sync layer lands.
class PreferencesRepositoryImpl implements PreferencesRepository {
  const PreferencesRepositoryImpl({
    required PreferencesLocalDataSource localDataSource,
    required Clock clock,
  })  : _localDataSource = localDataSource,
        _clock = clock;

  final PreferencesLocalDataSource _localDataSource;
  final Clock _clock;

  @override
  Future<Either<Failure, PreferencesEntity>> load({
    required Locale deviceLocale,
  }) async {
    try {
      final stored = await _localDataSource.read();
      if (stored != null) return Right(stored);

      final seeded = PreferencesEntity.defaults(
        now: _clock.nowUtc(),
        deviceLocale: deviceLocale,
      );
      // Persisted at once so the locale-derived seeds are frozen on this first
      // launch: leaving them unwritten would re-derive them from whatever
      // locale the device reports next time (preferences.md rule 2).
      await _localDataSource.write(PreferencesModel.fromEntity(seeded));
      return Right(seeded);
    } on CacheException catch (error) {
      return Left(StorageFailure(error.message));
    } on StorageException catch (error) {
      return Left(StorageFailure(error.message));
    }
  }

  @override
  Future<Either<Failure, PreferencesEntity>> save(
    PreferencesEntity preferences,
  ) async {
    try {
      await _localDataSource.write(PreferencesModel.fromEntity(preferences));
      return Right(preferences);
    } on CacheException catch (error) {
      return Left(StorageFailure(error.message));
    } on StorageException catch (error) {
      return Left(StorageFailure(error.message));
    }
  }
}

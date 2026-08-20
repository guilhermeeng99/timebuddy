import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/sync/sync_coordinator.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/features/preferences/data/datasources/preferences_local_datasource.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';

/// Local-first implementation of the preferences document: the device store
/// decides the answer, Firestore runs behind it (docs/specs/sync.md rules 1
/// and 2).
///
/// The remote half is one line, and deliberately so — `SyncCoordinator` owns
/// the account id and the dirty flag, so this class still knows nothing about
/// who is signed in.
class PreferencesRepositoryImpl implements PreferencesRepository {
  const PreferencesRepositoryImpl({
    required PreferencesLocalDataSource localDataSource,
    required Clock clock,
    required SyncCoordinator syncCoordinator,
  }) : _localDataSource = localDataSource,
       _clock = clock,
       _syncCoordinator = syncCoordinator;

  final PreferencesLocalDataSource _localDataSource;
  final Clock _clock;

  /// The signed-in account's write path, or `null` in a build that has no
  /// remote half — which is also what every repository-level test runs as.
  /// A missing coordinator behaves exactly like a signed-out one: the local
  /// write still lands and nothing is marked dirty.
  final SyncCoordinator _syncCoordinator;

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
    } on CacheException catch (error) {
      return Left(StorageFailure(error.message));
    } on StorageException catch (error) {
      return Left(StorageFailure(error.message));
    }

    // Rule 2, and not awaited: a theme switch is applied in the frame the user
    // taps it, and awaiting Firestore here would hold the new palette behind
    // the network. The coordinator turns a failed push into a dirty flag, so
    // durability is retried without the user ever hearing about it (rules 3
    // and 4).
    unawaited(_syncCoordinator.pushPreferences(preferences));
    return Right(preferences);
  }
}

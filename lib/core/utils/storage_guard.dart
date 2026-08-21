import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';

/// Runs [body] and translates the device store's two exceptions into the one
/// [StorageFailure] the UI knows how to render.
///
/// This is the repository half of the contract `exceptions.dart` describes:
/// data sources throw, the repository that owns them catches and hands back a
/// `Failure`, and nothing above the repository layer ever sees an exception.
/// [CacheException] (a document that is present but unreadable) and
/// [StorageException] (a write the platform refused) both become
/// `StorageFailure` because the user-facing recovery is identical — the
/// distinction between them earns its keep at the data source, not on screen —
/// and [Failure.message] carries the thrown message through for the logs.
///
/// Only those two are caught. Anything else is a bug rather than a device
/// condition, and swallowing it here would hide it behind a snackbar about
/// local storage.
///
/// ```dart
/// Future<Either<Failure, PreferencesEntity>> load() {
///   return guardStorage(() async {
///     final stored = await _localDataSource.read();
///     return stored ?? await _seedDefaults();
///   });
/// }
/// ```
Future<Either<Failure, T>> guardStorage<T>(Future<T> Function() body) async {
  try {
    return Right(await body());
  } on CacheException catch (error) {
    return Left(StorageFailure(error.message));
  } on StorageException catch (error) {
    return Left(StorageFailure(error.message));
  }
}

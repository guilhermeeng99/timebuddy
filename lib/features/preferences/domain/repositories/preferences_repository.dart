import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

/// Local-first access to the preferences document (docs/specs/sync.md rule 1).
///
/// **No method here takes a `userId`, and that is a decision, not an
/// omission.** The remote write that follows a local one needs an account id
/// (rule 2), but the account is session state: `SyncCoordinator`
/// (`lib/core/sync/sync_coordinator.dart`) holds it and the implementation
/// hands it the saved document, so neither this contract nor the cubit above
/// it has to know who is signed in.
///
/// ```dart
/// const deviceLocale = Locale('en', 'US');
/// final result = await repository.load(deviceLocale: deviceLocale);
/// final preferences = result.getOrElse(() => fallback);
/// ```
abstract class PreferencesRepository {
  /// Reads the stored document, seeding and persisting the locale-derived
  /// defaults when nothing has been written yet (preferences.md rules 1 and 2).
  ///
  /// [deviceLocale] is only consulted on that first seeding.
  Future<Either<Failure, PreferencesEntity>> load({
    required Locale deviceLocale,
  });

  /// Persists [preferences] as given, then pushes them to the account in the
  /// background (rule 2).
  ///
  /// Answers `Right` as soon as the *local* write lands. A failed remote write
  /// is never a `Left` (rule 4): it sets a dirty flag and is retried by
  /// `SyncService` on the next start, sync or resume (rule 3). A `Left` here
  /// therefore means the device store refused the write.
  ///
  /// Bumping `revision` and stamping `updatedAt` is the caller's job, so a
  /// re-save during sync reconciliation does not inflate the revision it is
  /// trying to reconcile.
  Future<Either<Failure, PreferencesEntity>> save(
    PreferencesEntity preferences,
  );
}

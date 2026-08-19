import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

/// Local-first access to the preferences document (docs/specs/sync.md rule 1).
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

  /// Persists [preferences] as given. Bumping `revision` and stamping
  /// `updatedAt` is the caller's job, so a re-save during sync reconciliation
  /// does not inflate the revision it is trying to reconcile.
  Future<Either<Failure, PreferencesEntity>> save(
    PreferencesEntity preferences,
  );
}

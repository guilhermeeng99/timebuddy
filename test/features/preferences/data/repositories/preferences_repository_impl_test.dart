import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_coordinator.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/data/datasources/preferences_local_datasource.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/data/repositories/preferences_repository_impl.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

import '../../../../harness/factories/preferences_factory.dart';
import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  const brazilianDevice = Locale('pt', 'BR');
  const americanDevice = Locale('en', 'US');
  final launchInstant = utcDate(2024, 1, 15, 12);

  // Mocked at the store, not at the datasource: the datasource is a thin
  // encode/decode wrapper, and letting the real one run keeps these tests
  // honest about the JSON that actually reaches the disk.
  late MockLocalStore store;
  late FakeClock clock;
  late _MockRemoteSettings remote;
  late PreferencesRepositoryImpl repository;

  setUp(() {
    store = MockLocalStore();
    clock = FakeClock(launchInstant);
    remote = _MockRemoteSettings();
    // Signed out on purpose: these tests are about the LOCAL half of
    // the write. A coordinator with no session pushes nothing, so the
    // assertions below stay about the store and nothing else.
    repository = PreferencesRepositoryImpl(
      localDataSource: PreferencesLocalDataSourceImpl(store),
      clock: clock,
      syncCoordinator: SyncCoordinator(
        remoteDataSource: remote,
        localStore: store,
      ),
    );
    when(() => store.writeRaw(any(), any())).thenAnswer((_) async {});
  });

  void storeHolds(String? document) {
    when(
      () => store.readRaw(StorageKeys.preferences),
    ).thenAnswer((_) async => document);
  }

  String encoded(PreferencesEntity entity) =>
      jsonEncode(PreferencesModel.fromEntity(entity).toJson());

  /// Reads back what the repository actually put on disk.
  ///
  /// Call once per test: mocktail only matches calls it has not verified yet,
  /// so a second call finds nothing.
  PreferencesModel lastWrittenDocument() {
    final raw = verify(
      () => store.writeRaw(StorageKeys.preferences, captureAny()),
    ).captured.last as String;
    return PreferencesModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  PreferencesEntity valueOf(Either<Failure, PreferencesEntity> result) =>
      result.getOrElse(() => fail('expected a Right, got $result'));

  Failure failureOf(Either<Failure, PreferencesEntity> result) =>
      result.fold((failure) => failure, (_) => fail('expected a Left'));

  group('load', () {
    test('returns the stored document without rewriting it', () async {
      final stored = aPreferences(
        hourFormat: ClockFormat.h12,
        workingHours: const WorkingHours(startHour: 22, endHour: 6),
        localeTag: 'en',
        revision: 4,
      );
      storeHolds(encoded(stored));

      // A pt-BR device would seed h24, so a stored h12 surviving is the proof
      // that seeding is a first-launch event only (preferences.md rule 2).
      final result = await repository.load(deviceLocale: brazilianDevice);

      expect(
        result,
        Right<Failure, PreferencesEntity>(PreferencesModel.fromEntity(stored)),
      );
      verifyNever(() => store.writeRaw(any(), any()));
    });

    test('seeds the defaults when nothing is stored', () async {
      storeHolds(null);

      final result = await repository.load(deviceLocale: brazilianDevice);

      expect(
        result,
        Right<Failure, PreferencesEntity>(
          PreferencesEntity.defaults(
            now: launchInstant,
            deviceLocale: brazilianDevice,
          ),
        ),
      );
    });

    // Written on the spot rather than on the next mutation: an unwritten seed
    // would be re-derived from whatever locale the device reports next launch,
    // silently rewriting a setting that now belongs to the user (rule 2).
    test('persists the seeded defaults immediately', () async {
      storeHolds(null);

      final result = await repository.load(deviceLocale: brazilianDevice);

      expect(lastWrittenDocument().props, valueOf(result).props);
    });

    test('seeds 24h and Monday on a pt-BR device', () async {
      storeHolds(null);

      final seeded = valueOf(
        await repository.load(deviceLocale: brazilianDevice),
      );

      expect(seeded.hourFormat, ClockFormat.h24);
      expect(seeded.weekStartsOn, WeekStart.monday);
      expect(seeded.localeTag, isNull);
      expect(seeded.revision, 0);
      expect(seeded.updatedAt, launchInstant);
    });

    test('seeds 12h and Sunday on an en-US device', () async {
      storeHolds(null);

      final seeded = valueOf(
        await repository.load(deviceLocale: americanDevice),
      );

      expect(seeded.hourFormat, ClockFormat.h12);
      expect(seeded.weekStartsOn, WeekStart.sunday);
      expect(seeded.localeTag, isNull);
    });

    test('maps an unreadable document to a StorageFailure', () async {
      storeHolds('}{ not json at all');

      final result = await repository.load(deviceLocale: brazilianDevice);

      expect(failureOf(result), isA<StorageFailure>());
    });

    test('maps a refused write during seeding to a StorageFailure', () async {
      storeHolds(null);
      when(
        () => store.writeRaw(any(), any()),
      ).thenThrow(const StorageException('disk full'));

      final result = await repository.load(deviceLocale: brazilianDevice);

      final failure = failureOf(result);
      expect(failure, isA<StorageFailure>());
      // The message rides along for the log only; the UI localises by type
      // (failures.dart) and never renders it.
      expect(failure.message, 'disk full');
    });
  });

  group('save', () {
    test('writes through and echoes the document back', () async {
      final preferences = aPreferences(showSeconds: true, revision: 9);

      final result = await repository.save(preferences);

      expect(result, Right<Failure, PreferencesEntity>(preferences));
      expect(lastWrittenDocument().props, preferences.props);
    });

    test('writes under the versioned preferences key', () async {
      await repository.save(aPreferences());

      verify(() => store.writeRaw(StorageKeys.preferences, any())).called(1);
    });

    // Bumping the revision is deliberately the caller's job: a re-save during
    // sync reconciliation would inflate the very revision it is reconciling.
    test('persists the revision and stamp it was given, unchanged', () async {
      final preferences = aPreferences(
        revision: 9,
        updatedAt: utcDate(2024, 6, 1, 8, 30),
      );

      await repository.save(preferences);

      // The stamp is the caller's too: it differs from the clock's instant
      // here precisely so a restamp would show up as a failure.
      final persisted = lastWrittenDocument();
      expect(persisted.revision, 9);
      expect(persisted.updatedAt, preferences.updatedAt);
    });

    test('maps a refused write to a StorageFailure', () async {
      when(
        () => store.writeRaw(any(), any()),
      ).thenThrow(const StorageException());

      final result = await repository.save(aPreferences());

      expect(failureOf(result), isA<StorageFailure>());
    });

    test('a saved document reloads identically', () async {
      final preferences = aPreferences(
        hourFormat: ClockFormat.h12,
        workingHours: const WorkingHours(startHour: 22, endHour: 6),
        showSeconds: true,
        localeTag: 'pt-BR',
        revision: 3,
      );

      await repository.save(preferences);
      storeHolds(encoded(preferences));

      final reloaded = valueOf(
        await repository.load(deviceLocale: americanDevice),
      );
      expect(reloaded.props, preferences.props);
    });
  });
}

/// Local-only tests still have to hand the repository a coordinator,
/// and a coordinator needs a remote. It is never reached: no session is
/// ever started on it.
class _MockRemoteSettings extends Mock implements RemoteSettingsDataSource {}

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';

import '../../../../harness/factories/preferences_factory.dart';
import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

/// One setter under test: how to invoke it, and the document it must produce
/// before the revision and the stamp are applied.
typedef SetterCase = ({
  Future<void> Function(PreferencesCubit cubit) act,
  PreferencesEntity expected,
});

void main() {
  setUpAll(registerCommonFallbacks);

  final mutationInstant = utcDate(2024, 1, 15, 12);
  final laterInstant = utcDate(2024, 1, 15, 12, 5);

  // A non-default revision and a real locale tag, so a bump and a clear are
  // both visible changes rather than coincidences.
  final seeded = aPreferences(revision: 3, localeTag: 'pt-BR');
  final reconciled = aPreferences(
    themeMode: ThemeMode.light,
    revision: 12,
    updatedAt: utcDate(2024, 2),
  );

  const storageFailure = Left<Failure, PreferencesEntity>(StorageFailure());

  late MockPreferencesRepository repository;
  late FakeClock clock;

  setUp(() {
    repository = MockPreferencesRepository();
    clock = FakeClock(mutationInstant);
    when(
      () => repository.save(any()),
    ).thenAnswer((_) async => Right<Failure, PreferencesEntity>(seeded));
  });

  PreferencesCubit buildCubit() =>
      PreferencesCubit(repository: repository, clock: clock);

  void stubLoad(Either<Failure, PreferencesEntity> result) {
    when(
      () => repository.load(deviceLocale: any(named: 'deviceLocale')),
    ).thenAnswer((_) async => result);
  }

  /// The single state one mutation of [seeded] must emit: the changed field,
  /// one more revision, and the clock's instant (sync.md rule 5).
  List<PreferencesState> statesAfter(PreferencesEntity changed) => [
        PreferencesReady(
          changed.copyWith(
            revision: seeded.revision + 1,
            updatedAt: mutationInstant,
          ),
        ),
      ];

  test('starts in PreferencesLoading until the first read resolves', () {
    // Only the startup splash ever sees this state, which is why it is not in
    // any blocTest below: bloc_test records emissions, not the initial value.
    final cubit = buildCubit();
    addTearDown(cubit.close);

    expect(cubit.state, const PreferencesLoading());
  });

  group('load', () {
    blocTest<PreferencesCubit, PreferencesState>(
      'emits the stored document once the read resolves',
      setUp: () => stubLoad(Right<Failure, PreferencesEntity>(seeded)),
      build: buildCubit,
      act: (cubit) async {
        await cubit.load(deviceLocale: const Locale('pt', 'BR'));
      },
      expect: () => [PreferencesReady(seeded)],
    );

    // preferences.md, State Machine: there is no error state. A device that
    // cannot read its own storage still gets a coherent app; durability is the
    // sync layer's to report passively (sync.md rule 4).
    blocTest<PreferencesCubit, PreferencesState>(
      'falls back to locale-seeded defaults when the read fails',
      setUp: () => stubLoad(storageFailure),
      build: buildCubit,
      act: (cubit) async {
        await cubit.load(deviceLocale: const Locale('en', 'US'));
      },
      expect: () => [
        PreferencesReady(
          PreferencesEntity.defaults(
            now: mutationInstant,
            deviceLocale: const Locale('en', 'US'),
          ),
        ),
      ],
    );
  });

  group('setters', () {
    // Table-driven: every setter obeys the same contract, so the part worth
    // reading is which field each one moves, not nine near-identical bodies.
    final setterCases = <String, SetterCase>{
      'setThemeMode': (
        act: (cubit) => cubit.setThemeMode(ThemeMode.dark),
        expected: seeded.copyWith(themeMode: ThemeMode.dark),
      ),
      'setLightPalette': (
        act: (cubit) => cubit.setLightPalette(LightPalette.sunsetCoral),
        expected: seeded.copyWith(lightPalette: LightPalette.sunsetCoral),
      ),
      'setDarkPalette': (
        act: (cubit) => cubit.setDarkPalette(DarkPalette.crimsonEmber),
        expected: seeded.copyWith(darkPalette: DarkPalette.crimsonEmber),
      ),
      'setClockFormat': (
        act: (cubit) => cubit.setClockFormat(ClockFormat.h12),
        expected: seeded.copyWith(hourFormat: ClockFormat.h12),
      ),
      'setWorkingHours': (
        act: (cubit) => cubit.setWorkingHours(
          const WorkingHours(startHour: 22, endHour: 6),
        ),
        expected: seeded.copyWith(
          workingHours: const WorkingHours(startHour: 22, endHour: 6),
        ),
      ),
      'setWeekStart': (
        act: (cubit) => cubit.setWeekStart(WeekStart.sunday),
        expected: seeded.copyWith(weekStartsOn: WeekStart.sunday),
      ),
      'setShowSeconds': (
        act: (cubit) => cubit.setShowSeconds(value: true),
        expected: seeded.copyWith(showSeconds: true),
      ),
      'setLocaleTag': (
        act: (cubit) => cubit.setLocaleTag('en'),
        expected: seeded.copyWith(localeTag: 'en'),
      ),
      // `null` is a value, not an absence: it means follow the device again
      // (preferences.md rule 3).
      'setLocaleTag(null)': (
        act: (cubit) => cubit.setLocaleTag(null),
        expected: seeded.copyWith(clearLocaleTag: true),
      ),
    };

    for (final setter in setterCases.entries) {
      blocTest<PreferencesCubit, PreferencesState>(
        '${setter.key} emits the updated document and persists it',
        build: buildCubit,
        seed: () => PreferencesReady(seeded),
        act: (cubit) async {
          await setter.value.act(cubit);
        },
        expect: () => statesAfter(setter.value.expected),
        verify: (_) {
          verify(() => repository.save(any())).called(1);
        },
      );
    }

    blocTest<PreferencesCubit, PreferencesState>(
      'setWorkingHours clamps a window longer than 16 hours',
      build: buildCubit,
      seed: () => PreferencesReady(seeded),
      act: (cubit) async {
        // 17 hours. Past the cap the bands stop discriminating, and there is
        // no partial repair: a pair this wrong carries no reliable intent, so
        // the whole default window comes back (preferences.md rule 5).
        await cubit.setWorkingHours(
          const WorkingHours(startHour: 6, endHour: 23),
        );
      },
      expect: () => statesAfter(
        seeded.copyWith(workingHours: WorkingHours.defaultHours),
      ),
    );

    blocTest<PreferencesCubit, PreferencesState>(
      'setWorkingHours clamps a window whose start equals its end',
      build: buildCubit,
      seed: () => PreferencesReady(seeded),
      act: (cubit) async {
        await cubit.setWorkingHours(
          const WorkingHours(startHour: 9, endHour: 9),
        );
      },
      expect: () => statesAfter(
        seeded.copyWith(workingHours: WorkingHours.defaultHours),
      ),
    );

    blocTest<PreferencesCubit, PreferencesState>(
      'keeps the new value when the write fails, with no error state',
      setUp: () {
        when(
          () => repository.save(any()),
        ).thenAnswer((_) async => storageFailure);
      },
      build: buildCubit,
      seed: () => PreferencesReady(seeded),
      act: (cubit) async {
        await cubit.setShowSeconds(value: true);
      },
      // Exactly one state: the optimistic one. A rollback or an error state
      // would show up here as a second emission (sync.md rule 4).
      expect: () => statesAfter(seeded.copyWith(showSeconds: true)),
      verify: (cubit) {
        expect(
          cubit.state,
          isA<PreferencesReady>().having(
            (state) => state.preferences.showSeconds,
            'showSeconds',
            isTrue,
          ),
        );
      },
    );

    blocTest<PreferencesCubit, PreferencesState>(
      'ignores a mutation that arrives before the first load resolves',
      build: buildCubit,
      act: (cubit) async {
        await cubit.setThemeMode(ThemeMode.dark);
      },
      // Settings are unreachable before startup finishes, so a mutation here
      // is a caller jumping the gun; inventing a document to mutate would
      // hand it back as if it were the user's.
      expect: () => <PreferencesState>[],
      verify: (_) {
        verifyNever(() => repository.save(any()));
      },
    );
  });

  group('revision and stamp', () {
    blocTest<PreferencesCubit, PreferencesState>(
      'every mutation bumps the revision and restamps updatedAt',
      build: buildCubit,
      seed: () => PreferencesReady(seeded),
      act: (cubit) async {
        await cubit.setClockFormat(ClockFormat.h12);
        clock.advance(const Duration(minutes: 5));
        await cubit.setWeekStart(WeekStart.sunday);
      },
      expect: () => [
        PreferencesReady(
          seeded.copyWith(
            hourFormat: ClockFormat.h12,
            revision: seeded.revision + 1,
            updatedAt: mutationInstant,
          ),
        ),
        PreferencesReady(
          seeded.copyWith(
            hourFormat: ClockFormat.h12,
            weekStartsOn: WeekStart.sunday,
            revision: seeded.revision + 2,
            updatedAt: laterInstant,
          ),
        ),
      ],
    );

    blocTest<PreferencesCubit, PreferencesState>(
      'persists the same document it emitted',
      build: buildCubit,
      seed: () => PreferencesReady(seeded),
      act: (cubit) async {
        await cubit.setThemeMode(ThemeMode.dark);
      },
      verify: (_) {
        final saved = verify(
          () => repository.save(captureAny()),
        ).captured.last as PreferencesEntity;

        expect(
          saved.props,
          seeded
              .copyWith(
                themeMode: ThemeMode.dark,
                revision: seeded.revision + 1,
                updatedAt: mutationInstant,
              )
              .props,
        );
      },
    );
  });

  group('adoptFromSync', () {
    blocTest<PreferencesCubit, PreferencesState>(
      'emits the reconciled document without writing it back',
      build: buildCubit,
      seed: () => PreferencesReady(seeded),
      act: (cubit) {
        cubit.adoptFromSync(reconciled);
      },
      expect: () => [PreferencesReady(reconciled)],
      verify: (cubit) {
        // Sync already wrote both sides. Saving here would bump the revision
        // again and bounce a fresh write back at the document just adopted
        // (sync.md rule 5).
        verifyNever(() => repository.save(any()));
        expect(
          cubit.state,
          isA<PreferencesReady>().having(
            (state) => state.preferences.revision,
            'revision',
            reconciled.revision,
          ),
        );
      },
    );

    blocTest<PreferencesCubit, PreferencesState>(
      'adopts even before the first load, so startup order cannot lose it',
      build: buildCubit,
      act: (cubit) {
        cubit.adoptFromSync(reconciled);
      },
      expect: () => [PreferencesReady(reconciled)],
    );
  });
}

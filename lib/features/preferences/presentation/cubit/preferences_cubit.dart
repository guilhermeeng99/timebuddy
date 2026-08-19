import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/preferences/presentation/cubit/preferences_state.dart';

/// Single source of truth for every user preference, including theme mode and
/// the two palettes: the app widget reads them from this state and reassigns
/// `AppColors` before building `MaterialApp`.
///
/// Registered as a singleton, so a change is immediate and global: grid,
/// clocks, planner and converter all rebuild from it (preferences.md rule 6).
/// There is no save button anywhere in settings.
///
/// ```dart
/// await context.read<PreferencesCubit>().setClockFormat(ClockFormat.h12);
/// ```
class PreferencesCubit extends Cubit<PreferencesState> {
  PreferencesCubit({
    required PreferencesRepository repository,
    required Clock clock,
  })  : _repository = repository,
        _clock = clock,
        super(const PreferencesLoading());

  final PreferencesRepository _repository;
  final Clock _clock;

  /// Reads the stored document, seeding defaults from [deviceLocale] on a first
  /// launch. Called once, by the startup flow, before any page mounts.
  Future<void> load({required Locale deviceLocale}) async {
    final result = await _repository.load(deviceLocale: deviceLocale);
    final preferences = result.fold(
      // A device that cannot read its own storage still gets a coherent app;
      // the failure is the sync layer's to report, not this cubit's.
      (_) => PreferencesEntity.defaults(
        now: _clock.nowUtc(),
        deviceLocale: deviceLocale,
      ),
      (stored) => stored,
    );
    emit(PreferencesReady(preferences));
  }

  Future<void> setThemeMode(ThemeMode value) =>
      _mutate((current) => current.copyWith(themeMode: value));

  Future<void> setLightPalette(LightPalette value) =>
      _mutate((current) => current.copyWith(lightPalette: value));

  Future<void> setDarkPalette(DarkPalette value) =>
      _mutate((current) => current.copyWith(darkPalette: value));

  Future<void> setClockFormat(ClockFormat value) =>
      _mutate((current) => current.copyWith(hourFormat: value));

  /// Clamps [value] to the 1..16 hour bounds (preferences.md rule 5) before
  /// storing it: below one hour the grid is a wall of `poor`, above sixteen the
  /// bands stop discriminating.
  Future<void> setWorkingHours(WorkingHours value) =>
      _mutate((current) => current.copyWith(workingHours: value.clamped()));

  Future<void> setWeekStart(WeekStart value) =>
      _mutate((current) => current.copyWith(weekStartsOn: value));

  /// Also changes the ticker rate, not just the display (world_clock rule 4).
  Future<void> setShowSeconds({required bool value}) =>
      _mutate((current) => current.copyWith(showSeconds: value));

  /// Pass `null` to follow the device again (preferences.md rule 3).
  Future<void> setLocaleTag(String? value) => _mutate(
        (current) => value == null
            ? current.copyWith(clearLocaleTag: true)
            : current.copyWith(localeTag: value),
      );

  /// Adopts the document that won reconciliation (sync.md rule 5).
  ///
  /// Deliberately does not persist: the sync layer already wrote both sides, so
  /// saving here would bump the revision again and bounce a fresh write back at
  /// the remote document it just adopted.
  void adoptFromSync(PreferencesEntity value) => emit(PreferencesReady(value));

  Future<void> _mutate(
    PreferencesEntity Function(PreferencesEntity current) change,
  ) async {
    final current = state;
    // Settings are unreachable before the startup load resolves, so a mutation
    // arriving here means a caller jumped the gun; dropping it is safer than
    // inventing a document to mutate.
    if (current is! PreferencesReady) return;

    final updated = change(current.preferences).copyWith(
      revision: current.preferences.revision + 1,
      updatedAt: _clock.nowUtc(),
    );

    // Optimistic: the UI must not wait on a disk write to repaint a theme.
    emit(PreferencesReady(updated));

    // The result is intentionally dropped. A failed write is never shown as an
    // error (sync.md rule 4) and the in-memory value stays authoritative; the
    // dirty flag and the passive indicator handle durability in M3.
    await _repository.save(updated);
  }
}

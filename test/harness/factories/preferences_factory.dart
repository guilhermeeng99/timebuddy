import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

/// The `updatedAt` every factory-built [PreferencesEntity] carries unless a
/// test overrides it.
///
/// Fixed, and deliberately mid-January so it sits far from any DST transition:
/// a factory that called `DateTime.now()` would make equality assertions
/// depend on how long the test took to run.
final DateTime preferencesFixtureUpdatedAt = DateTime.utc(2024, 1, 15, 12);

/// Builds a [PreferencesEntity] with coherent fixed values, overriding only
/// the fields a test actually cares about.
///
/// The values are written out here rather than delegated to
/// `PreferencesEntity.defaults()` on purpose: a test asserting what the
/// defaults are must not be able to pass by comparing defaults to themselves.
///
/// ```dart
/// final prefs = aPreferences(
///   hourFormat: ClockFormat.h12,
///   workingHours: const WorkingHours(startHour: 22, endHour: 6),
/// );
/// ```
///
/// [localeTag] defaults to `null`, which is the real "follow the device"
/// value, so no clear-sentinel is needed to build the nullable case.
PreferencesEntity aPreferences({
  ThemeMode themeMode = ThemeMode.system,
  LightPalette lightPalette = LightPalette.indigoCloud,
  DarkPalette darkPalette = DarkPalette.midnightIndigo,
  ClockFormat hourFormat = ClockFormat.h24,
  WorkingHours workingHours = WorkingHours.defaultHours,
  WeekStart weekStartsOn = WeekStart.monday,
  bool showSeconds = false,
  String? localeTag,
  int revision = 1,
  DateTime? updatedAt,
}) {
  return PreferencesEntity(
    themeMode: themeMode,
    lightPalette: lightPalette,
    darkPalette: darkPalette,
    hourFormat: hourFormat,
    workingHours: workingHours,
    weekStartsOn: weekStartsOn,
    showSeconds: showSeconds,
    localeTag: localeTag,
    revision: revision,
    updatedAt: updatedAt ?? preferencesFixtureUpdatedAt,
  );
}

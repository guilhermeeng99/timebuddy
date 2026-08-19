import 'package:flutter/material.dart';
import 'package:mocktail/mocktail.dart';
// The `timezone` package is restricted to lib/core/time/ (CLAUDE.md), but the
// harness has to load the database the engine reads, so this is the one
// sanctioned import outside that folder.
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'factories/preferences_factory.dart';

bool _timeZonesLoaded = false;

/// Loads the IANA tzdata for the current test process, at most once.
///
/// `initializeTimeZones()` rebuilds every location on each call, so calling it
/// from a `setUpAll` in each of dozens of test files would cost real seconds.
/// The guard makes repeated calls free, so every test touching the engine can
/// declare the dependency without coordinating with the others.
///
/// ```dart
/// setUpAll(initTestTimeZones);
/// ```
void initTestTimeZones() {
  if (_timeZonesLoaded) return;
  tz_data.initializeTimeZones();
  _timeZonesLoaded = true;
}

/// Builds a UTC instant, tersely.
///
/// Exists so a test never types the bare `DateTime(...)` constructor, which
/// silently produces a host-local instant and makes the suite's results depend
/// on the machine's timezone.
///
/// ```dart
/// final springForward = utcDate(2024, 3, 10, 7); // US spring-forward
/// ```
DateTime utcDate(
  int year, [
  int month = 1,
  int day = 1,
  int hour = 0,
  int minute = 0,
  int second = 0,
]) {
  return DateTime.utc(year, month, day, hour, minute, second);
}

/// Registers the mocktail fallback values for every non-primitive type this
/// milestone passes through `any()` / `captureAny()`.
///
/// Without a fallback, `when(() => repo.save(any()))` throws at match time
/// with an error that points at mocktail rather than at the test. Registering
/// is idempotent, so calling this from every `setUpAll` is free.
///
/// ```dart
/// setUpAll(registerCommonFallbacks);
/// ```
void registerCommonFallbacks() {
  // DateTime: every TimeZoneEngine method takes the instant it answers for.
  registerFallbackValue(utcDate(2024));
  // Locale: PreferencesRepository.load(deviceLocale:).
  registerFallbackValue(const Locale('en'));
  // PreferencesEntity: PreferencesRepository.save(...).
  registerFallbackValue(aPreferences());
}

/// Every zone id the shipped database carries, in database order.
///
/// Lives here rather than in a test so the `timezone` import stays inside the
/// one sanctioned file (CLAUDE.md restricts the package to `lib/core/time/`).
/// Tests use it to assert a property over the whole database instead of over a
/// hand-copied sample, which is the only way to catch a bad alias entry that
/// nobody thought to list.
List<String> allShippedZoneIds() =>
    tz.timeZoneDatabase.locations.keys.toList(growable: false);

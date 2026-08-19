import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';

/// Everything the user can tune, as one immutable document.
///
/// Persisted and synced whole (docs/specs/sync.md): [revision] is what conflict
/// resolution compares, never the individual fields, so every mutation must go
/// through `PreferencesCubit`, which bumps it.
///
/// [workingHours] is not cosmetic: it feeds `hourBandFor`, and so decides
/// every colour in the grid and every verdict in the planner.
///
/// ```dart
/// final prefs = PreferencesEntity.defaults(
///   now: clock.nowUtc(),
///   deviceLocale: const Locale('pt', 'BR'),
/// ); // -> 24h clock, week starts Monday, locale follows the device
/// ```
class PreferencesEntity extends Equatable {
  const PreferencesEntity({
    required this.themeMode,
    required this.lightPalette,
    required this.darkPalette,
    required this.hourFormat,
    required this.workingHours,
    required this.weekStartsOn,
    required this.showSeconds,
    required this.revision,
    required this.updatedAt,
    this.localeTag,
  });

  /// The values a user who never opens settings gets (preferences.md rule 1).
  ///
  /// `hourFormat` and `weekStartsOn` are seeded from [deviceLocale] here and
  /// only here: after the first launch they belong to the user, so plugging
  /// the phone into a different locale must not rewrite them (rule 2).
  factory PreferencesEntity.defaults({
    required DateTime now,
    required Locale deviceLocale,
  }) {
    final followsUsClockConventions = _seedsTwelveHourWeek(deviceLocale);
    return PreferencesEntity(
      themeMode: ThemeMode.system,
      lightPalette: LightPalette.indigoCloud,
      darkPalette: DarkPalette.midnightIndigo,
      hourFormat: followsUsClockConventions ? ClockFormat.h12 : ClockFormat.h24,
      workingHours: WorkingHours.defaultHours,
      weekStartsOn:
          followsUsClockConventions ? WeekStart.sunday : WeekStart.monday,
      showSeconds: false,
      revision: 0,
      updatedAt: now.toUtc(),
    );
  }

  final ThemeMode themeMode;
  final LightPalette lightPalette;
  final DarkPalette darkPalette;
  final ClockFormat hourFormat;
  final WorkingHours workingHours;
  final WeekStart weekStartsOn;
  final bool showSeconds;

  /// `null` means "follow the device" and is a real value, not a missing one
  /// (preferences.md rule 3): a user who picked Portuguese on an English phone
  /// keeps Portuguese, and a user who never picked follows the phone.
  final String? localeTag;

  /// Monotonic per document, bumped on every write (sync.md rules 5 and 7).
  final int revision;

  /// UTC. Only ever breaks a [revision] tie (sync.md rule 8).
  final DateTime updatedAt;

  /// Countries whose everyday clock is 12-hour *and* whose week starts on
  /// Sunday, so one predicate can seed both fields.
  ///
  /// Deliberately tiny: it only has to be a good guess on first launch, both
  /// settings are one tap away, and a full CLDR table would be several hundred
  /// rows of maintenance for a value the user can correct in a second.
  static const Set<String> _twelveHourSundayCountries = {'US', 'CA', 'PH'};

  static bool _seedsTwelveHourWeek(Locale locale) =>
      _twelveHourSundayCountries.contains(locale.countryCode?.toUpperCase());

  /// Pass `clearLocaleTag: true` to go back to following the device; passing
  /// `localeTag: null` cannot express that, since it is indistinguishable from
  /// "leave it alone".
  PreferencesEntity copyWith({
    ThemeMode? themeMode,
    LightPalette? lightPalette,
    DarkPalette? darkPalette,
    ClockFormat? hourFormat,
    WorkingHours? workingHours,
    WeekStart? weekStartsOn,
    bool? showSeconds,
    String? localeTag,
    int? revision,
    DateTime? updatedAt,
    bool clearLocaleTag = false,
  }) {
    return PreferencesEntity(
      themeMode: themeMode ?? this.themeMode,
      lightPalette: lightPalette ?? this.lightPalette,
      darkPalette: darkPalette ?? this.darkPalette,
      hourFormat: hourFormat ?? this.hourFormat,
      workingHours: workingHours ?? this.workingHours,
      weekStartsOn: weekStartsOn ?? this.weekStartsOn,
      showSeconds: showSeconds ?? this.showSeconds,
      localeTag: clearLocaleTag ? null : localeTag ?? this.localeTag,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        themeMode,
        lightPalette,
        darkPalette,
        hourFormat,
        workingHours,
        weekStartsOn,
        showSeconds,
        localeTag,
        revision,
        updatedAt,
      ];
}

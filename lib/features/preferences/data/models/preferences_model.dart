import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/utils/enum_parse.dart';
import 'package:timebuddy/core/utils/json_parse.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

/// Serialization for [PreferencesEntity].
///
/// One shape feeds both writers (sync.md): `shared_preferences` today,
/// Firestore in M3. Timestamps are written as ISO-8601 and read back from
/// either an ISO-8601 string or a millisecond epoch int, so a document copied
/// between the two sides never needs a conversion pass.
///
/// Every parse degrades instead of throwing. A settings screen that crashes on
/// one unknown palette name is worse than a settings screen showing the default
/// palette (preferences.md rule 9).
///
/// ```dart
/// final model = PreferencesModel.fromEntity(preferences);
/// await store.writeRaw(StorageKeys.preferences, jsonEncode(model.toJson()));
/// ```
class PreferencesModel extends PreferencesEntity {
  const PreferencesModel({
    required super.themeMode,
    required super.lightPalette,
    required super.darkPalette,
    required super.hourFormat,
    required super.workingHours,
    required super.weekStartsOn,
    required super.showSeconds,
    required super.revision,
    required super.updatedAt,
    super.localeTag,
  });

  factory PreferencesModel.fromJson(Map<String, dynamic> json) {
    return PreferencesModel(
      themeMode: enumByName(
        ThemeMode.values,
        filledStringOrNull(json['themeMode']),
        orElse: ThemeMode.system,
      ),
      lightPalette: enumByName(
        LightPalette.values,
        filledStringOrNull(json['lightPalette']),
        orElse: LightPalette.indigoCloud,
      ),
      darkPalette: enumByName(
        DarkPalette.values,
        filledStringOrNull(json['darkPalette']),
        orElse: DarkPalette.midnightIndigo,
      ),
      hourFormat: enumByName(
        ClockFormat.values,
        filledStringOrNull(json['hourFormat']),
        orElse: ClockFormat.h24,
      ),
      workingHours: _workingHoursFrom(json['workingHours']),
      weekStartsOn: enumByName(
        WeekStart.values,
        filledStringOrNull(json['weekStartsOn']),
        orElse: WeekStart.monday,
      ),
      showSeconds: json['showSeconds'] == true,
      localeTag: filledStringOrNull(json['locale']),
      revision: intOrNull(json['revision']) ?? 0,
      updatedAt: timestampFromJson(json['updatedAt']),
    );
  }

  factory PreferencesModel.fromEntity(PreferencesEntity entity) {
    return PreferencesModel(
      themeMode: entity.themeMode,
      lightPalette: entity.lightPalette,
      darkPalette: entity.darkPalette,
      hourFormat: entity.hourFormat,
      workingHours: entity.workingHours,
      weekStartsOn: entity.weekStartsOn,
      showSeconds: entity.showSeconds,
      localeTag: entity.localeTag,
      revision: entity.revision,
      updatedAt: entity.updatedAt,
    );
  }

  /// The window is parsed as a unit: a valid start with an invalid end falls
  /// back to the whole default window, because a half-adopted window silently
  /// recolours the entire grid (preferences.md, Model Serialization).
  static WorkingHours _workingHoursFrom(Object? raw) {
    if (raw is! Map<String, dynamic>) return WorkingHours.defaultHours;

    final startHour = intOrNull(raw['start']);
    final endHour = intOrNull(raw['end']);
    if (startHour == null || endHour == null) return WorkingHours.defaultHours;

    final parsed = WorkingHours(startHour: startHour, endHour: endHour);
    return parsed.isValid ? parsed : WorkingHours.defaultHours;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      'lightPalette': lightPalette.name,
      'darkPalette': darkPalette.name,
      // `this.` is load-bearing here and nowhere else in this map, however
      // inconsistent it looks. `hourFormat` is *inherited* from
      // [PreferencesEntity], and an inherited member is not in this class's
      // lexical scope, so the bare name falls through to the library scope and
      // finds the top-level `hourFormat({required TimeOfDayFormat of})` that
      // `package:flutter/material.dart` exports — a compile error, not a wrong
      // value. Every sibling key names a field with no such twin. Kept
      // explicit rather than hidden behind an import alias, so the next reader
      // to "fix" the inconsistency finds the reason before the error.
      'hourFormat': this.hourFormat.name,
      'workingHours': <String, dynamic>{
        'start': workingHours.startHour,
        'end': workingHours.endHour,
      },
      'weekStartsOn': weekStartsOn.name,
      'showSeconds': showSeconds,
      // Named 'locale' to match the documented Firestore field (CLAUDE.md,
      // Firestore Collections); the entity calls it localeTag because it holds
      // a BCP-47 tag, not a dart:ui Locale.
      'locale': localeTag,
      'revision': revision,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

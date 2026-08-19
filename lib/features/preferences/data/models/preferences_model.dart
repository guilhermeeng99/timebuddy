import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/utils/enum_parse.dart';
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
        _asString(json['themeMode']),
        orElse: ThemeMode.system,
      ),
      lightPalette: enumByName(
        LightPalette.values,
        _asString(json['lightPalette']),
        orElse: LightPalette.indigoCloud,
      ),
      darkPalette: enumByName(
        DarkPalette.values,
        _asString(json['darkPalette']),
        orElse: DarkPalette.midnightIndigo,
      ),
      hourFormat: enumByName(
        ClockFormat.values,
        _asString(json['hourFormat']),
        orElse: ClockFormat.h24,
      ),
      workingHours: _workingHoursFrom(json['workingHours']),
      weekStartsOn: enumByName(
        WeekStart.values,
        _asString(json['weekStartsOn']),
        orElse: WeekStart.monday,
      ),
      showSeconds: json['showSeconds'] == true,
      localeTag: _asString(json['locale']),
      revision: _asInt(json['revision']) ?? 0,
      updatedAt: _updatedAtFrom(json['updatedAt']),
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

    final startHour = _asInt(raw['start']);
    final endHour = _asInt(raw['end']);
    if (startHour == null || endHour == null) return WorkingHours.defaultHours;

    final parsed = WorkingHours(startHour: startHour, endHour: endHour);
    return parsed.isValid ? parsed : WorkingHours.defaultHours;
  }

  /// Accepts both encodings of the dual-write contract, and falls back to the
  /// epoch rather than to "now": an unreadable timestamp must lose every tie it
  /// enters (sync.md rule 5), not win them by looking freshly written.
  static DateTime _updatedAtFrom(Object? raw) {
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static String? _asString(Object? raw) => raw is String ? raw : null;

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      'lightPalette': lightPalette.name,
      'darkPalette': darkPalette.name,
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

import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// Serialization for [SavedLocationEntity].
///
/// One shape feeds both writers (docs/specs/sync.md): `shared_preferences`
/// today, Firestore in M3. Parsing is defensive on both boundaries, because
/// the board is the user's whole state and one bad field must not cost them
/// the list (docs/specs/locations.md, Model Serialization).
///
/// ```dart
/// final row = SavedLocationModel.tryFromJson(entry); // null if unsalvageable
/// ```
class SavedLocationModel extends SavedLocationEntity {
  const SavedLocationModel({
    required super.id,
    required super.zoneId,
    required super.label,
    required super.countryCode,
    required super.sortIndex,
    required super.addedAt,
  });

  factory SavedLocationModel.fromEntity(SavedLocationEntity entity) {
    return SavedLocationModel(
      id: entity.id,
      zoneId: entity.zoneId,
      label: entity.label,
      countryCode: entity.countryCode,
      sortIndex: entity.sortIndex,
      addedAt: entity.addedAt,
    );
  }

  /// Parses one entry of the `locations` array, or returns `null` when the
  /// entry cannot be salvaged.
  ///
  /// A static rather than a `fromJson` factory precisely so it can answer
  /// `null`: a malformed row is dropped and the rest of the board is kept,
  /// where a throwing parser would cost the user every other city they saved.
  ///
  /// Three fields are load-bearing and drop the row when they are missing or
  /// of the wrong type: `id` addresses the row for every mutation, `zoneId`
  /// is the only field the engine reads, and `sortIndex` places it. `label`
  /// and `countryCode` are display data, so a missing one degrades — to the
  /// zone id and to the empty string — instead of deleting a real location.
  static SavedLocationModel? tryFromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;

    final id = _asFilledString(raw['id']);
    final zoneId = _asFilledString(raw['zoneId']);
    final sortIndex = _asInt(raw['sortIndex']);
    if (id == null || zoneId == null || sortIndex == null) return null;

    return SavedLocationModel(
      id: id,
      zoneId: zoneId,
      label: _asFilledString(raw['label']) ?? zoneId,
      countryCode: _asFilledString(raw['countryCode']) ?? '',
      sortIndex: sortIndex,
      addedAt: timestampFromJson(raw['addedAt']),
    );
  }

  static String? _asFilledString(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'zoneId': zoneId,
      'label': label,
      'countryCode': countryCode,
      'sortIndex': sortIndex,
      'addedAt': addedAt.toUtc().toIso8601String(),
    };
  }
}

/// Decodes both halves of the dual timestamp encoding (docs/specs/sync.md):
/// an ISO-8601 string from `shared_preferences`, a millisecond epoch int from
/// a Firestore `Timestamp` that has already been unwrapped.
///
/// Shared by `BoardModel.updatedAt` and `SavedLocationEntity.addedAt` rather
/// than copied into each: they are two fields of one document, and a parser
/// that drifted would make a board's own timestamps disagree.
///
/// An unreadable value falls back to the epoch, never to "now": a timestamp
/// nobody can read must lose every tie it enters (sync.md rule 5) instead of
/// winning them by looking freshly written.
DateTime timestampFromJson(Object? raw) {
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

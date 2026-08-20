import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';

/// Serialization for [CityEntity].
///
/// Read-only in practice: the catalog asset is generated offline by
/// `scripts/build_city_catalog.dart` and never written by the app. [toJson]
/// exists so a test can build a fixture in exactly the shape the script emits,
/// which is the only way a parsing test stays honest about the real file.
///
/// The asset omits an absent `admin1` and an empty `aliases` rather than
/// writing `null` and `[]`, which is what keeps 500 rows inside 60 KB. Both
/// are therefore *expected* to be missing, not damage to be tolerated.
///
/// ```dart
/// final city = cityOrNull(entry); // null when the entry is junk
/// ```
class CityModel extends CityEntity {
  const CityModel({
    required super.zoneId,
    required super.name,
    required super.countryCode,
    required super.countryName,
    required super.prominence,
    super.admin1,
    super.aliases,
  });

  /// Parses one catalog entry.
  ///
  /// Throws [FormatException] when an identifying field is missing or of the
  /// wrong type. Prefer [cityOrNull] when walking the asset: one bad row must
  /// cost that row, not the catalog.
  factory CityModel.fromJson(Map<String, dynamic> json) {
    final zoneId = _asText(json['zoneId']);
    final name = _asText(json['name']);
    final countryCode = _asText(json['countryCode']);
    final countryName = _asText(json['countryName']);
    // Identity and display are non-negotiable: a row with no zone cannot be
    // added to a board, and a row with no name cannot be recognised in a list.
    // Every optional field below has a meaningful zero value, so those degrade
    // instead of failing the row.
    if (zoneId == null ||
        name == null ||
        countryCode == null ||
        countryName == null) {
      throw FormatException('Incomplete city entry.', json);
    }
    return CityModel(
      zoneId: zoneId,
      name: name,
      countryCode: countryCode,
      countryName: countryName,
      prominence: _asProminence(json['prominence']),
      admin1: _asText(json['admin1']),
      aliases: _asAliases(json['aliases']),
    );
  }

  /// The exact shape `scripts/build_city_catalog.dart` writes, key order
  /// included: an absent `admin1` and empty `aliases` are omitted, not nulled.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'zoneId': zoneId,
      'name': name,
      'countryCode': countryCode,
      'countryName': countryName,
      if (admin1 != null) 'admin1': admin1,
      'prominence': prominence,
      if (aliases.isNotEmpty) 'aliases': aliases,
    };
  }

  static String? _asText(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Missing or non-numeric degrades to 0, which reads as "derived, not
  /// curated" everywhere else in the app.
  static int _asProminence(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static List<String> _asAliases(Object? value) {
    if (value is! List<dynamic>) return const <String>[];
    final aliases = <String>[];
    for (final alias in value) {
      final text = _asText(alias);
      if (text != null) aliases.add(text);
    }
    return List<String>.unmodifiable(aliases);
  }
}

/// [CityModel.fromJson] for one element of the asset's `cities` array, or
/// `null` when that element is unusable.
///
/// A non-map element, a missing zone or a numeric name skips that entry and
/// leaves the rest of the catalog searchable. Only a regenerated asset can
/// introduce such a row, and shipping a search that finds 499 of 500 cities
/// beats shipping one that finds none.
///
/// A free function rather than a static on [CityModel], mirroring
/// `zoneOrNull`: the nullable answer is the ordinary one here, and a
/// constructor cannot express it.
///
/// ```dart
/// for (final entry in decoded['cities'] as List<dynamic>) {
///   final city = cityOrNull(entry);
///   if (city != null) catalog.add(city);
/// }
/// ```
CityModel? cityOrNull(Object? entry) {
  if (entry is! Map<String, dynamic>) return null;
  try {
    return CityModel.fromJson(entry);
  } on FormatException {
    return null;
  }
}

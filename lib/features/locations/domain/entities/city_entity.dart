import 'package:equatable/equatable.dart';

/// One searchable place in the city catalog.
///
/// The catalog is a static asset derived from the shipped tz database, so
/// [zoneId] is always a canonical IANA id that `zoneOrNull` resolves. Several
/// cities legitimately share one id: Oslo, Stockholm and Copenhagen all read
/// `Europe/Berlin`, and the board rejects the second of them as a duplicate
/// zone (docs/specs/locations.md rule 2). That is the intended behaviour, not
/// a catalog defect - two rows showing the identical clock would be noise.
///
/// A [CityEntity] is only ever a *search result*. What the board stores is a
/// `SavedLocationEntity` carrying a copy of [name] and [countryCode], so a
/// later catalog regeneration cannot rename or drop a place the user saved
/// (rule 12).
///
/// ```dart
/// final results = await catalog.search('sampa');
/// // -> CityEntity(zoneId: 'America/Sao_Paulo', name: 'Sao Paulo', ...)
/// ```
class CityEntity extends Equatable {
  const CityEntity({
    required this.zoneId,
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.prominence,
    this.admin1,
    this.aliases = const <String>[],
  });

  /// Canonical IANA identifier, the only field the timezone engine reads.
  final String zoneId;

  /// English display name, without diacritics ('Sao Paulo', 'Zurich').
  ///
  /// Stored unfolded: `normalizeForSearch` is applied when matching, never
  /// when rendering.
  final String name;

  /// ISO 3166-1 alpha-2 code. `ZZ` marks the non-country entry `UTC`.
  final String countryCode;

  /// English country name, also matched by search ("brazil" finds Sao Paulo).
  final String countryName;

  /// State or province, present only where it disambiguates.
  ///
  /// The catalog holds several Sao Paulos and two Portlands; the sheet renders
  /// this before [countryName] so the two are told apart before a tap, not
  /// after.
  final String? admin1;

  /// Search weight: higher sorts first among equally good matches.
  ///
  /// Assigned in bands by the curated seed table (100 for a global hub, 80 for
  /// a national capital, 60 for a large regional city). **Zero means the row
  /// was derived from the tz database rather than curated**, which is also
  /// what tells the default list which entries are worth showing before the
  /// user types anything.
  final int prominence;

  /// Extra strings that must find this city: 'NYC', 'Bengaluru', 'Sampa'.
  ///
  /// Never rendered. Aliases exist so a user's own name for a place works, and
  /// showing them back would only make the result list ambiguous.
  final List<String> aliases;

  /// Whether this row came from the curated seed table (see [prominence]).
  bool get isCurated => prominence > 0;

  CityEntity copyWith({
    String? zoneId,
    String? name,
    String? countryCode,
    String? countryName,
    String? admin1,
    int? prominence,
    List<String>? aliases,
    bool clearAdmin1 = false,
  }) {
    return CityEntity(
      zoneId: zoneId ?? this.zoneId,
      name: name ?? this.name,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      admin1: clearAdmin1 ? null : admin1 ?? this.admin1,
      prominence: prominence ?? this.prominence,
      aliases: aliases ?? this.aliases,
    );
  }

  @override
  List<Object?> get props => [
    zoneId,
    name,
    countryCode,
    countryName,
    admin1,
    prominence,
    aliases,
  ];
}

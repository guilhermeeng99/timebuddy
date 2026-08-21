import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';

/// Builds a [CityEntity], overriding only the fields a test cares about.
///
/// The defaults describe one real catalog row rather than a placeholder: the
/// zone id is canonical and resolvable, because almost every rule a city takes
/// part in — the duplicate check, the alias fold, the unresolved banner — is
/// decided by `zoneOrNull` reading exactly that field.
///
/// [prominence] defaults to `0`, which is what the catalog builder assigns to
/// a row derived from the tz database rather than from the curated seed table
/// (`CityEntity.isCurated` is false). A test about ranking or about the
/// default list therefore has to state the weight it means, and cannot pass by
/// inheriting a number the factory chose.
///
/// ```dart
/// final tokyo = aCity(zoneId: 'Asia/Tokyo', name: 'Tokyo', countryCode: 'JP');
/// final hub = aCity(prominence: 100);
/// ```
CityEntity aCity({
  String zoneId = 'America/Sao_Paulo',
  String name = 'Sao Paulo',
  String countryCode = 'BR',
  String countryName = 'Brazil',
  int prominence = 0,
  String? admin1,
  List<String> aliases = const <String>[],
}) {
  return CityEntity(
    zoneId: zoneId,
    name: name,
    countryCode: countryCode,
    countryName: countryName,
    prominence: prominence,
    admin1: admin1,
    aliases: aliases,
  );
}

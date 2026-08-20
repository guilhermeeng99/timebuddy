// Regenerates lib/app/assets/data/cities.json.
//
//     dart run scripts/build_city_catalog.dart
//
// WHY THE CATALOG IS DERIVED, NOT DOWNLOADED. The usual recipe joins a public
// city dataset (GeoNames and friends) against the tzdata zone list on
// latitude/longitude or on a country column. That join is where clock apps go
// wrong: a mis-joined row does not fail, it ships a city pointing at a
// plausible neighbouring zone and shows an hour that is wrong for half the
// year. Here the IANA id *is* the authority on which clock a place keeps, so
// deriving the catalog from the shipped database cannot produce that class of
// error at all - and the build stays offline, reproducible and dependency-free.
//
// WHAT THAT COSTS, HONESTLY. The tz database knows the id and nothing else. It
// does not know what country `Asia/Kuching` is in, and it certainly does not
// know that Mumbai exists. So:
//
//   * every derived row's country comes from [countryCodeByZone] /
//     [countryCodeByRegion] below, which are hand-written and therefore a
//     best-effort human judgement, not data;
//   * every derived row's display name is the last id segment with the
//     underscores taken out, which is right for `Sao_Paulo` and merely
//     tolerable for `DumontDUrville`;
//   * a zone absent from [countryCodeByZone] is not emitted at all, and is
//     printed under "not emitted" at the end of the run.
//
// The curated table in `city_seeds.dart` is the answer to all three: a seed
// overrides its derived row in *every* field, and adds the cities that share
// another city's clock. Roughly 250 of the ~500 emitted rows are curated.
//
// DETERMINISM IS A REQUIREMENT, not a nicety. The output is sorted by
// (zoneId, name, countryCode), the JSON keys are written in a fixed order, and
// nothing about the current time or the machine enters the file - so
// regenerating without changing an input produces a byte-identical file and an
// empty diff. Milestone 1 learned this from a code generator that stamped a
// timestamp into its output and made every regeneration look like a change.
//
// This file imports `package:timezone` directly, which CLAUDE.md restricts to
// `lib/core/time/`. That restriction is about the app: a feature that reaches
// past `TimeZoneEngine` gets to invent its own timezone semantics. A build
// script is not the app, ships in no binary, and its entire job is to walk the
// database. It does still resolve every id through `zoneOrNull`, because that
// is the function the app will use at runtime and the only way this build can
// promise that what it emits will resolve there.

import 'dart:convert';
import 'dart:io';

import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'city_seeds.dart';

/// Where the generated catalog goes, relative to the package root.
const String outputPath = 'lib/app/assets/data/cities.json';

/// Bumped when the JSON shape changes, so a stale asset is recognisable.
const int catalogVersion = 1;

void main() {
  tz_data.initializeTimeZones();

  final notEmitted = <String>[];
  final unresolved = <String>[];
  final rows = _collectRows(notEmitted: notEmitted, unresolved: unresolved);

  if (unresolved.isNotEmpty) {
    _abort('These zone names do not resolve through zoneOrNull:', unresolved);
  }
  _verifyEmitted(rows);
  _verifyUnique(rows);

  File(outputPath).writeAsStringSync(_encode(rows));
  _report(rows, notEmitted);
}

/// Every row the catalog will hold, sorted into its final order.
///
/// Three passes, in this order because each one wins over the last: derive a
/// row per allowed database name, let [citySeeds] replace the derived row for
/// the same name outright, then append [extraCitySeeds], which are cities that
/// have no database name of their own.
List<_CatalogRow> _collectRows({
  required List<String> notEmitted,
  required List<String> unresolved,
}) {
  final byZoneName = <String, CitySeed>{};
  for (final seed in _derivedSeeds(notEmitted)) {
    byZoneName[seed.zoneName] = seed;
  }
  for (final seed in citySeeds) {
    byZoneName[seed.zoneName] = seed;
  }

  final rows = <_CatalogRow>[];
  for (final seed in [...byZoneName.values, ...extraCitySeeds]) {
    // The one gate that matters: a seed naming a zone this tzdata release no
    // longer carries must fail the build, not ship a city that silently falls
    // back to UTC on the user's phone.
    final ref = zoneOrNull(seed.zoneName);
    if (ref == null) {
      unresolved.add(seed.zoneName);
      continue;
    }
    rows.add(_rowFor(seed, ref.id));
  }
  return rows..sort(_byZoneThenName);
}

/// One seed per emittable database name, carrying only what the id itself
/// implies. Prominence 0 is exactly what marks these as derived.
List<CitySeed> _derivedSeeds(List<String> notEmitted) {
  final seeds = <CitySeed>[];
  for (final zoneName in tz.timeZoneDatabase.locations.keys) {
    if (_isNotAPlace(zoneName)) continue;
    final countryCode = _countryCodeFor(zoneName);
    if (countryCode == null) {
      notEmitted.add(zoneName);
      continue;
    }
    seeds.add(CitySeed(zoneName, _displayNameFor(zoneName), countryCode, 0));
  }
  return seeds;
}

_CatalogRow _rowFor(CitySeed seed, String zoneId) {
  final countryName = countryNameByCode[seed.countryCode];
  if (countryName == null) {
    throw StateError(
      'No country name for "${seed.countryCode}" (${seed.name}).',
    );
  }
  return _CatalogRow(
    zoneId: zoneId,
    name: seed.name,
    countryCode: seed.countryCode,
    countryName: countryName,
    prominence: seed.prominence,
    aliases: seed.aliases,
    admin1: seed.admin1,
  );
}

/// Whether [zoneName] names an offset rather than somewhere people live.
///
/// `Etc/GMT+5` and the bare spellings (`CET`, `EST5EDT`, `Factory`) are
/// timekeeping constructs; nobody searches a clock app for Etc/GMT-14. Plain
/// `UTC` is the exception and comes back in through [citySeeds], because a
/// user picking a neutral reference is a real thing to want.
bool _isNotAPlace(String zoneName) =>
    !zoneName.contains('/') || zoneName.startsWith('Etc/');

/// The last id segment, made readable: `America/Sao_Paulo` -> `Sao Paulo`,
/// `America/St_Johns` -> `St. Johns`, `Africa/Dar_es_Salaam` unchanged apart
/// from its underscores.
///
/// No capitalisation pass: the segments are already correctly cased, and a
/// naive title-case would turn `Dar es Salaam` into `Dar Es Salaam`.
String _displayNameFor(String zoneName) =>
    zoneName.split('/').last.split('_').map(_expandAbbreviation).join(' ');

String _expandAbbreviation(String word) => word == 'St' ? 'St.' : word;

/// The zone's country, zone table first so a region default can be overridden.
String? _countryCodeFor(String zoneName) =>
    countryCodeByZone[zoneName] ?? countryCodeByRegion[_regionOf(zoneName)];

String _regionOf(String zoneName) => zoneName.split('/').first;

/// Re-checks the *emitted* ids, not the seed spellings [_collectRows] read.
///
/// Belt and braces: canonicalisation is the step most likely to be wrong after
/// a tzdata upgrade, and an id that does not resolve here is an id that would
/// degrade to UTC at runtime, which is the one failure this catalog exists to
/// make impossible.
void _verifyEmitted(List<_CatalogRow> rows) {
  final broken = <String>[];
  for (final row in rows) {
    if (zoneOrNull(row.zoneId) == null) {
      broken.add('${row.zoneId} (${row.name})');
    }
  }
  if (broken.isNotEmpty) {
    _abort('These emitted zone ids do not resolve:', broken);
  }
}

/// Two rows may share a `zoneId` - Oslo and Berlin do - but not a zone *and* a
/// name, which would mean the same city was written down twice.
void _verifyUnique(List<_CatalogRow> rows) {
  final seen = <String>{};
  final duplicates = <String>[];
  for (final row in rows) {
    if (!seen.add('${row.zoneId}|${row.name}')) {
      duplicates.add('${row.zoneId} (${row.name})');
    }
  }
  if (duplicates.isNotEmpty) {
    _abort('These rows are duplicated:', duplicates);
  }
}

/// One row per line inside a hand-built envelope, rather than
/// `JsonEncoder.withIndent`, which would spend nine lines on every city and
/// turn a one-city change into an unreadable diff.
String _encode(List<_CatalogRow> rows) {
  final buffer = StringBuffer()
    ..writeln('{')
    ..writeln('  "version": $catalogVersion,')
    ..writeln('  "cities": [');
  for (var i = 0; i < rows.length; i++) {
    final separator = i == rows.length - 1 ? '' : ',';
    buffer.writeln('    ${jsonEncode(rows[i].toJson())}$separator');
  }
  buffer
    ..writeln('  ]')
    ..writeln('}');
  return buffer.toString();
}

/// Total order, so the file is a function of its inputs alone.
int _byZoneThenName(_CatalogRow a, _CatalogRow b) {
  final byZone = a.zoneId.compareTo(b.zoneId);
  if (byZone != 0) return byZone;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  return a.countryCode.compareTo(b.countryCode);
}

void _report(List<_CatalogRow> rows, List<String> notEmitted) {
  final curated = rows.where((row) => row.prominence > 0).length;
  notEmitted.sort();
  stdout
    ..writeln('Wrote $outputPath')
    ..writeln('  rows        ${rows.length}')
    ..writeln('  curated     $curated')
    ..writeln('  derived     ${rows.length - curated}')
    ..writeln('  not emitted ${notEmitted.length}');
  for (final zoneName in notEmitted) {
    stdout.writeln('    $zoneName');
  }
}

Never _abort(String reason, List<String> offenders) {
  stderr.writeln(reason);
  for (final offender in offenders) {
    stderr.writeln('  $offender');
  }
  exit(1);
}

/// One line of the emitted JSON.
class _CatalogRow {
  const _CatalogRow({
    required this.zoneId,
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.prominence,
    required this.aliases,
    required this.admin1,
  });

  final String zoneId;
  final String name;
  final String countryCode;
  final String countryName;
  final int prominence;
  final List<String> aliases;
  final String? admin1;

  /// Fixed key order, and absent optional fields left out entirely. Both are
  /// load-bearing: the order keeps regeneration byte-stable, and the omission
  /// keeps 500 rows inside 60 KB, which `CityModel` is written to expect.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'zoneId': zoneId,
      'name': name,
      'countryCode': countryCode,
      'countryName': countryName,
      if (admin1 != null) 'admin1': admin1,
      'prominence': prominence,
      if (aliases.isNotEmpty) 'aliases': aliases,
    };
  }
}

/// Regions whose first id segment alone pins the country.
///
/// Only two qualify. `Antarctica/*` is every research station on the
/// continent, and `Arctic/*` is Longyearbyen alone. Consulted after
/// [countryCodeByZone], so `Antarctica/Macquarie` can still be the Australian
/// island it is.
const Map<String, String> countryCodeByRegion = <String, String>{
  'Antarctica': 'AQ',
  'Arctic': 'SJ',
};

/// tz database name -> ISO 3166-1 alpha-2, and the catalog's allow-list.
///
/// Two jobs in one table, deliberately. A zone listed here is a real,
/// inhabited place worth offering, and its country is the best guess a
/// human made while writing the row down. A zone that is absent is not
/// emitted at all, and the build prints it under "not emitted" so the next
/// tzdata upgrade cannot silently add or drop a city behind our backs.
///
/// What absence is used for, besides genuinely unknown zones: the legacy
/// groupings that are not places (`US/Pacific`, `Brazil/East`,
/// `Australia/NSW`) and the superseded spellings of a place that is already
/// here under its current name (`Asia/Calcutta` beside `Asia/Kolkata`,
/// `Europe/Kiev` beside `Europe/Kyiv`). Both would otherwise become rows that
/// look like separate cities and are not.
const Map<String, String> countryCodeByZone = <String, String>{
  // --- Africa ------------------------------------------------------------
  'Africa/Abidjan': 'CI',
  'Africa/Accra': 'GH',
  'Africa/Addis_Ababa': 'ET',
  'Africa/Algiers': 'DZ',
  'Africa/Asmara': 'ER',
  'Africa/Bamako': 'ML',
  'Africa/Bangui': 'CF',
  'Africa/Banjul': 'GM',
  'Africa/Bissau': 'GW',
  'Africa/Blantyre': 'MW',
  'Africa/Brazzaville': 'CG',
  'Africa/Bujumbura': 'BI',
  'Africa/Cairo': 'EG',
  'Africa/Casablanca': 'MA',
  'Africa/Ceuta': 'ES',
  'Africa/Conakry': 'GN',
  'Africa/Dakar': 'SN',
  'Africa/Dar_es_Salaam': 'TZ',
  'Africa/Djibouti': 'DJ',
  'Africa/Douala': 'CM',
  'Africa/El_Aaiun': 'EH',
  'Africa/Freetown': 'SL',
  'Africa/Gaborone': 'BW',
  'Africa/Harare': 'ZW',
  'Africa/Johannesburg': 'ZA',
  'Africa/Juba': 'SS',
  'Africa/Kampala': 'UG',
  'Africa/Khartoum': 'SD',
  'Africa/Kigali': 'RW',
  'Africa/Kinshasa': 'CD',
  'Africa/Lagos': 'NG',
  'Africa/Libreville': 'GA',
  'Africa/Lome': 'TG',
  'Africa/Luanda': 'AO',
  'Africa/Lubumbashi': 'CD',
  'Africa/Lusaka': 'ZM',
  'Africa/Malabo': 'GQ',
  'Africa/Maputo': 'MZ',
  'Africa/Maseru': 'LS',
  'Africa/Mbabane': 'SZ',
  'Africa/Mogadishu': 'SO',
  'Africa/Monrovia': 'LR',
  'Africa/Nairobi': 'KE',
  'Africa/Ndjamena': 'TD',
  'Africa/Niamey': 'NE',
  'Africa/Nouakchott': 'MR',
  'Africa/Ouagadougou': 'BF',
  'Africa/Porto-Novo': 'BJ',
  'Africa/Sao_Tome': 'ST',
  'Africa/Tripoli': 'LY',
  'Africa/Tunis': 'TN',
  'Africa/Windhoek': 'NA',

  // --- The Americas ------------------------------------------------------
  'America/Adak': 'US',
  'America/Anchorage': 'US',
  'America/Anguilla': 'AI',
  'America/Antigua': 'AG',
  'America/Araguaina': 'BR',
  'America/Argentina/Buenos_Aires': 'AR',
  'America/Argentina/Catamarca': 'AR',
  'America/Argentina/Cordoba': 'AR',
  'America/Argentina/Jujuy': 'AR',
  'America/Argentina/La_Rioja': 'AR',
  'America/Argentina/Mendoza': 'AR',
  'America/Argentina/Rio_Gallegos': 'AR',
  'America/Argentina/Salta': 'AR',
  'America/Argentina/San_Juan': 'AR',
  'America/Argentina/San_Luis': 'AR',
  'America/Argentina/Tucuman': 'AR',
  'America/Argentina/Ushuaia': 'AR',
  'America/Aruba': 'AW',
  'America/Asuncion': 'PY',
  'America/Atikokan': 'CA',
  'America/Bahia': 'BR',
  'America/Bahia_Banderas': 'MX',
  'America/Barbados': 'BB',
  'America/Belem': 'BR',
  'America/Belize': 'BZ',
  'America/Blanc-Sablon': 'CA',
  'America/Boa_Vista': 'BR',
  'America/Bogota': 'CO',
  'America/Boise': 'US',
  'America/Cambridge_Bay': 'CA',
  'America/Campo_Grande': 'BR',
  'America/Cancun': 'MX',
  'America/Caracas': 'VE',
  'America/Cayenne': 'GF',
  'America/Cayman': 'KY',
  'America/Chicago': 'US',
  'America/Chihuahua': 'MX',
  'America/Ciudad_Juarez': 'MX',
  'America/Costa_Rica': 'CR',
  'America/Coyhaique': 'CL',
  'America/Creston': 'CA',
  'America/Cuiaba': 'BR',
  'America/Curacao': 'CW',
  'America/Danmarkshavn': 'GL',
  'America/Dawson': 'CA',
  'America/Dawson_Creek': 'CA',
  'America/Denver': 'US',
  'America/Detroit': 'US',
  'America/Dominica': 'DM',
  'America/Edmonton': 'CA',
  'America/Eirunepe': 'BR',
  'America/El_Salvador': 'SV',
  'America/Fort_Nelson': 'CA',
  'America/Fortaleza': 'BR',
  'America/Glace_Bay': 'CA',
  'America/Goose_Bay': 'CA',
  'America/Grand_Turk': 'TC',
  'America/Grenada': 'GD',
  'America/Guadeloupe': 'GP',
  'America/Guatemala': 'GT',
  'America/Guayaquil': 'EC',
  'America/Guyana': 'GY',
  'America/Halifax': 'CA',
  'America/Havana': 'CU',
  'America/Hermosillo': 'MX',
  'America/Indiana/Indianapolis': 'US',
  'America/Indiana/Knox': 'US',
  'America/Indiana/Marengo': 'US',
  'America/Indiana/Petersburg': 'US',
  'America/Indiana/Tell_City': 'US',
  'America/Indiana/Vevay': 'US',
  'America/Indiana/Vincennes': 'US',
  'America/Indiana/Winamac': 'US',
  'America/Inuvik': 'CA',
  'America/Iqaluit': 'CA',
  'America/Jamaica': 'JM',
  'America/Juneau': 'US',
  'America/Kentucky/Louisville': 'US',
  'America/Kentucky/Monticello': 'US',
  'America/Kralendijk': 'BQ',
  'America/La_Paz': 'BO',
  'America/Lima': 'PE',
  'America/Los_Angeles': 'US',
  'America/Lower_Princes': 'SX',
  'America/Maceio': 'BR',
  'America/Managua': 'NI',
  'America/Manaus': 'BR',
  'America/Marigot': 'MF',
  'America/Martinique': 'MQ',
  'America/Matamoros': 'MX',
  'America/Mazatlan': 'MX',
  'America/Menominee': 'US',
  'America/Merida': 'MX',
  'America/Metlakatla': 'US',
  'America/Mexico_City': 'MX',
  'America/Miquelon': 'PM',
  'America/Moncton': 'CA',
  'America/Monterrey': 'MX',
  'America/Montevideo': 'UY',
  'America/Montreal': 'CA',
  'America/Montserrat': 'MS',
  'America/Nassau': 'BS',
  'America/New_York': 'US',
  'America/Nome': 'US',
  'America/Noronha': 'BR',
  'America/North_Dakota/Beulah': 'US',
  'America/North_Dakota/Center': 'US',
  'America/North_Dakota/New_Salem': 'US',
  'America/Nuuk': 'GL',
  'America/Ojinaga': 'MX',
  'America/Panama': 'PA',
  'America/Paramaribo': 'SR',
  'America/Phoenix': 'US',
  'America/Port-au-Prince': 'HT',
  'America/Port_of_Spain': 'TT',
  'America/Porto_Velho': 'BR',
  'America/Puerto_Rico': 'PR',
  'America/Punta_Arenas': 'CL',
  'America/Rankin_Inlet': 'CA',
  'America/Recife': 'BR',
  'America/Regina': 'CA',
  'America/Resolute': 'CA',
  'America/Rio_Branco': 'BR',
  'America/Santarem': 'BR',
  'America/Santiago': 'CL',
  'America/Santo_Domingo': 'DO',
  'America/Sao_Paulo': 'BR',
  'America/Scoresbysund': 'GL',
  'America/Sitka': 'US',
  'America/St_Barthelemy': 'BL',
  'America/St_Johns': 'CA',
  'America/St_Kitts': 'KN',
  'America/St_Lucia': 'LC',
  'America/St_Thomas': 'VI',
  'America/St_Vincent': 'VC',
  'America/Swift_Current': 'CA',
  'America/Tegucigalpa': 'HN',
  'America/Thule': 'GL',
  'America/Thunder_Bay': 'CA',
  'America/Tijuana': 'MX',
  'America/Toronto': 'CA',
  'America/Tortola': 'VG',
  'America/Vancouver': 'CA',
  'America/Whitehorse': 'CA',
  'America/Winnipeg': 'CA',
  'America/Yakutat': 'US',
  'America/Yellowknife': 'CA',

  // --- Antarctica --------------------------------------------------------
  'Antarctica/Macquarie': 'AU',

  // --- Asia --------------------------------------------------------------
  'Asia/Aden': 'YE',
  'Asia/Almaty': 'KZ',
  'Asia/Amman': 'JO',
  'Asia/Anadyr': 'RU',
  'Asia/Aqtau': 'KZ',
  'Asia/Aqtobe': 'KZ',
  'Asia/Ashgabat': 'TM',
  'Asia/Atyrau': 'KZ',
  'Asia/Baghdad': 'IQ',
  'Asia/Bahrain': 'BH',
  'Asia/Baku': 'AZ',
  'Asia/Bangkok': 'TH',
  'Asia/Barnaul': 'RU',
  'Asia/Beirut': 'LB',
  'Asia/Bishkek': 'KG',
  'Asia/Brunei': 'BN',
  'Asia/Chita': 'RU',
  'Asia/Choibalsan': 'MN',
  'Asia/Colombo': 'LK',
  'Asia/Damascus': 'SY',
  'Asia/Dhaka': 'BD',
  'Asia/Dili': 'TL',
  'Asia/Dubai': 'AE',
  'Asia/Dushanbe': 'TJ',
  'Asia/Famagusta': 'CY',
  'Asia/Gaza': 'PS',
  'Asia/Hebron': 'PS',
  'Asia/Ho_Chi_Minh': 'VN',
  'Asia/Hong_Kong': 'HK',
  'Asia/Hovd': 'MN',
  'Asia/Irkutsk': 'RU',
  'Asia/Jakarta': 'ID',
  'Asia/Jayapura': 'ID',
  'Asia/Jerusalem': 'IL',
  'Asia/Kabul': 'AF',
  'Asia/Kamchatka': 'RU',
  'Asia/Karachi': 'PK',
  'Asia/Kathmandu': 'NP',
  'Asia/Khandyga': 'RU',
  'Asia/Kolkata': 'IN',
  'Asia/Krasnoyarsk': 'RU',
  'Asia/Kuala_Lumpur': 'MY',
  'Asia/Kuching': 'MY',
  'Asia/Kuwait': 'KW',
  'Asia/Macau': 'MO',
  'Asia/Magadan': 'RU',
  'Asia/Makassar': 'ID',
  'Asia/Manila': 'PH',
  'Asia/Muscat': 'OM',
  'Asia/Nicosia': 'CY',
  'Asia/Novokuznetsk': 'RU',
  'Asia/Novosibirsk': 'RU',
  'Asia/Omsk': 'RU',
  'Asia/Oral': 'KZ',
  'Asia/Phnom_Penh': 'KH',
  'Asia/Pontianak': 'ID',
  'Asia/Pyongyang': 'KP',
  'Asia/Qatar': 'QA',
  'Asia/Qostanay': 'KZ',
  'Asia/Qyzylorda': 'KZ',
  'Asia/Riyadh': 'SA',
  'Asia/Sakhalin': 'RU',
  'Asia/Samarkand': 'UZ',
  'Asia/Seoul': 'KR',
  'Asia/Shanghai': 'CN',
  'Asia/Singapore': 'SG',
  'Asia/Srednekolymsk': 'RU',
  'Asia/Taipei': 'TW',
  'Asia/Tashkent': 'UZ',
  'Asia/Tbilisi': 'GE',
  'Asia/Tehran': 'IR',
  'Asia/Thimphu': 'BT',
  'Asia/Tokyo': 'JP',
  'Asia/Tomsk': 'RU',
  'Asia/Ulaanbaatar': 'MN',
  'Asia/Urumqi': 'CN',
  'Asia/Ust-Nera': 'RU',
  'Asia/Vientiane': 'LA',
  'Asia/Vladivostok': 'RU',
  'Asia/Yakutsk': 'RU',
  'Asia/Yangon': 'MM',
  'Asia/Yekaterinburg': 'RU',
  'Asia/Yerevan': 'AM',

  // --- The Atlantic ------------------------------------------------------
  'Atlantic/Azores': 'PT',
  'Atlantic/Bermuda': 'BM',
  'Atlantic/Canary': 'ES',
  'Atlantic/Cape_Verde': 'CV',
  'Atlantic/Faroe': 'FO',
  'Atlantic/Jan_Mayen': 'SJ',
  'Atlantic/Madeira': 'PT',
  'Atlantic/Reykjavik': 'IS',
  'Atlantic/South_Georgia': 'GS',
  'Atlantic/St_Helena': 'SH',
  'Atlantic/Stanley': 'FK',

  // --- Australia ---------------------------------------------------------
  'Australia/Adelaide': 'AU',
  'Australia/Brisbane': 'AU',
  'Australia/Broken_Hill': 'AU',
  'Australia/Canberra': 'AU',
  'Australia/Currie': 'AU',
  'Australia/Darwin': 'AU',
  'Australia/Eucla': 'AU',
  'Australia/Hobart': 'AU',
  'Australia/Lindeman': 'AU',
  'Australia/Lord_Howe': 'AU',
  'Australia/Melbourne': 'AU',
  'Australia/Perth': 'AU',
  'Australia/Sydney': 'AU',

  // --- Europe ------------------------------------------------------------
  'Europe/Amsterdam': 'NL',
  'Europe/Andorra': 'AD',
  'Europe/Astrakhan': 'RU',
  'Europe/Athens': 'GR',
  'Europe/Belgrade': 'RS',
  'Europe/Berlin': 'DE',
  'Europe/Bratislava': 'SK',
  'Europe/Brussels': 'BE',
  'Europe/Bucharest': 'RO',
  'Europe/Budapest': 'HU',
  'Europe/Busingen': 'DE',
  'Europe/Chisinau': 'MD',
  'Europe/Copenhagen': 'DK',
  'Europe/Dublin': 'IE',
  'Europe/Gibraltar': 'GI',
  'Europe/Guernsey': 'GG',
  'Europe/Helsinki': 'FI',
  'Europe/Isle_of_Man': 'IM',
  'Europe/Istanbul': 'TR',
  'Europe/Jersey': 'JE',
  'Europe/Kaliningrad': 'RU',
  'Europe/Kirov': 'RU',
  'Europe/Kyiv': 'UA',
  'Europe/Lisbon': 'PT',
  'Europe/Ljubljana': 'SI',
  'Europe/London': 'GB',
  'Europe/Luxembourg': 'LU',
  'Europe/Madrid': 'ES',
  'Europe/Malta': 'MT',
  'Europe/Mariehamn': 'AX',
  'Europe/Minsk': 'BY',
  'Europe/Monaco': 'MC',
  'Europe/Moscow': 'RU',
  'Europe/Oslo': 'NO',
  'Europe/Paris': 'FR',
  'Europe/Podgorica': 'ME',
  'Europe/Prague': 'CZ',
  'Europe/Riga': 'LV',
  'Europe/Rome': 'IT',
  'Europe/Samara': 'RU',
  'Europe/San_Marino': 'SM',
  'Europe/Sarajevo': 'BA',
  'Europe/Saratov': 'RU',
  'Europe/Simferopol': 'UA',
  'Europe/Skopje': 'MK',
  'Europe/Sofia': 'BG',
  'Europe/Stockholm': 'SE',
  'Europe/Tallinn': 'EE',
  'Europe/Tirane': 'AL',
  'Europe/Ulyanovsk': 'RU',
  'Europe/Vaduz': 'LI',
  'Europe/Vatican': 'VA',
  'Europe/Vienna': 'AT',
  'Europe/Vilnius': 'LT',
  'Europe/Volgograd': 'RU',
  'Europe/Warsaw': 'PL',
  'Europe/Zagreb': 'HR',
  'Europe/Zurich': 'CH',

  // --- The Indian Ocean --------------------------------------------------
  'Indian/Antananarivo': 'MG',
  'Indian/Chagos': 'IO',
  'Indian/Christmas': 'CX',
  'Indian/Cocos': 'CC',
  'Indian/Comoro': 'KM',
  'Indian/Kerguelen': 'TF',
  'Indian/Mahe': 'SC',
  'Indian/Maldives': 'MV',
  'Indian/Mauritius': 'MU',
  'Indian/Mayotte': 'YT',
  'Indian/Reunion': 'RE',

  // --- The Pacific -------------------------------------------------------
  'Pacific/Apia': 'WS',
  'Pacific/Auckland': 'NZ',
  'Pacific/Bougainville': 'PG',
  'Pacific/Chatham': 'NZ',
  'Pacific/Chuuk': 'FM',
  'Pacific/Easter': 'CL',
  'Pacific/Efate': 'VU',
  'Pacific/Fakaofo': 'TK',
  'Pacific/Fiji': 'FJ',
  'Pacific/Funafuti': 'TV',
  'Pacific/Galapagos': 'EC',
  'Pacific/Gambier': 'PF',
  'Pacific/Guadalcanal': 'SB',
  'Pacific/Guam': 'GU',
  'Pacific/Honolulu': 'US',
  'Pacific/Kanton': 'KI',
  'Pacific/Kiritimati': 'KI',
  'Pacific/Kosrae': 'FM',
  'Pacific/Kwajalein': 'MH',
  'Pacific/Majuro': 'MH',
  'Pacific/Marquesas': 'PF',
  'Pacific/Midway': 'UM',
  'Pacific/Nauru': 'NR',
  'Pacific/Niue': 'NU',
  'Pacific/Norfolk': 'NF',
  'Pacific/Noumea': 'NC',
  'Pacific/Pago_Pago': 'AS',
  'Pacific/Palau': 'PW',
  'Pacific/Pitcairn': 'PN',
  'Pacific/Pohnpei': 'FM',
  'Pacific/Port_Moresby': 'PG',
  'Pacific/Rarotonga': 'CK',
  'Pacific/Saipan': 'MP',
  'Pacific/Tahiti': 'PF',
  'Pacific/Tarawa': 'KI',
  'Pacific/Tongatapu': 'TO',
  'Pacific/Wake': 'UM',
  'Pacific/Wallis': 'WF',
};

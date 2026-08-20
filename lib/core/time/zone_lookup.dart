import 'package:equatable/equatable.dart';
import 'package:timezone/timezone.dart' as tz;

/// The id this app falls back to whenever no better zone can be resolved.
///
/// It is deliberately the short `UTC` rather than the IANA canonical
/// `Etc/UTC`: it is what gets persisted, shown in Settings and compared in
/// tests, and `Etc/UTC` reads like an implementation detail to a user.
const String utcZoneId = 'UTC';

/// An IANA zone id that has been resolved against the loaded tzdata.
///
/// [id] is the canonical id the engine will actually use; [requestedId] is
/// whatever the caller passed in. They differ when the caller handed over a
/// legacy alias (`Asia/Calcutta`), an id the tzdata dropped, or nothing usable
/// at all and a fallback was applied.
///
/// ```dart
/// final ref = zoneOrHome(saved.zoneId, board.homeZoneId);
/// if (ref.wasAliased) {
///   // Rewrite the stored row so the next launch resolves on the first try.
///   await repository.updateZoneId(saved.id, ref.id);
/// }
/// ```
class ZoneRef extends Equatable {
  const ZoneRef({required this.id, required this.requestedId});

  /// The canonical IANA id, guaranteed to be loadable from the tzdata.
  final String id;

  /// The id the caller asked for, kept so callers can detect stale storage.
  final String requestedId;

  /// Whether [id] differs from what was asked for, i.e. the stored value is
  /// out of date and worth rewriting.
  bool get wasAliased => id != requestedId;

  @override
  List<Object?> get props => [id, requestedId];
}

/// Resolves [zoneId] to a canonical [ZoneRef], or `null` when the tzdata knows
/// neither the id nor any alias of it.
///
/// The raw id wins over the alias map, so a canonical id never pays for the
/// lookup and a future tzdata release that re-adds a name takes precedence
/// over our hardcoded mapping.
///
/// ```dart
/// zoneOrNull('Asia/Calcutta')!.id;  // 'Asia/Kolkata'
/// zoneOrNull('Not/AZone');          // null
/// ```
ZoneRef? zoneOrNull(String zoneId) {
  final requested = zoneId.trim();
  if (requested.isEmpty) return null;

  // Canonicalise BEFORE accepting the raw id. With the `latest_all` dataset
  // both `Europe/Oslo` and its target `Europe/Berlin` resolve, so raw-first
  // would hand back whichever spelling the caller happened to have. Two board
  // rows in one real zone would then slip past the duplicate check
  // (docs/specs/locations.md rule 2), and a stored legacy id would never be
  // rewritten. Every alias points at the same real zone, which
  // zone_lookup_test.dart pins by comparing offsets across the year.
  final canonical = _zoneAliases[requested];
  if (canonical != null && _locationNamed(canonical) != null) {
    return ZoneRef(id: canonical, requestedId: zoneId);
  }

  if (_locationNamed(requested) != null) {
    return ZoneRef(id: requested, requestedId: zoneId);
  }

  return null;
}

/// Resolves [zoneId], falling back to [homeZoneId] and then to [utcZoneId].
///
/// Never throws and never returns `null`, which is the whole point: a single
/// stale row in a synced board must not be able to blank the screen. The
/// fallback stays visible through [ZoneRef.wasAliased] so the caller can decide
/// whether to warn, rewrite or ignore it.
///
/// ```dart
/// final ref = zoneOrHome('Pacific/Atlantis', 'America/Sao_Paulo');
/// ref.id;          // 'America/Sao_Paulo'
/// ref.wasAliased;  // true
/// ```
ZoneRef zoneOrHome(String zoneId, String homeZoneId) {
  final direct = zoneOrNull(zoneId);
  if (direct != null) return direct;

  final home = zoneOrNull(homeZoneId);
  if (home != null) return ZoneRef(id: home.id, requestedId: zoneId);

  // The home zone is corrupt too. UTC always resolves, so this branch cannot
  // fail and callers never need a try/catch around a saved board.
  return ZoneRef(id: utcZoneId, requestedId: zoneId);
}

/// The tz [tz.Location] behind [zoneId], or `null` when it does not resolve.
///
/// Engine-internal: only `lib/core/time/` may hold a `tz` type. Features ask
/// `TimeZoneEngine` instead.
tz.Location? locationOrNull(String zoneId) {
  final ref = zoneOrNull(zoneId);
  if (ref == null) return null;
  return _locationNamed(ref.id);
}

/// Direct tzdata lookup, without the alias map.
///
/// `tz.getLocation` throws on an unknown name, so the database map is read
/// directly: a miss here is an ordinary answer, not an exception.
tz.Location? _locationNamed(String name) {
  // `latest_all` does register the short `UTC`, unlike `latest`, which knows
  // it only as `Etc/UTC`. The wiring stays explicit anyway so the one id this
  // app persists cannot be taken away by a dataset change
  // (docs/specs/timezone_engine.md rule 4).
  if (name == utcZoneId) return tz.UTC;
  return tz.timeZoneDatabase.locations[name];
}

/// Legacy and merged IANA ids mapped to the canonical id the tzdata ships.
///
/// This map **canonicalises**, it does not rescue. The engine imports
/// `data/latest_all.dart` (598 names), which keeps every `Link` line of the
/// IANA distribution, so `Europe/Oslo`, `Asia/Kuala_Lumpur` and
/// `Africa/Accra` already resolve on their own. What they resolve to is the
/// problem: a `Link` and its target are one clock under two spellings, and
/// without the rewrite the board takes them for two places, slips both past
/// the duplicate-zone check (docs/specs/locations.md rule 2) and draws two
/// identical rows. The ids renamed upstream (`Asia/Calcutta`) and the pre-IANA
/// names (`US/Pacific`) are the same story: `latest_all` still answers to them,
/// and the answer has to be rewritten to the one name the rest of the app
/// stores and compares against.
///
/// **These entries are not dead weight, and the two datasets do not differ
/// only in size.** Delete a row and the id it covered still resolves, which is
/// precisely why the damage is invisible: the board just gains a second row for
/// a clock it already had, and an id stored under its old name is never
/// rewritten. Switch the import to `data/latest.dart` because 185 KB looks
/// worth saving and the damage moves rather than disappearing: that dataset
/// carries 341 locations and no `Link` at all, so every link name this map does
/// not happen to list stops resolving, degrades to UTC, and reads as a
/// perfectly plausible clock that is an hour wrong for half the year. See
/// CLAUDE.md rule 8 and docs/specs/timezone_engine.md rule 4.
///
/// Three groups live here:
///   * renamed zones (`Asia/Calcutta`, `Europe/Kiev`, `America/Godthab`),
///   * zones merged into a neighbour because their clocks have agreed since
///     1970 (`Europe/Oslo`, `America/Montreal`, `Atlantic/Reykjavik`),
///   * the pre-IANA country and region names still found in old data
///     (`US/Pacific`, `Brazil/East`, `Japan`).
const Map<String, String> _zoneAliases = {
  // --- UTC and its many spellings -----------------------------------------
  'Etc/UTC': utcZoneId,
  'UCT': utcZoneId,
  'Etc/UCT': utcZoneId,
  'Universal': utcZoneId,
  'Etc/Universal': utcZoneId,
  'Zulu': utcZoneId,
  'Etc/Zulu': utcZoneId,
  'UT': utcZoneId,
  'Etc/UT': utcZoneId,
  'GMT': utcZoneId,
  'GMT0': utcZoneId,
  'GMT+0': utcZoneId,
  'GMT-0': utcZoneId,
  'Etc/GMT': utcZoneId,
  'Etc/GMT0': utcZoneId,
  'Etc/GMT+0': utcZoneId,
  'Etc/GMT-0': utcZoneId,
  'Greenwich': utcZoneId,
  'Etc/Greenwich': utcZoneId,

  // --- Africa --------------------------------------------------------------
  'Africa/Accra': 'Africa/Abidjan',
  'Africa/Bamako': 'Africa/Abidjan',
  'Africa/Banjul': 'Africa/Abidjan',
  'Africa/Conakry': 'Africa/Abidjan',
  'Africa/Dakar': 'Africa/Abidjan',
  'Africa/Freetown': 'Africa/Abidjan',
  'Africa/Lome': 'Africa/Abidjan',
  'Africa/Nouakchott': 'Africa/Abidjan',
  'Africa/Ouagadougou': 'Africa/Abidjan',
  'Africa/Timbuktu': 'Africa/Abidjan',
  'Atlantic/St_Helena': 'Africa/Abidjan',
  'Atlantic/Reykjavik': 'Africa/Abidjan',
  'Iceland': 'Africa/Abidjan',
  'Africa/Bangui': 'Africa/Lagos',
  'Africa/Brazzaville': 'Africa/Lagos',
  'Africa/Douala': 'Africa/Lagos',
  'Africa/Kinshasa': 'Africa/Lagos',
  'Africa/Libreville': 'Africa/Lagos',
  'Africa/Luanda': 'Africa/Lagos',
  'Africa/Malabo': 'Africa/Lagos',
  'Africa/Niamey': 'Africa/Lagos',
  'Africa/Porto-Novo': 'Africa/Lagos',
  'Africa/Addis_Ababa': 'Africa/Nairobi',
  'Africa/Asmara': 'Africa/Nairobi',
  'Africa/Asmera': 'Africa/Nairobi',
  'Africa/Dar_es_Salaam': 'Africa/Nairobi',
  'Africa/Djibouti': 'Africa/Nairobi',
  'Africa/Kampala': 'Africa/Nairobi',
  'Africa/Mogadishu': 'Africa/Nairobi',
  'Indian/Antananarivo': 'Africa/Nairobi',
  'Indian/Comoro': 'Africa/Nairobi',
  'Indian/Mayotte': 'Africa/Nairobi',
  'Africa/Blantyre': 'Africa/Maputo',
  'Africa/Bujumbura': 'Africa/Maputo',
  'Africa/Gaborone': 'Africa/Maputo',
  'Africa/Harare': 'Africa/Maputo',
  'Africa/Kigali': 'Africa/Maputo',
  'Africa/Lubumbashi': 'Africa/Maputo',
  'Africa/Lusaka': 'Africa/Maputo',
  'Africa/Maseru': 'Africa/Johannesburg',
  'Africa/Mbabane': 'Africa/Johannesburg',
  'Egypt': 'Africa/Cairo',
  'Libya': 'Africa/Tripoli',

  // --- Americas ------------------------------------------------------------
  'America/Godthab': 'America/Nuuk',
  'America/Montreal': 'America/Toronto',
  'America/Nassau': 'America/Toronto',
  'America/Nipigon': 'America/Toronto',
  'America/Thunder_Bay': 'America/Toronto',
  'Canada/Eastern': 'America/Toronto',
  'America/Rainy_River': 'America/Winnipeg',
  'Canada/Central': 'America/Winnipeg',
  'America/Yellowknife': 'America/Edmonton',
  'Canada/Mountain': 'America/Edmonton',
  'America/Pangnirtung': 'America/Iqaluit',
  'Canada/Atlantic': 'America/Halifax',
  'Canada/Newfoundland': 'America/St_Johns',
  'Canada/Pacific': 'America/Vancouver',
  'Canada/Saskatchewan': 'America/Regina',
  'Canada/Yukon': 'America/Whitehorse',
  'America/Atikokan': 'America/Panama',
  'America/Cayman': 'America/Panama',
  'America/Coral_Harbour': 'America/Panama',
  'America/Creston': 'America/Phoenix',
  'US/Arizona': 'America/Phoenix',
  'America/Anguilla': 'America/Puerto_Rico',
  'America/Antigua': 'America/Puerto_Rico',
  'America/Aruba': 'America/Puerto_Rico',
  'America/Blanc-Sablon': 'America/Puerto_Rico',
  'America/Curacao': 'America/Puerto_Rico',
  'America/Dominica': 'America/Puerto_Rico',
  'America/Grenada': 'America/Puerto_Rico',
  'America/Guadeloupe': 'America/Puerto_Rico',
  'America/Kralendijk': 'America/Puerto_Rico',
  'America/Lower_Princes': 'America/Puerto_Rico',
  'America/Marigot': 'America/Puerto_Rico',
  'America/Montserrat': 'America/Puerto_Rico',
  'America/Port_of_Spain': 'America/Puerto_Rico',
  'America/St_Barthelemy': 'America/Puerto_Rico',
  'America/St_Kitts': 'America/Puerto_Rico',
  'America/St_Lucia': 'America/Puerto_Rico',
  'America/St_Thomas': 'America/Puerto_Rico',
  'America/St_Vincent': 'America/Puerto_Rico',
  'America/Tortola': 'America/Puerto_Rico',
  'America/Virgin': 'America/Puerto_Rico',
  'America/Atka': 'America/Adak',
  'US/Aleutian': 'America/Adak',
  'US/Alaska': 'America/Anchorage',
  'US/Pacific': 'America/Los_Angeles',
  'US/Central': 'America/Chicago',
  'US/Eastern': 'America/New_York',
  'US/Mountain': 'America/Denver',
  'America/Shiprock': 'America/Denver',
  'Navajo': 'America/Denver',
  'US/Michigan': 'America/Detroit',
  'US/Hawaii': 'Pacific/Honolulu',
  'Pacific/Johnston': 'Pacific/Honolulu',
  'America/Fort_Wayne': 'America/Indiana/Indianapolis',
  'America/Indianapolis': 'America/Indiana/Indianapolis',
  'US/East-Indiana': 'America/Indiana/Indianapolis',
  'America/Knox_IN': 'America/Indiana/Knox',
  'US/Indiana-Starke': 'America/Indiana/Knox',
  'America/Louisville': 'America/Kentucky/Louisville',
  'America/Ensenada': 'America/Tijuana',
  'America/Santa_Isabel': 'America/Tijuana',
  'Mexico/BajaNorte': 'America/Tijuana',
  'Mexico/BajaSur': 'America/Mazatlan',
  'Mexico/General': 'America/Mexico_City',
  'Cuba': 'America/Havana',
  'Jamaica': 'America/Jamaica',
  'Brazil/East': 'America/Sao_Paulo',
  'Brazil/West': 'America/Manaus',
  'Brazil/Acre': 'America/Rio_Branco',
  'America/Porto_Acre': 'America/Rio_Branco',
  'Brazil/DeNoronha': 'America/Noronha',
  'America/Buenos_Aires': 'America/Argentina/Buenos_Aires',
  'America/Catamarca': 'America/Argentina/Catamarca',
  'America/Argentina/ComodRivadavia': 'America/Argentina/Catamarca',
  'America/Cordoba': 'America/Argentina/Cordoba',
  'America/Rosario': 'America/Argentina/Cordoba',
  'America/Jujuy': 'America/Argentina/Jujuy',
  'America/Mendoza': 'America/Argentina/Mendoza',
  'Chile/Continental': 'America/Santiago',
  'Chile/EasterIsland': 'Pacific/Easter',

  // --- Asia ----------------------------------------------------------------
  'Asia/Calcutta': 'Asia/Kolkata',
  'Asia/Rangoon': 'Asia/Yangon',
  'Indian/Cocos': 'Asia/Yangon',
  'Asia/Saigon': 'Asia/Ho_Chi_Minh',
  'Asia/Katmandu': 'Asia/Kathmandu',
  'Asia/Thimbu': 'Asia/Thimphu',
  'Asia/Dacca': 'Asia/Dhaka',
  'Asia/Ashkhabad': 'Asia/Ashgabat',
  'Asia/Ulan_Bator': 'Asia/Ulaanbaatar',
  'Asia/Ujung_Pandang': 'Asia/Makassar',
  'Asia/Chongqing': 'Asia/Shanghai',
  'Asia/Chungking': 'Asia/Shanghai',
  'Asia/Harbin': 'Asia/Shanghai',
  'PRC': 'Asia/Shanghai',
  'Asia/Kashgar': 'Asia/Urumqi',
  'Antarctica/Vostok': 'Asia/Urumqi',
  'Asia/Macao': 'Asia/Macau',
  'Asia/Istanbul': 'Europe/Istanbul',
  'Turkey': 'Europe/Istanbul',
  'Asia/Tel_Aviv': 'Asia/Jerusalem',
  'Israel': 'Asia/Jerusalem',
  'Asia/Kuala_Lumpur': 'Asia/Singapore',
  'Singapore': 'Asia/Singapore',
  'Asia/Brunei': 'Asia/Kuching',
  'Asia/Phnom_Penh': 'Asia/Bangkok',
  'Asia/Vientiane': 'Asia/Bangkok',
  'Indian/Christmas': 'Asia/Bangkok',
  'Asia/Aden': 'Asia/Riyadh',
  'Asia/Kuwait': 'Asia/Riyadh',
  'Antarctica/Syowa': 'Asia/Riyadh',
  'Asia/Bahrain': 'Asia/Qatar',
  'Asia/Muscat': 'Asia/Dubai',
  'Indian/Mahe': 'Asia/Dubai',
  'Indian/Reunion': 'Asia/Dubai',
  'Indian/Kerguelen': 'Indian/Maldives',
  'Hongkong': 'Asia/Hong_Kong',
  'Japan': 'Asia/Tokyo',
  'ROK': 'Asia/Seoul',
  'ROC': 'Asia/Taipei',
  'Iran': 'Asia/Tehran',

  // --- Europe --------------------------------------------------------------
  'Europe/Kiev': 'Europe/Kyiv',
  'Europe/Uzhgorod': 'Europe/Kyiv',
  'Europe/Zaporozhye': 'Europe/Kyiv',
  'Europe/Nicosia': 'Asia/Nicosia',
  'Europe/Belfast': 'Europe/London',
  'Europe/Guernsey': 'Europe/London',
  'Europe/Isle_of_Man': 'Europe/London',
  'Europe/Jersey': 'Europe/London',
  'GB': 'Europe/London',
  'GB-Eire': 'Europe/London',
  'Eire': 'Europe/Dublin',
  'Europe/Copenhagen': 'Europe/Berlin',
  'Europe/Oslo': 'Europe/Berlin',
  'Europe/Stockholm': 'Europe/Berlin',
  'Arctic/Longyearbyen': 'Europe/Berlin',
  'Atlantic/Jan_Mayen': 'Europe/Berlin',
  'Europe/Amsterdam': 'Europe/Brussels',
  'Europe/Luxembourg': 'Europe/Brussels',
  'Europe/Monaco': 'Europe/Paris',
  'Europe/Bratislava': 'Europe/Prague',
  'Europe/Busingen': 'Europe/Zurich',
  'Europe/Vaduz': 'Europe/Zurich',
  'Europe/San_Marino': 'Europe/Rome',
  'Europe/Vatican': 'Europe/Rome',
  'Europe/Ljubljana': 'Europe/Belgrade',
  'Europe/Podgorica': 'Europe/Belgrade',
  'Europe/Sarajevo': 'Europe/Belgrade',
  'Europe/Skopje': 'Europe/Belgrade',
  'Europe/Zagreb': 'Europe/Belgrade',
  'Europe/Mariehamn': 'Europe/Helsinki',
  'Europe/Tiraspol': 'Europe/Chisinau',
  'Poland': 'Europe/Warsaw',
  'Portugal': 'Europe/Lisbon',
  'W-SU': 'Europe/Moscow',
  'Atlantic/Faeroe': 'Atlantic/Faroe',

  // --- Oceania and Antarctica ---------------------------------------------
  'Australia/ACT': 'Australia/Sydney',
  'Australia/Canberra': 'Australia/Sydney',
  'Australia/NSW': 'Australia/Sydney',
  'Australia/Victoria': 'Australia/Melbourne',
  'Australia/Queensland': 'Australia/Brisbane',
  'Australia/South': 'Australia/Adelaide',
  'Australia/North': 'Australia/Darwin',
  'Australia/West': 'Australia/Perth',
  'Australia/Tasmania': 'Australia/Hobart',
  'Australia/Currie': 'Australia/Hobart',
  'Australia/Yancowinna': 'Australia/Broken_Hill',
  'Australia/LHI': 'Australia/Lord_Howe',
  'NZ': 'Pacific/Auckland',
  'Antarctica/McMurdo': 'Pacific/Auckland',
  'Antarctica/South_Pole': 'Pacific/Auckland',
  'NZ-CHAT': 'Pacific/Chatham',
  'Pacific/Chuuk': 'Pacific/Port_Moresby',
  'Pacific/Truk': 'Pacific/Port_Moresby',
  'Pacific/Yap': 'Pacific/Port_Moresby',
  'Antarctica/DumontDUrville': 'Pacific/Port_Moresby',
  'Pacific/Pohnpei': 'Pacific/Guadalcanal',
  'Pacific/Ponape': 'Pacific/Guadalcanal',
  'Pacific/Funafuti': 'Pacific/Tarawa',
  'Pacific/Majuro': 'Pacific/Tarawa',
  'Pacific/Wake': 'Pacific/Tarawa',
  'Pacific/Wallis': 'Pacific/Tarawa',
  'Pacific/Enderbury': 'Pacific/Kanton',
  'Pacific/Saipan': 'Pacific/Guam',
  'Pacific/Midway': 'Pacific/Pago_Pago',
  'Pacific/Samoa': 'Pacific/Pago_Pago',
  'US/Samoa': 'Pacific/Pago_Pago',
  'Kwajalein': 'Pacific/Kwajalein',
};

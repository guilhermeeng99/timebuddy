// Curated seed data for `build_city_catalog.dart`. Data only: no imports and
// no logic, so it can be reviewed as a table rather than as code.
//
// WHY A SEED TABLE AT ALL. The catalog is derived from the shipped tz database
// (see the header of build_city_catalog.dart), which knows exactly one thing
// about a place: its IANA id. That is enough for `America/Sao_Paulo` to become
// a row called "Sao Paulo", and not nearly enough for it to be findable. The
// table below adds what the database cannot: the country a user would search
// by, the state that tells two Portlands apart, a weight that puts London
// above Lord Howe, the names people actually type ("NYC", "Bengaluru",
// "Sampa"), and the cities that have no zone of their own because they share a
// clock with a neighbour - Rio de Janeiro, Mumbai, Frankfurt.
//
// Seeds win every field of the row they override. A tzdata upgrade may rename
// or drop a zone, and when it does the build fails loudly (every seed's
// `zoneName` is verified through `zoneOrNull`) rather than quietly shipping a
// city that resolves to UTC.

/// One curated city, as it will be merged into the derived catalog.
///
/// Positional on purpose: the table below is ~250 rows, and named arguments
/// would triple its height for no gain in a fixed six-column shape. The order
/// is zone, name, country, prominence, aliases, state.
///
/// ```dart
/// CitySeed('America/Sao_Paulo', 'Sao Paulo', 'BR', 100, ['Sampa', 'SP'])
/// ```
class CitySeed {
  const CitySeed(
    this.zoneName,
    this.name,
    this.countryCode,
    this.prominence, [
    this.aliases = const <String>[],
    this.admin1,
  ]);

  /// The tz database entry this row stands for, canonical or `Link` alias.
  ///
  /// Not necessarily the id that ends up in the JSON: `Europe/Oslo` is a
  /// `Link` onto `Europe/Berlin`, and the build stores the canonical target so
  /// two spellings of one clock cannot become two board rows. Writing the
  /// spelling that names the *place* keeps this table readable, and keeps the
  /// verification honest - if a future tzdata drops the alias, the build says
  /// which city lost its zone.
  final String zoneName;

  /// English display name, deliberately without diacritics.
  ///
  /// `normalizeForSearch` folds an accented query onto the plain spelling, so
  /// "são paulo" finds "Sao Paulo" either way; storing the plain form keeps
  /// the asset ASCII and the JSON diff-friendly.
  final String name;

  /// ISO 3166-1 alpha-2. `ZZ` marks the one non-country row, `UTC`.
  final String countryCode;

  /// Search weight, assigned in bands rather than measured:
  ///
  /// * 100 - a global hub someone in any timezone might watch (London, Tokyo)
  /// * 85-99 - a major world city (Beijing, Mumbai, Rio de Janeiro)
  /// * 70-84 - a national capital or a large regional centre
  /// * 50-69 - a well-known city, or the largest one of a small country
  /// * 1-49 - known but rarely watched (Fernando de Noronha, Thimphu)
  ///
  /// Bands, not a population figure, because the question this answers is
  /// "which of these did the user probably mean", and that is a judgement
  /// about familiarity. A population column would also be a second dataset to
  /// keep current, and would rank Chongqing above Zurich for an audience that
  /// is far more likely to be typing the second.
  ///
  /// Never 0: zero is what marks a derived, uncurated row everywhere else.
  final int prominence;

  /// Extra strings that must find this city. Never displayed.
  ///
  /// Only real ones: a local spelling ('Lisboa'), a nickname people type
  /// ('Sampa', 'BH', 'Joburg'), a former name still in use ('Bombay',
  /// 'Calcutta'), or the IATA code of the city's main airport, which is how a
  /// frequent traveller often thinks of it ('GRU', 'JFK').
  final List<String> aliases;

  /// State or province, set only where it disambiguates a name.
  ///
  /// Left null when it would merely repeat the city ("Sao Paulo, Sao Paulo").
  final String? admin1;
}

/// Curated rows that replace the derived row for the same `zoneName`.
///
/// One entry per tz database name at most; the build asserts it. To add a city
/// that shares another city's clock, use [extraCitySeeds] instead.
const List<CitySeed> citySeeds = <CitySeed>[
  // --- Coordinated Universal Time ----------------------------------------
  CitySeed(
    'UTC',
    'UTC',
    'ZZ',
    5,
    ['GMT', 'Zulu', 'Coordinated Universal Time'],
  ),

  // --- The Americas ------------------------------------------------------
  CitySeed('America/Sao_Paulo', 'Sao Paulo', 'BR', 100, ['Sampa', 'SP', 'GRU']),
  CitySeed('America/Bahia', 'Salvador', 'BR', 82, ['Bahia', 'SSA'], 'Bahia'),
  CitySeed('America/Fortaleza', 'Fortaleza', 'BR', 80, [], 'Ceara'),
  CitySeed('America/Recife', 'Recife', 'BR', 80, ['REC'], 'Pernambuco'),
  CitySeed('America/Manaus', 'Manaus', 'BR', 75, [], 'Amazonas'),
  CitySeed('America/Belem', 'Belem', 'BR', 72, [], 'Para'),
  CitySeed(
    'America/Campo_Grande',
    'Campo Grande',
    'BR',
    65,
    [],
    'Mato Grosso do Sul',
  ),
  CitySeed('America/Cuiaba', 'Cuiaba', 'BR', 65, [], 'Mato Grosso'),
  CitySeed('America/Maceio', 'Maceio', 'BR', 62, [], 'Alagoas'),
  CitySeed('America/Porto_Velho', 'Porto Velho', 'BR', 58, [], 'Rondonia'),
  CitySeed('America/Rio_Branco', 'Rio Branco', 'BR', 55, [], 'Acre'),
  CitySeed('America/Boa_Vista', 'Boa Vista', 'BR', 52, [], 'Roraima'),
  CitySeed('America/Araguaina', 'Araguaina', 'BR', 50, [], 'Tocantins'),
  CitySeed('America/Santarem', 'Santarem', 'BR', 50, [], 'Para'),
  CitySeed(
    'America/Noronha',
    'Fernando de Noronha',
    'BR',
    45,
    ['Noronha'],
    'Pernambuco',
  ),
  CitySeed(
    'America/New_York',
    'New York',
    'US',
    100,
    ['NYC', 'New York City', 'JFK'],
  ),
  CitySeed(
    'America/Los_Angeles',
    'Los Angeles',
    'US',
    96,
    ['LA', 'LAX'],
    'California',
  ),
  CitySeed('America/Chicago', 'Chicago', 'US', 92, ['ORD'], 'Illinois'),
  CitySeed('America/Denver', 'Denver', 'US', 78, ['DEN'], 'Colorado'),
  CitySeed('America/Phoenix', 'Phoenix', 'US', 76, [], 'Arizona'),
  CitySeed('America/Detroit', 'Detroit', 'US', 70, [], 'Michigan'),
  CitySeed('America/Anchorage', 'Anchorage', 'US', 60, [], 'Alaska'),

  // --- The Pacific -------------------------------------------------------
  CitySeed('Pacific/Honolulu', 'Honolulu', 'US', 70, ['Hawaii'], 'Hawaii'),

  // --- The Americas ------------------------------------------------------
  CitySeed('America/Toronto', 'Toronto', 'CA', 90, ['YYZ'], 'Ontario'),
  CitySeed('America/Montreal', 'Montreal', 'CA', 84, ['YUL'], 'Quebec'),
  CitySeed(
    'America/Vancouver',
    'Vancouver',
    'CA',
    84,
    ['YVR'],
    'British Columbia',
  ),
  CitySeed('America/Edmonton', 'Edmonton', 'CA', 70, [], 'Alberta'),
  CitySeed('America/Winnipeg', 'Winnipeg', 'CA', 66, [], 'Manitoba'),
  CitySeed('America/Halifax', 'Halifax', 'CA', 64, [], 'Nova Scotia'),
  CitySeed(
    'America/St_Johns',
    "St. John's",
    'CA',
    60,
    ['St Johns'],
    'Newfoundland and Labrador',
  ),
  CitySeed('America/Regina', 'Regina', 'CA', 55, [], 'Saskatchewan'),
  CitySeed(
    'America/Mexico_City',
    'Mexico City',
    'MX',
    92,
    ['CDMX', 'Ciudad de Mexico', 'MEX'],
    'Ciudad de Mexico',
  ),
  CitySeed('America/Monterrey', 'Monterrey', 'MX', 74, [], 'Nuevo Leon'),
  CitySeed('America/Tijuana', 'Tijuana', 'MX', 68, [], 'Baja California'),
  CitySeed('America/Cancun', 'Cancun', 'MX', 66, [], 'Quintana Roo'),
  CitySeed('America/Havana', 'Havana', 'CU', 70, ['La Habana']),
  CitySeed('America/Panama', 'Panama City', 'PA', 72, ['Panama']),
  CitySeed('America/Guatemala', 'Guatemala City', 'GT', 66, ['Guatemala']),
  CitySeed('America/Costa_Rica', 'San Jose', 'CR', 64, ['Costa Rica']),
  CitySeed('America/El_Salvador', 'San Salvador', 'SV', 60),
  CitySeed('America/Tegucigalpa', 'Tegucigalpa', 'HN', 56),
  CitySeed('America/Managua', 'Managua', 'NI', 56),
  CitySeed('America/Puerto_Rico', 'San Juan', 'PR', 66, ['Puerto Rico']),
  CitySeed('America/Santo_Domingo', 'Santo Domingo', 'DO', 64),
  CitySeed('America/Port-au-Prince', 'Port-au-Prince', 'HT', 58),
  CitySeed('America/Jamaica', 'Kingston', 'JM', 60, ['Jamaica']),
  CitySeed(
    'America/Argentina/Buenos_Aires',
    'Buenos Aires',
    'AR',
    88,
    ['BA', 'BsAs', 'EZE'],
  ),
  CitySeed('America/Argentina/Cordoba', 'Cordoba', 'AR', 64),
  CitySeed('America/Argentina/Mendoza', 'Mendoza', 'AR', 55),
  CitySeed('America/Santiago', 'Santiago', 'CL', 84, ['SCL']),
  CitySeed('America/Bogota', 'Bogota', 'CO', 84, ['BOG']),
  CitySeed('America/Lima', 'Lima', 'PE', 82, ['LIM']),
  CitySeed('America/Caracas', 'Caracas', 'VE', 72),
  CitySeed('America/Montevideo', 'Montevideo', 'UY', 70, ['MVD']),
  CitySeed('America/La_Paz', 'La Paz', 'BO', 66),
  CitySeed('America/Guayaquil', 'Guayaquil', 'EC', 66),
  CitySeed('America/Asuncion', 'Asuncion', 'PY', 64),
  CitySeed('America/Paramaribo', 'Paramaribo', 'SR', 50),
  CitySeed('America/Cayenne', 'Cayenne', 'GF', 45),

  // --- Europe ------------------------------------------------------------
  CitySeed('Europe/London', 'London', 'GB', 100, ['LHR', 'LON'], 'England'),
  CitySeed('Europe/Paris', 'Paris', 'FR', 96, ['CDG'], 'Ile-de-France'),
  CitySeed('Europe/Berlin', 'Berlin', 'DE', 92, ['BER']),
  CitySeed('Europe/Madrid', 'Madrid', 'ES', 88, ['MAD']),
  CitySeed('Europe/Amsterdam', 'Amsterdam', 'NL', 88, ['AMS']),
  CitySeed('Europe/Rome', 'Rome', 'IT', 88, ['Roma', 'FCO']),
  CitySeed('Europe/Zurich', 'Zurich', 'CH', 84, ['ZRH']),
  CitySeed('Europe/Dublin', 'Dublin', 'IE', 82, ['DUB']),
  CitySeed('Europe/Lisbon', 'Lisbon', 'PT', 82, ['Lisboa', 'LIS']),
  CitySeed(
    'Europe/Brussels',
    'Brussels',
    'BE',
    82,
    ['Bruxelles', 'Brussel', 'BRU'],
  ),
  CitySeed('Europe/Vienna', 'Vienna', 'AT', 80, ['Wien', 'VIE']),
  CitySeed('Europe/Luxembourg', 'Luxembourg', 'LU', 62),
  CitySeed('Europe/Monaco', 'Monaco', 'MC', 50),
  CitySeed('Europe/Stockholm', 'Stockholm', 'SE', 80, ['ARN']),
  CitySeed('Europe/Copenhagen', 'Copenhagen', 'DK', 80, ['Kobenhavn', 'CPH']),
  CitySeed('Europe/Oslo', 'Oslo', 'NO', 78, ['OSL']),
  CitySeed('Europe/Helsinki', 'Helsinki', 'FI', 76, ['HEL']),

  // --- The Atlantic ------------------------------------------------------
  CitySeed('Atlantic/Reykjavik', 'Reykjavik', 'IS', 60, ['KEF']),

  // --- Europe ------------------------------------------------------------
  CitySeed('Europe/Tallinn', 'Tallinn', 'EE', 62),
  CitySeed('Europe/Riga', 'Riga', 'LV', 62),
  CitySeed('Europe/Vilnius', 'Vilnius', 'LT', 62),
  CitySeed('Europe/Warsaw', 'Warsaw', 'PL', 78, ['Warszawa', 'WAW']),
  CitySeed('Europe/Prague', 'Prague', 'CZ', 78, ['Praha', 'PRG']),
  CitySeed('Europe/Budapest', 'Budapest', 'HU', 74, ['BUD']),
  CitySeed('Europe/Bucharest', 'Bucharest', 'RO', 72, ['Bucuresti']),
  CitySeed('Europe/Belgrade', 'Belgrade', 'RS', 68, ['Beograd']),
  CitySeed('Europe/Sofia', 'Sofia', 'BG', 68),
  CitySeed('Europe/Zagreb', 'Zagreb', 'HR', 64),
  CitySeed('Europe/Bratislava', 'Bratislava', 'SK', 62),
  CitySeed('Europe/Ljubljana', 'Ljubljana', 'SI', 58),
  CitySeed('Europe/Athens', 'Athens', 'GR', 76, ['Athina', 'ATH']),
  CitySeed('Europe/Istanbul', 'Istanbul', 'TR', 88, ['IST', 'Constantinople']),
  CitySeed('Europe/Kyiv', 'Kyiv', 'UA', 76, ['Kiev', 'KBP']),
  CitySeed('Europe/Minsk', 'Minsk', 'BY', 66),
  CitySeed('Europe/Moscow', 'Moscow', 'RU', 88, ['Moskva', 'SVO']),
  CitySeed('Europe/Malta', 'Valletta', 'MT', 58, ['Malta']),

  // --- The Atlantic ------------------------------------------------------
  CitySeed(
    'Atlantic/Canary',
    'Las Palmas',
    'ES',
    50,
    ['Canary Islands', 'Canarias'],
    'Canary Islands',
  ),

  // --- Africa ------------------------------------------------------------
  CitySeed('Africa/Cairo', 'Cairo', 'EG', 88, ['Al Qahirah', 'CAI']),
  CitySeed('Africa/Lagos', 'Lagos', 'NG', 86, ['LOS']),
  CitySeed(
    'Africa/Johannesburg',
    'Johannesburg',
    'ZA',
    84,
    ['Joburg', 'JNB'],
    'Gauteng',
  ),
  CitySeed('Africa/Nairobi', 'Nairobi', 'KE', 80, ['NBO']),
  CitySeed('Africa/Kinshasa', 'Kinshasa', 'CD', 78),
  CitySeed(
    'Africa/Casablanca',
    'Casablanca',
    'MA',
    78,
    ['Dar el Beida', 'CMN'],
  ),
  CitySeed('Africa/Abidjan', 'Abidjan', 'CI', 74),
  CitySeed('Africa/Addis_Ababa', 'Addis Ababa', 'ET', 74, ['ADD']),
  CitySeed('Africa/Accra', 'Accra', 'GH', 74, ['ACC']),
  CitySeed('Africa/Algiers', 'Algiers', 'DZ', 72, ['Alger']),
  CitySeed('Africa/Dar_es_Salaam', 'Dar es Salaam', 'TZ', 72),
  CitySeed('Africa/Luanda', 'Luanda', 'AO', 72),
  CitySeed('Africa/Dakar', 'Dakar', 'SN', 70),
  CitySeed('Africa/Tunis', 'Tunis', 'TN', 68),
  CitySeed('Africa/Khartoum', 'Khartoum', 'SD', 68),
  CitySeed('Africa/Kampala', 'Kampala', 'UG', 66),
  CitySeed('Africa/Maputo', 'Maputo', 'MZ', 66),
  CitySeed('Africa/Harare', 'Harare', 'ZW', 62),
  CitySeed('Africa/Windhoek', 'Windhoek', 'NA', 56),

  // --- Asia --------------------------------------------------------------
  CitySeed('Asia/Tokyo', 'Tokyo', 'JP', 100, ['Tokio', 'HND', 'NRT']),
  CitySeed('Asia/Shanghai', 'Shanghai', 'CN', 96, ['PVG']),
  CitySeed('Asia/Hong_Kong', 'Hong Kong', 'HK', 94, ['HKG']),
  CitySeed('Asia/Singapore', 'Singapore', 'SG', 94, ['SIN']),
  CitySeed('Asia/Seoul', 'Seoul', 'KR', 90, ['ICN']),
  CitySeed('Asia/Bangkok', 'Bangkok', 'TH', 88, ['Krung Thep', 'BKK']),
  CitySeed('Asia/Jakarta', 'Jakarta', 'ID', 88, ['CGK']),
  CitySeed('Asia/Manila', 'Manila', 'PH', 84, ['MNL']),
  CitySeed('Asia/Ho_Chi_Minh', 'Ho Chi Minh City', 'VN', 84, ['Saigon', 'SGN']),
  CitySeed('Asia/Kuala_Lumpur', 'Kuala Lumpur', 'MY', 84, ['KL', 'KUL']),
  CitySeed('Asia/Taipei', 'Taipei', 'TW', 82, ['TPE']),
  CitySeed('Asia/Macau', 'Macau', 'MO', 64, ['Macao']),
  CitySeed('Asia/Yangon', 'Yangon', 'MM', 66, ['Rangoon']),
  CitySeed('Asia/Phnom_Penh', 'Phnom Penh', 'KH', 62),
  CitySeed('Asia/Vientiane', 'Vientiane', 'LA', 56),
  CitySeed('Asia/Ulaanbaatar', 'Ulaanbaatar', 'MN', 58, ['Ulan Bator']),
  CitySeed('Asia/Pyongyang', 'Pyongyang', 'KP', 50),
  CitySeed(
    'Asia/Kolkata',
    'Kolkata',
    'IN',
    84,
    ['Calcutta', 'CCU'],
    'West Bengal',
  ),
  CitySeed('Asia/Karachi', 'Karachi', 'PK', 84, ['KHI'], 'Sindh'),
  CitySeed('Asia/Dhaka', 'Dhaka', 'BD', 82, ['DAC']),
  CitySeed('Asia/Colombo', 'Colombo', 'LK', 68, ['CMB']),
  CitySeed('Asia/Kathmandu', 'Kathmandu', 'NP', 64, ['KTM']),
  CitySeed('Asia/Kabul', 'Kabul', 'AF', 60),
  CitySeed('Asia/Thimphu', 'Thimphu', 'BT', 45),
  CitySeed('Asia/Tashkent', 'Tashkent', 'UZ', 66),
  CitySeed('Asia/Almaty', 'Almaty', 'KZ', 66),
  CitySeed('Asia/Bishkek', 'Bishkek', 'KG', 55),
  CitySeed('Asia/Dushanbe', 'Dushanbe', 'TJ', 52),
  CitySeed('Asia/Ashgabat', 'Ashgabat', 'TM', 52),
  CitySeed('Asia/Dubai', 'Dubai', 'AE', 92, ['DXB']),
  CitySeed('Asia/Riyadh', 'Riyadh', 'SA', 80, ['RUH']),
  CitySeed('Asia/Tehran', 'Tehran', 'IR', 78, ['THR']),
  CitySeed('Asia/Jerusalem', 'Jerusalem', 'IL', 78),
  CitySeed('Asia/Qatar', 'Doha', 'QA', 74, ['Qatar', 'DOH']),
  CitySeed('Asia/Baghdad', 'Baghdad', 'IQ', 70),
  CitySeed('Asia/Kuwait', 'Kuwait City', 'KW', 68, ['Kuwait']),
  CitySeed('Asia/Beirut', 'Beirut', 'LB', 66, ['BEY']),
  CitySeed('Asia/Amman', 'Amman', 'JO', 64),
  CitySeed('Asia/Muscat', 'Muscat', 'OM', 62),
  CitySeed('Asia/Damascus', 'Damascus', 'SY', 62),
  CitySeed('Asia/Bahrain', 'Manama', 'BH', 58, ['Bahrain']),
  CitySeed('Asia/Baku', 'Baku', 'AZ', 66),
  CitySeed('Asia/Tbilisi', 'Tbilisi', 'GE', 62),
  CitySeed('Asia/Yerevan', 'Yerevan', 'AM', 60),
  CitySeed('Asia/Yekaterinburg', 'Yekaterinburg', 'RU', 64),
  CitySeed('Asia/Novosibirsk', 'Novosibirsk', 'RU', 62),
  CitySeed('Asia/Vladivostok', 'Vladivostok', 'RU', 60),
  CitySeed('Asia/Krasnoyarsk', 'Krasnoyarsk', 'RU', 55),
  CitySeed('Asia/Irkutsk', 'Irkutsk', 'RU', 52),

  // --- Europe ------------------------------------------------------------
  CitySeed('Europe/Kaliningrad', 'Kaliningrad', 'RU', 50),

  // --- Australia ---------------------------------------------------------
  CitySeed('Australia/Sydney', 'Sydney', 'AU', 92, ['SYD'], 'New South Wales'),
  CitySeed('Australia/Melbourne', 'Melbourne', 'AU', 88, ['MEL'], 'Victoria'),
  CitySeed('Australia/Brisbane', 'Brisbane', 'AU', 80, ['BNE'], 'Queensland'),
  CitySeed('Australia/Perth', 'Perth', 'AU', 78, ['PER'], 'Western Australia'),
  CitySeed(
    'Australia/Adelaide',
    'Adelaide',
    'AU',
    74,
    ['ADL'],
    'South Australia',
  ),
  CitySeed(
    'Australia/Canberra',
    'Canberra',
    'AU',
    70,
    ['CBR'],
    'Australian Capital Territory',
  ),
  CitySeed('Australia/Hobart', 'Hobart', 'AU', 62, [], 'Tasmania'),
  CitySeed('Australia/Darwin', 'Darwin', 'AU', 62, [], 'Northern Territory'),

  // --- The Pacific -------------------------------------------------------
  CitySeed('Pacific/Auckland', 'Auckland', 'NZ', 80, ['AKL']),
  CitySeed('Pacific/Fiji', 'Suva', 'FJ', 56, ['Fiji']),
  CitySeed('Pacific/Port_Moresby', 'Port Moresby', 'PG', 56),
  CitySeed('Pacific/Tahiti', 'Papeete', 'PF', 54, ['Tahiti']),
  CitySeed('Pacific/Noumea', 'Noumea', 'NC', 52),
  CitySeed('Pacific/Guam', 'Hagatna', 'GU', 50, ['Guam', 'Agana']),

  // --- The Indian Ocean --------------------------------------------------
  CitySeed('Indian/Maldives', 'Male', 'MV', 50, ['Maldives']),
];

/// Curated cities that have no zone of their own.
///
/// `zoneName` here names the *clock* the city keeps, not the city: Rio de
/// Janeiro reads `America/Sao_Paulo`, Frankfurt reads `Europe/Berlin`. These
/// are appended rather than merged, so several rows legitimately share one
/// canonical `zoneId` - which is also why the board rejects the second of them
/// as a duplicate zone (docs/specs/locations.md rule 2).
const List<CitySeed> extraCitySeeds = <CitySeed>[
  // --- The Americas ------------------------------------------------------
  CitySeed(
    'America/Sao_Paulo',
    'Rio de Janeiro',
    'BR',
    95,
    ['Rio', 'RJ', 'GIG'],
  ),
  CitySeed(
    'America/Sao_Paulo',
    'Brasilia',
    'BR',
    90,
    ['BSB'],
    'Distrito Federal',
  ),
  CitySeed(
    'America/Sao_Paulo',
    'Belo Horizonte',
    'BR',
    85,
    ['BH', 'Beaga', 'CNF'],
    'Minas Gerais',
  ),
  CitySeed(
    'America/Sao_Paulo',
    'Porto Alegre',
    'BR',
    78,
    ['Poa', 'POA'],
    'Rio Grande do Sul',
  ),
  CitySeed('America/Sao_Paulo', 'Curitiba', 'BR', 76, ['CWB'], 'Parana'),
  CitySeed('America/Sao_Paulo', 'Goiania', 'BR', 70, [], 'Goias'),
  CitySeed(
    'America/Sao_Paulo',
    'Florianopolis',
    'BR',
    66,
    ['Floripa', 'FLN'],
    'Santa Catarina',
  ),
  CitySeed('America/Sao_Paulo', 'Campinas', 'BR', 62, [], 'Sao Paulo'),
  CitySeed('America/Sao_Paulo', 'Vitoria', 'BR', 58, [], 'Espirito Santo'),
  CitySeed('America/Fortaleza', 'Natal', 'BR', 60, [], 'Rio Grande do Norte'),
  CitySeed('America/Fortaleza', 'Joao Pessoa', 'BR', 55, [], 'Paraiba'),
  CitySeed('America/Fortaleza', 'Teresina', 'BR', 55, [], 'Piaui'),
  CitySeed('America/Fortaleza', 'Sao Luis', 'BR', 55, [], 'Maranhao'),
  CitySeed('America/Bahia', 'Aracaju', 'BR', 50, [], 'Sergipe'),
  CitySeed(
    'America/New_York',
    'Washington',
    'US',
    88,
    ['Washington DC', 'DC', 'IAD'],
    'District of Columbia',
  ),
  CitySeed('America/New_York', 'Miami', 'US', 86, ['MIA'], 'Florida'),
  CitySeed('America/New_York', 'Boston', 'US', 84, ['BOS'], 'Massachusetts'),
  CitySeed(
    'America/New_York',
    'Philadelphia',
    'US',
    80,
    ['Philly', 'PHL'],
    'Pennsylvania',
  ),
  CitySeed('America/New_York', 'Atlanta', 'US', 78, ['ATL'], 'Georgia'),
  CitySeed('America/New_York', 'Orlando', 'US', 70, ['MCO'], 'Florida'),
  CitySeed(
    'America/Los_Angeles',
    'San Francisco',
    'US',
    94,
    ['SF', 'Bay Area', 'SFO'],
    'California',
  ),
  CitySeed('America/Los_Angeles', 'Seattle', 'US', 82, ['SEA'], 'Washington'),
  CitySeed('America/Los_Angeles', 'San Diego', 'US', 76, ['SAN'], 'California'),
  CitySeed('America/Los_Angeles', 'Las Vegas', 'US', 72, ['LAS'], 'Nevada'),
  CitySeed('America/Los_Angeles', 'Portland', 'US', 70, ['PDX'], 'Oregon'),
  CitySeed('America/Chicago', 'Houston', 'US', 80, ['IAH'], 'Texas'),
  CitySeed('America/Chicago', 'Dallas', 'US', 80, ['DFW'], 'Texas'),
  CitySeed('America/Chicago', 'Austin', 'US', 74, ['AUS'], 'Texas'),
  CitySeed('America/Chicago', 'Minneapolis', 'US', 70, ['MSP'], 'Minnesota'),
  CitySeed('America/Toronto', 'Ottawa', 'CA', 76, ['YOW'], 'Ontario'),
  CitySeed('America/Toronto', 'Quebec City', 'CA', 66, ['Quebec'], 'Quebec'),
  CitySeed('America/Edmonton', 'Calgary', 'CA', 74, ['YYC'], 'Alberta'),
  CitySeed('America/Mexico_City', 'Guadalajara', 'MX', 76, ['GDL'], 'Jalisco'),
  CitySeed('America/Mexico_City', 'Puebla', 'MX', 62),
  CitySeed('America/Bogota', 'Medellin', 'CO', 70, ['MDE'], 'Antioquia'),
  CitySeed('America/Guayaquil', 'Quito', 'EC', 68, ['UIO']),

  // --- Europe ------------------------------------------------------------
  CitySeed('Europe/Berlin', 'Frankfurt', 'DE', 84, ['FRA'], 'Hesse'),
  CitySeed(
    'Europe/Berlin',
    'Munich',
    'DE',
    80,
    ['Munchen', 'Muenchen', 'MUC'],
    'Bavaria',
  ),
  CitySeed('Europe/Berlin', 'Hamburg', 'DE', 74, ['HAM']),
  CitySeed('Europe/Madrid', 'Barcelona', 'ES', 86, ['BCN'], 'Catalonia'),
  CitySeed('Europe/Rome', 'Milan', 'IT', 84, ['Milano', 'MXP'], 'Lombardy'),
  CitySeed('Europe/Paris', 'Lyon', 'FR', 70, ['LYS'], 'Auvergne-Rhone-Alpes'),
  CitySeed(
    'Europe/Paris',
    'Marseille',
    'FR',
    68,
    ['MRS'],
    "Provence-Alpes-Cote d'Azur",
  ),
  CitySeed('Europe/London', 'Manchester', 'GB', 74, ['MAN'], 'England'),
  CitySeed('Europe/London', 'Edinburgh', 'GB', 70, ['EDI'], 'Scotland'),
  CitySeed('Europe/Lisbon', 'Porto', 'PT', 70, ['Oporto', 'OPO']),
  CitySeed('Europe/Zurich', 'Geneva', 'CH', 78, ['Geneve', 'Genf', 'GVA']),

  // --- Africa ------------------------------------------------------------
  CitySeed('Africa/Lagos', 'Abuja', 'NG', 70, ['ABV']),
  CitySeed(
    'Africa/Johannesburg',
    'Cape Town',
    'ZA',
    82,
    ['Kaapstad', 'CPT'],
    'Western Cape',
  ),
  CitySeed('Africa/Johannesburg', 'Durban', 'ZA', 66, ['DUR'], 'KwaZulu-Natal'),
  CitySeed('Africa/Cairo', 'Alexandria', 'EG', 68),

  // --- Asia --------------------------------------------------------------
  CitySeed('Asia/Dubai', 'Abu Dhabi', 'AE', 80, ['AUH']),
  CitySeed('Asia/Riyadh', 'Jeddah', 'SA', 72, ['JED']),
  CitySeed('Asia/Jerusalem', 'Tel Aviv', 'IL', 80, ['TLV']),
  CitySeed('Asia/Tokyo', 'Osaka', 'JP', 84, ['KIX']),
  CitySeed('Asia/Tokyo', 'Kyoto', 'JP', 72),
  CitySeed('Asia/Shanghai', 'Beijing', 'CN', 96, ['Peking', 'PEK']),
  CitySeed('Asia/Shanghai', 'Shenzhen', 'CN', 86, ['SZX'], 'Guangdong'),
  CitySeed(
    'Asia/Shanghai',
    'Guangzhou',
    'CN',
    86,
    ['Canton', 'CAN'],
    'Guangdong',
  ),
  CitySeed('Asia/Shanghai', 'Chengdu', 'CN', 76, ['CTU'], 'Sichuan'),
  CitySeed(
    'Asia/Kolkata',
    'Mumbai',
    'IN',
    92,
    ['Bombay', 'BOM'],
    'Maharashtra',
  ),
  CitySeed('Asia/Kolkata', 'Delhi', 'IN', 92, ['New Delhi', 'DEL']),
  CitySeed(
    'Asia/Kolkata',
    'Bangalore',
    'IN',
    88,
    ['Bengaluru', 'BLR'],
    'Karnataka',
  ),
  CitySeed('Asia/Kolkata', 'Hyderabad', 'IN', 80, ['HYD'], 'Telangana'),
  CitySeed(
    'Asia/Kolkata',
    'Chennai',
    'IN',
    80,
    ['Madras', 'MAA'],
    'Tamil Nadu',
  ),
  CitySeed('Asia/Kolkata', 'Pune', 'IN', 74, ['PNQ'], 'Maharashtra'),
  CitySeed('Asia/Karachi', 'Lahore', 'PK', 78, ['LHE'], 'Punjab'),
  CitySeed('Asia/Karachi', 'Islamabad', 'PK', 72, ['ISB']),
  CitySeed('Asia/Ho_Chi_Minh', 'Hanoi', 'VN', 78, ['HAN']),
  CitySeed('Asia/Seoul', 'Busan', 'KR', 70, ['PUS']),

  // --- The Pacific -------------------------------------------------------
  CitySeed('Pacific/Auckland', 'Wellington', 'NZ', 72, ['WLG']),
  CitySeed('Pacific/Auckland', 'Christchurch', 'NZ', 64, ['CHC']),

  // --- Australia ---------------------------------------------------------
  CitySeed('Australia/Brisbane', 'Gold Coast', 'AU', 64, ['OOL'], 'Queensland'),
];

/// English country names, keyed by ISO 3166-1 alpha-2.
///
/// The one name table for the whole catalog: a derived row and a seeded row
/// both resolve their `countryName` through here, so the two can never
/// disagree about what `BR` is called. Plain ASCII and the short common form
/// ("Ivory Coast", not the official French name), because this string is both
/// displayed under the city and folded into the search index.
const Map<String, String> countryNameByCode = <String, String>{
  'AD': 'Andorra',
  'AE': 'United Arab Emirates',
  'AF': 'Afghanistan',
  'AG': 'Antigua and Barbuda',
  'AI': 'Anguilla',
  'AL': 'Albania',
  'AM': 'Armenia',
  'AO': 'Angola',
  'AQ': 'Antarctica',
  'AR': 'Argentina',
  'AS': 'American Samoa',
  'AT': 'Austria',
  'AU': 'Australia',
  'AW': 'Aruba',
  'AX': 'Aland Islands',
  'AZ': 'Azerbaijan',
  'BA': 'Bosnia and Herzegovina',
  'BB': 'Barbados',
  'BD': 'Bangladesh',
  'BE': 'Belgium',
  'BF': 'Burkina Faso',
  'BG': 'Bulgaria',
  'BH': 'Bahrain',
  'BI': 'Burundi',
  'BJ': 'Benin',
  'BL': 'Saint Barthelemy',
  'BM': 'Bermuda',
  'BN': 'Brunei',
  'BO': 'Bolivia',
  'BQ': 'Caribbean Netherlands',
  'BR': 'Brazil',
  'BS': 'Bahamas',
  'BT': 'Bhutan',
  'BW': 'Botswana',
  'BY': 'Belarus',
  'BZ': 'Belize',
  'CA': 'Canada',
  'CC': 'Cocos Islands',
  'CD': 'DR Congo',
  'CF': 'Central African Republic',
  'CG': 'Republic of the Congo',
  'CH': 'Switzerland',
  'CI': 'Ivory Coast',
  'CK': 'Cook Islands',
  'CL': 'Chile',
  'CM': 'Cameroon',
  'CN': 'China',
  'CO': 'Colombia',
  'CR': 'Costa Rica',
  'CU': 'Cuba',
  'CV': 'Cape Verde',
  'CW': 'Curacao',
  'CX': 'Christmas Island',
  'CY': 'Cyprus',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DJ': 'Djibouti',
  'DK': 'Denmark',
  'DM': 'Dominica',
  'DO': 'Dominican Republic',
  'DZ': 'Algeria',
  'EC': 'Ecuador',
  'EE': 'Estonia',
  'EG': 'Egypt',
  'EH': 'Western Sahara',
  'ER': 'Eritrea',
  'ES': 'Spain',
  'ET': 'Ethiopia',
  'FI': 'Finland',
  'FJ': 'Fiji',
  'FK': 'Falkland Islands',
  'FM': 'Micronesia',
  'FO': 'Faroe Islands',
  'FR': 'France',
  'GA': 'Gabon',
  'GB': 'United Kingdom',
  'GD': 'Grenada',
  'GE': 'Georgia',
  'GF': 'French Guiana',
  'GG': 'Guernsey',
  'GH': 'Ghana',
  'GI': 'Gibraltar',
  'GL': 'Greenland',
  'GM': 'Gambia',
  'GN': 'Guinea',
  'GP': 'Guadeloupe',
  'GQ': 'Equatorial Guinea',
  'GR': 'Greece',
  'GS': 'South Georgia',
  'GT': 'Guatemala',
  'GU': 'Guam',
  'GW': 'Guinea-Bissau',
  'GY': 'Guyana',
  'HK': 'Hong Kong',
  'HN': 'Honduras',
  'HR': 'Croatia',
  'HT': 'Haiti',
  'HU': 'Hungary',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IM': 'Isle of Man',
  'IN': 'India',
  'IO': 'British Indian Ocean Territory',
  'IQ': 'Iraq',
  'IR': 'Iran',
  'IS': 'Iceland',
  'IT': 'Italy',
  'JE': 'Jersey',
  'JM': 'Jamaica',
  'JO': 'Jordan',
  'JP': 'Japan',
  'KE': 'Kenya',
  'KG': 'Kyrgyzstan',
  'KH': 'Cambodia',
  'KI': 'Kiribati',
  'KM': 'Comoros',
  'KN': 'Saint Kitts and Nevis',
  'KP': 'North Korea',
  'KR': 'South Korea',
  'KW': 'Kuwait',
  'KY': 'Cayman Islands',
  'KZ': 'Kazakhstan',
  'LA': 'Laos',
  'LB': 'Lebanon',
  'LC': 'Saint Lucia',
  'LI': 'Liechtenstein',
  'LK': 'Sri Lanka',
  'LR': 'Liberia',
  'LS': 'Lesotho',
  'LT': 'Lithuania',
  'LU': 'Luxembourg',
  'LV': 'Latvia',
  'LY': 'Libya',
  'MA': 'Morocco',
  'MC': 'Monaco',
  'MD': 'Moldova',
  'ME': 'Montenegro',
  'MF': 'Saint Martin',
  'MG': 'Madagascar',
  'MH': 'Marshall Islands',
  'MK': 'North Macedonia',
  'ML': 'Mali',
  'MM': 'Myanmar',
  'MN': 'Mongolia',
  'MO': 'Macau',
  'MP': 'Northern Mariana Islands',
  'MQ': 'Martinique',
  'MR': 'Mauritania',
  'MS': 'Montserrat',
  'MT': 'Malta',
  'MU': 'Mauritius',
  'MV': 'Maldives',
  'MW': 'Malawi',
  'MX': 'Mexico',
  'MY': 'Malaysia',
  'MZ': 'Mozambique',
  'NA': 'Namibia',
  'NC': 'New Caledonia',
  'NE': 'Niger',
  'NF': 'Norfolk Island',
  'NG': 'Nigeria',
  'NI': 'Nicaragua',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'NP': 'Nepal',
  'NR': 'Nauru',
  'NU': 'Niue',
  'NZ': 'New Zealand',
  'OM': 'Oman',
  'PA': 'Panama',
  'PE': 'Peru',
  'PF': 'French Polynesia',
  'PG': 'Papua New Guinea',
  'PH': 'Philippines',
  'PK': 'Pakistan',
  'PL': 'Poland',
  'PM': 'Saint Pierre and Miquelon',
  'PN': 'Pitcairn Islands',
  'PR': 'Puerto Rico',
  'PS': 'Palestine',
  'PT': 'Portugal',
  'PW': 'Palau',
  'PY': 'Paraguay',
  'QA': 'Qatar',
  'RE': 'Reunion',
  'RO': 'Romania',
  'RS': 'Serbia',
  'RU': 'Russia',
  'RW': 'Rwanda',
  'SA': 'Saudi Arabia',
  'SB': 'Solomon Islands',
  'SC': 'Seychelles',
  'SD': 'Sudan',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'SH': 'Saint Helena',
  'SI': 'Slovenia',
  'SJ': 'Svalbard and Jan Mayen',
  'SK': 'Slovakia',
  'SL': 'Sierra Leone',
  'SM': 'San Marino',
  'SN': 'Senegal',
  'SO': 'Somalia',
  'SR': 'Suriname',
  'SS': 'South Sudan',
  'ST': 'Sao Tome and Principe',
  'SV': 'El Salvador',
  'SX': 'Sint Maarten',
  'SY': 'Syria',
  'SZ': 'Eswatini',
  'TC': 'Turks and Caicos Islands',
  'TD': 'Chad',
  'TF': 'French Southern Territories',
  'TG': 'Togo',
  'TH': 'Thailand',
  'TJ': 'Tajikistan',
  'TK': 'Tokelau',
  'TL': 'Timor-Leste',
  'TM': 'Turkmenistan',
  'TN': 'Tunisia',
  'TO': 'Tonga',
  'TR': 'Turkey',
  'TT': 'Trinidad and Tobago',
  'TV': 'Tuvalu',
  'TW': 'Taiwan',
  'TZ': 'Tanzania',
  'UA': 'Ukraine',
  'UG': 'Uganda',
  'UM': 'US Minor Outlying Islands',
  'US': 'United States',
  'UY': 'Uruguay',
  'UZ': 'Uzbekistan',
  'VA': 'Vatican City',
  'VC': 'Saint Vincent and the Grenadines',
  'VE': 'Venezuela',
  'VG': 'British Virgin Islands',
  'VI': 'US Virgin Islands',
  'VN': 'Vietnam',
  'VU': 'Vanuatu',
  'WF': 'Wallis and Futuna',
  'WS': 'Samoa',
  'YE': 'Yemen',
  'YT': 'Mayotte',
  'ZA': 'South Africa',
  'ZM': 'Zambia',
  'ZW': 'Zimbabwe',
  'ZZ': 'Coordinated Universal Time',
};

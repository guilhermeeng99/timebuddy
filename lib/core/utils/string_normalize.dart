/// Accented letters grouped by the ASCII sequence they fold to.
///
/// Covers Latin-1 Supplement plus Latin Extended-A, which is every letter the
/// city catalog actually contains: the Portuguese set (a-tilde, o-tilde,
/// c-cedilla, the acute and circumflex vowels), the Nordic slashed o and
/// a-ring, the Central European carons and ogoneks, and the Romanian and
/// Turkish comma/cedilla forms. Only lower-case forms are listed because the
/// input is lower-cased before it is folded.
///
/// A few letters expand to more than one character (ae, ss, oe, th), which is
/// why the table maps *base sequence to variants* rather than the reverse.
const Map<String, String> _variantsByBase = {
  'a': 'àáâãäåāăą',
  'ae': 'æ',
  'c': 'çćĉċč',
  'd': 'ðďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįı',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņňŉ',
  'o': 'òóôõöøōŏő',
  'oe': 'œ',
  'r': 'ŕŗř',
  's': 'śŝşšș',
  'ss': 'ß',
  't': 'ţťŧț',
  'th': 'þ',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

/// First and last code point of the Unicode combining diacritical marks block.
const int _combiningMarksStart = 0x0300;
const int _combiningMarksEnd = 0x036f;

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Flattened [_variantsByBase]: one entry per accented code point.
///
/// Built once at first use, because a per-call rebuild would run on every
/// keystroke of the location search.
final Map<int, String> _foldByRune = _buildFoldTable();

Map<int, String> _buildFoldTable() {
  final table = <int, String>{};
  for (final MapEntry(key: base, value: variants) in _variantsByBase.entries) {
    for (final rune in variants.runes) {
      table[rune] = base;
    }
  }
  return table;
}

/// Folds [input] into the single form the search index and every query share:
/// lower-case, diacritic-free, single-spaced, trimmed.
///
/// Search must not care about the user's keyboard. `Sao Paulo`, `SAO PAULO`
/// and the accented spelling are one query (locations.md rule 9), so both the
/// catalog entries and the typed text are folded and only fold-to-fold
/// comparisons are made. Never fold a value that is going to be stored or
/// displayed: this is a lossy index key, not a label.
///
/// ```dart
/// normalizeForSearch('  SÃO   Paulo ');  // 'sao paulo'
/// normalizeForSearch('Zürich');          // 'zurich'
/// ```
///
/// Diacritics are folded through the explicit table above rather than through
/// Unicode normalization: Dart's core library has no NFD decomposition, and a
/// package dependency for one letter set is not worth the weight. Combining
/// marks (U+0300..U+036F) are dropped outright, which additionally handles
/// text that arrives already decomposed - macOS filenames, some upstream city
/// datasets, and Dart's own lower-casing of the Turkish dotted capital I.
String normalizeForSearch(String input) {
  final folded = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    if (rune >= _combiningMarksStart && rune <= _combiningMarksEnd) continue;
    folded.write(_foldByRune[rune] ?? String.fromCharCode(rune));
  }
  return folded.toString().replaceAll(_whitespaceRun, ' ').trim();
}

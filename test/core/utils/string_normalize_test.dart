import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/utils/string_normalize.dart';

void main() {
  group('normalizeForSearch', () {
    test('folds every spelling of Sao Paulo onto one key', () {
      // locations rule: search must not care about the user keyboard, so the
      // catalog entry and the typed query have to land on the same string.
      const spellings = [
        'São Paulo',
        'Sao Paulo',
        'SÃO PAULO',
        'sao paulo',
        'SAO PAULO',
        '  São   Paulo  ',
      ];
      for (final spelling in spellings) {
        expect(normalizeForSearch(spelling), 'sao paulo', reason: spelling);
      }
    });

    test('folds decomposed text, where the accent is a separate rune', () {
      // macOS filenames and some upstream city datasets arrive this way:
      // an ASCII letter followed by a combining mark. Spelled as an escape
      // so an editor that normalises this file cannot quietly turn it back
      // into the precomposed form and retire the test.
      const decomposed = 'Sa\u0303o Paulo';
      expect(decomposed.length, greaterThan('Sao Paulo'.length));
      expect(normalizeForSearch(decomposed), 'sao paulo');
    });

    test('case folds', () {
      expect(normalizeForSearch('ZURICH'), 'zurich');
      expect(normalizeForSearch('Zürich'), 'zurich');
      expect(normalizeForSearch('ZÜRICH'), 'zurich');
      expect(normalizeForSearch('New York'), 'new york');
    });

    test('collapses runs of whitespace and trims the ends', () {
      expect(normalizeForSearch('  New   York  '), 'new york');
      expect(normalizeForSearch('New\tYork'), 'new york');
      expect(normalizeForSearch('New\n\nYork'), 'new york');
      expect(normalizeForSearch('   '), '');
      expect(normalizeForSearch(''), '');
    });

    test('folds the Latin letters the city catalog actually contains', () {
      const foldings = <String, String>{
        'København': 'kobenhavn',
        'Kraków': 'krakow',
        'Reykjavík': 'reykjavik',
        'Malmö': 'malmo',
        'Düsseldorf': 'dusseldorf',
        'Chișinău': 'chisinau',
        'Curaçao': 'curacao',
        'Brasília': 'brasilia',
        'İstanbul': 'istanbul',
      };
      for (final MapEntry(key: input, value: expected) in foldings.entries) {
        expect(normalizeForSearch(input), expected, reason: input);
      }
    });

    test('expands the letters that fold to more than one character', () {
      expect(normalizeForSearch('Ærøskøbing'), 'aeroskobing');
      expect(normalizeForSearch('Straße'), 'strasse');
    });

    test('passes unfoldable scripts through, lower-cased', () {
      // The table is Latin-only by design; anything else must survive intact
      // rather than be mangled into a key nothing else produces.
      expect(normalizeForSearch(' МОСКВА '), 'москва');
    });

    test('is idempotent, so an already folded key stays put', () {
      const input = '  SÃO   Paulo ';
      final once = normalizeForSearch(input);
      expect(normalizeForSearch(once), once);
    });

    test('lets a folded query prefix-match a folded entry', () {
      expect(
        normalizeForSearch('São Paulo').startsWith(normalizeForSearch('SÃO')),
        isTrue,
      );
    });
  });
}

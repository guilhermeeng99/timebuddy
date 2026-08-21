import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/utils/json_parse.dart';

// Every case below is a shape that can actually reach these functions: a value
// `jsonDecode` produced from a stored document, or one Firestore handed back.
// Nothing here is a synthetic type the app would never see.
void main() {
  group('filledStringOrNull', () {
    test('returns the value of a plain string', () {
      expect(filledStringOrNull('America/Sao_Paulo'), 'America/Sao_Paulo');
    });

    test('trims the surrounding whitespace', () {
      // Trimming before the emptiness test is what makes a padded value the
      // setting the user chose rather than a fall back to the default.
      expect(filledStringOrNull(' Sao Paulo '), 'Sao Paulo');
      expect(filledStringOrNull('\n dark \t'), 'dark');
    });

    test('collapses an empty or whitespace-only string to null', () {
      // A stored `"   "` is damage, not a label, and every caller treats it
      // the same way it treats an absent field.
      expect(filledStringOrNull(''), isNull);
      expect(filledStringOrNull('   '), isNull);
      expect(filledStringOrNull('\t\n'), isNull);
    });

    test('returns null for a null value', () {
      expect(filledStringOrNull(null), isNull);
    });

    test('returns null for a value of the wrong type', () {
      // A field that changed type between releases, or a document another
      // client wrote. Degrades, never throws.
      expect(filledStringOrNull(42), isNull);
      expect(filledStringOrNull(true), isNull);
      expect(filledStringOrNull(<String>['a']), isNull);
      expect(filledStringOrNull(<String, dynamic>{'a': 1}), isNull);
    });

    test('never throws where a cast would', () {
      final decoded = jsonDecode('{"zoneId": 7}') as Map<String, dynamic>;

      expect(() => decoded['zoneId'] as String, throwsA(isA<TypeError>()));
      expect(() => filledStringOrNull(decoded['zoneId']), returnsNormally);
    });
  });

  group('intOrNull', () {
    test('returns an int unchanged', () {
      expect(intOrNull(0), 0);
      expect(intOrNull(3), 3);
      expect(intOrNull(-1), -1);
    });

    test('narrows a whole double to an int', () {
      // JSON has one number type and Firestore has two, so a `sortIndex` the
      // app wrote as 3 can come back as 3.0 from the other side.
      expect(intOrNull(3.0), 3);
      expect(intOrNull(jsonDecode('3.0')), 3);
    });

    test('truncates a fractional double rather than rejecting it', () {
      // `toInt()` truncates toward zero. Pinned because the alternative -
      // rejecting the row - would cost a location over a rounding artefact.
      expect(intOrNull(3.7), 3);
      expect(intOrNull(-3.7), -3);
    });

    test('returns null for a numeric string', () {
      // Deliberately not parsed: a stored `"3"` means some writer disagreed
      // about the shape, and guessing would hide that.
      expect(intOrNull('3'), isNull);
    });

    test('returns null for a null value', () {
      expect(intOrNull(null), isNull);
    });

    test('returns null for a value of the wrong type', () {
      expect(intOrNull(true), isNull);
      expect(intOrNull(<int>[3]), isNull);
      expect(intOrNull(<String, dynamic>{'value': 3}), isNull);
    });

    test('leaves the meaningful zero to the caller', () {
      // The two defaults in the app, side by side: `revision` and `prominence`
      // both degrade to 0, and both say so at their own call site.
      expect(intOrNull(null) ?? 0, 0);
      expect(intOrNull('junk') ?? 0, 0);
      expect(intOrNull(5) ?? 0, 5);
    });
  });

  group('timestampFromJson', () {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    test('reads the ISO-8601 string shared_preferences holds', () {
      expect(
        timestampFromJson('2026-03-14T09:30:00.000Z'),
        DateTime.utc(2026, 3, 14, 9, 30),
      );
    });

    test('converts an offset-bearing string to UTC', () {
      // The models write UTC, but a document hand-edited or written by an
      // older build can carry an offset. The instant is what matters.
      expect(
        timestampFromJson('2026-03-14T06:30:00.000-03:00'),
        DateTime.utc(2026, 3, 14, 9, 30),
      );
      expect(timestampFromJson('2026-03-14T09:30:00.000Z').isUtc, isTrue);
    });

    test('reads the millisecond epoch int an unwrapped Timestamp becomes', () {
      final instant = DateTime.utc(2026, 3, 14, 9, 30);

      expect(timestampFromJson(instant.millisecondsSinceEpoch), instant);
    });

    test('both encodings of one instant agree', () {
      // The whole point of sharing this parser: a document copied between the
      // two stores must not shift by a millisecond.
      final instant = DateTime.utc(2026, 3, 14, 9, 30);

      expect(
        timestampFromJson(instant.toIso8601String()),
        timestampFromJson(instant.millisecondsSinceEpoch),
      );
    });

    test('falls back to the epoch, never to now', () {
      // sync.md rule 5: an unreadable timestamp must lose every tie it enters
      // rather than win them by looking freshly written.
      expect(timestampFromJson(null), epoch);
      expect(timestampFromJson('not a date'), epoch);
      expect(timestampFromJson(''), epoch);
      expect(timestampFromJson(true), epoch);
      expect(timestampFromJson(<String, dynamic>{'seconds': 1}), epoch);
    });

    test('the fallback is UTC, so a comparison cannot read a local hour', () {
      expect(timestampFromJson('junk').isUtc, isTrue);
    });
  });
}

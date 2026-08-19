import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/utils/enum_parse.dart';

// ClockFormat and WeekStart stand in for every persisted enum in the app:
// these are the real `enum.name` strings that sit in SharedPreferences and in
// Firestore, so the parsing contract is tested against the wire format itself
// rather than against a synthetic enum.
void main() {
  group('enumByNameOrNull', () {
    test('returns the value whose name matches', () {
      expect(enumByNameOrNull(ClockFormat.values, 'h12'), ClockFormat.h12);
      expect(enumByNameOrNull(ClockFormat.values, 'h24'), ClockFormat.h24);
      expect(enumByNameOrNull(WeekStart.values, 'sunday'), WeekStart.sunday);
    });

    test('returns null for a name no value carries', () {
      // A document written by a newer client, or a value dropped in a later
      // release. Both must degrade, neither may throw.
      expect(enumByNameOrNull(ClockFormat.values, 'h13'), isNull);
    });

    test('returns null for a null raw value', () {
      // An absent field and an unknown one are the same miss to every caller.
      expect(enumByNameOrNull(ClockFormat.values, null), isNull);
    });

    test('returns null for an empty string', () {
      expect(enumByNameOrNull(ClockFormat.values, ''), isNull);
    });

    test('matches exactly, without trimming or case folding', () {
      expect(enumByNameOrNull(ClockFormat.values, 'H12'), isNull);
      expect(enumByNameOrNull(ClockFormat.values, ' h12'), isNull);
      expect(enumByNameOrNull(ClockFormat.values, 'h12 '), isNull);
    });

    test('never throws where byName would', () {
      expect(() => ClockFormat.values.byName('h13'), throwsArgumentError);
      expect(
        () => enumByNameOrNull(ClockFormat.values, 'h13'),
        returnsNormally,
      );
    });
  });

  group('enumByName', () {
    test('returns the value whose name matches', () {
      expect(
        enumByName(ClockFormat.values, 'h12', orElse: ClockFormat.h24),
        ClockFormat.h12,
      );
    });

    test('falls back for a name no value carries', () {
      expect(
        enumByName(ClockFormat.values, 'h13', orElse: ClockFormat.h24),
        ClockFormat.h24,
      );
    });

    test('falls back for a null raw value', () {
      expect(
        enumByName(ClockFormat.values, null, orElse: ClockFormat.h24),
        ClockFormat.h24,
      );
    });

    test('falls back for an empty string', () {
      expect(
        enumByName(WeekStart.values, '', orElse: WeekStart.monday),
        WeekStart.monday,
      );
    });

    test('costs one setting rather than the whole document', () {
      // The point of the fallback: a single corrupted field still leaves the
      // rest of the parsed preferences usable.
      const raw = <String, String?>{
        'hourFormat': 'h12',
        'weekStartsOn': 'sabado',
      };
      final hourFormat = enumByName(
        ClockFormat.values,
        raw['hourFormat'],
        orElse: ClockFormat.h24,
      );
      final weekStart = enumByName(
        WeekStart.values,
        raw['weekStartsOn'],
        orElse: WeekStart.monday,
      );

      expect(hourFormat, ClockFormat.h12);
      expect(weekStart, WeekStart.monday);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';

import '../../harness/helpers.dart';

/// Legacy, merged and pre-IANA ids that must still resolve, mapped to the
/// canonical id the shipped tzdata actually carries.
///
/// The `timezone` package embeds only canonical zones: every `Link` line of
/// the IANA distribution is dropped. Without the alias map a saved location
/// for Oslo, Accra or Kuala Lumpur silently becomes UTC, so each row here is
/// a clock that would otherwise be up to an hour wrong for half the year.
const _aliases = <String, String>{
  // Renamed upstream.
  'Asia/Calcutta': 'Asia/Kolkata',
  'Asia/Rangoon': 'Asia/Yangon',
  'Asia/Saigon': 'Asia/Ho_Chi_Minh',
  'Asia/Katmandu': 'Asia/Kathmandu',
  'Europe/Kiev': 'Europe/Kyiv',
  'America/Godthab': 'America/Nuuk',
  // Merged into a neighbour whose clocks have agreed since 1970.
  'Europe/Oslo': 'Europe/Berlin',
  'Europe/Copenhagen': 'Europe/Berlin',
  'Europe/Amsterdam': 'Europe/Brussels',
  'Europe/Nicosia': 'Asia/Nicosia',
  'Asia/Kuala_Lumpur': 'Asia/Singapore',
  'America/Montreal': 'America/Toronto',
  'Africa/Accra': 'Africa/Abidjan',
  'Atlantic/Reykjavik': 'Africa/Abidjan',
  'Australia/Canberra': 'Australia/Sydney',
  'Australia/LHI': 'Australia/Lord_Howe',
  'Pacific/Chuuk': 'Pacific/Port_Moresby',
  // Pre-IANA country and region names still found in old exports.
  'US/Pacific': 'America/Los_Angeles',
  'US/Eastern': 'America/New_York',
  'Brazil/East': 'America/Sao_Paulo',
  'Japan': 'Asia/Tokyo',
  'NZ-CHAT': 'Pacific/Chatham',
  // Spellings of UTC that arrive from platform APIs and old storage.
  'GMT': utcZoneId,
  'Zulu': utcZoneId,
};

void main() {
  setUpAll(initTestTimeZones);

  group('zoneOrNull', () {
    test('a canonical id comes back unchanged and unaliased', () {
      final ref = zoneOrNull('America/Sao_Paulo');

      expect(ref, isNotNull);
      expect(ref!.id, 'America/Sao_Paulo');
      expect(ref.requestedId, 'America/Sao_Paulo');
      expect(ref.wasAliased, isFalse);
    });

    test('Asia/Calcutta resolves to Asia/Kolkata and flags the rewrite', () {
      final ref = zoneOrNull('Asia/Calcutta');

      expect(ref, isNotNull);
      expect(ref!.id, 'Asia/Kolkata');
      // The caller keeps the original so it can rewrite the stored row.
      expect(ref.requestedId, 'Asia/Calcutta');
      expect(ref.wasAliased, isTrue);
    });

    for (final entry in _aliases.entries) {
      test('${entry.key} resolves to ${entry.value}', () {
        final ref = zoneOrNull(entry.key);

        expect(ref, isNotNull, reason: '${entry.key} must not fall through');
        expect(ref!.id, entry.value);
        expect(ref.wasAliased, isTrue);
        // A typo in the alias map would produce a ZoneRef the engine cannot
        // load, which is worse than returning null.
        expect(locationOrNull(entry.key), isNotNull);
      });
    }

    test('UTC resolves to itself under the short id this app persists', () {
      expect(
        zoneOrNull(utcZoneId),
        const ZoneRef(id: utcZoneId, requestedId: utcZoneId),
      );
    });

    test('an id the tzdata never heard of is null', () {
      expect(zoneOrNull('Not/AZone'), isNull);
    });

    test('an empty or blank id is null rather than a fallback', () {
      expect(zoneOrNull(''), isNull);
      expect(zoneOrNull('   '), isNull);
    });

    test('lookup is case sensitive, as IANA ids are', () {
      expect(zoneOrNull('asia/kolkata'), isNull);
      expect(zoneOrNull('AMERICA/NEW_YORK'), isNull);
    });

    test('surrounding whitespace is trimmed and reported as a rewrite', () {
      final ref = zoneOrNull('  Asia/Kolkata  ');

      expect(ref, isNotNull);
      expect(ref!.id, 'Asia/Kolkata');
      expect(ref.requestedId, '  Asia/Kolkata  ');
      // The stored value differs from the canonical one, so it is worth
      // rewriting even though only whitespace changed.
      expect(ref.wasAliased, isTrue);
    });

    test('the alias map canonicalises even when the raw id resolves too', () {
      // Deliberately the opposite of raw-first. The shipped database keeps the
      // IANA Link lines, so a Link and its target BOTH resolve; raw-first would
      // hand back whichever spelling the caller happened to hold. Two board
      // rows in one real zone would then slip past the duplicate check
      // (docs/specs/locations.md rule 2), and a stored legacy id would never be
      // rewritten. The invariant below is what makes this safe.
      final ref = zoneOrNull('Etc/UTC');

      expect(ref, isNotNull);
      expect(ref!.id, utcZoneId);
      expect(ref.wasAliased, isTrue);
    });

    test('canonicalising never changes which clock a zone shows', () {
      // The guard for canonicalise-first, run over the WHOLE database rather
      // than over a hand-copied sample: an alias pointing at a genuinely
      // different zone would silently move a user's city to the wrong clock,
      // and no sample list would be guaranteed to contain it.
      //
      // Four probes a year apart catch a wrong target whether it differs in
      // standard offset or only in its daylight-saving schedule, which a
      // single January probe would miss for a southern-hemisphere mistake.
      const probes = [
        '2024-01-15T12:00:00Z',
        '2024-04-15T12:00:00Z',
        '2024-07-15T12:00:00Z',
        '2024-10-15T12:00:00Z',
      ];
      final broken = <String>[];

      for (final name in allShippedZoneIds()) {
        final ref = zoneOrNull(name);
        if (ref == null) {
          broken.add('$name does not resolve at all');
          continue;
        }
        final requested = locationOrNull(name);
        final resolved = locationOrNull(ref.id);
        if (requested == null || resolved == null) {
          broken.add('$name -> ${ref.id} has no location');
          continue;
        }
        for (final probe in probes) {
          final ms = DateTime.parse(probe).millisecondsSinceEpoch;
          final a = requested.timeZone(ms).offset;
          final b = resolved.timeZone(ms).offset;
          if (a != b) {
            broken.add('$name -> ${ref.id} differs at $probe ($a vs $b)');
            break;
          }
        }
      }

      expect(
        broken,
        isEmpty,
        reason: 'the alias map moves a zone onto another clock',
      );
    });
  });

  group('zoneOrHome', () {
    test('a resolvable id ignores the home zone entirely', () {
      final ref = zoneOrHome('Europe/London', 'America/Sao_Paulo');

      expect(ref.id, 'Europe/London');
      expect(ref.wasAliased, isFalse);
    });

    test('an alias resolves canonically without touching the home zone', () {
      final ref = zoneOrHome('Asia/Calcutta', 'America/Sao_Paulo');

      expect(ref.id, 'Asia/Kolkata');
      expect(ref.requestedId, 'Asia/Calcutta');
    });

    test('an unknown id falls back to the home zone', () {
      final ref = zoneOrHome('Not/AZone', 'America/Sao_Paulo');

      expect(ref.id, 'America/Sao_Paulo');
      // requestedId still names the broken row so the board can flag it.
      expect(ref.requestedId, 'Not/AZone');
      expect(ref.wasAliased, isTrue);
    });

    test('an aliased home zone is itself canonicalised', () {
      final ref = zoneOrHome('Not/AZone', 'Europe/Kiev');

      expect(ref.id, 'Europe/Kyiv');
      expect(ref.requestedId, 'Not/AZone');
    });

    test('a broken id and a broken home fall back to UTC', () {
      // One corrupt saved board must never be able to blank the screen, so
      // this branch has to be unreachable-by-failure rather than a throw.
      final ref = zoneOrHome('Not/AZone', 'Also/Broken');

      expect(ref.id, utcZoneId);
      expect(ref.requestedId, 'Not/AZone');
      expect(ref.wasAliased, isTrue);
    });

    test('a broken home does not break an otherwise valid id', () {
      expect(zoneOrHome('Asia/Tokyo', 'Also/Broken').id, 'Asia/Tokyo');
    });

    test('an empty id falls back rather than resolving to UTC', () {
      expect(zoneOrHome('', 'America/Sao_Paulo').id, 'America/Sao_Paulo');
    });
  });

  group('locationOrNull', () {
    test('returns the tz location for a canonical id', () {
      expect(locationOrNull('Europe/London')?.name, 'Europe/London');
    });

    test('returns the canonical location for a legacy id', () {
      expect(locationOrNull('Asia/Calcutta')?.name, 'Asia/Kolkata');
    });

    test('resolves the short UTC id the database does not register', () {
      // The shipped database only knows UTC as Etc/UTC, so the short id this
      // app persists has to be wired to it explicitly.
      expect(locationOrNull(utcZoneId), isNotNull);
    });

    test('returns null for an unknown id instead of throwing', () {
      expect(locationOrNull('Not/AZone'), isNull);
    });
  });

  group('ZoneRef', () {
    test('is compared by value', () {
      expect(
        zoneOrNull('Asia/Calcutta'),
        const ZoneRef(id: 'Asia/Kolkata', requestedId: 'Asia/Calcutta'),
      );
      expect(
        const ZoneRef(id: 'Asia/Kolkata', requestedId: 'Asia/Kolkata'),
        isNot(const ZoneRef(id: 'Asia/Kolkata', requestedId: 'Asia/Calcutta')),
      );
    });

    test('wasAliased is exactly the id-versus-request comparison', () {
      const same = ZoneRef(id: 'UTC', requestedId: 'UTC');
      const different = ZoneRef(id: 'UTC', requestedId: 'GMT');

      expect(same.wasAliased, isFalse);
      expect(different.wasAliased, isTrue);
    });
  });
}

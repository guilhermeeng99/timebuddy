import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timezone/timezone.dart' as tz;

// The one test file in the suite that must NOT call `initTestTimeZones()`,
// and the reason it exists at all.
//
// CLAUDE.md's ninth Time & Timezone rule — import `data/latest_all.dart`,
// never `data/latest.dart` — was, until this file, the only rule in that list
// with no possible coverage. `TzTimeZoneEngine.initialize()` short-circuits on
// `if (!tz.timeZoneDatabase.isInitialized)`, and every other test file has
// already loaded the database through the harness's own `latest_all` import by
// the time the engine is asked. The engine's import was therefore dead code
// under test: switching it to `data/latest.dart` left all 733 tests green
// while shipping an app on a dataset with 257 fewer zone names.
//
// The alias tests do not close the gap either, and measuring why corrected the
// rule itself. Running the whole shipped catalog through `zoneOrNull` against
// both datasets gives 313 distinct zone ids, **0** unresolved under
// `latest_all` and **1** under `latest`: `Asia/Choibalsan`. Every other id
// CLAUDE.md names — `Europe/Oslo`, `Asia/Kuala_Lumpur`, `Africa/Accra` — comes
// back with the same canonical answer under both, because the alias map (rule
// 9) is consulted before the direct lookup and folds each of them onto a
// target the trimmed dataset does keep. So the quiet fallback to UTC that rule
// 8 warns about does not happen for those ids; the alias map already caught
// it. What `latest_all` actually buys is one city today, and independence from
// a hand-maintained map of roughly 250 entries for the rest.
//
// That is why the assertions below are split the way they are: one bites on
// the raw database, one on the single id the alias map does not cover.
//
// `flutter test` gives each file its own isolate, so the global tz database
// starts empty here and `initialize()` runs its real import path. Keep it that
// way: adding an `initTestTimeZones()` call to this file, or a `setUpAll` that
// touches the engine from another file merged into this one, silently turns
// every assertion below into a tautology again.
void main() {
  // Measured against `timezone` 0.11.1 and stated in
  // docs/specs/timezone_engine.md: `latest_all.tzf` carries 598 names and
  // `latest.tzf` 341, because the trimmed dataset drops every IANA `Link`
  // line. The bound is a floor rather than an equality so a future release
  // that *adds* zones does not fail the build for doing the right thing; it
  // still sits far above anything `latest.dart` could satisfy.
  const latestAllLocationFloor = 598;

  test('the engine loads the full dataset, Links included', () async {
    expect(
      tz.timeZoneDatabase.isInitialized,
      isFalse,
      reason: 'this file must reach initialize() with an empty database, or '
          'it proves nothing — see the note at the top',
    );

    await TzTimeZoneEngine().initialize();

    expect(
      tz.timeZoneDatabase.locations.length,
      greaterThanOrEqualTo(latestAllLocationFloor),
      reason: 'the trimmed dataset carries 341 names; anything near that '
          'means the engine is importing data/latest.dart',
    );
  });

  test('the Link names are in the database, not just in the alias map', () {
    // Asserted against the raw tz database rather than through `zoneOrNull`,
    // which is the distinction that makes this bite: the lookup answers
    // correctly for all of these under either dataset, because the alias map
    // folds them onto targets `latest.dart` keeps. Membership does not.
    for (final id in const <String>[
      'Europe/Oslo',
      'Asia/Kuala_Lumpur',
      'Africa/Accra',
      'Europe/Stockholm',
      'Atlantic/Reykjavik',
    ]) {
      expect(tz.timeZoneDatabase.locations, contains(id), reason: id);
    }
  });

  test('the short UTC resolves, whatever the dataset registers', () {
    // Not a dataset assertion: `zone_lookup` wires `UTC` to `tz.UTC` by hand
    // precisely so the one id this app persists cannot be taken away by an
    // upstream change. Pinned here because this is the file that would notice.
    expect(zoneOrNull(utcZoneId)?.id, utcZoneId);
  });

  test('Asia/Choibalsan resolves, and only latest_all makes it', () {
    // The single city in the shipped 313-zone catalog that the trimmed dataset
    // loses: it is a `Link` the alias map does not carry, so `zoneOrNull`
    // returns null and the board flags the row unresolved (locations.md rule
    // 11). One city is a thin argument for 185 KB on its own — the real case
    // is not depending on a hand-maintained map for the other 256 — but it is
    // the one assertion here that fails the moment the import changes and the
    // count check above is somehow satisfied.
    expect(zoneOrNull('Asia/Choibalsan'), isNotNull);

    final engine = TzTimeZoneEngine();
    final midsummer = DateTime.utc(2024, 7, 1, 4);
    final local = engine.wallTimeAt(
      zoneId: 'Asia/Choibalsan',
      instant: midsummer,
    );
    expect(local.hour, 12, reason: 'Choibalsan is UTC+08:00 in 2024');
  });
}

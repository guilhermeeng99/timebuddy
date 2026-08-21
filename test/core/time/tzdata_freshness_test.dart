import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';

import '../../harness/helpers.dart';

// A deadline tripwire, and the one test in this suite that reads the real
// wall clock on purpose.
//
// `timezone` 0.11.1 — the latest published release, 2026-06-29 — embeds IANA
// tzdata **2025c**, stated on line 2 of the package's own
// `lib/data/latest_all.dart`. Upstream is at 2026c. There is no upgrade to
// take, so the decision taken on 2026-08-21 was to wait for a release carrying
// 2026c rather than ship a generated `.tzf` asset — and to make the waiting
// impossible to forget.
//
// Each row below is a real rule change the shipped dataset does not have, and
// the date the app starts answering wrong because of it. **Before that date
// the test passes and says nothing. On and after it, the build goes red until
// somebody decides.** That is the whole design: a roadmap entry is a note, and
// a note is exactly what gets scrolled past in September.
//
// **This deliberately violates the "always inject a FakeClock" rule.** That
// rule exists because a test whose result depends on the day it runs is
// flaky. Here the dependency *is* the feature: nothing else can notice that a
// date has passed. It is safe in the way the rule cares about, because the
// wall clock is only ever compared against a fixed deadline, never used to
// build an instant an assertion reads.
//
// **When a `timezone` release carrying 2026c lands, every row starts
// resolving and this file starts failing the other way** — the assertions are
// written so a fixed dataset is loud too, and the fix is to delete the file.
void main() {
  setUpAll(initTestTimeZones);

  /// One rule change the shipped tzdata is missing.
  ///
  /// [probe] is a UTC instant safely past the transition; [expectedMinutes] is
  /// the offset the zone should report there once the dataset is current, and
  /// [staleMinutes] is what 2025c answers today. [deadline] is the date the
  /// app begins showing a wrong hour to a real user.
  final changes = <({
    String zoneId,
    DateTime probe,
    int expectedMinutes,
    int staleMinutes,
    DateTime deadline,
    String release,
    String change,
  })>[
    (
      zoneId: 'Africa/Casablanca',
      probe: DateTime.utc(2026, 10),
      expectedMinutes: 0,
      staleMinutes: 60,
      deadline: DateTime.utc(2026, 9, 20),
      release: '2026c',
      change: 'Morocco moves to permanent UTC on 2026-09-20 at 02:00',
    ),
    (
      zoneId: 'America/Vancouver',
      probe: DateTime.utc(2026, 11, 15),
      expectedMinutes: -420,
      staleMinutes: -480,
      deadline: DateTime.utc(2026, 11),
      release: '2026b',
      change: 'British Columbia is on permanent -07; tzdb models the change '
          'as 2026-11-01 at 02:00',
    ),
    (
      zoneId: 'America/Edmonton',
      probe: DateTime.utc(2026, 11, 15),
      expectedMinutes: -360,
      staleMinutes: -420,
      deadline: DateTime.utc(2026, 11),
      release: '2026c',
      change: 'Alberta is on permanent -06; tzdb models the change as '
          '2026-11-01 at 02:00',
    ),
  ];

  for (final c in changes) {
    final title =
        '${c.zoneId}: tzdata ${c.release} lands before ${_ymd(c.deadline)}';
    test(title, () {
      final engine = TzTimeZoneEngine();
      final minutes = engine
          .stateAt(zoneId: c.zoneId, instant: c.probe)
          .offset
          .inMinutes;

      if (minutes == c.expectedMinutes) {
        // The dataset caught up. Nothing here is a defect any more, and a
        // tripwire nobody can disarm is just noise on every future run.
        fail(
          'GOOD NEWS: the shipped tzdata now carries ${c.release}, so '
          '${c.zoneId} answers ${c.expectedMinutes}min at ${_ymd(c.probe)} as '
          'it should.\n'
          'Delete this row. When the last row goes, delete the file and the '
          '"Open risks" entry in docs/roadmap.md with it.',
        );
      }

      expect(
        minutes,
        c.staleMinutes,
        reason: 'neither the current nor the corrected offset — the dataset '
            'moved in a way this tripwire does not model, so re-read it '
            'before trusting any clock in ${c.zoneId}',
      );

      // Comparing dates, not building one an assertion reads: see the note at
      // the top about why the wall clock is allowed in here at all.
      final today = DateTime.now().toUtc();
      expect(
        today.isBefore(c.deadline),
        isTrue,
        reason:
            '\n\nDEADLINE PASSED — ${c.zoneId} is now showing the wrong '
            'hour to real users.\n\n'
            '${c.change} (tzdb ${c.release}).\n'
            'The app ships IANA tzdata 2025c via `timezone` 0.11.1 and does '
            'not have it: it answers ${c.staleMinutes}min at ${_ymd(c.probe)} '
            'where the right answer is ${c.expectedMinutes}min.\n\n'
            'Two ways out, both recorded under "Open risks" in '
            'docs/roadmap.md:\n'
            '  1. Upgrade `timezone` if a release carrying 2026c now exists.\n'
            '  2. Stop depending on the embedded dataset: generate a .tzf with '
            "the package's own tool/get.dart + tool/encode_tzf.dart, ship it "
            'as an asset, and call initializeDatabase(Uint8List) instead of '
            "latest_all.dart's initializeTimeZones().\n",
      );
    });
  }
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

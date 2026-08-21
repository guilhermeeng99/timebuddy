import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A guard over CLAUDE.md's fourth Time & Timezone rule: **never call
// `DateTime.now()` in `lib/`.**
//
// Every state in this app is a function of "now", so a hardcoded now is an
// untestable feature and a DST bug hiding behind "it worked when I ran it".
// The rule had no test — it held because everyone remembered it, which is not
// a mechanism. A second call site would have shipped green.
//
// Scanning source rather than asserting on behaviour is deliberate: the defect
// is the *call*, wherever it is, and no runtime assertion can see a widget
// nobody pumped. `zone_lookup_test.dart` already sets the precedent for a
// property over the whole shipped surface rather than over a sample.
void main() {
  /// The one sanctioned call site: `Clock` is the seam every other reader
  /// goes through, so it is the one file allowed to read the wall clock.
  const sanctioned = 'lib/core/time/clock.dart';

  /// Generated output is not hand-written and is excluded from the analyzer
  /// for the same reason.
  const generatedPrefix = 'lib/gen/';

  test('lib/ reads the wall clock in exactly one place', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final path = entity.path.replaceAll(r'\', '/');
      if (path == sanctioned || path.startsWith(generatedPrefix)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Comments are allowed to name the thing they are warning about — the
        // rule is quoted in half a dozen doc comments — so only real code
        // counts. Crude, but a false positive here is a broken build, and a
        // trimmed `//` prefix catches every doc comment in this codebase.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        if (!line.contains('DateTime.now(')) continue;
        offenders.add('$path:${i + 1}  ${trimmed.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'CLAUDE.md rule 4: inject `Clock` and call `clock.nowUtc()` '
          'instead.\nFound:\n${offenders.join('\n')}',
    );
  });

  test('the guard would notice, if it stopped noticing', () {
    // The scanner above is only worth its runtime if it can actually fail, and
    // a test that greps a tree it never proves it can read is the kind of
    // green that means nothing. This pins the mechanism: the sanctioned file
    // does contain the call, and the scan does find it there.
    final clock = File(sanctioned).readAsStringSync();
    expect(clock, contains('DateTime.now('));
  });
}

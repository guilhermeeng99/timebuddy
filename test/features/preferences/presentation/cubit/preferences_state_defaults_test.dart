import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state_defaults.dart';

import '../../../../harness/factories/preferences_factory.dart';

// The loading fallback, in the one place that owns it.
//
// This `switch` used to be written out six times — three cubits and three
// widgets — identical but for a word of comment. The tests that matter here
// are not "does a getter return a field": they are that the ready branch
// reports what the user chose rather than the default that happens to equal
// it, and that the loading branch answers with the *entity's* default rather
// than an improvised one, so a widget built in that frame and the same widget
// a frame later do not disagree.
void main() {
  group('while the document is loading', () {
    const loading = PreferencesLoading();

    test('the window is the seeded default, not an invented one', () {
      // Compared against what a first launch actually writes rather than
      // against a literal 09:00-17:00: a test that hardcoded the hours would
      // keep passing if the seeded default and this fallback ever drifted
      // apart, which is the whole failure this getter exists to prevent.
      final seeded = PreferencesEntity.defaults(
        deviceLocale: const Locale('en', 'US'),
        now: DateTime.utc(2024),
      );
      expect(loading.workingHoursOrDefault, seeded.workingHours);
    });

    test('the clock is 24h', () {
      expect(loading.hourFormatOrDefault, ClockFormat.h24);
    });

    test('seconds are off, which is the cautious direction', () {
      // Not arbitrary: this drives the app-wide ticker rate
      // (docs/specs/preferences.md rule 10), so guessing `true` for one frame
      // would spin every clock on screen at 1 Hz before anyone asked for it.
      expect(loading.showSecondsOrDefault, isFalse);
    });
  });

  group('once the document is ready', () {
    /// Every value deliberately *different* from its loading fallback, so a
    /// getter that ignored the state entirely would fail all three.
    final chosen = aPreferences(
      workingHours: const WorkingHours(startHour: 22, endHour: 6),
      hourFormat: ClockFormat.h12,
      showSeconds: true,
    );
    final ready = PreferencesReady(chosen);

    test('the window is the one the user set, wrap included', () {
      // A night shift, which is also the case a naive default would mask: it
      // is a valid wrap-around window, not a broken one (WorkingHours).
      expect(ready.workingHoursOrDefault, chosen.workingHours);
      expect(ready.workingHoursOrDefault.startHour, 22);
      expect(ready.workingHoursOrDefault.endHour, 6);
    });

    test('the clock format is the one the user set', () {
      expect(ready.hourFormatOrDefault, ClockFormat.h12);
    });

    test('seconds follow the preference', () {
      expect(ready.showSecondsOrDefault, isTrue);
    });
  });
}

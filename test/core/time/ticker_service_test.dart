import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/time/ticker_service.dart';

import '../../harness/fake_clock.dart';
import '../../harness/helpers.dart';

// Two clocks are in play here, and keeping them apart is what makes these
// tests deterministic:
//
//  * `FakeClock` decides *what instant* a tick carries, and what the minute
//    alignment is measured against. Only `clock.advance()` moves it.
//  * The fake async owned by the widget binding decides *when* the timers
//    fire. `tester.pump(duration)` moves it, and no wall-clock time passes.
//
// The second one is why these are `testWidgets` cases rather than plain
// `test` cases: `testWidgets` runs its body inside a `FakeAsync`, so a one
// minute cadence costs microseconds. Importing `package:fake_async` directly
// would do the same job, but it is only a transitive dependency here and
// importing it would trip `depend_on_referenced_packages` for a fake zone the
// binding already hands us.
//
// Every case disposes its ticker before returning: the binding fails a test
// that leaves a pending timer behind, which doubles as a free assertion that
// dispose really does cancel the timer.

void main() {
  late FakeClock clock;

  setUp(() {
    // Second 0 of the minute, so the alignment delay is a whole 60s and the
    // arithmetic in each expectation stays readable. One test below moves the
    // clock off the boundary on purpose.
    clock = FakeClock(utcDate(2024, 3, 10, 12));
  });

  group('cadence', () {
    testWidgets('starts on the minute rate', (tester) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);

      expect(ticker.needsSeconds, isFalse);
      await tester.pump(const Duration(seconds: 59));
      expect(ticks, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(ticks, hasLength(1));

      await tester.pump(const Duration(minutes: 1));
      expect(ticks, hasLength(2));

      await ticker.dispose();
    });

    testWidgets('aligns the first minute tick to the next :00', (tester) async {
      // The displayed minute must flip when the minute actually changes, not
      // up to 59 seconds later.
      clock.setTo(utcDate(2024, 3, 10, 12, 0, 30));
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);

      await tester.pump(const Duration(seconds: 29));
      expect(ticks, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(ticks, hasLength(1));

      await tester.pump(const Duration(minutes: 1));
      expect(ticks, hasLength(2));

      await ticker.dispose();
    });

    testWidgets('emits the instant read from the injected clock', (
      tester,
    ) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);

      clock.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(ticks, [utcDate(2024, 3, 10, 12, 1)]);
      expect(ticks.single.isUtc, isTrue);

      await ticker.dispose();
    });
  });

  group('setNeedsSeconds', () {
    testWidgets('switches the cadence to 1 Hz', (tester) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);

      ticker.setNeedsSeconds(value: true);
      expect(ticker.needsSeconds, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(ticks, hasLength(1));

      await tester.pump(const Duration(seconds: 2));
      expect(ticks, hasLength(3));

      await ticker.dispose();
    });

    testWidgets('switches back to the minute cadence', (tester) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);
      ticker.setNeedsSeconds(value: true);

      await tester.pump(const Duration(seconds: 3));
      expect(ticks, hasLength(3));

      ticker.setNeedsSeconds(value: false);
      await tester.pump(const Duration(seconds: 59));
      expect(ticks, hasLength(3), reason: 'the 1 Hz timer must be cancelled');

      await tester.pump(const Duration(seconds: 1));
      expect(ticks, hasLength(4));

      await ticker.dispose();
    });

    testWidgets('ignores a value it is already on', (tester) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);

      await tester.pump(const Duration(seconds: 30));
      // A restart here would push the pending tick out to t+90s, so the tick
      // landing at t+60s is what proves the early return.
      ticker.setNeedsSeconds(value: false);

      await tester.pump(const Duration(seconds: 30));
      expect(ticks, hasLength(1));

      await ticker.dispose();
    });
  });

  group('pause and resume', () {
    testWidgets('pause stops emissions without closing the stream', (
      tester,
    ) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      var isDone = false;
      ticker.stream.listen(ticks.add, onDone: () => isDone = true);

      ticker.pause();
      await tester.pump(const Duration(minutes: 5));

      expect(ticks, isEmpty);
      expect(isDone, isFalse, reason: 'the subscription must survive pause');

      await ticker.dispose();
    });

    testWidgets('resume emits immediately, then resumes ticking', (
      tester,
    ) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);
      ticker.pause();

      // A phone unlocked an hour after it was locked must not keep showing
      // the minute it was locked at until the next tick lands.
      clock.advance(const Duration(hours: 1));
      ticker.resume();
      await tester.pump(Duration.zero);

      expect(ticks, [utcDate(2024, 3, 10, 13)]);

      await tester.pump(const Duration(minutes: 1));
      expect(ticks, hasLength(2));

      await ticker.dispose();
    });

    testWidgets('adopts a rate that was set while paused', (tester) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);
      ticker
        ..pause()
        ..setNeedsSeconds(value: true);

      await tester.pump(const Duration(seconds: 3));
      expect(ticks, isEmpty, reason: 'setNeedsSeconds must not defeat pause');

      ticker.resume();
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, hasLength(2), reason: 'the resume tick plus one second');

      await ticker.dispose();
    });
  });

  group('subscribers', () {
    testWidgets('runs one timer whatever the subscriber count', (tester) async {
      var timersCreated = 0;
      final counting = ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          timersCreated++;
          return parent.createTimer(zone, duration, callback);
        },
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          timersCreated++;
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      );
      // Timers created by callbacks of these timers run in the same forked
      // zone, so the handover from the aligned tick to the periodic one is
      // counted too.
      final ticker = runZoned(
        () => TickerService(clock: clock),
        zoneSpecification: counting,
      );

      expect(timersCreated, 1, reason: 'the aligned first tick');

      final grid = <DateTime>[];
      final worldClock = <DateTime>[];
      final planner = <DateTime>[];
      ticker.stream.listen(grid.add);
      ticker.stream.listen(worldClock.add);
      ticker.stream.listen(planner.add);
      expect(timersCreated, 1, reason: 'subscribing must not create a timer');

      await tester.pump(const Duration(minutes: 1));
      expect(timersCreated, 2, reason: 'the handover to the periodic timer');

      await tester.pump(const Duration(minutes: 2));
      expect(timersCreated, 2);
      expect(grid, hasLength(3));
      expect(worldClock, grid);
      expect(planner, grid);

      await ticker.dispose();
    });

    testWidgets('is a broadcast stream a late subscriber can join', (
      tester,
    ) async {
      final ticker = TickerService(clock: clock);
      expect(ticker.stream.isBroadcast, isTrue);

      final early = <DateTime>[];
      ticker.stream.listen(early.add);
      await tester.pump(const Duration(minutes: 1));

      final joinedLate = <DateTime>[];
      ticker.stream.listen(joinedLate.add);
      await tester.pump(const Duration(minutes: 1));

      expect(early, hasLength(2));
      expect(
        joinedLate,
        hasLength(1),
        reason: 'a broadcast stream keeps no backlog',
      );

      await ticker.dispose();
    });
  });

  group('dispose', () {
    testWidgets('closes the stream and stops the timer', (tester) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      var isDone = false;
      ticker.stream.listen(ticks.add, onDone: () => isDone = true);

      await ticker.dispose();
      await tester.pump(const Duration(minutes: 5));

      expect(isDone, isTrue);
      expect(ticks, isEmpty);
    });

    testWidgets('leaves resume inert instead of adding to a closed stream', (
      tester,
    ) async {
      final ticker = TickerService(clock: clock);
      final ticks = <DateTime>[];
      ticker.stream.listen(ticks.add);

      await ticker.dispose();
      ticker.resume();
      await tester.pump(const Duration(minutes: 5));

      expect(ticks, isEmpty);
    });
  });
}

import 'package:timebuddy/core/time/clock.dart';

/// A [Clock] whose "now" only moves when a test moves it.
///
/// Every screen in this app is a function of the current instant, so a test
/// that reads the real wall clock is a test that fails once a year at 02:00.
/// This is the only sanctioned way for a test to know the time: never call
/// `DateTime.now()` in a test either.
///
/// ```dart
/// final clock = FakeClock(utcDate(2024, 3, 10, 6, 59));
/// final cubit = WorldClockCubit(clock: clock, engine: engine);
/// clock.advance(const Duration(minutes: 1)); // crosses US spring-forward
/// ```
class FakeClock implements Clock {
  FakeClock(DateTime initialInstantUtc) : _nowUtc = _asUtc(initialInstantUtc);

  DateTime _nowUtc;

  @override
  DateTime nowUtc() => _nowUtc;

  /// Moves the clock by [delta].
  ///
  /// A negative [delta] rewinds, which is how a test exercises a backwards
  /// clock correction (NTP resync, user changing the device date).
  ///
  /// Arithmetic here is safe because [_nowUtc] is always UTC: adding 24 hours
  /// to a *local* DateTime across a DST boundary yields 23 or 25 real hours.
  void advance(Duration delta) {
    _nowUtc = _nowUtc.add(delta);
  }

  /// Jumps to an absolute instant, for tests that pin a specific transition
  /// rather than a duration since setup.
  void setTo(DateTime instantUtc) {
    _nowUtc = _asUtc(instantUtc);
  }

  /// Rejects local-time instants: `DateTime(2024, 3, 10)` and
  /// `DateTime.utc(2024, 3, 10)` differ by the host's offset, so accepting the
  /// former would make the same test pass in Sao Paulo and fail in Berlin.
  static DateTime _asUtc(DateTime instant) {
    assert(
      instant.isUtc,
      'FakeClock takes UTC instants, got a local DateTime ($instant). '
      'Use DateTime.utc(...) or utcDate(...) from test/harness/helpers.dart.',
    );
    return instant.toUtc();
  }
}

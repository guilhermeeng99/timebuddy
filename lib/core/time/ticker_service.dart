import 'dart:async';

import 'package:timebuddy/core/time/clock.dart';

/// The app's single heartbeat.
///
/// Every widget that has to repaint as time advances subscribes to [stream]
/// instead of owning a `Timer`: a 20-city board would otherwise mean 20 timers
/// and 20 rebuilds per second (CLAUDE.md, Performance; world_clock rule 3).
///
/// The stream is broadcast and carries UTC instants read from the injected
/// [Clock], so tests drive it with a fake clock and never the wall clock.
///
/// ```dart
/// final ticker = TickerService(clock: const SystemClock());
/// final sub = ticker.stream.listen((utcInstant) => rebuildDigits(utcInstant));
/// // ... on AppLifecycleState.paused / .resumed:
/// ticker
///   ..pause()
///   ..resume();
/// ```
class TickerService {
  /// Starts ticking straight away at the minute rate. A broadcast stream drops
  /// events while nobody listens, so the cost before the first subscriber is
  /// one callback a minute.
  TickerService({required Clock clock}) : _clock = clock {
    _startTimer();
  }

  static const Duration _secondInterval = Duration(seconds: 1);
  static const Duration _minuteInterval = Duration(minutes: 1);

  final Clock _clock;

  // One controller and one timer for the whole app. Both are owned here so
  // that subscriber count and tick cost stay independent of each other.
  final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast();
  Timer? _timer;

  bool _needsSeconds = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  /// Broadcast stream of UTC instants, one per tick.
  Stream<DateTime> get stream => _controller.stream;

  bool get needsSeconds => _needsSeconds;

  /// Switches the tick rate: `true` gives 1 Hz, `false` gives 1/60 Hz aligned
  /// to the minute boundary.
  ///
  /// This is a plain setter driven by the `showSeconds` preference
  /// (preferences rule 10), **not** a reference count over the widgets that
  /// currently want seconds. Reference counting is out of scope by design: the
  /// preference is global, so a count would always collapse to the same answer
  /// while adding a leak surface, since one widget that forgets to release its
  /// claim would pin the whole app at 1 Hz.
  void setNeedsSeconds({required bool value}) {
    if (_needsSeconds == value) return;
    _needsSeconds = value;
    // A paused ticker adopts the new rate when it resumes; restarting the
    // timer here would defeat the pause.
    if (_isDisposed || _isPaused) return;
    _startTimer();
  }

  /// Stops the timer without closing [stream], so existing subscriptions
  /// survive a trip to the background (`AppLifecycleState.paused`).
  void pause() {
    _isPaused = true;
    _cancelTimer();
  }

  /// Emits the current instant immediately, then restarts the timer.
  ///
  /// The immediate emission is world_clock rule 10: a phone unlocked an hour
  /// after it was locked must not keep showing the minute it was locked at
  /// until the next tick lands.
  void resume() {
    if (_isDisposed) return;
    _isPaused = false;
    _emit();
    _startTimer();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _cancelTimer();
    await _controller.close();
  }

  void _startTimer() {
    _cancelTimer();
    if (_needsSeconds) {
      _timer = Timer.periodic(_secondInterval, (_) => _emit());
      return;
    }
    // Align the first minute tick to the next :00 so the displayed minute
    // flips when it actually changes, not up to 59 seconds later.
    _timer = Timer(_untilNextMinute(), () {
      _emit();
      _timer = Timer.periodic(_minuteInterval, (_) => _emit());
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Duration _untilNextMinute() {
    final nowUtc = _clock.nowUtc();
    final sinceMinuteStart = Duration(
      seconds: nowUtc.second,
      milliseconds: nowUtc.millisecond,
      microseconds: nowUtc.microsecond,
    );
    return _minuteInterval - sinceMinuteStart;
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(_clock.nowUtc());
  }
}

/// The app's single source of "now".
///
/// Every screen in TimeBuddy is a pure function of the current instant, so a
/// bare `DateTime.now()` anywhere in `lib/` makes that screen impossible to
/// test and hides DST bugs behind "it worked when I ran it". The grid, the
/// world clock and the planner all render a different answer at 01:59 and at
/// 03:00 on a transition day, and neither of those moments can be reached by a
/// test that reads the real wall clock.
///
/// Inject a [Clock] instead and hand tests a fake that returns a pinned
/// instant.
///
/// ```dart
/// final cubit = PreferencesCubit(
///   repository: repository,
///   clock: const SystemClock(),
/// );
/// ```
// Clock exists to be swapped for FakeClock in tests; a top-level function
// would not be injectable, which is the entire point of the type.
// ignore: one_member_abstracts
abstract class Clock {
  /// The current instant, always in UTC.
  ///
  /// Nothing in the app reads a local `DateTime` from the platform: callers
  /// that need a wall-clock time convert this instant through
  /// `TimeZoneEngine`, which knows which zone they meant.
  DateTime nowUtc();
}

/// The production [Clock]: the device clock, normalised to UTC.
///
/// This is the one sanctioned `DateTime.now()` call site in `lib/`. It is
/// deliberately trivial so that "is the time wrong?" is never a question about
/// this class.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

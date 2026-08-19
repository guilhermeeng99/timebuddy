import 'package:equatable/equatable.dart';

/// The user's daily working window, the input that colours every hour surface
/// in the app through `hourBandFor`.
///
/// The window is half-open: [startHour] is inclusive and [endHour] is
/// **exclusive**, so `09:00-17:00` is `WorkingHours(startHour: 9, endHour: 17)`
/// and covers the hours 9 through 16.
///
/// [endHour] MAY be smaller than [startHour]: a night shift of `22:00-06:00`
/// is `WorkingHours(startHour: 22, endHour: 6)` and wraps past midnight. Every
/// member below is wrap-aware precisely so no caller has to special-case it
/// (preferences rule 4).
///
/// ```dart
/// const nightShift = WorkingHours(startHour: 22, endHour: 6);
/// nightShift.contains(23);   // true
/// nightShift.contains(6);    // false, the end is exclusive
/// nightShift.lengthInHours;  // 8
/// ```
class WorkingHours extends Equatable {
  const WorkingHours({required this.startHour, required this.endHour});

  /// First-launch default and the repair value returned by [clamped].
  static const WorkingHours defaultHours = WorkingHours(
    startHour: 9,
    endHour: 17,
  );

  /// Preferences rule 5. Below [minLength] the grid degenerates into a wall of
  /// `poor`; above [maxLength] the colour coding stops discriminating.
  static const int minLength = 1;
  static const int maxLength = 16;

  /// Inclusive start of the window, `0..23`.
  final int startHour;

  /// Exclusive end of the window, `1..24`. May be less than [startHour].
  final int endHour;

  /// Whether [hour] falls inside the window.
  ///
  /// Measured as a distance from [startHour] rather than as a pair of
  /// comparisons, so the midnight wrap needs no branch. Values outside `0..23`
  /// are taken modulo 24, which is what lets callers pass `(hour + 23) % 24`
  /// style neighbours without guarding.
  bool contains(int hour) => (hour - startHour) % 24 < lengthInHours;

  /// Length of the window in whole hours, wrap-aware.
  ///
  /// A window whose start equals its end reads as a full day (24) rather than
  /// as an empty one; [isValid] then rejects it, which is the intended
  /// outcome for a pair the settings form never produces.
  int get lengthInHours {
    final span = endHour - startHour;
    return span > 0 ? span : span + 24;
  }

  /// Both ends in range and the resulting span within
  /// [minLength]..[maxLength]. Range is checked first so a wild persisted
  /// value never reaches the span arithmetic.
  bool get isValid =>
      startHour >= 0 &&
      startHour <= 23 &&
      endHour >= 1 &&
      endHour <= 24 &&
      lengthInHours >= minLength &&
      lengthInHours <= maxLength;

  /// This instance when [isValid], otherwise [defaultHours].
  ///
  /// There is deliberately no partial repair: a pair that survived a bad parse
  /// or an older schema carries no reliable intent, and nudging one end would
  /// hand the user a working window they never chose.
  WorkingHours clamped() => isValid ? this : defaultHours;

  WorkingHours copyWith({int? startHour, int? endHour}) => WorkingHours(
    startHour: startHour ?? this.startHour,
    endHour: endHour ?? this.endHour,
  );

  @override
  List<Object?> get props => [startHour, endHour];
}

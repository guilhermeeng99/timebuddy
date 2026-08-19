/// How a clock face is rendered.
///
/// Seeded from the device locale on first launch and owned by the user from
/// then on (preferences.md rule 2). Persisted as `enum.name` in both the local
/// store and Firestore, so these identifiers are part of the wire format:
/// renaming a value orphans every saved preference. Read back through
/// `enumByName(..., orElse:)` so an unknown value degrades instead of throwing
/// (preferences.md rule 9).
enum ClockFormat {
  /// 24-hour clock: `07:05`, `19:05`. Default for `pt-BR` devices.
  h24,

  /// 12-hour clock with an am/pm marker: `7:05 AM`. Default for `en-US`.
  h12,
}

/// The first column of a week, for the planner's day strip and date pickers.
///
/// Locale-seeded and persisted under the same rules as [ClockFormat].
enum WeekStart {
  /// ISO-8601 order, the default on `pt-BR` devices.
  monday,

  /// US order, the default on `en-US` devices.
  sunday,
}

import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state.dart';

/// Reading a preference from a state that may not have resolved yet.
///
/// **One owner for the loading fallback.** `PreferencesLoading` is a frame that
/// barely exists in production — the document is read during startup, before
/// any page mounts (docs/specs/startup.md) — but every consumer still has to
/// answer for it, and each was answering separately. The same `switch` was
/// written out in `TimeGridCubit`, `WorldClockCubit`, `TimeConverterCubit`,
/// `ClockText`, `TimeConverterPage` and `WorldClockPage`: six copies of one
/// rule, identical but for a word of comment, and six places for a future
/// default to be changed in five of them.
///
/// The fallbacks are deliberately the *entity's* defaults rather than
/// improvised ones, so a widget rendered in that one frame and the same widget
/// a frame later disagree about nothing.
///
/// ```dart
/// final hours = context.watch<PreferencesCubit>().state.workingHoursOrDefault;
/// ```
extension PreferencesStateDefaults on PreferencesState {
  /// The working window, or the default one while the document is loading.
  WorkingHours get workingHoursOrDefault => switch (this) {
    PreferencesReady(:final preferences) => preferences.workingHours,
    PreferencesLoading() => WorkingHours.defaultHours,
  };

  /// The 12h/24h choice, or 24h while the document is loading.
  ClockFormat get hourFormatOrDefault => switch (this) {
    PreferencesReady(:final preferences) => preferences.hourFormat,
    PreferencesLoading() => ClockFormat.h24,
  };

  /// Whether clocks show seconds, or `false` while the document is loading.
  ///
  /// The cautious direction on purpose: this drives the app-wide ticker rate
  /// (docs/specs/preferences.md rule 10), so guessing `true` for one frame
  /// would spin every clock at 1 Hz before anyone asked.
  bool get showSecondsOrDefault => switch (this) {
    PreferencesReady(:final preferences) => preferences.showSeconds,
    PreferencesLoading() => false,
  };
}

/// Safe parsing of enums stored as `enum.name`.
///
/// `Values.byName(raw)` throws an [ArgumentError] on anything it does not
/// recognize, which is the wrong behavior at every persistence boundary. Three
/// things routinely produce an unrecognized name: a value dropped in a later
/// release, a document written by a newer client on the user's other device,
/// and a corrupted blob. `byName` turns any of them into a crashed screen for
/// data the app could simply have defaulted. So no JSON, SharedPreferences or
/// Firestore field is ever parsed with `byName` in this project - it goes
/// through the two functions below (preferences.md rule 9).
library;

/// Returns the value of [values] whose `name` equals [raw], or `null`.
///
/// A `null` [raw] is a miss, not an error: an absent field and an unknown one
/// are handled the same way by every caller.
///
/// ```dart
/// enumByNameOrNull(ClockFormat.values, 'h12');   // ClockFormat.h12
/// enumByNameOrNull(ClockFormat.values, 'h13');   // null
/// enumByNameOrNull(ClockFormat.values, null);    // null
/// ```
T? enumByNameOrNull<T extends Enum>(List<T> values, String? raw) {
  if (raw == null) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}

/// Returns the value of [values] whose `name` equals [raw], or [orElse].
///
/// The parsing form used by models: it cannot fail, so a single bad field
/// costs one setting rather than the whole document.
///
/// ```dart
/// final palette = enumByName(
///   LightPalette.values,
///   json['lightPalette'] as String?,
///   orElse: LightPalette.indigoCloud,
/// );
/// ```
T enumByName<T extends Enum>(
  List<T> values,
  String? raw, {
  required T orElse,
}) =>
    enumByNameOrNull(values, raw) ?? orElse;

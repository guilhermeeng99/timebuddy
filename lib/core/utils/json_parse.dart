/// Safe parsing of the primitive shapes a persisted document can hold.
///
/// The companion of `enum_parse.dart`, and it exists for the same reason: no
/// field this app reads comes from a source it controls. A JSON blob can be a
/// `shared_preferences` string written by an older build, a Firestore document
/// written by the user's other device, or a value corrupted somewhere in
/// between, and a cast that throws on any of those turns one bad field into a
/// screen the user cannot open. So a boundary parser degrades: the functions
/// below never throw, they answer `null` (or the epoch) and leave the fallback
/// visible at the call site, where the caller is the only code that knows what
/// a missing value should mean.
///
/// ```dart
/// final zoneId = filledStringOrNull(json['zoneId']);
/// if (zoneId == null) return null;               // load-bearing: drop the row
/// final revision = intOrNull(json['revision']) ?? 0;  // degrades
/// ```
library;

/// Returns [raw] trimmed, or `null` when it is not a string or is blank.
///
/// Blank collapses to `null` rather than to `''` because every caller treats
/// the two the same way, and a stored `"   "` is damage, not a label. Trimming
/// before the emptiness test is what makes a padded value usable instead of
/// silently falling back: `" dark "` is the setting the user chose.
///
/// ```dart
/// filledStringOrNull(' Sao Paulo ');  // 'Sao Paulo'
/// filledStringOrNull('   ');          // null
/// filledStringOrNull(42);             // null
/// filledStringOrNull(null);           // null
/// ```
String? filledStringOrNull(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Returns [raw] as an `int`, or `null` when it is not a number.
///
/// The `num` arm is not decoration. JSON has a single number type and
/// Firestore has two, so a whole number can come back as a `double` from a
/// document another client wrote; a plain `raw is int` test would reject a
/// `sortIndex` of `3.0` and drop a perfectly good row. Callers that have a
/// meaningful zero write `?? 0` and say why there.
///
/// ```dart
/// intOrNull(3);      // 3
/// intOrNull(3.0);    // 3
/// intOrNull('3');    // null - a numeric string is not a number here
/// intOrNull(null);   // null
/// ```
int? intOrNull(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

/// Decodes both halves of the dual timestamp encoding (docs/specs/sync.md):
/// an ISO-8601 string from `shared_preferences`, and a millisecond epoch int
/// from a Firestore `Timestamp` that has already been unwrapped.
///
/// Shared rather than copied into each model: `BoardModel.updatedAt`,
/// `SavedLocationEntity.addedAt` and `PreferencesModel.updatedAt` are fields
/// of one synced state, and a parser that drifted would make a document's own
/// timestamps disagree.
///
/// A Firestore `Timestamp` arm is deliberately *not* here. `Timestamp` is a
/// cloud_firestore type, and this library is imported by models that only ever
/// see `shared_preferences`; adding the import would hand the Firebase SDK to
/// every one of them to serve a single caller. `RemoteSettingsDataSource`
/// unwraps the board's and the preferences' timestamps into epoch ints before
/// their models run, and `UserModel` — the one model handed a raw snapshot —
/// unwraps its own and delegates the rest here.
///
/// An unreadable value falls back to the epoch, never to "now": a timestamp
/// nobody can read must lose every tie it enters (sync.md rule 5) instead of
/// winning them by looking freshly written.
///
/// ```dart
/// timestampFromJson('2026-01-01T00:00:00Z');  // that instant, UTC
/// timestampFromJson(1767225600000);           // the same instant
/// timestampFromJson('not a date');            // the epoch
/// ```
DateTime timestampFromJson(Object? raw) {
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

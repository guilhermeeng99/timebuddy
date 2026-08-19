import 'package:shared_preferences/shared_preferences.dart';
import 'package:timebuddy/core/errors/exceptions.dart';

/// Raw key/value access to the device's persistent store.
///
/// The entire persisted state of TimeBuddy is two JSON documents, always read
/// and written whole, so this contract deals in strings and leaves encoding to
/// the data layer. See `docs/specs/sync.md` for why there is no database here.
///
/// ```dart
/// final store = SharedPreferencesLocalStore(prefs);
/// await store.writeRaw(StorageKeys.preferences, jsonEncode(model.toJson()));
/// final raw = await store.readRaw(StorageKeys.preferences); // null if absent
/// ```
abstract class LocalStore {
  /// Returns the stored string, or `null` when the key was never written.
  Future<String?> readRaw(String key);

  /// Persists [value] under [key].
  ///
  /// Throws [StorageException] when the platform refuses the write.
  Future<void> writeRaw(String key, String value);

  /// Drops a single key. Missing keys are not an error.
  Future<void> remove(String key);

  /// Wipes every key. Called on sign-out and account deletion (sync.md
  /// rule 10), so a pending write never leaks into the next session.
  Future<void> clearAll();
}

/// [LocalStore] backed by `shared_preferences` (`localStorage` on web).
///
/// Takes an already-resolved [SharedPreferences] instance instead of awaiting
/// `getInstance()` internally: the DI container resolves it once at startup,
/// and tests can seed it with `SharedPreferences.setMockInitialValues`.
class SharedPreferencesLocalStore implements LocalStore {
  const SharedPreferencesLocalStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> readRaw(String key) async => _prefs.getString(key);

  @override
  Future<void> writeRaw(String key, String value) async {
    final persisted = await _prefs.setString(key, value);
    // A refused write breaks the read path, not just durability (sync.md,
    // Edge Cases), so the caller has to learn that the session is now
    // memory-only rather than silently believing the data is safe.
    if (!persisted) {
      throw StorageException('Could not persist "$key" to local storage.');
    }
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }

  @override
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}

/// Every key TimeBuddy writes to [LocalStore].
///
/// The `.v1` suffix is load-bearing (sync.md rule 11): a breaking change to a
/// JSON shape writes `.v2` and leaves `.v1` untouched, so a user who downgrades
/// still finds a document their build can parse.
abstract class StorageKeys {
  static const String board = 'timebuddy.board.v1';
  static const String preferences = 'timebuddy.preferences.v1';
  static const String boardDirty = 'timebuddy.dirty.board';
  static const String preferencesDirty = 'timebuddy.dirty.preferences';
}

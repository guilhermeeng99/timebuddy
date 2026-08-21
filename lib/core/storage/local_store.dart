import 'dart:convert';

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

/// Reading a whole JSON document through [LocalStore.readRaw].
///
/// Both documents this app persists are read the same way — one string, one
/// `jsonDecode`, one "is it even an object" test — so the body lives once.
/// An extension rather than a member of [LocalStore] because that interface is
/// implemented by more than the real store: the mocks and the in-memory fakes
/// the widget tests build would each have to reimplement a method that has
/// exactly one correct body. Extensions are dispatched statically, so a fake
/// that stubs `readRaw` gets this decoder for free.
extension LocalStoreJson on LocalStore {
  /// Returns the object stored under [key], or `null` when the key was never
  /// written.
  ///
  /// Throws [CacheException] carrying [malformedMessage] when the stored
  /// string is not a JSON object: a document that is not even an object cannot
  /// be salvaged field by field, so it is reported rather than silently
  /// replaced, and the repository decides whether to seed a fresh one or
  /// surface the failure. The message belongs to the caller because it names
  /// the document, which is the one part of the answer this method cannot
  /// know.
  ///
  /// ```dart
  /// final json = await store.readJsonObject(
  ///   StorageKeys.board,
  ///   malformedMessage: 'The stored board is not a readable JSON object.',
  /// );
  /// ```
  Future<Map<String, dynamic>?> readJsonObject(
    String key, {
    required String malformedMessage,
  }) async {
    final raw = await readRaw(key);
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Object?;
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException catch (_) {
      // Falls through to the exception below: the message is the same either
      // way, and the caller cannot act on the difference.
    }
    throw CacheException(malformedMessage);
  }
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

  /// Whether this device chose to use the app without an account
  /// (docs/specs/guest_mode.md).
  ///
  /// A device fact, not a user one, which is why it is a key of its own rather
  /// than a field of the preferences document: that document syncs, and a
  /// guest flag pushed to Firestore would tell every other device that this
  /// account is a guest.
  ///
  /// `clearAll()` on sign-out removes it along with everything else, so
  /// whoever wants a guest session afterwards writes it back *after* the wipe
  /// (guest_mode.md rule 9).
  static const String guest = 'timebuddy.guest.v1';
}

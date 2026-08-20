import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/storage/local_store.dart';

/// The names and constants the sync layer shares between its parts.
///
/// Declared once, here, for the same reason `StorageKeys` exists: a path
/// segment retyped at a second call site is how a build starts writing
/// `users/{id}/setting/board` and reading an empty account forever.
///
/// ```dart
/// firestore
///     .collection(SyncKeys.usersCollection)
///     .doc(userId)
///     .collection(SyncKeys.settingsCollection)
///     .doc(SyncKeys.boardDocument);
/// ```
abstract class SyncKeys {
  /// `users/{userId}`, the profile document (docs/specs/auth.md).
  static const String usersCollection = 'users';

  /// `users/{userId}/settings`, holding the two synced documents.
  ///
  /// A subcollection rather than two fields of the profile, so a profile read
  /// is never coupled to a board read and a board write never rewrites the
  /// user's name.
  static const String settingsCollection = 'settings';

  /// `users/{userId}/settings/board`.
  static const String boardDocument = 'board';

  /// `users/{userId}/settings/preferences`.
  static const String preferencesDocument = 'preferences';

  /// What a remote document that is absent, or whose `revision` cannot be
  /// read, is worth on the conflict ladder (sync.md rule 5, Edge Cases).
  ///
  /// `-1` and not `0`: a fresh local document starts at revision `0`, so a
  /// missing remote counted as `0` would tie with it and fall through to the
  /// `updatedAt` tie-break, where the remote wins by default. It would
  /// overwrite the user's first board with nothing. At `-1` the missing side
  /// always loses, which is exactly what makes provisioning a case of
  /// reconciliation rather than a code path of its own.
  static const int missingRevision = -1;

  /// What a set dirty flag holds.
  ///
  /// The *presence* of the key is the flag; this value exists so a developer
  /// reading the store sees a word rather than an empty string.
  static const String dirtyMarker = 'true';
}

/// The two "this document still owes the server a write" markers.
///
/// A flag is set when a remote write fails and cleared when one lands, so the
/// next start, the next successful sync and the next resume know what to push
/// without retrying in a loop (sync.md rule 3). Retrying in place would spin a
/// dead radio; a flag costs one key and waits for a moment that is likely to
/// work.
///
/// The flag is an optimisation, not the durability mechanism: even if it is
/// lost, the revision ladder still uploads the newer document on the next
/// sync. That is why nothing here fails loudly.
///
/// ```dart
/// final flags = SyncDirtyFlags(localStore);
/// if (await flags.isDirty(StorageKeys.boardDirty)) { /* push it */ }
/// ```
class SyncDirtyFlags {
  const SyncDirtyFlags(this._store);

  final LocalStore _store;

  /// Whether [key] is currently marked.
  Future<bool> isDirty(String key) async => await _store.readRaw(key) != null;

  /// Marks [key], swallowing a store that refuses the write.
  ///
  /// A failed flag must not fail the operation that set it: it is raised while
  /// handling a *remote* failure that rule 4 says the user never sees, and the
  /// document it describes is still uploaded by the next sync's ladder.
  Future<void> mark(String key) async {
    try {
      await _store.writeRaw(key, SyncKeys.dirtyMarker);
    } on StorageException catch (_) {
      // Deliberately silent: see the doc comment above.
    }
  }

  /// Unmarks [key]. Clearing a key that was never set is not an error.
  Future<void> clear(String key) => _store.remove(key);
}

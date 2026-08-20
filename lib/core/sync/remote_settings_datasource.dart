import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/sync/sync_keys.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';

/// A [ServerException] the device could plausibly recover from by waiting.
///
/// Still a [ServerException], so every `on ServerException` handler above the
/// data layer keeps working and nothing has to learn a second type. The
/// subtype exists for one decision only: whether the passive indicator says
/// "offline" or "error" (docs/specs/sync.md, Edge Cases). A dropped connection
/// resolves itself and deserves no explanation; a permission denied never will
/// and the profile page has to say so.
class RemoteUnavailableException extends ServerException {
  const RemoteUnavailableException([
    super.message = 'Firestore could not be reached.',
  ]);

  @override
  String toString() => 'RemoteUnavailableException: $message';
}

/// Reads and writes the three documents one account owns in Firestore.
///
/// The whole remote state is `users/{userId}` plus the two documents under
/// `users/{userId}/settings`, addressed by id: no queries, no indexes, no
/// listeners (CLAUDE.md, Firestore Rules). A full sync is therefore two reads.
///
/// The two settings documents are typed, and they are typed with the *same*
/// models `shared_preferences` uses: one serializer per document, not two
/// (sync.md, Storage model). The profile is not, on purpose — see
/// [readProfile].
///
/// Every Firestore error leaves this class as a [ServerException], so the
/// layer above catches one type (CLAUDE.md, Error handling).
///
/// ```dart
/// final board = await remote.readBoard(
///   userId: user.id,
///   homeZoneIdFallback: localBoard.homeZoneId,
/// );          // null when the account has no board document yet
/// ```
abstract class RemoteSettingsDataSource {
  /// The account's board, or `null` when the document does not exist.
  ///
  /// [homeZoneIdFallback] fills in only a *missing* `homeZoneId`, exactly as
  /// in `BoardModel.fromJson`. Pass the local board's home zone rather than
  /// the device's: both documents belong to the same account, so the user's
  /// own reference zone is the better guess, and the device's would quietly
  /// move every offset on the board when they travel.
  ///
  /// A document whose `revision` cannot be read comes back as
  /// [SyncKeys.missingRevision], so it loses reconciliation and is overwritten
  /// instead of crashing the sync (sync.md, Edge Cases).
  Future<BoardModel?> readBoard({
    required String userId,
    required String homeZoneIdFallback,
  });

  /// Overwrites the account's board document wholesale.
  ///
  /// Throws [ServerException]; the caller turns that into a dirty flag rather
  /// than into an error the user sees (sync.md rules 3 and 4).
  Future<void> writeBoard({
    required String userId,
    required BoardModel board,
  });

  /// The account's preferences, or `null` when the document does not exist.
  Future<PreferencesModel?> readPreferences({required String userId});

  /// Overwrites the account's preferences document wholesale.
  Future<void> writePreferences({
    required String userId,
    required PreferencesModel preferences,
  });

  /// The raw `users/{userId}` document, or `null` when it does not exist.
  ///
  /// Deliberately untyped and unconverted: `UserModel` lives in the auth
  /// feature and owns the `Timestamp` to `DateTime` mapping of `createdAt`
  /// (auth.md, Model Serialization), and `core/` translating it here would put
  /// a second parser on one document — the exact duplication the typed methods
  /// above exist to avoid. The map is handed over exactly as Firestore decoded
  /// it, `Timestamp` values included.
  Future<Map<String, dynamic>?> readProfile({required String userId});

  /// Merges [profile] into `users/{userId}`, creating it when absent.
  ///
  /// A merge, because provisioning has to be idempotent (auth.md rule 3): a
  /// retry after a partial failure must complete the document, not blank the
  /// fields another client already wrote to it.
  Future<void> writeProfile({
    required String userId,
    required Map<String, dynamic> profile,
  });
}

/// [RemoteSettingsDataSource] backed by Cloud Firestore.
class FirestoreRemoteSettingsDataSource implements RemoteSettingsDataSource {
  const FirestoreRemoteSettingsDataSource(this._firestore);

  /// Codes that mean "try again later" rather than "this will never work".
  ///
  /// Everything else, `permission-denied` and `unauthenticated` above all, is
  /// a real error: rules are misconfigured or the account was revoked, and no
  /// amount of waiting fixes either.
  static const Set<String> _retryableCodes = {
    'unavailable',
    'deadline-exceeded',
  };

  /// The fields the models write as ISO-8601 strings and Firestore should
  /// hold as `Timestamp`s.
  ///
  /// Named rather than sniffed: a rule like "every key ending in At" would
  /// silently convert the first future field that merely looks like a date,
  /// and the failure would be a wrong value in the store, not a crash.
  static const Set<String> _timestampFields = {'updatedAt', 'addedAt'};

  final FirebaseFirestore _firestore;

  @override
  Future<BoardModel?> readBoard({
    required String userId,
    required String homeZoneIdFallback,
  }) async {
    final data = await _read(
      _settingsDocument(userId, SyncKeys.boardDocument),
    );
    if (data == null) return null;

    final board = BoardModel.fromJson(
      _withUnwrappedTimestamps(data),
      homeZoneIdFallback: homeZoneIdFallback,
    );
    if (_hasReadableRevision(data)) return board;

    // `BoardModel.fromJson` degrades an unreadable revision to 0, which is
    // right for local storage and wrong here: 0 ties with a fresh local
    // document and the tie goes to the remote, so a corrupt server copy would
    // overwrite the user's first board. Reporting -1 makes it lose instead.
    return BoardModel.fromEntity(
      board.copyWith(revision: SyncKeys.missingRevision),
    );
  }

  @override
  Future<void> writeBoard({
    required String userId,
    required BoardModel board,
  }) {
    return _write(
      _settingsDocument(userId, SyncKeys.boardDocument),
      _withFirestoreTimestamps(board.toJson()),
    );
  }

  @override
  Future<PreferencesModel?> readPreferences({required String userId}) async {
    final data = await _read(
      _settingsDocument(userId, SyncKeys.preferencesDocument),
    );
    if (data == null) return null;

    final preferences = PreferencesModel.fromJson(
      _withUnwrappedTimestamps(data),
    );
    if (_hasReadableRevision(data)) return preferences;

    return PreferencesModel.fromEntity(
      preferences.copyWith(revision: SyncKeys.missingRevision),
    );
  }

  @override
  Future<void> writePreferences({
    required String userId,
    required PreferencesModel preferences,
  }) {
    return _write(
      _settingsDocument(userId, SyncKeys.preferencesDocument),
      _withFirestoreTimestamps(preferences.toJson()),
    );
  }

  @override
  Future<Map<String, dynamic>?> readProfile({required String userId}) {
    return _read(_profileDocument(userId));
  }

  @override
  Future<void> writeProfile({
    required String userId,
    required Map<String, dynamic> profile,
  }) {
    return _write(_profileDocument(userId), profile, merge: true);
  }

  DocumentReference<Map<String, dynamic>> _profileDocument(String userId) {
    return _firestore.collection(SyncKeys.usersCollection).doc(userId);
  }

  DocumentReference<Map<String, dynamic>> _settingsDocument(
    String userId,
    String documentId,
  ) {
    return _profileDocument(userId)
        .collection(SyncKeys.settingsCollection)
        .doc(documentId);
  }

  Future<Map<String, dynamic>?> _read(
    DocumentReference<Map<String, dynamic>> document,
  ) async {
    try {
      final snapshot = await document.get();
      return snapshot.data();
    } on FirebaseException catch (error) {
      throw _asException(error);
    } on Exception catch (error) {
      // Firestore's web and platform channels can surface a plain exception
      // that never reaches the Firebase type. It is still a remote failure,
      // and the caller must not have to know the difference.
      throw ServerException('$error');
    }
  }

  /// Writes [data], replacing the document unless [merge] is set.
  ///
  /// Replacing is the default because the document is the unit of
  /// reconciliation (sync.md rule 6): a location the user deleted has to
  /// disappear from the server copy, and a merge write would resurrect it on
  /// the next read.
  Future<void> _write(
    DocumentReference<Map<String, dynamic>> document,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    try {
      await document.set(data, SetOptions(merge: merge));
    } on FirebaseException catch (error) {
      throw _asException(error);
    } on Exception catch (error) {
      throw ServerException('$error');
    }
  }

  /// Whether the document carries a `revision` the ladder can compare.
  static bool _hasReadableRevision(Map<String, dynamic> data) =>
      data['revision'] is num;

  static ServerException _asException(FirebaseException error) {
    final message = '${error.code}: ${error.message ?? error.plugin}';
    if (_retryableCodes.contains(error.code)) {
      return RemoteUnavailableException(message);
    }
    return ServerException(message);
  }

  /// Replaces every Firestore `Timestamp` with the millisecond epoch int the
  /// models already accept.
  ///
  /// Unwrapped here rather than in the models because `Timestamp` is a
  /// cloud_firestore type and those models are shared with
  /// `shared_preferences`, which never sees one. Recursive, so the board's
  /// `locations[].addedAt` costs no extra code.
  static Map<String, dynamic> _withUnwrappedTimestamps(
    Map<String, dynamic> data,
  ) {
    return data.map<String, dynamic>(
      (key, value) => MapEntry(key, _unwrapped(value)),
    );
  }

  static Object? _unwrapped(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is Map<String, dynamic>) return _withUnwrappedTimestamps(value);
    if (value is List) return value.map(_unwrapped).toList();
    return value;
  }

  /// Re-encodes the ISO-8601 timestamps `toJson` produced as `Timestamp`s.
  ///
  /// The models write one string form for both stores; Firestore is the side
  /// that wants the native type (sync.md, Storage model), and reading a date
  /// in the console beats reading a quoted string when something has gone
  /// wrong. Both parsers accept either form, so a document copied between the
  /// two sides still needs no conversion.
  static Map<String, dynamic> _withFirestoreTimestamps(
    Map<String, dynamic> json,
  ) {
    return json.map<String, dynamic>(
      (key, value) => MapEntry(key, _encoded(key, value)),
    );
  }

  static Object? _encoded(String key, Object? value) {
    if (_timestampFields.contains(key) && value is String) {
      final parsed = DateTime.tryParse(value);
      // An unparseable string is left exactly as it is: the models read it
      // back as the epoch, which loses every tie, where inventing a date here
      // would let a broken document win one.
      if (parsed != null) return Timestamp.fromDate(parsed.toUtc());
    }
    if (value is Map<String, dynamic>) return _withFirestoreTimestamps(value);
    if (value is List) return [for (final item in value) _encoded(key, item)];
    return value;
  }
}

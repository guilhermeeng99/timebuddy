import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timebuddy/core/utils/json_parse.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';

/// The stand-in for a profile whose `name` is missing or blank.
///
/// Deliberately **not** a slang string, even though it can reach the screen:
/// this value is parsed on one device and written back to a document the
/// user's other device reads, so localizing it would persist "Usuário" for a
/// browser that then renders it in English. A stored default is data, not
/// copy (docs/specs/auth.md, Model Serialization).
const String _fallbackName = 'User';

/// Serialization for [UserEntity], against `users/{userId}`.
///
/// Every parse degrades instead of throwing. The profile is the document that
/// decides whether the app opens at all, so one unreadable field must cost a
/// label, never the session (auth.md rules 4 and 8).
///
/// ```dart
/// final snapshot = await firestore.collection('users').doc(uid).get();
/// final profile = UserModel.fromFirestore(snapshot);
/// await snapshot.reference.set(profile.toJson(), SetOptions(merge: true));
/// ```
class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    required super.name,
    required super.email,
    required super.createdAt,
    super.photoUrl,
  });

  /// Reads `users/{userId}`, taking the id from the document rather than from
  /// a field: the document *is* addressed by the Auth UID, so a duplicated
  /// `id` field could only ever disagree with it.
  ///
  /// A snapshot that does not exist parses to an all-defaults profile rather
  /// than throwing; callers check `snapshot.exists` when the difference
  /// matters, which is what makes provisioning idempotent (rule 3).
  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return UserModel(
      id: doc.id,
      name: filledStringOrNull(data['name']) ?? _fallbackName,
      email: filledStringOrNull(data['email']) ?? '',
      photoUrl: filledStringOrNull(data['photoUrl']),
      createdAt: _createdAtFrom(data['createdAt']),
    );
  }

  /// The profile Firebase Auth alone can vouch for.
  ///
  /// This is what a first sign-in writes and what rule 4 falls back to when
  /// Firestore is unreachable: every field came from the token that was just
  /// verified, so it is accurate — merely not yet durable.
  ///
  /// Takes plain values rather than a `User`, so the model stays free of
  /// `firebase_auth`: the data source owns that transport, the model owns the
  /// Firestore shape.
  factory UserModel.fromAuth({
    required String id,
    required String? name,
    required String? email,
    required String? photoUrl,
    required DateTime createdAt,
  }) {
    return UserModel(
      id: id,
      name: filledStringOrNull(name) ?? _fallbackName,
      email: filledStringOrNull(email) ?? '',
      photoUrl: filledStringOrNull(photoUrl),
      createdAt: createdAt.toUtc(),
    );
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      name: entity.name,
      email: entity.email,
      photoUrl: entity.photoUrl,
      createdAt: entity.createdAt,
    );
  }

  /// Accepts every encoding the two writers can produce.
  ///
  /// A Firestore `Timestamp` is the shape this model writes; the `int` and
  /// `String` arms `timestampFromJson` covers are for a document that
  /// travelled through the JSON path shared with `shared_preferences`
  /// (docs/specs/sync.md), so a profile copied between the two sides never
  /// needs converting. An unreadable value becomes the epoch rather than
  /// "now", so a timestamp nobody can read cannot pass itself off as freshly
  /// written.
  ///
  /// The `Timestamp` arm is unwrapped here rather than inside
  /// `timestampFromJson` because this is the only model that ever sees one:
  /// `RemoteSettingsDataSource` unwraps the board's and the preferences'
  /// before their models run, and moving this arm into `core/utils` would
  /// hand cloud_firestore to every JSON parser in the app to serve one caller.
  static DateTime _createdAtFrom(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    return timestampFromJson(raw);
  }

  /// The document body, without `id`: that is the document's own key.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'email': email,
      // Written even when null, because every write to this document is a
      // merge: an omitted field is left untouched, so a user who removed
      // their Google picture would keep the stale URL forever.
      'photoUrl': photoUrl,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
  }
}

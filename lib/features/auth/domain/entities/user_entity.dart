import 'package:equatable/equatable.dart';

/// The signed-in person, as the app knows them.
///
/// The account exists for exactly one reason: the same board and preferences
/// on the phone and in the browser (docs/specs/auth.md). It is not a paywall,
/// not a social graph and not a permission system, which is why there is no
/// `role`, no `plan` and no allowlist flag on this type — rule 11 says the
/// access control Financo needs has no counterpart in a world clock.
///
/// The profile carries **no app data**. The board and the preferences live in
/// their own documents under `users/{userId}/settings/`, so reading a profile
/// never drags a board read along with it (docs/specs/sync.md).
///
/// ```dart
/// final user = UserEntity(
///   id: 'firebase-uid',
///   name: 'Ada Lovelace',
///   email: 'ada@example.com',
///   createdAt: clock.nowUtc(),
/// );
/// ```
class UserEntity extends Equatable {
  const UserEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    this.photoUrl,
  });

  /// Firebase Auth UID, and the id of the `users/{userId}` document.
  ///
  /// The only stable key: an email address can be reassigned by whoever owns
  /// its domain, and a display name changes whenever the user edits it, so
  /// neither can address a profile.
  final String id;

  /// Display name, from the Google account and editable afterwards.
  final String name;

  /// The Google account's address. Shown in the profile page; never used as
  /// an identity (see [id]) and never checked against a list (rule 11).
  final String email;

  /// Google profile picture, absent for accounts that have none.
  ///
  /// Nullable rather than defaulted to a placeholder URL: "there is no photo"
  /// is a decision the UI makes with an avatar of its own, and a fake URL
  /// would make it a failed network request instead.
  final String? photoUrl;

  /// UTC, stamped on first sign-in.
  ///
  /// Read from Firebase Auth's own account metadata rather than from the
  /// device, so two devices signing into one account agree on it and a skewed
  /// device clock cannot invent a membership date.
  final DateTime createdAt;

  /// [clearPhotoUrl] is the only way to *remove* a photo: `photoUrl: null`
  /// cannot mean "clear it" and "leave it alone" at once. Same shape as
  /// `CityEntity.clearAdmin1` and `PreferencesEntity.clearLocaleTag`.
  UserEntity copyWith({
    String? id,
    String? name,
    String? email,
    String? photoUrl,
    DateTime? createdAt,
    bool clearPhotoUrl = false,
  }) {
    return UserEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: clearPhotoUrl ? null : photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, email, photoUrl, createdAt];
}

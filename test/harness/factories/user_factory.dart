import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';

/// The `createdAt` every factory-built [UserEntity] carries unless a test
/// overrides it.
///
/// Fixed, like every other fixture instant in this harness: `createdAt` is
/// part of entity equality (docs/specs/auth.md, Entity Contract), so a factory
/// that read the wall clock would make a user unequal to itself between two
/// frames of the same test. Mid-January, and far from any DST transition, so a
/// test that does convert it is reading an unambiguous instant.
final DateTime userFixtureCreatedAt = DateTime.utc(2024, 1, 15, 12);

/// Builds a [UserEntity], overriding only the fields a test cares about.
///
/// [photoUrl] defaults to a real URL because a Google account normally has
/// one. A test that wants the missing-picture case passes `photoUrl: null`
/// explicitly and needs no clear-sentinel for it: this factory *builds* a
/// user, it does not merge into an existing one, so `null` can only mean
/// "absent" here (unlike `UserEntity.copyWith`, which needs `clearPhotoUrl`).
///
/// ```dart
/// final ada = aUser(id: 'uid-ada');
/// final withoutPicture = aUser(photoUrl: null);
/// ```
UserEntity aUser({
  String id = 'uid-ada',
  String name = 'Ada Lovelace',
  String email = 'ada@example.com',
  String? photoUrl = 'https://example.com/ada.png',
  DateTime? createdAt,
}) {
  return UserEntity(
    id: id,
    name: name,
    email: email,
    photoUrl: photoUrl,
    createdAt: createdAt ?? userFixtureCreatedAt,
  );
}

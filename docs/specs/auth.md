# Auth & Profile Spec

Sign-in exists for one reason: the same board and preferences on the phone and in
the browser. It is not a paywall, not a social graph, and not a permission
system.

The app is **Google-only**. There is no email/password sign-in, no public
sign-up form, and no `SignInPage`: the unauthenticated landing is the
`OnboardingPage`, whose final slide hosts the Google button.

---

## Entity Contract

```dart
UserEntity {
  id:        String    (required, Firebase Auth UID / Firestore doc ID)
  name:      String    (required)
  email:     String    (required)
  photoUrl:  String?   (nullable, Google profile picture URL)
  createdAt: DateTime  (required, UTC, set on first sign-in)
}
```

No computed properties. Equatable by all fields, plus `copyWith`.

The user document carries **no app data**. The board and the preferences live in
their own documents under `users/{userId}/settings/`, so a profile read is never
coupled to a board read. See [sync.md](sync.md).

---

## Business Rules

1. **Sign-in is required to use the app.** There is no guest mode in v1: the
   whole point of the account is cross-device sync, and a local-only mode would
   need a migration path (local board into a fresh cloud board, with conflict
   rules) that is not worth building before the app has users. Recorded as a
   deferred decision in [roadmap.md](../roadmap.md).

2. **Google sign-in is platform-specific.** Redirect flow on web (a popup trips
   COOP restrictions in several browsers), the `google_sign_in` plugin on
   Android. Both land in the same `signInWithGoogle` repository method.

3. **First sign-in provisions everything.** A new user gets, in one flow: the
   Firestore profile document, a board seeded with `homeZoneId` from
   `deviceZoneId()` and an empty location list, and a preferences document with
   defaults. Provisioning is idempotent, so a retry after a partial failure
   completes rather than duplicating.

4. **Sign-in is resilient to a Firestore outage.** If Firebase Auth succeeds and
   Firestore does not, the repository returns a minimal profile built from the
   Auth credentials. The user reaches the app with their local board; the next
   sync reconciles. An auth success followed by an error screen would be the
   worst of both.

5. **Cancellation is not an error.** A dismissed Google dialog raises
   `GoogleSignInException`, which is caught and mapped to `AuthFailure` with a
   cancelled marker so the UI returns to onboarding silently instead of showing a
   red banner.

6. **Sign-out is platform-specific.** On web the `google_sign_in` plugin is not
   initialised (Firebase's redirect flow owns the GSI lifecycle), so calling its
   `signOut()` would throw `StateError`; the datasource skips it on web. On
   Android, Google sign-out is attempted but non-fatal: any failure is swallowed
   so `FirebaseAuth.signOut()` always runs.

7. **Sign-out clears local data.** On success the repository wipes the cached
   board and preferences from `shared_preferences`. Leaving another account's
   cities on a shared browser is a privacy leak, however mild.

8. **`getCurrentUser` self-heals a missing profile.** An authenticated user with
   no Firestore document (the classic web-redirect race) gets one created from
   their Auth data rather than being bounced to onboarding.

9. **`authStateChanges` never crashes the app.** A Firestore error while mapping
   an auth event yields `null` (treated as signed out) rather than an unhandled
   stream error.

10. **Error mapping is uniform:** `AuthException` to `AuthFailure`, generic
    `Exception` to `ServerFailure`, applied at every repository method.

11. **There is no allowlist.** Financo gates sign-in on an `allowed_emails`
    collection because it holds financial data; a world clock does not.
    Anyone with a Google account can sign in.

---

## Repository Contract

```dart
abstract class AuthRepository {
  /// Google-only sign-in. Provisions profile, board and preferences on first
  /// use (rule 3). Degrades to a minimal profile if Firestore is down (rule 4).
  Future<Either<Failure, UserEntity>> signInWithGoogle();

  /// Signs out and clears the local cache (rule 7).
  Future<Either<Failure, void>> signOut();

  Future<Either<Failure, UserEntity?>> getCurrentUser();

  /// Stream of session changes. Emits null when signed out.
  Stream<UserEntity?> get authStateChanges;
}

abstract class ProfileRepository {
  Future<Either<Failure, UserEntity>> getProfile(String userId);
  Future<Either<Failure, UserEntity>> updateProfile(UserEntity user);

  /// Deletes the Firestore subtree and the Auth user, then clears local data.
  Future<Either<Failure, void>> deleteAccount(String userId);
}
```

**Behavior:**

- `signInWithGoogle` → Auth, then provision (rule 3), then local cache write.
- `signOut` → remote sign-out, then `clearLocalData()`.
- `getCurrentUser` → Auth session check, profile fetch, self-heal (rule 8).
- `authStateChanges` → delegates to the datasource stream, mapped defensively.
- `deleteAccount` → deletes `users/{userId}` and its `settings` subcollection,
  then the Auth user. Idempotent.

---

## Model Serialization

**Firestore to model (`fromFirestore`):**

| Firestore field | Dart field | Cast |
|---|---|---|
| `doc.id` | `id` | `String` |
| `name` | `name` | `String`, defaults to `'User'` when empty |
| `email` | `email` | `String`, defaults to `''` |
| `photoUrl` | `photoUrl` | `String?` |
| `createdAt` | `createdAt` | `Timestamp` to UTC `DateTime` |

**Model to Firestore (`toJson`):** all fields except `id`; `createdAt` as a
`Timestamp`; `photoUrl` written even when null.

---

## State Machine

### AuthBloc

Singleton, provided app-wide.

**Events:** `AuthCheckRequested`, `AuthGoogleSignInRequested`,
`AuthSignOutRequested`, `AuthUserChanged(user)` (internal, from the
`authStateChanges` subscription).

**States:** `AuthInitial`, `AuthLoading`, `Authenticated(user)`,
`Unauthenticated`, `AuthError(failure)`.

```
AuthInitial ──CheckRequested──→ Authenticated(user)   [session found]
                              → Unauthenticated       [no session or failure]

Any ──GoogleSignInRequested──→ AuthLoading → Authenticated  [ok]
                                           → Unauthenticated [cancelled, rule 5]
                                           → AuthError       [other failure]

Any ──SignOutRequested──→ Unauthenticated  [success]
                        → AuthError        [failure]

Authenticated ──session revoked remotely──→ Unauthenticated
```

There is no `AccessDenied` state: rule 11.

### ProfileCubit

Session-scoped.

```dart
ProfileInitial
ProfileLoading
ProfileLoaded({ user: UserEntity })
ProfileError({ failure: Failure })
```

```
Initial ──load()──→ Loading → Loaded(user) | Error(failure)
Loaded ──load(forceRefresh: false)──→ (no-op)
Loaded ──load(forceRefresh: true)───→ Loading → …
```

---

## Edge Cases

- **User cancels the Google dialog** → back to onboarding, no error UI (rule 5).
- **Firestore unavailable during sign-in** → minimal profile, app opens (rule 4).
- **Authenticated but no profile document** → created on the fly (rule 8).
- **Provisioning partially failed** (profile written, board not) → the next
  `getBoard` finds no remote document and provisions the board then; rule 3's
  idempotence is what makes this safe.
- **Sign-out fails remotely** → `AuthError`, and local data is **not** cleared,
  so the user is not left signed in with an empty board.
- **Token expires while offline** → `authStateChanges` emits null on the next
  connection; the local board stays cached and is restored on the next sign-in
  with the same account.
- **Two accounts on the same browser** → sign-out clears local data (rule 7), so
  the second account starts from its own remote state.
- **Account deletion** → `deleteAccount` removes remote and local state. The user
  lands on onboarding.

---

## Firestore

**Document:** `users/{userId}`. Fields: `name`, `email`, `photoUrl`,
`createdAt`. Read by document id only; no indexes.

**Rules:** a signed-in user may read and write `users/{userId}` and everything
under it if and only if `request.auth.uid == userId`.

---

## i18n

Copy under `t.auth.*`: `onboardingTitle1..3`, `onboardingBody1..3`,
`signInWithGoogle`, `signInFailed`, `signOut`, `signOutConfirm`,
`deleteAccount`, `deleteAccountConfirm`, `deleteAccountWarning`.

---

## Testing

`test/features/auth/`:

- `AuthBloc`: check with and without a session, sign-in success, cancellation
  mapping to `Unauthenticated` (rule 5), sign-in failure, sign-out success and
  failure, `AuthUserChanged` from the stream.
- `AuthRepository`: provisioning is idempotent (rule 3), Firestore outage yields
  a minimal profile (rule 4), sign-out clears local data (rule 7), self-heal on a
  missing profile (rule 8), stream error yields null (rule 9).
- Platform branches (web vs mobile sign-out, rule 6) are covered by injecting a
  platform flag rather than by `kIsWeb` at the call site, so both paths are
  testable.

Mocks in `test/harness/mocks.dart`: `MockFirebaseAuth`, `MockGoogleSignIn`,
`FakeFirebaseFirestore` (via `fake_cloud_firestore`), `MockLocalStore`.

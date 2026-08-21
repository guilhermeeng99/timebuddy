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

1. **Sign-in is optional.** A visitor uses the entire app against local-only
   documents and signs in when they want the board to survive the device. The
   contract lives in [guest_mode.md](guest_mode.md); what matters here is that
   nothing in this spec may be written as though a session were a
   precondition.

   **This rule used to say "sign-in is required", and reversing it was the
   point, so here is what changed and what did not.** The objection was real:
   a local-only mode needs a migration path with its own conflict rules, and
   inventing one badly destroys data. What made it affordable is that the
   migration turned out to be one rule rather than a system —
   [guest_mode.md](guest_mode.md) rule 6, "the account wins whenever it already
   has documents" — which needs no merge, no field-level reconciliation and no
   prompt. The conflict ladder is untouched; adoption sits beside it for
   exactly one call.

   What did **not** change: the app is still Google-only, there is still no
   `SignInPage`, and the account still exists for one reason, which is
   cross-device sync. A guest is not a second tier of user with a smaller app.

2. **Google sign-in is platform-specific, and on web it is popup-first with a
   redirect fallback.** Android drives the `google_sign_in` plugin. The browser
   calls `signInWithPopup` first, and reaches `signInWithRedirect` only when
   the browser refused to open a popup. Both platforms land in the same
   `signInWithGoogle` repository method, and the platform question is asked
   through the injected `AppPlatform`, never through `kIsWeb` at a call site.

   **This rule used to say "redirect on web". Reversing it was the point, so
   here is the evidence, to save the next person from reversing it back.**

   The redirect flow parks its intermediate state on the Firebase auth domain
  : `timebuddy-app-2026.firebaseapp.com`, see `firebase_options.dart`: and
   reads it back after a full-page navigation to `guilhermeeng99.github.io`.
   That read is cross-site, and every browser that partitions third-party
   storage drops it: Safari under ITP, Firefox under Total Cookie Protection,
   Chrome with third-party cookies disabled. `getRedirectResult()` then
   resolves with a `UserCredential` whose `user` is null: which is the
   *identical* value it returns when no redirect was ever started
   (`firebase_auth` 6.5.7, `FirebaseAuth.getRedirectResult`, and
   `firebase_auth_web` 6.2.6 passes it straight through). The user lands back
   in the app, signed out, with no error raised anywhere. It never reproduces
   on localhost, because there the app origin and the auth domain are not
   being partitioned from one another; it only shows up from the deployed
   origin.

   The popup does not have that problem. The OAuth handshake happens in a
   window this page opened, the credential comes back to the opener by
   `postMessage`, and the session is written to the app origin's *own*
   IndexedDB. Nothing has to survive a cross-site navigation.

   **The COOP objection that originally chose the redirect is not live on this
   deployment.** `signInWithPopup` breaks when the *app* page is served with
   `Cross-Origin-Opener-Policy: same-origin`, which severs `window.opener` in
   the popup and the `window.closed` handle in the opener, so the result can
   never be delivered and a closed popup can never be detected. TimeBuddy is
   served by GitHub Pages, which sends no COOP header and gives no way to set
   one, and `web/index.html` sets none either. Two changes would bring the
   objection back and must revisit this rule: enabling Flutter's
   multi-threaded `skwasm` renderer, which requires cross-origin isolation and
   therefore COOP, or moving to a host that sets the header.

   The trade, stated plainly: popup-first fails **loudly and recoverably**,
   redirect-first fails **silently**, for a large share of real browsers.

   Three refusals, three answers, because they are three different problems
   for the person holding the phone:

   | The browser… | Codes | Outcome | What the user gets |
   |---|---|---|---|
   | closed the popup | `popup-closed-by-user`, `cancelled-popup-request`, `user-cancelled` | `GoogleSignInCancelled` | nothing: back to onboarding in silence (rule 5) |
   | would not open the popup | `popup-blocked`, `operation-not-supported-in-this-environment` | `GoogleSignInPopupUnavailable` | a redirect, automatically; nothing to do |
   | would not give Firebase storage | `web-storage-unsupported` | `GoogleSignInStorageBlocked` | `signInStorageBlockedFailure`, and **no** redirect: the round trip would only lose the state again, silently |

   Matched on `FirebaseException.code` rather than on `FirebaseAuthException`,
   whose constructor is `@protected` and cannot be built by a test. The code is
   the stable contract anyway: `firebase_auth_web` strips the `auth/` prefix
   off the JS SDK error and hands the rest through untouched.

   **The silent case is made loud by a first-party note.** Before handing the
   page to the redirect, the repository writes `pending` under
   `timebuddy.auth.webRedirect.v1` in `LocalStore`. That key is first-party to
   the app's own origin, which is precisely the storage a partitioning browser
   leaves alone. On the next boot, `getCurrentUser` reads the note *before* the
   session check: the check is what consumes the redirect, so afterwards the
   question has no answer left: and then:

   - session found → the note is cleared and nothing else happens;
   - no session, note `pending` → **the partitioned-storage case**. It answers
     `signInStorageBlockedFailure`, not `Right(null)`, and rewrites the note as
     `unusable`;
   - the session check threw, note `pending` → the same diagnosis. A rejected
     auth event or a mismatched nonce is the loud form of the same lost state;
   - no note → an ordinary signed-out boot, `Right(null)`, no failure.

   Once the note reads `unusable`, a later blocked popup is answered with
   `signInPopupBlockedFailure` instead of a second redirect: the round trip is
   already known to fail here, and "allow pop-ups for this site" is the one
   remedy left that the user can actually carry out. A successful sign-in
   clears the note, and so does sign-out (rule 7 wipes every key), so the
   verdict is re-learned per session rather than outliving the browser it was
   made about.

   Known imprecision, written down so nobody re-derives it: a user who
   abandons the flow at Google's account chooser and navigates back is
   indistinguishable from one whose state was dropped, and gets the same
   verdict. The cost is that their next blocked popup says "allow pop-ups"
   rather than redirecting: advice that would have worked either way.

   **What the user is told.** Both verdicts reach the screen as
   `Unauthenticated(blockedBy: SignInBlock.storage | SignInBlock.popup)`: the
   state a signed-out user is in anyway, carrying the one extra thing there is
   to say. `AuthBloc` is the only place in the app that reads the markers: it
   translates them once into `SignInBlock`, so no widget ever compares a
   marker string and a third obstacle added later is a compile error rather
   than a silent fall through to the generic message. `OnboardingPage` draws
   the matching copy in a notice above the Google button, and opens on the
   sign-in slide when it mounts carrying one.

   **Drawn, not snackbarred**, and that is the whole difference between a
   diagnosis that exists and one that arrives. The boot-leg verdict is settled
   while the splash is still up, so by the time onboarding mounts there is no
   state *change* left for a listener to fire on: a snackbar raised from there
   would be shown to nobody, on precisely the failure this rule exists for.

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

5. **Cancellation is not an error.** A dismissed Android dialog raises
   `GoogleSignInException`; a closed browser popup raises one of rule 2's
   dismissal codes. Both become `GoogleSignInCancelled`, which the repository
   maps to `AuthFailure` with a cancelled marker, so the UI returns to
   onboarding silently instead of showing a red banner. A cancellation is never
   answered with a redirect: the user just closed a window on purpose, and
   sending them to Google anyway overrides a decision they made a moment ago.

6. **Sign-out is platform-specific.** On web the `google_sign_in` plugin is not
   initialised (Firebase owns the GSI lifecycle there, whether the session came
   from a popup or a redirect), so calling its `signOut()` would throw
   `StateError`; the datasource skips it on web. On Android, Google sign-out is
   attempted but non-fatal: any failure is swallowed so `FirebaseAuth.signOut()`
   always runs.

7. **Sign-out clears local data, then re-enters guest mode.** On success the
   repository wipes every key from `shared_preferences` — leaving another
   account's cities on a shared browser is a privacy leak, however mild — and
   *then* writes the guest marker back, in that order, because `clearAll()`
   removes it too ([guest_mode.md](guest_mode.md) rule 9).

   The user therefore lands in the app on an empty board rather than on the
   onboarding tour they have already read. The wipe is not softened to keep
   their cities: this rule's whole justification is the shared browser, and a
   sign-out that left the board behind would defeat it.

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
  On web it also owns rule 2's flow policy: popup first, redirect only as a
  fallback, and only while the redirect is still believed to work here.
- `signOut` → remote sign-out, then `clearLocalData()`.
- `getCurrentUser` → redirect note, Auth session check, profile fetch,
  self-heal (rule 8). It is the only place the partitioned-storage case can be
  seen, so it answers `Left(signInStorageBlockedFailure)` there rather than
  `Right(null)`.
- `authStateChanges` → delegates to the datasource stream, mapped defensively.
- `deleteAccount` → deletes `users/{userId}` and its `settings` subcollection,
  then the Auth user. Idempotent.

**Failure markers.** `AuthFailure` is `final` and `Failure` is sealed, so a
subtype cannot be declared for these; each marker travels in the
developer-facing `message`, which is never rendered, and is read through its
predicate, never by comparing strings at a call site.

| Marker | Predicate | Means |
|---|---|---|
| `signInCancelledMarker` | `isSignInCancelled` | the user walked away, or a redirect is navigating away (rule 5) |
| `signInStorageBlockedMarker` | `isSignInStorageBlocked` | the browser dropped the sign-in state (rule 2) |
| `signInPopupBlockedMarker` | `isSignInPopupBlocked` | the popup was blocked and the redirect is known not to work here (rule 2) |

The first lives in `auth_repository.dart` beside the contract; the two added by
rule 2 live in `auth_repository_impl.dart` for now and belong next to it.

**Data source contract.** `AuthRemoteDataSource.signInWithGoogle` answers a
sealed `GoogleSignInOutcome`: `GoogleSignInSucceeded`,
`GoogleSignInCancelled`, `GoogleSignInPopupUnavailable`,
`GoogleSignInStorageBlocked`: rather than a nullable `UserModel`. A `null`
return used to carry all four, and the one that matters is invisible if it
shares a value with a dismissed dialog. `startGoogleRedirect()` is web-only and
is reached only from `GoogleSignInPopupUnavailable`, which no other platform
can produce; the data source reports what the browser did, and the repository
owns the policy, because deciding whether a redirect is still worth trying
needs a memory that outlives the page and only the repository has one.

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
`Unauthenticated({blockedBy})`, `AuthError(failure)`.

`blockedBy` is a `SignInBlock?`: `storage` when the browser dropped the
sign-in's state, `popup` when the pop-up was blocked and the redirect is
already known unusable here, and `null` for every ordinary signed-out session
,  a first launch, a cancelled dialog, a sign-out.

```
AuthInitial ──CheckRequested──→ Authenticated(user)    [session found]
                              → Unauthenticated        [no session, or a
                                                        failure with no remedy]
                              → Unauthenticated(blockedBy: storage)
                                                       [rule 2's boot verdict]

Any ──GoogleSignInRequested──→ AuthLoading → Authenticated   [ok]
                                           → Unauthenticated [cancelled, rule 5]
                                           → Unauthenticated(blockedBy: …)
                                                             [rule 2's verdict]
                                           → AuthError       [other failure]

Any ──SignOutRequested──→ Unauthenticated  [success]
                        → AuthError        [failure]

Authenticated ──session revoked remotely──→ Unauthenticated

Unauthenticated(blockedBy: …) ──null from authStateChanges──→ (ignored)
```

There is no `AccessDenied` state: rule 11.

`CheckRequested` answering `Unauthenticated` for "failure" as well as for "no
session" is deliberate: an error screen in front of a button the user could
simply press is a dead end. The one thing it no longer folds away is rule 2's
verdict, which rides along as `blockedBy`: still signed out, because that is
the truth of it, and no longer silent.

**Why a field and not a sixth state.** A blocked sign-in leaves the app in
exactly the situation `Unauthenticated` already names: nobody signed in, the
onboarding page in front of the button: and the only difference is that there
is something to say. It also has to *travel*: the boot-leg verdict is produced
on the splash and read on the onboarding page that replaces it, one router
redirect and several frames later. A state meaning "signed out" makes that
trip untouched, while an error state has to be re-read as signed out by
everything on the way, which `StartupCubit._terminalReading` and `ProfilePage`
already do for `AuthError`: the same folding that swallowed this diagnosis in
the first place. `AuthState` is sealed besides, and `ProfilePage` switches over
it with all five cases spelled out and no wildcard, so a sixth state is a
compile error in a file that has nothing to do with browser storage.

**A `null` from `authStateChanges` never clears `blockedBy`.** Firebase
publishes one moments after startup on every signed-out boot, including the one
a dropped redirect lands on, and it says nothing the state does not already
say. Honouring it would erase the verdict a few frames before onboarding mounts
to read it. The next attempt clears it instead: `AuthLoading` is the first
thing a sign-in emits.

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

- **User cancels the Google dialog, or closes the browser popup** → back to
  onboarding, no error UI, and no redirect started behind their back (rule 5).
- **The browser blocks the popup** → a full-page redirect is started instead,
  automatically. The user is told nothing, because nothing has gone wrong: a
  redirect is not a popup and no blocker stops it.
- **The redirect comes back with no session** (`getRedirectResult` yields no
  user, `currentUser` is null, and this page wrote the `pending` note before
  leaving) → **partitioned third-party storage**, not a cancelled sign-in.
  `getCurrentUser` answers `signInStorageBlockedFailure`, and the note is
  rewritten `unusable` so the next blocked popup does not spend another page
  load discovering the same thing (rule 2). `AuthBloc` carries the verdict on
  as `Unauthenticated(blockedBy: SignInBlock.storage)`, and the onboarding page
  the redirect lands on opens on its sign-in slide with `signInStorageBlocked`
  above the button: which is the difference between this case and the identical
  screen a user who never signed in gets.
- **The redirect comes back throwing** (rejected auth event, mismatched nonce)
  with the note `pending` → the same diagnosis. The state was lost either way;
  this browser is only being louder about it.
- **The popup is blocked and the redirect is already known unusable** →
  `signInPopupBlockedFailure`. Distinct from every other failure precisely
  because it has a remedy the user can carry out: allow pop-ups and press the
  button again. Reaches the page as
  `Unauthenticated(blockedBy: SignInBlock.popup)` and draws
  `signInPopupBlocked`, not the red generic banner: nothing is broken, a
  browser setting is in the way.
- **The onboarding page mounts carrying a verdict** → it opens on the sign-in
  slide rather than on slide 1 of the tour. The advice is about one button,
  and the user has just been through the tour on the way out.
- **A verdict is followed by the `null` `authStateChanges` publishes on every
  signed-out boot** → ignored, so the diagnosis survives to be read (State
  Machine). Cleared by the next attempt, not by the boot that produced it.
- **A sign-in is cancelled after a blocked one** → plain `Unauthenticated`,
  and the notice disappears with it. The browser's old verdict is not what the
  page should be saying about a window the user just closed on purpose
  (rule 5).
- **Firebase refuses the popup for want of storage** (`web-storage-unsupported`)
  → reported immediately as `signInStorageBlockedFailure`, with no redirect
  attempted; the redirect would lose the same storage, silently.
- **The redirect fails to start** → the `pending` note is removed again, so the
  next boot does not deliver a verdict about a browser that never got the
  chance to prove anything.
- **The local store refuses to read or write the note** → the note is treated
  as absent. A `localStorage` hiccup is not evidence that a browser blocked a
  sign-in, and a diagnosis that cannot be persisted costs the diagnosis, never
  the sign-in.
- **User abandons the flow at Google's account chooser and comes back** →
  indistinguishable from the partitioned case and diagnosed the same way. Known
  and accepted (rule 2): the cost is one piece of advice: "allow pop-ups" , 
  that would have worked anyway.
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
`signInWithGoogle`, `signInFailed`, `signInStorageBlocked`,
`signInPopupBlocked`, `signOut`, `signOutConfirm`, `deleteAccount`,
`deleteAccountConfirm`, `deleteAccountWarning`.

Rule 2's two strings must each say what to **do**. Saying only that something
failed is `signInFailed`, and being told a thing failed with no next move is
the experience these exist to replace:

- `signInStorageBlocked`: this browser is dropping the storage the sign-in
  needs. There is no in-app remedy: the flow needs storage the browser
  partitions away: so the advice is another browser, or allowing cross-site
  cookies for this site;
- `signInPopupBlocked`: the sign-in window was blocked. Allow pop-ups for this
  site and press the button again.

They are picked by a `switch` on `SignInBlock` in `_SignInBlockedNotice`, with
no default branch, so a third obstacle has to be given words before it
compiles rather than reaching the user as an empty box. `AuthBloc` is what
turns the repository's markers into that enum (State Machine); no widget reads
a marker string.

---

## Testing

`test/features/auth/`:

- `AuthBloc`: check with and without a session, sign-in success, cancellation
  mapping to `Unauthenticated` (rule 5), sign-in failure, sign-out success and
  failure, `AuthUserChanged` from the stream. Rule 2's verdict is pinned on
  both legs, together with the three things that would quietly lose it again:
  `blockedBy` belonging to the state's `props`, the boot-time `null` not
  clearing it, and a later cancellation not leaving stale advice behind.
- `AuthRepository`: provisioning is idempotent (rule 3), Firestore outage yields
  a minimal profile (rule 4), sign-out clears local data (rule 7), self-heal on a
  missing profile (rule 8), stream error yields null (rule 9).
- Platform branches (web vs mobile sign-out, rule 6; popup vs plugin, rule 2)
  are covered by injecting a platform flag rather than by `kIsWeb` at the call
  site, so both paths are testable. A test binary is never a browser, so
  without the seam the whole web half would be unreachable code.

**Rule 2's web flow**, in `auth_repository_impl_test.dart`. Every case below is
pinned, because the one this rule exists for produces no exception, no log line
and no visible difference from a user who never signed in:

- popup first: a web sign-in calls `signInWithPopup` and never
  `signInWithRedirect`; an Android sign-in calls neither;
- a closed popup and a superseded popup request are cancellations, and neither
  starts a redirect;
- a blocked popup, and an environment with no popup at all, fall back to the
  redirect **and write the `pending` note before leaving**;
- `web-storage-unsupported` is reported as `signInStorageBlockedFailure` with no
  redirect attempted;
- `unauthorized-domain` is a plain failure: not a cancellation, not a storage
  verdict, and no redirect;
- **the empty return**: note `pending`, `getRedirectResult` yields no user,
  `currentUser` is null → `signInStorageBlockedFailure`, note rewritten
  `unusable`. Driven end to end through the real data source, since this is the
  bug the rule is about;
- a return that *threw* with the note `pending` is the same diagnosis;
- a return carrying a session clears the note and writes no verdict;
- no note and no session is still a plain `Right(null)`: the ordinary
  signed-out boot must not become a failure;
- a second blocked popup once the note reads `unusable` answers
  `signInPopupBlockedFailure` and starts no redirect;
- a redirect that failed to start removes the note again;
- a `LocalStore` that throws on read invents no diagnosis, and one that throws
  on write does not stop the redirect;
- the three markers are mutually distinguishable, which is the property the UI
  will switch on.

The redirect note's key and values are spelled out as literals in the test
rather than imported. It is a persisted key: a rename is a storage change that
strands the note a redirect already wrote, so it has to be a deliberate edit on
both sides.

Mocks in `test/harness/mocks.dart`: `MockFirebaseAuth`, `MockGoogleSignIn`,
`FakeFirebaseFirestore` (via `fake_cloud_firestore`), `MockLocalStore`.
`FirebaseAuthException` is never constructed in a test: its constructor is
`@protected`: so browser refusals are staged as
`FirebaseException(plugin: 'firebase_auth', code: …)`, which is what the data
source discriminates on anyway.

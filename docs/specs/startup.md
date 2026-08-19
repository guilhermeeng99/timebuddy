# Startup Spec

The gate between "the app process exists" and "a screen the user can trust". It
owns the splash route (`/startup`), initializes the timezone engine, waits for
auth to settle, runs the first sync, and tells the router where to go.

It has no domain or data layer: only `StartupCubit` and `StartupPage`. It
composes four collaborators.

---

## Responsibilities

1. Initialize `TimeZoneEngine` before **anything** reads a clock. Every other
   feature assumes tzdata is loaded (engine rule 1).
2. Load the city catalog into memory (locations.md).
3. Wait until auth has resolved (never render against `AuthInitial` /
   `AuthLoading`).
4. For authenticated users, run `SyncService.sync()` once, so the board and
   preferences are reconciled before any feature page mounts.
5. Drive the router redirect away from `/startup`:
   - `Authenticated` → `/grid`
   - `Unauthenticated` → `/onboarding`
6. Recover from failure with an in-page retry, not with a router escape.

---

## Collaborators

```dart
StartupCubit({
  required AuthBloc authBloc,
  required TimeZoneEngine engine,
  required CityCatalogRepository catalog,
  required SyncService syncService,
});
```

- `AuthBloc` is read-only: the cubit reads `.state` and listens to `.stream`. It
  never dispatches events.
- `TimeZoneEngine.initialize()` and `CityCatalogRepository.load()` run
  **concurrently** with the auth wait, since neither depends on a user.

---

## Business Rules

1. **Single-shot initialization.** `initialize()` is invoked exactly once by
   `StartupPage.initState`. Re-entry happens only through the error-state retry.

2. **Engine first, and unconditionally.** tzdata loading is not gated on auth: an
   unauthenticated user still lands on onboarding, which shows a live clock.
   Engine failure is fatal to the app and is the one hard error here.

3. **Auth-first for the user branch.** The cubit always emits
   `StartupLoading(progress: 0)` first, whatever `AuthBloc` currently holds, so
   the UI animates in consistently.

4. **Synchronous fast path.** If `AuthBloc.state` is already `Authenticated` or
   `Unauthenticated` when `initialize()` runs, no stream subscription is created.

5. **Stream slow path.** If the state is `AuthInitial` (or any non-terminal
   state), the cubit subscribes to `AuthBloc.stream` and waits for the first
   terminal event. `Authenticated` completes with true; `Unauthenticated` and
   `AuthError` complete with false. The subscription is cancelled before the wait
   returns, and every `complete()` is guarded by `!completer.isCompleted` so a
   duplicate terminal event does not throw.

6. **Sync only when authenticated.** The unauthenticated branch skips
   `SyncService.sync()` entirely.

7. **Sync failure is not fatal.** Unlike Financo (whose local cache would be
   empty without a sync), TimeBuddy has a usable local board. A failed sync emits
   `StartupAuthenticated` with `syncFailed: true`; the app opens on the local
   board and the passive offline indicator explains the rest (sync.md rule 4).
   The user is never held at a splash screen because Firestore is slow.

8. **Sync is time-boxed to 5 seconds.** Past that the cubit proceeds with local
   data and lets the sync finish in the background. A splash screen that can hang
   on a bad network is a broken app.

9. **Progress sentinels are asserted by tests.** `0.0` on entry, `0.3` before the
   engine and catalog complete, `0.6` before sync, `1.0` on a terminal state. The
   page derives its localized step label from these thresholds; the cubit carries
   no user-facing strings.

10. **Engine or catalog failure yields `StartupError`.** The raw exception is
    logged via `dart:developer log` and never surfaced; the page renders
    localized error copy with a retry.

---

## State Machine

```dart
sealed class StartupState extends Equatable
StartupInitial
StartupLoading({ progress: double })
StartupAuthenticated({ userId: String, syncFailed: bool })
StartupUnauthenticated
StartupError   // field-less: the page owns the localized copy
```

**Transitions:**

```
StartupInitial ──initialize()──→ StartupLoading(0.0)

StartupLoading(0.0) ──engine + catalog ok──→ StartupLoading(0.3)
                    ──engine or catalog threw──→ StartupError

StartupLoading(0.3) ──auth = Unauthenticated──→ StartupUnauthenticated
                    ──auth = AuthError────────→ StartupUnauthenticated  [treated as signed out]
                    ──auth = Authenticated────→ StartupLoading(0.6)

StartupLoading(0.6) ──sync ok───────────────→ StartupAuthenticated(userId, syncFailed: false)
                    ──sync failed or timed out→ StartupAuthenticated(userId, syncFailed: true)

StartupError ──retry──→ StartupLoading(0.0) → …
```

The cubit never returns to `StartupInitial`. Retry re-emits `StartupLoading`
directly.

---

## Page Behavior

- `initState` calls `context.read<StartupCubit>().initialize()` (fire and forget;
  the cubit owns the future).
- `BlocListener<StartupCubit, StartupState>`:
  - `StartupAuthenticated` → `context.go(AppRoutes.grid)`
  - `StartupUnauthenticated` → `context.go(AppRoutes.onboarding)`
- `BlocBuilder` renders the progress bar from `progress` (0 for initial, 1 for
  terminal non-error states) or the error block on `StartupError`.
- The brand mark sits above a live `ClockText` of the device zone. It costs
  nothing (the engine is already loaded by then) and it tells the user what kind
  of app this is before they sign in.

---

## Edge Cases

- **`AuthBloc` already terminal** → fast path, no subscription (rule 4).
- **`AuthError` while waiting** → treated as unauthenticated; the user reaches
  onboarding and can retry Google sign-in (auth.md).
- **Sync exceeds 5 seconds** → rule 8; the app opens and the sync completes in
  the background, with `BoardCubit.adoptFromSync` applying the result if it
  changes anything.
- **Sync fails outright** → rule 7.
- **Engine fails** (corrupt asset, unsupported platform) → `StartupError`. This
  is the only unrecoverable case, and the retry is genuinely the only option.
- **Catalog fails** → also `StartupError`, though the board would technically
  render; without a catalog the user cannot add a city, which makes an empty
  first-run app useless.
- **Cold start on web with a slow tzdata fetch** → the progress bar sits at 0.0
  to 0.3 for as long as it takes. tzdata is bundled, not fetched, so this is a
  disk read, not a network round trip.
- **Page torn down mid-load** (deep link redirect) → the cubit's stream
  subscription is cancelled as soon as the completer resolves; `close()` is safe
  at any point.

---

## Lifecycle & DI

Registered as `registerLazySingleton<StartupCubit>` and provided app-wide by
`TimeBuddyApp`'s `MultiBlocProvider` (`lib/app/di/injection_container.dart`,
`lib/app/app_widget.dart`). It holds no resources beyond one transient stream
subscription.

---

## i18n

Copy under `t.startup.*`: `tagline`, `stepLoadingData`, `stepCheckingAuth`,
`stepSyncing`, `stepReady`, `errorTitle`, `errorBody`, `errorRetry`.

The cubit carries no strings: `StartupLoading` exposes only `progress` and
`StartupError` is field-less, so every visible label is localized in the page.

---

## Testing

`test/features/startup/presentation/cubit/startup_cubit_test.dart`:

- Initial state.
- Engine and catalog are initialized before auth is read (rule 2).
- Fast path: already `Authenticated` → sync called → `StartupAuthenticated`.
- Fast path: already `Unauthenticated` → sync **not** called →
  `StartupUnauthenticated` (rule 6).
- Sync failure → `StartupAuthenticated(syncFailed: true)`, not `StartupError`
  (rule 7).
- Sync timeout at 5 seconds → same, with a `FakeAsync` clock (rule 8).
- Engine throw → `StartupError` (rule 10).
- Slow path: `AuthInitial` keeps the cubit loading until the stream emits a
  terminal state; duplicate terminal events do not throw (rule 5).
- Progress sentinels 0.0 / 0.3 / 0.6 are emitted in order (rule 9).

Mocks: `MockAuthBloc extends MockBloc<AuthEvent, AuthState>`, `MockSyncService`,
`MockTimeZoneEngine`, `MockCityCatalogRepository` from `test/harness/mocks.dart`.
No widget tests on the page: the routing side effects are exercised through the
cubit's terminal states.

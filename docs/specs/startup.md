# Startup Spec

The gate between "the app process exists" and "a screen the user can trust". It
owns the splash route (`/startup`), initializes the timezone engine, waits for
auth to settle, runs the first sync, and tells the router where to go.

It has no domain or data layer: only `StartupCubit` and `StartupPage`. It
composes four collaborators, plus one optional sink for the reconciled
preferences.

---

## Responsibilities

1. Initialize `TimeZoneEngine` before **anything** reads a clock. Every other
   feature assumes tzdata is loaded (engine rule 1).
2. Load the city catalog into memory (locations.md).
3. Wait until auth has resolved (never render against `AuthInitial` /
   `AuthLoading`).
4. For authenticated users, run `SyncService.sync()` once, so the board and
   preferences are reconciled before any feature page mounts.
5. Decide where the app opens, and let `StartupPage` act on it:
   - `StartupAuthenticated` → `context.go(AppRoutes.grid)`, which is `/`
   - `StartupUnauthenticated` → `context.go(AppRoutes.onboarding)`

   The router's own `redirect` is the guard, not the driver. It holds every
   other route at `/startup` until the cubit reaches a terminal state, sends a
   signed-out user to `/onboarding`, and bounces a signed-in one who lands on
   `/onboarding` back through `/startup` so the account's documents are
   reconciled before a page reads them. Leaving the splash is deliberately the
   page's `context.go`: the one place that knows startup finished is the one
   place that acts on it.
6. Recover from failure with an in-page retry, not with a router escape.
7. Hand the reconciled preferences to the singleton `PreferencesCubit`, which
   `TimeBuddyApp` loaded before the router existed. The board needs no
   equivalent — see Collaborators.

---

## Collaborators

```dart
StartupCubit({
  required AuthBloc authBloc,
  required TimeZoneEngine engine,
  required CityCatalogRepository catalog,
  required SyncService syncService,
  PreferencesCubit? preferencesCubit,
});
```

- `AuthBloc` is read-only: the cubit reads `.state` and listens to `.stream`. It
  never dispatches events. `AuthCheckRequested` is fired by `TimeBuddyApp`,
  because deciding *when* to check a session belongs to whoever owns the bloc,
  not to the screen waiting on the answer.
- `TimeZoneEngine.initialize()` and `CityCatalogRepository.load()` are started
  together and **concurrently** with the auth wait, since neither depends on a
  user. The engine is still started first: rule 2 makes tzdata unconditional.
- `PreferencesCubit` is the fifth collaborator and the only optional one. It is
  a sink, not a state-machine input: the singleton is loaded by `TimeBuddyApp`
  *before* the router exists, so without `adoptFromSync` its in-memory copy
  would outlive the document the sync just replaced. The app always passes it
  (`injection_container.dart`); a test that asserts on states alone leaves it
  out.
- **The board deliberately has no equivalent.** `SyncService` has already
  written the winning document to the side that lost, so by the time the cubit
  reaches a terminal state the *local* board document is the reconciled one.
  `AppShell` still owns `BoardCubit` and still loads it, and the shell is only
  built after the router leaves `/startup`, so that load reads the reconciled
  document. No second board owner, no adoption call, no write loop.

---

## Business Rules

1. **Single-shot initialization.** `initialize()` is invoked exactly once by
   `StartupPage.initState`. Re-entry happens only through the error-state
   retry, which is why the method re-announces `StartupLoading` and releases
   whatever the previous attempt left waiting before it starts anything.

2. **Engine first, and unconditionally.** tzdata loading is not gated on auth:
   an unauthenticated user still lands on onboarding, and the splash itself
   shows a live clock of the device zone the moment the engine is ready. Engine
   failure is fatal to the app and is the one hard error here. The catalog load
   is started in the same breath, and if the engine throws, that future is
   claimed with `ignore()` rather than dropped — an unlistened rejected future
   reaches the zone guard, so an engine failure would otherwise be followed by
   a crash.

3. **Auth-first for the user branch.** The cubit always emits
   `StartupLoading(progress: 0)` first, whatever `AuthBloc` currently holds, so
   the UI animates in consistently.

4. **Synchronous fast path.** If `AuthBloc.state` is already `Authenticated` or
   `Unauthenticated` when `initialize()` runs, no stream subscription is created.

5. **Stream slow path.** If the state is `AuthInitial` (or any non-terminal
   state, `AuthLoading` included), the cubit subscribes to `AuthBloc.stream` and
   waits for the first terminal event. The wait resolves to a **user id or
   `null`**, not to a boolean: `Authenticated` carries the id the sync needs,
   while `Unauthenticated` and `AuthError` both resolve to `null`. The
   subscription is dropped as the completer is settled, and every `complete()`
   is guarded by `isCompleted` so a duplicate terminal event — a sign-in landing
   while the session check is still running — does not throw. A stream that
   errors is treated as signed out and logged: a splash held forever by a failed
   bloc stream is unrecoverable, and "signed out" costs the user one tap.

6. **Sync only when authenticated.** The unauthenticated branch skips
   `SyncService.sync()` entirely.

7. **Sync failure is not fatal.** Unlike Financo (whose local cache would be
   empty without a sync), TimeBuddy has a usable local board. A failed sync emits
   `StartupAuthenticated` with `syncFailed: true`; the app opens on the local
   board and the passive offline indicator explains the rest (sync.md rule 4).
   The user is never held at a splash screen because Firestore is slow.

8. **Sync is time-boxed to 5 seconds** (`StartupCubit.syncTimeBox`). Past that
   the cubit proceeds with local data and lets the sync finish in the
   background: the pending future is timed *out*, never cancelled. A splash
   screen that can hang on a bad network is a broken app. The preferences
   adoption hangs off the sync itself rather than off the timed-out view of it,
   so a sync that lands late still reaches the cubit holding the stale copy
   instead of only replacing the document underneath it.

9. **Progress sentinels are asserted by tests,** and they are the cubit's whole
   vocabulary. `StartupLoading` carries exactly three values, declared on the
   state class so the page compares against the same constants:

   | Constant | Value | Emitted |
   |---|---|---|
   | `StartupLoading.startedProgress` | `0.0` | on entry to `initialize()`, before anything is attempted |
   | `StartupLoading.preparedProgress` | `0.3` | once the engine **and** the catalog are both ready, with auth next |
   | `StartupLoading.syncingProgress` | `0.6` | once auth resolved to a signed-in user, with the sync running |

   There is no `1.0` sentinel: the terminal states carry no progress at all,
   because they *are* the end. `StartupPage` maps every terminal state to `1`
   for the frame before the route changes, and derives its localized step label
   from the same thresholds, so the cubit still carries no user-facing
   strings.

10. **Engine or catalog failure yields `StartupError`.** The two fail
    differently and both are handled: the engine *throws*, while
    `CityCatalogRepository.load()` answers an `Either`, so its failure arrives
    as a value to unwrap rather than an exception to catch. Either way the raw
    reason is logged via `dart:developer log` and never surfaced; the page
    renders localized error copy with a retry.

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
                    ──engine threw / catalog answered Left──→ StartupError

StartupLoading(0.3) ──auth = Unauthenticated──→ StartupUnauthenticated
                    ──auth = AuthError────────→ StartupUnauthenticated  [treated as signed out]
                    ──auth stream errored─────→ StartupUnauthenticated  [treated as signed out]
                    ──auth = Authenticated────→ StartupLoading(0.6)

StartupLoading(0.6) ──sync ok───────────────→ StartupAuthenticated(userId, syncFailed: false)
                    ──sync Left, timed out or threw→ StartupAuthenticated(userId, syncFailed: true)

StartupError ──retry──→ StartupLoading(0.0) → …
```

The auth wait is *started* alongside the engine and the catalog and only
awaited once they are ready, so the `0.3` step is where its answer is read
rather than where it is asked for.

The cubit never returns to `StartupInitial`. Retry re-emits `StartupLoading`
directly. Every emit is guarded by `isClosed`, so a page torn down mid-load
cannot emit into a closed cubit.

---

## Page Behavior

- `initState` calls `context.read<StartupCubit>().initialize()` (fire and forget;
  the cubit owns the future).
- `BlocListener<StartupCubit, StartupState>`:
  - `StartupAuthenticated` → `context.go(AppRoutes.grid)`
  - `StartupUnauthenticated` → `context.go(AppRoutes.onboarding)`
- `BlocBuilder` renders the progress bar from `progress`, mapping
  `StartupInitial` to `0` and **every** terminal state to `1`, or the error
  block on `StartupError`.
- The step label is derived from the same sentinels rule 9 declares, not from a
  second state field: `>= 1` is *ready*, `>= 0.6` *syncing*, `>= 0.3` *checking
  your account*, and below that *loading time zone data*. Two enumerations of
  one set of steps would be one edit away from a label that lies.
- The brand mark sits above a live `ClockText` of the device zone, rendered only
  once `progress >= 0.3`: before that the engine has not loaded and every answer
  it could give would be wrong (rule 2). A fixed-height box holds the space in
  the meantime, so the layout does not step when the zone resolves. It costs
  nothing and it tells the user what kind of app this is before they sign in.

---

## Edge Cases

- **`AuthBloc` already terminal** → fast path, no subscription (rule 4).
- **`AuthError` while waiting** → treated as unauthenticated; the user reaches
  onboarding and can retry Google sign-in (auth.md).
- **Sync exceeds 5 seconds** → rule 8; the app opens on the local board and
  the sync completes behind it. When it lands, `SyncService` has already written
  the winner to the local document and the reconciled preferences are handed to
  `PreferencesCubit.adoptFromSync`. Nothing re-routes: the terminal state the
  cubit already emitted stands, so a late sync cannot move the user a second
  time.
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
  subscription is cancelled as soon as the completer resolves, and `close()`
  both cancels the subscription and settles the pending wait, in that order:
  cancelling alone would leave `initialize()` suspended on a completer nobody
  can finish. `close()` is safe at any point.

---

## Lifecycle & DI

Registered as `registerLazySingleton<StartupCubit>` and provided app-wide by
`TimeBuddyApp`'s `MultiBlocProvider` with `.value`, because it is a `GetIt`
singleton and the provider must not adopt it and close it with the widget
(`lib/app/di/injection_container.dart`, `lib/app/app_widget.dart`). A singleton
rather than a page-scoped cubit because the router's `redirect` reads its state
on every navigation to decide whether startup has answered yet. It holds no
resources beyond one transient stream subscription.

---

## i18n

Copy under `t.startup.*`: `tagline`, `stepLoadingData`, `stepCheckingAuth`,
`stepSyncing`, `stepReady`, `errorTitle`, `errorBody`, `errorRetry`.

The cubit carries no strings: `StartupLoading` exposes only `progress` and
`StartupError` is field-less, so every visible label is localized in the page.

---

## Testing

`test/features/startup/presentation/cubit/startup_cubit_test.dart`:

- Initial state, before `initialize()` has attempted anything.
- **Ordering**: the engine and the catalog are *started* before auth is read
  (rule 2), asserted against a recorded call order rather than a bare `verify`,
  which could only prove that all three were called.
- **Progress**: the loading states carry `0.0`, `0.3` and `0.6`, in that order
  (rule 9).
- **Fast path**: already `Authenticated` → sync called →
  `StartupAuthenticated`, with `AuthBloc.stream` never touched (rule 4); already
  `Unauthenticated` → sync **not** called → `StartupUnauthenticated`
  (rule 6); `AuthError` read as signed out, also without a sync.
- **Slow path**: `AuthInitial` keeps the cubit loading until the stream emits a
  terminal state, and a second terminal event does not throw (rule 5).
- **The first sync**: a `Left` → `StartupAuthenticated(syncFailed: true)`,
  never `StartupError` (rule 7); a sync that outruns the time box → the same,
  and the result that lands afterwards does not move the app a second time
  (rule 8).
- **The unrecoverable case**: an engine throw and a catalog `Left` both stop at
  `StartupError` (rule 10), and a retry after one starts the sequence over
  (rule 1).

The time-box case is a `testWidgets` test rather than a plain one, so the fake
async that `testWidgets` runs its body in owns the five second timer: the budget
costs no real time and cannot flake. Its stream subscription is cancelled with
`unawaited`, because awaiting the cancel of a broadcast subscription resumes the
body in the root zone and strands every microtask the fake async still owns.

Mocks: `_MockAuthBloc extends MockBloc<AuthEvent, AuthState>`,
`_MockSyncService` and `_MockCityCatalogRepository` are declared in the test
file itself; only `MockTimeZoneEngine` comes from `test/harness/mocks.dart`. The
cubit is built **without** `preferencesCubit`, which is exactly why that
parameter is optional. No widget tests on the page: the routing side effects are
exercised through the cubit's terminal states.

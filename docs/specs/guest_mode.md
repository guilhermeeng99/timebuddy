# Guest Mode Spec

A visitor can use the whole app without an account. Sign-in exists to make the
board durable and to carry it between devices, so it is an offer, not a gate.

This spec reverses [auth.md](auth.md) rule 1 and the "Guest mode (no account)"
entry in [roadmap.md](../roadmap.md)'s deferred decisions. What made it
expensive there was the local-to-cloud migration path; the migration rule this
spec picks is deliberately the cheapest one that never surprises a returning
user, and is written down in rule 6 so it is not re-argued.

---

## Entity Contract

There is no entity, and that is the design. "Guest" is a fact about **this
device**, not about a user and not about a document:

```dart
GuestSession {
  isGuest:           bool  (persisted, StorageKeys.guest)
  adoptionAttempted: bool  (in-memory, reset every process)
}
```

`GuestSession` is a `ChangeNotifier` over [`LocalStore`](../../lib/core/storage/local_store.dart)
registered as a singleton, and it is what `AppRouter` merges into its
`refreshListenable` alongside `AuthBloc`.

**It is deliberately not a field of `PreferencesEntity`.** Preferences is a
*synced* document, so a guest flag living there would be pushed to Firestore and
tell every other device that this account is a guest, which is a contradiction.

**It is deliberately not a sixth `AuthState`.** `AuthState` answers "does
Firebase have a session", and for a guest the honest answer stays
`Unauthenticated`. A `Guest` state would be one `AuthBloc` invents and the
repository never reports, and `auth_state.dart` already argues this exact
trade-off for `SignInBlock` and picks a field over a state.

**It is persisted rather than held in memory.** Web reloads and deep links
re-run the router's redirect against a process that has never heard of this
visitor; an in-memory flag would bounce a guest to onboarding on every refresh
and on every deep link to `/#/clocks`.

---

## Business Rules

1. **A guest uses the entire app.** Grid, world clock, converter,
   board mutations and every preference work exactly as they do for a signed-in
   user, because all of them already read and write the local documents and
   none of them takes a `userId`. Nothing is disabled, watermarked or
   trial-limited.

2. **Nothing a guest writes leaves the device.** `SyncCoordinator` already
   no-ops without a session ([sync.md](sync.md) rule 3), and a guest write must
   never set a dirty flag: a flag set with no owner would be flushed into
   whichever account signs in next, handing one person's cities to another.

3. **Guest mode is entered explicitly, once.** The only entry point is the
   "continue without an account" control on `OnboardingPage`, which is
   available on **every** slide, including the last one — a visitor whose
   browser blocked the Google popup lands on that slide and is precisely the
   person who most needs the way past it.

   The control writes the marker and **then navigates to the grid itself.**
   That is not a redundant second owner of the routing rule: the redirect is a
   *guard*, it says which routes a visitor may not be on, and rule 5 below
   deliberately lets a guest stay on `/onboarding` so the tour remains readable.
   So the marker alone moves nobody. `StartupPage` works under the same
   division — the page that knows a decision was made is the page that acts
   on it.

4. **Startup's answer is unchanged; only its destination moves.**
   `StartupState` gains no variant. `StartupUnauthenticated` still means "auth
   resolved to nobody"; `StartupPage` sends it to the grid when
   `GuestSession.isGuest` and to onboarding otherwise. Adding no state is what
   keeps `AppRouter._startupResolved`'s two-state allowlist correct — a third
   non-terminal state would silently pin the app at `/startup`.

5. **The router's gate is narrowed, not removed.** A signed-out visitor who is
   not a guest still lands on onboarding. See the State Machine below.

6. **At sign-in, the account wins whenever it already has documents.** The
   guest's local board and preferences are adopted upward **only into an
   account that has none**. This is the migration rule:

   | Remote document | Outcome |
   | --- | --- |
   | absent | the guest's document is uploaded (ordinary provisioning) |
   | present | the account's document replaces the guest's local copy |

   The asymmetry is the point. Letting the guest win a populated account would
   destroy a board that other devices also hold and that nothing can recover;
   losing the guest's direction costs only data that never left this device,
   and the person who just chose to sign in is asking for their account.

   **The adopting sync bypasses the conflict ladder entirely**
   ([sync.md](sync.md) rule 5). Two revision counters produced under two
   identities are not comparable: a guest who added six cities carries revision
   6 and would beat a real account at revision 3 on rung 2, replacing it
   wholesale.

7. **Adoption runs before the shell is rebuilt.** It is the startup sync, and
   it is **exempt from [startup.md](startup.md) rule 8's five-second box.**
   `AppShell` builds `BoardCubit` the moment the router leaves `/startup`, and
   a board loaded from a document adoption has not finished writing is the
   stale one — for a guest that means their own cities briefly reappear over
   the account's.

8. **A failed adoption does not clear the marker.** `GuestSession.leave()` runs
   only when the adopting sync lands. The visitor stays a guest, keeps working,
   and the next launch retries. `adoptionAttempted` is what stops the router
   retrying it in a loop inside the same process.

9. **Sign-out clears the device and returns to guest mode.**
   [auth.md](auth.md) rule 7's `clearAll()` stays exactly as it is — leaving one
   account's cities on a shared browser is a privacy leak — and the guest marker
   is written back **after** the wipe, in that order, because `clearAll()`
   removes it too. The user lands in the app on an empty board rather than on
   the onboarding tour, which they have already seen.

10. **Sign-in is offered where the account already lives.** Settings gains the
    Account group the spec has always listed, carrying the identity row through
    to `/profile`; for a guest it reads as an offer, not as a broken row. This
    is also what finally gives `/profile` an in-app entry point.

---

## Repository Contract

No repository. `GuestSession` talks to `LocalStore` directly, for the same
reason `LocalStore` itself has none: one boolean under one key, read whole,
never queried.

```dart
class GuestSession extends ChangeNotifier {
  bool get isGuest;
  bool adoptionAttempted;      // in-memory, one process
  Future<void> restore();      // hydrate before the first redirect
  Future<void> enter();
  Future<void> leave();
}
```

`restore()` is awaited inside `configureDependencies()`, not fired and
forgotten. The first `_redirect` runs before the first frame, and a guest whose
marker had not landed yet would be sent to onboarding.

**A refused read keeps the value already in memory**, and does not notify.
`restore()` catches `on Object` — not `StorageException` alone, because a
platform channel can fail in ways the store never wrapped — and returns without
touching `_isGuest`. On the path that matters, the one `configureDependencies()`
runs before the first redirect, that value is still the initial `false`, so the
effect is the documented "a device that cannot read cannot be trusted to have
stored consent, and onboarding is a recoverable place to be wrong". Stated as
"keeps the previous value" rather than "sets false" because a *second*
`restore()` after `enter()` would not un-guest the visitor, and a reader
building on the shorter sentence would get that wrong.

`enter()` and `leave()` swallow a refused write for the mirror-image reason:
the in-memory value is what the router reads, so a browser in private mode
still gets to use the app — it just meets onboarding again next launch. Both
await the store *before* notifying, so a listener that reacts by navigating
cannot outrun the marker it depends on.

---

## State Machine

`AppRouter._redirect`, in order. Rules 1 and 4 are unchanged from
[startup.md](startup.md); 2 is narrowed and 3 is new.

```
1. startup not resolved        -> /startup                     (unchanged)
2. !Authenticated && !isGuest  -> /onboarding                   (narrowed)
3. isGuest && Authenticated
     && !adoptionAttempted     -> /startup                           (new)
4. on /onboarding && Authenticated -> /startup                 (unchanged)
```

Rule 2 keeps the broad `is! Authenticated`, so it still covers `AuthInitial`
and `AuthError`. Rule 3 tests the narrow `is Authenticated`, so a guest who
starts a sign-in from inside the app is never ejected mid-flow while the Google
dialog is open.

Rule 3 replaces rule 4 as the thing that forces a fresh session through the
first sync. Rule 4 stays for the visitor who signs in *from* onboarding, where
`isGuest` is false and rule 3 cannot fire.

Transitions of `GuestSession` itself:

```
absent --(onboarding: continue without an account)--> guest
guest  --(sign-in, adopting sync landed)------------> signed in
guest  --(sign-in, adopting sync failed)------------> guest, retried next launch
signed in --(sign-out: clearAll, then enter)--------> guest, empty board
```

---

## Edge Cases

- **A guest deep-links to `/#/clocks`.** Works. The marker is on disk and
  hydrated before the router's first pass; rule 1 still holds them at the
  splash until tzdata is loaded, so no grid is ever built against an
  uninitialized engine.

- **A guest signs in on an account that has documents, offline.** The remote
  read fails, the sync answers `Left`, `leave()` is not called, and they carry
  on as a signed-in guest on their own board. The next launch retries the
  adoption. Their local board is not destroyed by a sync that could not read
  what was supposed to replace it.

- **A guest's board is at revision 6 and the account's at revision 3.** The
  account wins. This is rule 6 and it is the reason adoption does not use the
  ladder.

- **The adopting sync times out.** It cannot: rule 7 exempts it from the time
  box. A slow first sign-in shows the splash longer, which is honest.

- **Sign-out fails.** The session survives, so `clearAll()` never runs and the
  marker is never written — [auth.md](auth.md)'s existing rule. The user is
  still signed in and is told so.

- **A guest changes preferences, then signs in to an account with its own
  preferences.** The account's preferences win, `PreferencesCubit.adoptFromSync`
  replaces the singleton's in-memory copy, and the theme repaints during the
  splash rather than after the grid is drawn.

- **Two guests share a browser.** They share a board, because a guest has no
  identity to key one by. The only remedy is signing in, which is what the
  Account group in Settings offers.

---

## i18n

Guest mode added four keys, all under `t.auth.*` rather than a namespace of its
own — a guest is a state of the account offer, not a feature with copy of its
own, and a `t.guest.*` namespace would put "continue without an account" one
scroll away from the button it sits beside:

| Key | Where |
|---|---|
| `continueAsGuest` | the "continue without an account" control on every onboarding slide (rule 3) |
| `continueAsGuestHint` | the `Tooltip` wrapping that control, so the consequence of skipping the account is available without the button label having to carry it |
| `guestTitle` | the identity block on `/profile` when there is no session (rule 10) |
| `guestBody` | the line under it, and the same string again as the settings identity row's subtitle — one sentence, not two that drift |

`t.auth.signInToSave` was written for a prompt that would offer the account at
the moment a guest's data is most at risk. It has **no call site**: see
[auth.md](auth.md), i18n.

Nothing here is conditional on a *feature*: rule 1 means no screen renders
different copy for a guest, so there are no `t.<feature>.guest*` strings and
there must not be.

---

## Testing

`test/core/session/guest_session_test.dart`, 11 tests over the whole object.
`GuestSession` is tested directly against a `MockLocalStore` rather than
through a repository, because there is no repository (see Repository Contract):

- the initial value, before anything is read;
- **`restore`**: the marker is read from the device; an absent key means no
  guest session; a refused read leaves the visitor a non-guest; and an
  unchanged value does not notify — a `ChangeNotifier` wired into
  `AppRouter.refreshListenable` that notifies on every hydrate would re-run the
  redirect for nothing on every boot;
- **`enter`**: it writes the marker and notifies; it is idempotent; and it
  still enters when the device refuses the write (private mode);
- **`leave`**: it removes the marker and notifies, and does nothing when there
  was no guest session;
- `adoptionAttempted` does not survive a `restore`, which is rule 8's
  loop-breaker being in-memory on purpose.

The two rules that span objects are pinned where they act, not here:
adoption's three behaviours in
`test/features/startup/presentation/cubit/startup_cubit_test.dart`
(`group('adopting a guest who signed in')`, rules 6-8), and the onboarding
escape in
`test/features/auth/presentation/pages/onboarding_page_test.dart` (rule 3).

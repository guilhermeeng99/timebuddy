# Sync & Storage Spec

How the same account shows the same board on the phone and in the browser,
without a local database.

The reference project (Financo) uses Drift as a local SQLite cache and syncs a
dozen collections. TimeBuddy has **two documents**, both under 10 KB, both always
read whole. This spec exists to keep it that way.

---

## Storage model

| Layer | Technology | Holds |
|---|---|---|
| Local | `shared_preferences` | Two JSON strings, `timebuddy.board.v1` and `timebuddy.preferences.v1`, plus the two dirty flags `timebuddy.dirty.board` and `timebuddy.dirty.preferences` |
| Remote | Firestore | `users/{userId}/settings/board` and `users/{userId}/settings/preferences`, under the profile document `users/{userId}` that [auth.md](auth.md) owns |

The local keys are declared once in `StorageKeys` and the remote path segments
once in `SyncKeys`, for one shared reason: a segment retyped at a second call
site is how a build starts writing `users/{id}/setting/board` and reads an empty
account forever.

**The JSON shape is identical on both sides.** One `BoardModel.toJson()` feeds
both writers and one `fromJson` reads both; the same holds for
`PreferencesModel`. The only difference is how timestamps encode, and the seam
is one function wide in each direction:

- **Writing.** The models emit ISO-8601 strings for both stores.
  `FirestoreRemoteSettingsDataSource` re-encodes the named fields `updatedAt`
  and `addedAt` into `Timestamp`s on the way out, recursively, so the board's
  `locations[].addedAt` costs no extra code. Named rather than sniffed: a rule
  like "every key ending in `At`" would silently convert the first future field
  that merely looks like a date, and that failure is a wrong value in the store
  rather than a crash. A string that will not parse is passed through exactly as
  it is, so it reads back as the epoch instead of being invented into a date
  that could win a tie.
- **Reading.** The datasource unwraps every `Timestamp` into a millisecond
  epoch int, recursively again, and `timestampFromJson`
  (`saved_location_model.dart`, shared by both timestamp fields) accepts that
  int *and* an ISO-8601 string. Anything else falls back to the epoch, never to
  "now": a timestamp nobody can read must lose every tie it enters instead of
  winning them by looking freshly written.

The conversion lives in the datasource rather than in the models because
`Timestamp` is a `cloud_firestore` type and those models are shared with
`shared_preferences`, which never sees one. A document copied from one store to
the other therefore still needs no conversion.

### The Firestore boundary

`RemoteSettingsDataSource` is the whole of it, and small on purpose: four typed
methods for the two settings documents, two untyped ones for the profile.

```dart
abstract class RemoteSettingsDataSource {
  Future<BoardModel?> readBoard({
    required String userId,
    required String homeZoneIdFallback,
  });
  Future<void> writeBoard({required String userId, required BoardModel board});

  Future<PreferencesModel?> readPreferences({required String userId});
  Future<void> writePreferences({
    required String userId,
    required PreferencesModel preferences,
  });

  Future<Map<String, dynamic>?> readProfile({required String userId});
  Future<void> writeProfile({
    required String userId,
    required Map<String, dynamic> profile,
  });
}
```

- **A missing document is `null`, not an exception.** Absence is a value on the
  conflict ladder (`SyncKeys.missingRevision`, `-1`), not a failure.
- **A document whose `revision` is not a number is scored `-1` as well.**
  `BoardModel.fromJson` degrades an unreadable `revision` to `0`, which is right
  for local storage and wrong here: `0` ties with a fresh local document, and a
  tie goes to the remote by rule 5's last rung, so a corrupt server copy would
  overwrite the user's first board. The datasource re-stamps the parsed model
  with `-1` so it loses instead. Every other malformed field is still salvaged
  by the defensive parsers ([locations.md](locations.md), Model Serialization);
  only `revision` gets this treatment, because only `revision` decides who wins.
- **`homeZoneIdFallback` is the local board's home zone, not the device's.**
  Both documents belong to one account, so the user's own reference zone is the
  better guess for a remote document that is missing the field, and the device's
  would quietly move every offset on the board the first time they travel.
- **Writes replace; only the profile merges.** The document is the unit of
  reconciliation (rule 6), so a location the user deleted has to disappear from
  the server copy — a merge write would resurrect it on the next read. The
  profile merges because provisioning must be idempotent ([auth.md](auth.md)
  rule 3): a retry after a partial failure completes the document instead of
  blanking fields another client already wrote.
- **The profile is deliberately untyped here.** `UserModel` lives in the auth
  feature and owns the `Timestamp` mapping of `createdAt`; translating it in
  `core/` would put a second parser on one document, which is the duplication
  the typed methods exist to avoid. The map is handed over as Firestore decoded
  it, `Timestamp` values included.
- **Every failure leaves as a `ServerException`,** so the layer above catches
  one type. `unavailable` and `deadline-exceeded` become
  `RemoteUnavailableException`, a subtype, and that distinction exists for
  exactly one decision: whether the passive indicator says *offline* (waiting
  fixes it) or *error* (`permission-denied`, a revoked account — waiting never
  will).

> **Why not Drift.** There is no query. There is no join. There is no partial
> read. The largest realistic payload is 20 locations plus a preferences map,
> roughly 3 KB of JSON. Drift would add `build_runner` to the build, a schema
> migration surface to maintain, and a WASM worker plus asset pinning to the web
> deploy. All of that buys indexed queries the app will never issue.

---

## Business Rules

1. **Local is the read path. Remote is the durability path.** Every screen reads
   from `shared_preferences` and renders immediately. Firestore is consulted on
   startup and on explicit refresh, never in the critical path of a frame.

2. **Writes are local-first, then remote.** A cubit mutates its document, bumps
   `revision`, stamps `updatedAt` and calls `repository.save`, which persists to
   `shared_preferences`. That return **is** the operation's success; the remote
   write is fired after it and its failure does not fail it. The repositories
   know nothing about Firestore and neither do the cubits: the push that follows
   an ordinary local write belongs to a coordinator sitting above them
   (`SyncCoordinator`), so "save the board" stays one call at the call site and
   the remote half stays in one place. Reconciliation writes obey the same
   order for the same reason (`SyncServiceImpl._apply`): a refused *local* write
   ends the sync because it breaks the read path, a refused *remote* one does
   not.

3. **A failed remote write sets a dirty flag**
   (`timebuddy.dirty.board`, `timebuddy.dirty.preferences`) rather than
   retrying in a loop, which would only spin against a radio that is off. The
   flags are flushed on `AppLifecycleState.resumed` (`flushDirty`), and a
   successful sync *is* a flush: each flag is rewritten while its document's
   winner is written, so what stays marked is exactly what the server was not
   given. There is deliberately no second pass over the flags at the end of a
   sync — it could only re-upload a document the ladder had just retired,
   undoing the copy that won.

   The flag is an optimisation, not the durability mechanism. If it is lost the
   revision ladder still uploads the newer document on the next sync, which is
   why nothing in `SyncDirtyFlags` fails loudly, including a local store that
   refuses to write the flag itself.

4. **A failed remote write is never shown as an error.** The user reordered two
   cities; a red banner about Firestore is noise. The sync state is surfaced
   passively and in exactly one place: `SyncStatusRow` on the profile page,
   showing synced / syncing / offline / error as an icon and a line of text.
   Nothing modal, nothing that asks the user to act, and `error` renders in the
   *warning* token rather than the error one — the app is working, its backup
   is not, and that is not the same news. The status stream replays its last
   value to a new listener, because the indicator mounts long after the startup
   sync that found the app offline and would otherwise show "synced" over a
   failed session.

   Caveat as of M3: nothing navigates to `/profile`. The sidebar has a profile
   slot and `AppShell` passes nothing into it, and the settings page still has
   no Account group, so the only way to the indicator today is typing the URL.
   The rule is implemented; its entry point is not.

5. **Conflicts resolve by `revision`, then by `updatedAt`.** Every write
   increments `revision` by one and stamps `updatedAt`. On sync:
   - remote `revision` > local → remote wins, local is overwritten
   - local `revision` > remote → local wins, remote is overwritten
   - equal revisions and different content → the later `updatedAt` wins
   - equal revisions and equal `updatedAt` → remote wins (arbitrary but stable)

6. **There is no field-level merge.** The document is the unit. Merging two
   divergent location lists would need per-row identity, tombstones and ordering
   rules, which is a synchronization engine, not a world clock. The chosen
   trade-off: a user who edits the board on two devices while offline loses one
   set of edits, and is told which device won.

7. **`revision` is monotonic per document, not global.** Board and preferences
   diverge independently, so a preferences change never forces a board write.

8. **A clock-skewed device cannot win a conflict it should lose,** because
   `revision` is compared before `updatedAt`. `updatedAt` only breaks ties, and
   the remote value is a server timestamp. This is why rule 5 checks revision
   first.

9. **Sync is never automatic on a timer.** It runs at startup, on explicit pull
   to refresh, and on resume. A world clock does not need a live listener, and a
   Firestore snapshot listener on two documents per session would be cost with no
   benefit.

10. **Local data is cleared on sign-out** (auth rule 7) and on account deletion.
    The dirty flags are cleared with it: a pending write for an account that just
    signed out must not be flushed into the next session, which would hand one
    user's cities to the next.

    Two clearings exist and they are not the same call. The auth repository
    wipes the whole store (`LocalStore.clearAll()`) on sign-out;
    `SyncService.clearLocalData()` removes the two documents and the two flags
    **by name**, so a key belonging to the device rather than to the account —
    a "has seen the onboarding" marker, say — survives. Nothing calls the named
    version yet, so the two behave identically today; the moment a device-owned
    key exists, sign-out has to move to it.

11. **The storage keys carry a version suffix** (`.v1`). A future breaking change
    to the JSON shape writes `.v2` and leaves `.v1` untouched, so a downgrade
    does not read a shape it cannot parse. The migration reads `.v1` once,
    writes `.v2`, and never writes `.v1` again.

---

## Contract

```dart
abstract class LocalStore {
  Future<String?> readRaw(String key);
  Future<void> writeRaw(String key, String value);
  Future<void> remove(String key);
  Future<void> clearAll();
}

abstract class SyncService {
  /// Pulls both documents, reconciles them against local (rule 5), writes the
  /// winners to both sides, and flushes any dirty documents.
  /// Returns the reconciled board so callers do not re-read.
  Future<Either<Failure, SyncOutcome>> sync({required String userId});

  /// Flushes only the documents marked dirty. Called on resume.
  Future<void> flushDirty({required String userId});

  /// Wipes local state. Called on sign-out and account deletion.
  Future<void> clearLocalData();

  /// Passive status for the UI indicator, with the last value replayed to
  /// every new listener (rule 4).
  Stream<SyncStatus> get status;   // idle | syncing | offline | error
}

class SyncOutcome extends Equatable {
  final BoardEntity board;
  final PreferencesEntity preferences;
  final ConflictWinner boardWinner;        // local | remote | none
  final ConflictWinner preferencesWinner;
}
```

`SyncServiceImpl` holds no `Clock`, and that is a rule rather than an omission:
reconciliation never stamps a new `updatedAt` and never bumps a `revision`. The
winner is written to the losing side exactly as it was, so a sync cannot inflate
the numbers it just compared and manufacture a conflict for the next one.

`SyncOutcome` reports which side won so the UI can tell the user "your board was
updated from another device" once, rather than silently swapping their list.

---

## Provisioning

On first sign-in (auth rule 3) neither remote document exists.
`SyncService.sync` treats a missing remote document as `revision: -1`, so local
always wins and is written up. If local is also absent, defaults are created:

- Board: `homeZoneId` from `deviceZoneId()`, empty `locations`, `revision: 0`.
- Preferences: the defaults in [preferences.md](preferences.md), `revision: 0`.

This makes provisioning a special case of reconciliation rather than its own code
path. Both repository loads seed **and persist** their defaults when nothing is
stored, so the ladder always has a local document to compare against.
`SyncServiceImpl` therefore asks only two questions outside the two documents:
`TimeZoneEngine.deviceZone()` for the board's fallback home zone, and the device
`Locale` it was constructed with, which is what seeded preferences derive
`hourFormat` and `weekStartsOn` from ([preferences.md](preferences.md) rule 2).

---

## Sync flow

```
app start
  → read local board + preferences        (instant, app renders)
  → StartupCubit calls SyncService.sync()
      → fetch both remote documents        (2 reads)
      → reconcile per rule 5
      → write each winner to the side that lost, and
        rewrite that document's dirty flag while doing it
      → emit SyncOutcome
  → the reconciled documents are already on disk, so BoardCubit reads them
    when AppShell loads it; PreferencesCubit, loaded before the router
    exists, is handed the copy through adoptFromSync (startup.md)
```

On resume:

```
AppLifecycleState.resumed
  → flushDirty()                           (0 reads unless something is dirty)
  → if last sync > 15 minutes ago → sync()
```

The second line of the resume block is contract, not yet wired: nothing records
a last-sync instant today, so a resume flushes dirty documents and stops there.
Rule 9's third trigger, an explicit refresh, has no control on any page yet
either.

---

## Edge Cases

- **First run, no network** → local defaults are created, both documents are
  marked dirty, and the app is fully usable. The first successful sync uploads
  them.
- **Signed in on device B while device A is offline with edits** → on A's next
  sync, whichever has the higher `revision` wins wholesale (rule 6). The user is
  told which one won via `SyncOutcome`.
- **Remote document exists but is malformed** → the defensive parser
  ([locations.md](locations.md), Model Serialization) salvages what it can.
  `revision` is the exception: `RemoteSettingsDataSource` checks it is a `num`
  before trusting the parsed model and re-stamps it with `-1` when it is not, so
  local wins and the malformed remote is overwritten rather than tying at `0`
  and winning the tie-break.
- **`shared_preferences` write fails** (full disk, restricted profile) → this
  **is** surfaced, unlike a remote failure, because it breaks the read path
  every screen depends on. What ships today: the optimistic mutation is rolled
  back and its failure handed once to the caller that asked for it
  ([locations.md](locations.md)), and a local write refused during
  reconciliation ends the sync with a `Left` and `SyncStatus.error`. The
  memory-only session with a persistent banner is still contract rather than
  code.
- **Firestore permission denied** (rules misconfigured, or a revoked account) →
  `SyncStatus.error`, local keeps working, and the profile page shows the reason.
- **User signs out with dirty documents** → the pending write is dropped with
  the flag. Sign-out clears local data unconditionally and attempts no final
  flush, and if the clearing itself fails it is swallowed rather than failing
  the sign-out — a UI left signed in against a Firebase that signed out is worse
  than a stale local board, which the next sign-in reconciles. Documented and
  accepted: the alternative is holding another account's data on the device
  after they left.
- **Clock skew** → rule 8.
- **Two tabs of the web app open** → each is an independent client with its own
  local storage view. `shared_preferences` on web is `localStorage`, which is
  shared between tabs but not reactive, so tab B keeps its in-memory state until
  its next sync. Accepted; the revision rule makes the outcome deterministic.

---

## Testing

`test/core/sync/sync_service_impl_test.dart`. The Firestore boundary is mocked
at `RemoteSettingsDataSource`, so "the document is absent", "the document is
malformed" and "the radio is off" are three stubs rather than three emulator
setups; `fake_cloud_firestore` is used one layer down, in the auth repository's
tests, where the Firestore call itself is the thing under test. Five groups:

- **The conflict ladder** (rule 5): a higher remote revision wins and overwrites
  local; a higher local revision wins and is uploaded; equal revisions are
  broken by the later `updatedAt`, tested in both directions; a full tie goes to
  the remote; two sides that already agree write to neither
  (`ConflictWinner.none`); a clock-skewed device still loses on revision (rule
  8); and the two documents are reconciled independently of each other (rule 7).
- **Provisioning**: a missing remote document counts as revision `-1`, and so
  does a malformed one.
- **Dirty flags**: a failed remote write still returns success and marks the
  document (rules 2 and 3); a landed write retires a stale flag; `flushDirty`
  uploads the marked document and clears it; a second `flushDirty` is a no-op;
  a flush that fails again keeps the flag set for the next attempt.
- **`clearLocalData`**: removes both documents and both dirty flags (rule 10),
  and leaves keys that belong to the device rather than to the account.
- **The status stream**: idle → syncing → idle around a sync that lands;
  `offline` when the pull cannot reach Firestore; `error` when the remote
  refuses for good; and the last value replayed to a listener that mounts after
  the fact (rule 4).

`test/core/storage/local_store_test.dart` uses
`SharedPreferences.setMockInitialValues` and covers the key-version rule (11),
including its deliberate asymmetry: the dirty flags are *unversioned*, because
they carry no JSON shape and there is nothing for a suffix to protect.

Two gaps, named rather than left to be assumed covered:
`FirestoreRemoteSettingsDataSource` has no test file of its own, so the
timestamp re-encoding and the `FirebaseException` code mapping are exercised
only through the mocked interface; and no test refuses a *local* write during
reconciliation, so the `Left` that rule 2's local-first ordering exists to
produce is unasserted.

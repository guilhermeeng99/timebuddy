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
| Local | `shared_preferences` | Two JSON strings: `timebuddy.board.v1`, `timebuddy.preferences.v1` |
| Remote | Firestore | `users/{userId}/settings/board`, `users/{userId}/settings/preferences` |

**The JSON shape is identical on both sides.** One `BoardModel.toJson()` feeds
both writers, and one `fromJson` reads both. The only difference is how
timestamps encode: Firestore uses `Timestamp`, `shared_preferences` uses an
ISO-8601 string. Both parsers accept both, so a document copied from one to the
other never needs conversion.

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

2. **Writes are local-first, then remote.** `saveBoard` persists locally and
   returns success as soon as that succeeds. The remote write is fired after and
   its failure does not fail the operation.

3. **A failed remote write sets a dirty flag**
   (`timebuddy.dirty.board`, `timebuddy.dirty.preferences`) rather than
   retrying in a loop. `SyncService` flushes dirty documents on the next app
   start, on the next successful sync, and on `AppLifecycleState.resumed`.

4. **A failed remote write is never shown as an error.** The user reordered two
   cities; a red banner about Firestore is noise. The sync state is surfaced
   passively: a small "syncing" or "offline" indicator in the sidebar and profile
   page, nothing modal.

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
    signed out must not be flushed into the next session.

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

  /// Passive status for the UI indicator.
  Stream<SyncStatus> get status;   // idle | syncing | offline | error
}

class SyncOutcome {
  final BoardEntity board;
  final PreferencesEntity preferences;
  final ConflictWinner boardWinner;        // local | remote | none
  final ConflictWinner preferencesWinner;
}
```

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
path.

---

## Sync flow

```
app start
  → read local board + preferences        (instant, app renders)
  → StartupCubit calls SyncService.sync()
      → fetch both remote documents        (2 reads)
      → reconcile per rule 5
      → write winners to the losing side
      → flush dirty flags
      → emit SyncOutcome
  → BoardCubit / PreferencesCubit adopt the reconciled values
```

On resume:

```
AppLifecycleState.resumed
  → flushDirty()                           (0 reads unless something is dirty)
  → if last sync > 15 minutes ago → sync()
```

---

## Edge Cases

- **First run, no network** → local defaults are created, both documents are
  marked dirty, and the app is fully usable. The first successful sync uploads
  them.
- **Signed in on device B while device A is offline with edits** → on A's next
  sync, whichever has the higher `revision` wins wholesale (rule 6). The user is
  told which one won via `SyncOutcome`.
- **Remote document exists but is malformed** → the defensive parser
  (locations.md, Model Serialization) salvages what it can. If `revision` cannot
  be read it is treated as `-1`, so local wins and the malformed remote is
  overwritten.
- **`shared_preferences` write fails** (full disk, restricted profile) → this
  **is** surfaced, because it breaks the read path. The board falls back to
  memory-only for the session with a persistent banner.
- **Firestore permission denied** (rules misconfigured, or a revoked account) →
  `SyncStatus.error`, local keeps working, and the profile page shows the reason.
- **User signs out with dirty documents** → the flush is attempted once before
  clearing; if it fails, the data is lost. Documented and accepted: the
  alternative is holding another account's data on the device after sign-out.
- **Clock skew** → rule 8.
- **Two tabs of the web app open** → each is an independent client with its own
  local storage view. `shared_preferences` on web is `localStorage`, which is
  shared between tabs but not reactive, so tab B keeps its in-memory state until
  its next sync. Accepted; the revision rule makes the outcome deterministic.

---

## Testing

`test/core/sync/sync_service_test.dart`:

- Missing remote documents provision from local (Provisioning).
- Remote revision higher wins; local revision higher wins; tie broken by
  `updatedAt`; full tie goes to remote (rule 5, four cases).
- A local write with a failed remote write sets the dirty flag and still returns
  success (rules 2 and 3).
- `flushDirty` uploads and clears the flag; a second call is a no-op.
- `clearLocalData` removes both documents and both dirty flags (rule 10).
- Malformed remote document is treated as `revision: -1`.
- `SyncStatus` transitions: idle to syncing to idle, and idle to offline on a
  network error.

`test/core/storage/local_store_test.dart` uses
`SharedPreferences.setMockInitialValues` and covers the key-version rule (11).

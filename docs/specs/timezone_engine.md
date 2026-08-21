# Timezone Engine Spec

The engine is the only part of the app that knows what a timezone is. Every
feature (grid, clocks, converter) asks it questions and renders the answers. It
lives in `lib/core/time/` and is the **only** place in `lib/` allowed to import
`package:timezone`.

Getting this wrong is invisible: the app looks right for eleven months and shows
a meeting one hour off in the twelfth. Every rule below is testable and must have
a test pinned to a real transition.

---

## Responsibilities

1. Load the IANA tz database once at startup.
2. Resolve an IANA zone id to a usable zone object, safely.
3. Convert an instant (UTC) to wall-clock time in a zone, and back.
4. Answer offset questions **for a given instant**, including non-whole-hour and
   DST-shifted offsets.
5. Report the day structure of a given calendar day in a zone (how many hours it
   has, and where the transition sits).
6. Detect the device's current zone.

It does **not** know about the user's saved locations, preferences, working hours
or UI. Those belong to [locations.md](locations.md) and
[preferences.md](preferences.md).

---

## Entity Contract

```dart
/// A zone's offset, name and DST state at one instant.
ZoneState {
  zoneId:       String   (required, canonical IANA identifier, e.g. "America/Sao_Paulo")
  abbreviation: String   (required, e.g. "-03", "IST", "PDT": for the instant asked about)
  offset:       Duration (required, offset from UTC for the instant asked about)
  isDst:        bool     (required, whether DST is in effect for that instant)
}

/// The shape of one calendar day in one zone.
ZoneDay {
  zoneId:       String       (required)
  date:         DateTime     (required, the local calendar date at 00:00, date part only)
  hourCount:    int          (required, 23 | 24 | 25)
  hours:        List<DateTime> (required, one UTC instant per local hour slot, ascending)
  transition:   DstTransition? (nullable, present whenever a transition falls inside the day)
}

DstTransition {
  atUtc:        DateTime (required, the instant the offset changes)
  before:       Duration (required, offset before)
  after:        Duration (required, offset after)
  skippedHour:  int?     (the local hour that does not exist, on a spring-forward day)
  repeatedHour: int?     (the local hour that happens twice, on a fall-back day)
}
```

`ZoneState` is **a snapshot, not an identity.** It is always produced together
with the instant it describes and must never be cached across instants. See rule 2.
The names say so on purpose: neither of these is a `...Entity`, because an entity
has an identity that outlives any single moment and these two are answers to
"what was true at that instant".

`ZoneState.isDst` is **derived, not read.** The `timezone` package does expose a
per-period DST bit, but it encodes *legal* DST, and legal DST reads backwards in
a clock app: `Europe/Dublin` models winter as negative DST, so the bit says "DST
is on" in January. The engine instead probes the zone's offset on 1 January and
1 July of the year, takes the smaller of the two as that year's standard offset,
and reports `isDst` when the instant's offset is larger than it. That answers the
question a user is actually asking ("is this city shifted off its normal time
right now?"), and probing both halves of the year survives southern-hemisphere
zones whose DST season spans the new year: whichever hemisphere it is, one probe
lands inside the season and the other outside it.

---

## Business Rules

1. **Single initialization.** `TimeZoneEngine.initialize()` calls the tz package
   loader exactly once per process, before any other engine method. The guard is
   static, because tzdata lives in a process-wide singleton inside the `timezone`
   package: a second engine instance must not clear and rebuild the database out
   from under the first one. For the same reason `initialize` skips the load when
   the database is already initialized, which is what lets the test harness load
   tzdata itself. Calling any method before initialization throws a `StateError`
   in debug; in release the assert is stripped and the call degrades through the
   UTC fallback of rule 3, which is the safer failure for a user than a blank
   screen. `StartupCubit` owns the call.

2. **An offset belongs to an instant, never to a zone.** Every offset-returning
   method takes the instant as a required parameter. There is no
   `offsetOf(zoneId)` overload and there must never be one. A cached offset is
   correct until the next DST transition and then silently wrong.

3. **Unknown zone ids degrade, never throw.** `zoneOrNull(id)` returns `null`
   for an id neither the tzdata nor the alias map knows. Causes seen in
   practice: a zone renamed upstream (`Asia/Calcutta` to `Asia/Kolkata`), a zone
   removed from a newer tzdata release, and corrupted persisted state.
   `zoneOrNull` is the **only** sanctioned lookup: a `null` is an answer the
   caller has to hold, and holding it is what lets a board keep an unresolved
   row, mark it, and offer a repair.

   **`zoneOrHome(id, home)` has been deleted**, and its absence is the rule.
   It returned a guaranteed `ZoneRef` by falling back to the home zone and then
   to `utcZoneId`, which reads as convenience and behaves as data loss: it
   silently substituted a *different city's clock* for the one the user saved,
   which [locations.md](locations.md) rule 11 forbids outright — an unresolved
   row is kept and flagged, never quietly replaced. A caller that wants a
   guaranteed value now writes the fallback itself, at the call site, where it
   is visible.

   The engine's own methods still degrade rather than throw: `_resolve` falls
   through to `utcZoneId` / `tz.UTC` when `zoneOrNull` misses, so one bad saved
   row can never blank a screen. That is a rendering fallback inside a single
   call, not a stored substitution — the board still holds the id the user
   saved, and `BuildGridUseCase` / `BuildWorldClockUseCase` ask `zoneOrNull`
   themselves precisely so they can flag the row instead of drawing a plausible
   UTC clock over it.

4. **Zone ids are canonicalised, and the dataset choice is what makes that
   safe.** `package:timezone` ships three datasets at the same tzdata release.
   The engine imports `data/latest_all.dart`: roughly 435 KB over **598** names,
   because it is the only one that keeps the IANA `Link` lines.

   That choice is the whole rule. The obvious import, and what most projects
   use, is `data/latest.dart`. Measured, not assumed: it holds **341**
   locations and drops every `Link`, so `Europe/Oslo`, `Europe/Amsterdam`,
   `Asia/Kuala_Lumpur`, `America/Montreal` and `Atlantic/Reykjavik` are absent
   from its database, as is plain `UTC`. Both counts still hold exactly on
   `timezone` 0.11.1.

   **What that costs was over-stated here, and the correction is worth
   keeping.** This rule used to claim roughly two hundred everyday ids stop
   resolving under `latest.dart`. They stop being *in the database*; they do
   not stop resolving, because `zoneOrNull` consults the alias map first (see
   below) and folds each of them onto a target the trimmed dataset keeps.
   `tzdata_dataset_test.dart` ran the whole shipped catalog through
   `zoneOrNull` against both datasets: 313 distinct zone ids, **0** unresolved
   under `latest_all` and **1** under `latest` — `Asia/Choibalsan`, a `Link`
   the alias map does not carry.

   So the real trade is: one city today, plus **independence from a
   hand-maintained map of roughly 250 entries** for the other 256. That map is
   a file a person edits; the dataset is generated upstream from IANA. The
   silent-UTC failure mode is what makes the difference matter — a miss does
   not error, it prints a perfectly plausible clock that is an hour wrong for
   half the year — and 185 KB next to a CanvasKit payload is not a price. The
   argument is weaker than the one this rule used to make and still decides the
   same way.

   `zone_lookup.dart` still carries an alias map of roughly 250 entries, but the
   dataset changed its job: it no longer rescues dropped ids, it
   **canonicalises**. Three groups: zones renamed upstream (`Asia/Calcutta`,
   `Europe/Kiev`, `America/Godthab`), zones that are a `Link` onto a neighbour
   whose clock has agreed since 1970 (`Europe/Oslo` to `Europe/Berlin`,
   `Asia/Kuala_Lumpur` to `Asia/Singapore`, `Atlantic/Reykjavik` to
   `Africa/Abidjan`), and the pre-IANA country and region names still found in
   old data (`US/Pacific`, `Brazil/East`, `Japan`).

   **`zoneOrNull` consults the alias map before accepting the raw id.** Under
   `latest_all` a `Link` and its target both resolve, so raw-first would hand
   back whichever spelling the caller happened to hold. Two board rows in one
   real zone would then slip past the duplicate check
   ([locations.md](locations.md) rule 2), and a stored legacy id would never be
   rewritten. The returned `ZoneRef` carries both the canonical `id` and the
   `requestedId`, so a caller that sees `wasAliased` **could** persist the
   rewrite — **nothing does today**. `requestedId` and `wasAliased` have no
   consumer in `lib/`; `BoardCubit` canonicalises on load and writes the result
   back through its own `zoneOrNull(...)?.id ?? id` calls rather than by reading
   the flag. The two fields stay because the information is otherwise
   unrecoverable at a call site and they cost nothing, but the rewrite is a
   promise this codebase has not kept, and the note is here so the next reader
   does not go hunting for the caller.

   Canonicalising ahead of the raw id is only safe while no alias points at a
   different clock, so `zone_lookup_test.dart` asserts that over the **whole**
   database rather than over a sample: every one of the 598 shipped ids
   resolves, and its canonical target reports the same UTC offset at four
   instants spread across the year. Four probes rather than one because a wrong
   target can agree in January and diverge in July. A hand-copied sample cannot
   promise this: the entry nobody thought to list is exactly the one that would
   be wrong.

   The exported `utcZoneId` is the short `'UTC'`, not `'Etc/UTC'`: it is what
   gets persisted, shown in Settings and compared in tests, and `Etc/UTC` reads
   like an implementation detail to a user. `latest_all` does register the short
   name, but the lookup still wires `'UTC'` to `tz.UTC` explicitly so the id
   survives a future switch to a dataset that drops it; `Etc/UTC` and the other
   spellings that arrive from platform APIs and old storage (`GMT`, `Zulu`,
   `Universal`, `Etc/GMT+0`) alias onto it.

   > **Warning for the city catalog.** The catalog of milestone 2
   > ([locations.md](locations.md)) is seeded from a public dataset, and those
   > datasets name zones by IANA id, link names included. Every city **must** be
   > resolved through `zoneOrNull` at seed time and stored canonical, and a
   > `null` must fail the seed loudly. Shipping `latest_all` means a link name
   > now resolves rather than vanishing, so the catalogue's exposure is a stale
   > or misspelled id instead of two hundred live ones, but the failure mode is
   > unchanged: a trusted id does not error, it falls through to the UTC
   > fallback, and nothing in the app says a word. Storing the canonical id is
   > also what makes the duplicate-zone rule work, since Oslo and Berlin are one
   > clock under two names.

5. **Conversion is always through the tz calendar.** `wallTimeAt(instant,
   zoneId)` builds a `TZDateTime` from the UTC instant. `instantFor(localFields,
   zoneId)` builds a `TZDateTime` from calendar fields and returns its UTC
   instant. Neither is implemented by adding a `Duration` to a `DateTime`.

6. **Nonexistent local times shift forward by the width of the gap.** On a
   spring-forward day, 02:30 may not exist. `instantFor` keeps the requested
   minutes and moves the whole time forward by exactly the size of the gap, so
   02:30 on the 2024 US spring-forward day resolves to **03:30**, not 03:00, and
   the result carries `resolution: TimeResolution.shiftedForward`. It never
   throws and never returns the previous day.

   Shifting by the gap rather than clamping to "the first valid local time at or
   after the requested one" is the java.time and Temporal convention, and it is
   the one that generalizes. A clamp collapses every local time inside the gap
   onto a single instant, and it quietly assumes the gap is an hour wide.
   `Australia/Lord_Howe` jumps 30 minutes, so 02:00 there resolves to 02:30, and
   a rule written around a one-hour gap has nothing correct to say about it.
   tz has no "this local time did not exist" signal, so the shift is detected by
   comparing the fields that were asked for against the fields that came back.

7. **Ambiguous local times resolve to the first occurrence.** On a fall-back day,
   01:30 happens twice. `instantFor` returns the **earlier** instant (the
   pre-transition one) and carries `resolution: TimeResolution.ambiguousFirst`.
   The UI surfaces this via `DstBadge` so the user can shift the meeting if it
   matters.

   Getting the earlier one takes work, because `TZDateTime` does not choose
   consistently: it resolves an ambiguous local time to the **later** twin in
   positive-offset zones (`Europe/London`) and to the **earlier** one in
   negative-offset zones (`America/New_York`). A test written against only one of
   those passes with a broken implementation. So the engine does not trust the
   constructor. It reads the transition bounding the period the candidate falls
   in, derives the length of the repeated window from that transition's offset
   drop, and steps back by the drop when the candidate is still inside it.
   Measuring the window from the drop instead of probing at a fixed one-hour
   distance is also what makes `Australia/Lord_Howe` work, where only 30 minutes
   repeat.

8. **Day length comes from the engine.** `dayIn(zoneId, date)` returns a
   `ZoneDay` whose `hours` list has 23, 24 or 25 entries, walked one real hour at
   a time from local midnight until the local date changes. No caller may
   generate hour slots with `for (var h = 0; h < 24; h++)`. `transition` is
   populated whenever a change falls inside the day, not only when `hourCount`
   differs from 24, so `Australia/Lord_Howe` still gets its badge on a day whose
   slot count happens to come out at 24.

   The walk carries a hard stop at 26 slots (`_maxHourSlots`). It is a guard,
   not a bound: a real local day is 23 to 25, and the stop exists so a future
   tzdata row with an offset change this walk does not anticipate ends a loop
   instead of hanging a frame. A day that ever hits it is a bug, not a zone.

9. **Offsets carry minutes.** Every offset is a `Duration` and may be
   `+05:30`, `+05:45`, `+12:45` or `-09:30`. Any API returning `int hours` is
   forbidden. Formatting goes through `offsetLabel(duration)`.

10. **Relative offset is computed pairwise for an instant.**
    `relativeOffset(fromZoneId, toZoneId, instant)` returns
    `offset(to) - offset(from)` for that instant. It is not the difference of two
    cached offsets and it is not symmetric across DST boundaries: at a given
    instant, London may be `+4h` from New York and `+5h` two weeks later.

11. **Device zone detection is best-effort.** `deviceZone()` asks
    `flutter_timezone` across a platform channel, so it is asynchronous and
    returns `Future<DeviceZone>`. It is the only method besides `initialize()`
    that is. A vendor id the tzdata renamed years ago is canonicalised through
    the alias map of rule 4 rather than treated as a failure; a channel error, a
    missing plugin and an id nothing can resolve all land on the same fallback to
    `utcZoneId` with `isFallback` set, so the UI can prompt the user to pick a
    home city. It never blocks startup.

12. **The tzdata version is pinned and visible.** *Pinned, not yet visible: the
    surfacing is pending.* `timezone: ^0.11.1` resolves to 0.11.1, which embeds
    tzdata **2025c**. Showing that in Settings → About is still to build. When a
    user reports a wrong hour, the first question is which tzdata release they
    are running.

    **Where 2025c comes from, checked rather than assumed.** The package states
    it on line 2 of `lib/data/latest_all.dart` (and of `latest.dart`) as a
    plain `// Timezone data version: 2025c` comment, written by its generator.
    So the claim "the package does not expose the release it embeds" is still
    true *at runtime* — there is no exported constant, and a `//` comment is
    not reachable from Dart — but the value is now present in the source,
    which makes the upstream ask a one-line change rather than a feature
    request. Until it lands, anything this app displays would be a literal
    retyped from that comment, which goes stale silently on the next `pub
    upgrade`: exactly the failure the About line exists to prevent. That is why
    the second half of this rule is still open rather than shipped with a
    hardcoded string.

---

## Contract

```dart
// Resolution lives in `zone_lookup.dart` as top-level functions, not on the
// engine: it needs no state beyond the loaded tz database, and callers that
// only want to validate a stored id should not have to hold an engine.

/// Resolves an IANA id, applying the alias map of rule 4. `null` when unknown.
/// The one sanctioned lookup: see rule 3 for why there is no non-null
/// counterpart. Trims surrounding whitespace, and reports the trim through
/// `wasAliased` — a stored value with stray spaces is still worth rewriting.
ZoneRef? zoneOrNull(String zoneId);

/// The tz location behind an id. Engine-internal: only `lib/core/time/` may
/// hold a `tz` type, features ask `TimeZoneEngine` instead.
tz.Location? locationOrNull(String zoneId);

/// The id everything falls back to. Deliberately the short `'UTC'`: see rule 4.
const String utcZoneId = 'UTC';

abstract class TimeZoneEngine {
  /// Loads the tz database. Idempotent. Must complete before any other call.
  Future<void> initialize();

  /// The zone's state at [instant]: offset, abbreviation, DST flag.
  ZoneState stateAt({required String zoneId, required DateTime instant});

  /// The wall-clock time in [zoneId] for a UTC [instant]. A field carrier, not
  /// an instant: see below.
  DateTime wallTimeAt({required String zoneId, required DateTime instant});

  /// The UTC instant for a set of local calendar fields in [zoneId].
  /// Never throws: see rules 6 and 7.
  ResolvedInstant instantFor({
    required String zoneId,
    required int year,
    required int month,
    required int day,
    int hour = 0,
    int minute = 0,
  });

  /// offset(to) - offset(from) at [instant]. See rule 10.
  Duration relativeOffset({
    required String fromZoneId,
    required String toZoneId,
    required DateTime instant,
  });

  /// The structure of one calendar day in one zone. See rule 8.
  ZoneDay dayIn({required String zoneId, required DateTime localDate});

  /// The next offset change at or after [instant], found by binary search over
  /// the sorted transition array tzdata already carries, never by an hourly
  /// scan. Abbreviation-only renames are stepped over: a zone changing what it
  /// calls itself is not a transition to a user. `null` when nothing is
  /// scheduled inside the 400-day horizon, which covers the next change in
  /// either hemisphere and stops the search from walking a zone's whole future.
  DstTransition? nextTransition({
    required String zoneId,
    required DateTime instant,
  });

  /// Best-effort device zone. Falls back to UTC. See rule 11.
  Future<DeviceZone> deviceZone();
}
```

`ResolvedInstant` carries `{ utcInstant, resolution }` where `resolution` is
`exact | shiftedForward | ambiguousFirst`.

`DeviceZone` carries `{ zoneId, isFallback }`.

`ZoneRef` carries `{ id, requestedId }` plus `wasAliased`, which is exactly
`id != requestedId`. A caller that sees it set knows its stored value is stale
and worth rewriting — no caller reads it yet; see rule 4.

`wallTimeAt` returns a `DateTime` whose `isUtc` flag is a **carrier, not a
claim**: its fields are the zone's wall clock and its epoch value means nothing.
Read and format the fields, never do arithmetic with the result and never call
`toLocal()`. The flag is set precisely so that Dart does not re-read those fields
through the **device's** zone rules, which silently moves any wall time sitting
in the device's own DST gap: a user in New York asking for London's 02:30 on the
second Sunday in March would otherwise be shown 03:30.

The engine is **synchronous** after `initialize()`, with `deviceZone()` as the
single exception. Everything else it does is a lookup in in-memory tzdata, so
wrapping it in `Future` would only add awaits to every widget build. The two
asynchronous methods are the two that genuinely are: loading tzdata, and talking
to a platform channel.

---

## Error Model

The engine throws nothing to callers except the initialization `StateError` in
debug. Failures are expressed as:

- `zoneOrNull` returning `null`
- `ResolvedInstant.resolution` being non-`exact`
- `DeviceZone.isFallback` being `true`

Repositories that wrap engine calls map these into `Either<Failure, T>` where a
user-visible failure is warranted. Nothing in the engine surface returns
`Either`, because none of it is I/O.

---

## Edge Cases

- **Zone with a half-hour offset** (`Asia/Kolkata`, `+05:30`): every hour slot in
  the grid renders with a `:30` suffix relative to a whole-hour reference zone.
- **Zone with a 45-minute offset** (`Asia/Kathmandu` `+05:45`, `Pacific/Chatham`
  `+12:45`): same, with `:45`. These are the cases that break naive layouts.
- **Southern-hemisphere DST** (`Australia/Sydney`, `America/Sao_Paulo` before
  2019): DST runs across the new year, so "is it summer" is not a proxy for "is
  DST on". Only `stateAt().isDst` answers it.
- **Zone that abolished DST** (`America/Sao_Paulo` since 2019): historical dates
  still have transitions. A converter query for 2018 must apply them; a query for
  next month must not.
- **Lord Howe Island** (`Australia/Lord_Howe`): its DST shift is **30 minutes**,
  not 60. A transition day there is 23.5 or 24.5 hours long. `ZoneDay.hourCount`
  is an int and counts the real hour slots the walk produces, so the 23.5-hour
  spring-forward day comes back with **24** slots and the 24.5-hour fall-back day
  with **25**; in both cases the last slot sits half an hour short of the next
  local midnight. This is the one zone where `hours.length` and the day's real
  elapsed hours disagree, so the grid renders the shifted minutes from the
  per-slot instants rather than from `hourCount`. `transition` is populated on
  both days regardless of the slot count, so the badge still appears on the day
  that counts out at 24.
- **The date line** (`Pacific/Kiritimati` `+14:00`, `Pacific/Niue` `-11:00`): the
  two can be more than 24 hours apart, so "the same hour column" can be two
  different calendar dates. The grid must label the date per row, never once per
  screen.
- **UTC as home**: valid, and the fallback. Nothing special-cases it.
- **A leap second**: the tz database and Dart both ignore them. Documented as out
  of scope.
- **The device zone changes while the app is running** (traveling, or a manual
  change): the engine does not poll, and **nothing re-reads it either — this
  case is unbuilt.** `app_widget.dart`'s `didChangeAppLifecycleState` resumes
  the ticker and flushes pending writes on `AppLifecycleState.resumed`; it does
  not call `deviceZone()`. The intended behaviour stands as written: one
  re-read on resume, and if it changed and the home location was set
  automatically, the app *offers* to update it rather than changing it
  silently. The offer is the part that matters — a home zone the user picked
  must never move under them, and `BoardRepositoryImpl` freezes the seeded home
  on first launch for exactly that reason ([locations.md](locations.md) rule
  3).

---

## Testing

`test/core/time/timezone_engine_test.dart` must cover, with real zones and real
dates:

- `initialize()` being idempotent and leaving the harness's already-loaded
  database intact (rule 1). The static guard is what this pins: a second engine
  instance must not clear and rebuild tzdata out from under the first.
- Offset for `America/Sao_Paulo` on a 2018 DST date and on the same date in 2024
  (rule 2 and the abolition case).
- `Asia/Kolkata` returning `+05:30` and `Pacific/Chatham` returning `+12:45`
  (rule 9).
- `instantFor` on the US spring-forward date at 02:00 and again at 02:30,
  asserting `shiftedForward` and that 02:30 lands on 03:30 rather than 03:00
  (rule 6). The minutes are the assertion that separates a gap-preserving shift
  from a clamp; without them a clamp passes.
- `instantFor` on the US fall-back date at the repeated local hour, asserting
  `ambiguousFirst` and the earlier instant (rule 7).
- `instantFor` on the 2024 London fall-back date, asserting the earlier instant
  there too. London and New York exercise opposite branches of rule 7, so a
  suite that tests only one of them passes with a broken implementation.
- `dayIn` returning 23 and 25 on those two dates (rule 8).
- `dayIn` for `America/Santiago` on 2024-09-08, which springs forward at 00:00
  local: the day's first instant *is* the transition, so a search anchored there
  and stepping forward would walk straight past it and report 23 hours with no
  transition attached.
- `relativeOffset` between `Europe/London` and `America/New_York` on a date
  inside the two-week window where the two are 4 hours apart, and on a date
  outside it (rule 10).
- A legacy id handed to an engine method answered under its canonical name,
  `Asia/Calcutta` coming back as `Asia/Kolkata` (rule 4).
- An unknown id degrading to UTC inside `stateAt`, `instantFor` and
  `relativeOffset` rather than throwing (rule 3).
- Both `Australia/Lord_Howe` transition days (the 30-minute edge case):
  2024-10-06 returning 24 slots for a 23.5-hour day, 2024-04-07 returning 25 for
  a 24.5-hour day, each with its transition attached, plus 02:00 shifting to
  02:30 and 01:45 resolving to the earlier of its two occurrences.
- `nextTransition`: New York from 2024-01-01 finding the 2024-03-10 spring
  forward; a transition sitting exactly on the queried instant still counting;
  London from 2024-07-01 finding the 2024-10-27 fall back; `Lord_Howe` finding
  a 30-minute jump; and the two `null` cases that are `null` for different
  reasons — `America/Sao_Paulo`, which *had* transitions and has none scheduled
  since abolition, and `Asia/Kolkata`, which has never had one.
- `deviceZone()` with the `flutter_timezone` channel mocked: a zone adopted, a
  legacy id canonicalised, and the three fallback paths (an id the tzdata
  rejects, a channel error, no plugin registered at all). Mocking the channel is
  what keeps the assertions independent of the machine running the suite.

`test/core/time/zone_lookup_test.dart` covers the resolution layer on its own:
every alias resolving to its canonical id **and** that canonical id loading from
the shipped database, the short `UTC` id resolving, case sensitivity, whitespace
trimming reported as a rewrite, and — the one that guards canonicalise-first —
**the alias map winning even when the raw id also resolves**, backed by a sweep
over the *whole* database asserting that no alias moves a zone onto a different
clock, probed at four instants a year apart. Four probes rather than one because
a wrong target can agree in January and diverge in July, and a hand-copied
sample cannot promise it: the entry nobody thought to list is exactly the one
that would be wrong. Rule 4 is only ever as good as that file, so an alias added
without a row there is an alias that has not been checked.

**`test/core/time/tzdata_dataset_test.dart` is the one file in the suite that
must NOT call `initTestTimeZones()`**, and that is the whole reason it exists.
`TzTimeZoneEngine.initialize()` short-circuits on
`tz.timeZoneDatabase.isInitialized`, and every other test file has already
loaded the database through the harness's own `latest_all` import by the time
the engine is asked — so the engine's import was dead code under test, and
switching it to `data/latest.dart` left the whole suite green while shipping a
dataset with 257 fewer names. `flutter test` gives each file its own isolate, so
this one reaches `initialize()` with an empty database and runs the real import
path. It asserts: the loaded database holds at least 598 locations (a floor, not
an equality, so a release that *adds* zones does not fail the build); the `Link`
names are in the raw database rather than only in the alias map; the short `UTC`
resolves; and `Asia/Choibalsan` resolves, which is the single catalog id the
alias map does not cover and therefore the one assertion that bites if the
count check is somehow satisfied. Adding an `initTestTimeZones()` call to this
file turns every assertion in it back into a tautology.

Tests call `initTestTimeZones()` from `test/harness/helpers.dart` in `setUpAll`
— every file except the one above.

---

## Open questions

- **Decided, kept here for the record:** which dataset to ship. The pin is
  `timezone: ^0.11.1`, resolving to 0.11.1, which embeds tzdata 2025c. Of the
  three datasets it carries, `data/latest_10y.dart` (roughly 65 KB) keeps only
  about a decade of transitions and so answers historical converter queries
  wrong, which rules it out for a tool whose converter advertises dates far from
  now. `data/latest.dart` (roughly 250 KB, 341 zones) drops the `Link` lines.
  The engine imports `data/latest_all.dart` (roughly 435 KB, 598 names); rule 4
  carries the reasoning. Revisit only if the web bundle becomes a real
  constraint, and measure before touching it.
- `TODO:` the second half of rule 12. The tzdata release is pinned but not
  surfaced anywhere in the UI, so a user reporting a wrong hour cannot yet be
  asked which one they are on.

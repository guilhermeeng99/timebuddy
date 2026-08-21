# World Clock Spec

A live list of the user's saved locations, each showing the current time as it
ticks. It is the "glance" view; the grid is the "compare" view. Same board, same
engine, different question.

---

## Business Rules

1. **The home clock leads.** It renders as a hero block at the top (large digits,
   full date, zone abbreviation) and is visually distinct from the list. Everyone
   reads their own time first.

2. **The list is the board, in board order.** No separate ordering and no
   separate list. Reordering here writes through `BoardCubit.reorder`, exactly as
   the grid does.

3. **One ticker for every clock.** Every tile subscribes to the shared
   `TickerService` stream (`CLAUDE.md` § Performance). A `Timer.periodic` inside
   a tile is a review blocker: 20 tiles means 20 timers and 20 rebuilds per
   second.

4. **Seconds are a preference, not a default.** With `showSeconds` off (the
   default) the ticker runs at 1/60 Hz aligned to the minute boundary, so a
   20-city list repaints once a minute. With it on, the ticker runs at 1 Hz.
   `TickerService` switches rate based on whether any live subscriber asked for
   seconds.

5. **Each tile shows the relative offset from home**, resolved for the current
   instant through `relativeOffset` (engine rule 10) and rendered by
   `OffsetBadge`: `+4h`, `-3h30`, `same time`. It is never computed by
   subtracting two cached offsets.

6. **Each tile shows the local day relative to home** when they differ:
   `Tomorrow` or `Yesterday` next to the date. Across the date line this is the
   single most confusing fact and it must not require arithmetic from the user.

7. **Day and night are visible at a glance.** `DayNightDot` renders from
   `hourBandFor`, and the tile background carries the band tint at 8% alpha. A
   sleeping city should look asleep.

8. **A tile flags active DST.** `DstBadge` renders when `stateAt().isDst` is
   true.

   **Tapping it opens the location detail sheet** — the same sheet rule 9
   describes, which already carries `nextTransition`. There is no dedicated
   "explain DST" sheet and this rule no longer asks for one: the badge is
   handed the tile's own `onTap`, so a thumb landing on the badge and a thumb
   landing anywhere else on the tile reach the same place. One sheet with the
   fact in it beats two surfaces stating one fact, and the badge stays a
   reporter that never navigates (design_system §6).

9. **Tapping a tile opens the location detail sheet**: full date, zone id, offset
   from UTC, offset from home, next DST transition, and actions (set as home,
   remove, open in grid).

10. **The clock never drifts across a resume.** On `AppLifecycleState.resumed`
    the page re-reads `clock.nowUtc()` immediately instead of waiting for the
    next tick, so a phone unlocked after an hour never shows a stale minute.

11. **An empty board shows only the home clock**, with the add-city CTA below it.
    The hero is never empty: the home zone always resolves (falling back to UTC).

---

## Presentation Contract

```dart
WorldClockTile {
  location:       SavedLocationEntity (required)
  localTime:      DateTime  (required, wall-clock in the row's zone at nowInstant)
  offsetFromUtc:  Duration  (required, e.g. +05:45; rendered by OffsetBadge)
  offsetFromHome: Duration  (required, may be negative and may carry minutes)
  dayDelta:       int       (required, relative to the home local date)
  band:           HourBand  (required)
  isDst:          bool      (required)
  abbreviation:   String    (required, e.g. "IST")
  isHome:         bool      (required, this row's zone is the reference zone)
  isUnresolved:   bool      (required, the stored id matches no tzdata entry)
}

WorldClockViewModel {
  nowInstant:         DateTime             (required, UTC)
  home:               WorldClockTile       (required)
  tiles:              List<WorldClockTile> (required, board order, may be empty)
  homeHasBoardRow:    bool                 (required)
  homeZoneUnresolved: bool                 (required)
}
```

`dayDelta` is **not** clamped to `-1 | 0 | 1`. Pacific/Kiritimati (`+14:00`) and
Pacific/Niue (`-11:00`) are 25 hours apart and really do land two calendar days
apart for one hour a day; the widget names only `±1` and shows the bare date
otherwise, which is honest, where clamping would print "Yesterday" for a day
before yesterday.

`homeHasBoardRow` is `false` when the hero stands in for a zone the user never
saved — home is a zone id, not a row (locations.md rule 3) — and the detail
sheet then hides "remove", because there is nothing to remove.
`homeZoneUnresolved` is what the page banners on, rather than quietly
presenting UTC as the user's own city.

```dart
BuildWorldClockUseCase({required TimeZoneEngine engine}).call({
  required BoardEntity board,
  required WorkingHours workingHours,
  required DateTime nowInstant,
  required String homeFallbackLabel,
});
```

Pure and synchronous, and it takes `nowInstant` rather than a `Clock` so every
rule above is pinnable by a unit test at a real transition. It takes
`WorkingHours` rather than the whole preferences document, because the band is
the only preference it reads. `homeFallbackLabel` **arrives already localized**:
it names the hero on a board whose home zone has no row of its own, and the
domain has no catalog to look a city up in — `America/Sao_Paulo` is an
identifier, not a label.

Only `nowInstant` changes per tick, so the use case is cheap to re-run, but the
cubit still recomputes only what changed (see Performance).

---

## State Machine

### WorldClockCubit

Page-scoped. Depends on `BoardCubit`, `PreferencesCubit`,
`BuildWorldClockUseCase`, `TimeZoneEngine`, `Clock`, `TickerService` — all six
required by the constructor. The use case is injected rather than constructed
here for the usual reason: it is pure, so one instance serves the whole app and
the cubit does not build one per rebuild.

```dart
sealed class WorldClockState extends Equatable
WorldClockLoading
WorldClockReady({ model: WorldClockViewModel })
WorldClockError({ failure: Failure })
```

```
WorldClockLoading ──board loaded──→ WorldClockReady(model)
                  ──board failed──→ WorldClockError(failure)

WorldClockReady ──tick(now)──────────→ WorldClockReady(model with new nowInstant)
                ──board changed──────→ WorldClockReady(rebuilt)
                ──preferences changed→ WorldClockReady(rebuilt)
                ──resumed────────────→ WorldClockReady(immediate recompute)
```

There is no `WorldClockEmpty`: an empty board is a valid `Ready` with an empty
`tiles` list and a present `home` (rule 11).

---

## Performance

- The cubit emits a new `nowInstant` per tick; tiles rebuild only their digits
  via `ClockText`, which subscribes to the ticker itself. The list itself does
  not rebuild on a tick.
- `offsetFromHome`, `dayDelta` and `band` are recomputed per tick, but they are
  three engine lookups per row and the whole board is capped at 20 rows
  (locations rule 4).
- The ticker pauses on `AppLifecycleState.paused`. A backgrounded app must not
  wake the CPU once a second.

---

## Edge Cases

- **A zone with a 45-minute offset** → `OffsetBadge` renders `+5h45`, never
  rounded. Rule 5.
- **Home and a tile are in the same offset but different zones** → badge shows
  "same time"; both keep their own DST badges, since they can diverge later in
  the year.
- **A tile crosses midnight while the page is open** → `dayDelta` and the date
  label update on the tick that crosses it. No special handling; the model is
  recomputed from the instant.
- **DST transition happens while the page is open** → the offset badge changes
  value mid-session. Correct, and worth a test.
- **Board empty** → rule 11.
- **Home zone unresolved** → falls back to UTC with the same banner the grid uses
  (time_grid edge cases).
- **Device clock is wrong** → every clock is wrong by the same amount. Not
  corrected; see time_grid edge cases.

---

## i18n

Copy under `t.worldClock.*`, complete: `title`, `sameTime`, `tomorrow`,
`yesterday`, `dstActive`, `nextTransition(date)`, `emptyTitle`, `emptyMessage`,
`emptyCta`, `detailZoneId`, `detailOffsetUtc`, `detailOffsetHome`,
`actionRemove`, `actionOpenInGrid`.

There is deliberately no `actionSetHome` here. It existed, held the same
sentence as `t.locations.setAsHome` in both locales, and was deleted: setting
the home city is a board mutation, so the detail sheet renders the board's own
word for it. Two live screens reading two keys for one action is how the two
drift, and the user learns two vocabularies for one gesture.

The three `empty*` keys are one block on a board with no saved cities — a
headline, a message and the CTA, not a CTA alone. It renders *under* the home
hero rather than in place of it (rule 11), which is why it is a local column
and not `FeatureEmptyState`: that widget owns a whole screen, and this page
already has a clock on it.

---

## Testing

`test/features/world_clock/`:

- `BuildWorldClockUseCase`: offset with minutes, negative offset, `dayDelta` of
  +1 across the date line, `dayDelta` of -1, band assignment, DST flag.
- `WorldClockCubit`: tick updates `nowInstant` without touching the board,
  board change rebuilds, empty board yields `Ready` with an empty tile list.
- A regression test that no tile creates its own `Timer`.

  **Not a subscriber count.** `ClockText` subscribes to the ticker once per set
  of digits, by design and for the reason Performance gives: the `StreamBuilder`
  wraps the digits and nothing else, so a tick repaints one `Text` rather than a
  row. A page with a hero over N tiles therefore holds N+1 subscriptions plus
  the cubit's, and an assertion that the count equals 1 would be asserting the
  opposite of the design: red on a page that is behaving, and quiet about the
  thing rule 3 actually forbids.

  Pin the **cost** instead: the app runs exactly one `Timer` and `TickerService`
  owns it. Let the service's timer run rather than the paused one the harness
  installs, assert that a minute of elapsed time moves every clock on the page
  with nobody publishing a tick: which only a real timer inside the service can
  do: and then `pause()` it, which cancels that one timer and nothing else.
  `flutter_test` fails any test whose body returns with a `Timer` still pending,
  so a tile that started a `Timer.periodic` of its own is caught there and its
  creation site is printed. The subscription count is still worth asserting as
  N+1, because a tile that wrapped itself in a second `StreamBuilder` shows up
  in nothing else.

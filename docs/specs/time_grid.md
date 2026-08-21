# Time Grid Spec

The grid is the app's core screen and the reason it exists: one row per saved
location, one column per hour, so a user can see at a glance when a given hour is
reasonable in every place at once.

It is a **view over** the board ([locations.md](locations.md)) and the engine
([timezone_engine.md](timezone_engine.md)). It owns no persisted state except the
user's last reference date, which is view state, not data.

---

## Anatomy

```
┌──────────────┬────────────────────────────────────────────────────┐
│ Sao Paulo    │ 21 22 23 │ 00 01 02 03 ... 12 13 ... 22 23 │ 00 01 │  ← row
│ BRT  home    │          │                                 │       │
├──────────────┼──────────────────────────────────────────────────  ┤
│ London       │ 01 02 03 │ 04 05 ...                                │
│ GMT  +4h     │          │                                          │
└──────────────┴────────────────────────────────────────────────────┘
   pinned          scrollable hour track, aligned to the reference row
```

- **Pinned first column** (`GridMetrics.labelColumnWidth`): the `LocationRow`
  identity block. Never scrolls horizontally.
- **Hour track**: one `HourCell` per slot, `GridMetrics.hourColumnWidth` each.
  Only the header strip is a horizontal `Scrollable`; every row draws its cells
  at the offset the header publishes, so header and rows cannot drift apart.
- **Header strip**: the reference **zone's** hour numbers plus the date label.
  Read from the zone and not from the home row, because home is a zone and is
  not required to be a board row (locations rule 3): a header fed by a row would
  go blank exactly when the user has not added their own city.
- **Hour cursor**: a vertical `primary` highlight over one column, following
  pointer or keyboard.

---

## Business Rules

1. **The reference row defines the columns.** The reference is the home zone
   (`board.homeZoneId`). Column `n` is the `n`-th hour slot of the reference
   day, and every other row renders the wall-clock time in its own zone for the
   **same instant**. Rows are never independently aligned to their own midnight.

2. **The column set comes from `dayIn(homeZoneId, referenceDate)`,** so a DST
   transition day in the reference zone has 23 or 25 columns
   (engine rule 8). Nothing in the grid iterates `0..23`.

3. **The grid shows a window, not a day.** The visible window is
   `referenceDate 00:00` minus 3 hours through `referenceDate 23:00` plus 3
   hours, so the user can see the tail of the previous day and the head of the
   next without changing the date. Total slots: day length plus 6.

4. **Every cell's time is derived from its instant**, never from arithmetic on
   the neighbouring cell. `wallTimeAt(instant, row.zoneId)` per cell. Adding one
   hour to the previous cell's local time breaks on the row's own DST transition,
   which does not have to coincide with the reference zone's.

5. **Half-hour and 45-minute zones render their minutes.** A cell shows `hh:mm`
   (`05:30`) rather than `hh` when its own wall clock carries minutes
   (`GridCell.hasOffsetMinutes`), which is exactly when the row's offset from
   the reference zone is not a whole number of hours. The column stays aligned
   to the reference hour: the row is genuinely offset, and hiding that would be
   a lie. Cell width does not change; the type scale drops from `labelSmall` to
   a compact size on the cells that carry minutes. The question is asked per
   cell and not per row, because Lord Howe grows its `:30` mid-row when its
   30-minute DST starts.

6. **Day boundaries are marked per row.** A `1px` vertical rule sits before the
   cell where that row's local date changes, and the new date's short label
   (`Tue 24`) renders inside that cell. Rows near the date line change date at
   different columns; a single global boundary line would be wrong (engine edge
   case: date line).

7. **Hour band colors come from `hourBandFor(localHour, workingHours)`.** The
   working window is a user preference ([preferences.md](preferences.md)),
   default 09:00 to 17:00. No hour color is decided in a widget.

8. **The cursor is a single shared value.** Hovering or tapping any cell sets
   `cursorInstant`; every row highlights the cell containing that instant. On
   touch it follows drag; on pointer it follows hover; with a keyboard, left and
   right arrows move it one slot and `Home` returns it to now.

9. **"Now" is always visible as a distinct marker,** separate from the cursor: a
   `primary` vertical line at the exact fractional position of the current
   instant, updated from `TickerService` at 1/60 Hz (the line moves less than a
   pixel per second; a 1 Hz update would be wasted work).

10. **Changing the reference date does not move the cursor's time-of-day.** If
    the cursor sits on 14:00 and the user steps to tomorrow, it stays on 14:00 of
    the new day. The cursor is a time-of-day intent, not a pinned instant.

11. **Today is one tap away.** The date pill always offers a "Today" reset when
    `referenceDate` is not today in the home zone.

12. **The hour column fills the track in whole columns, down to a floor.**
    `GridLayout.resolve` divides the available track into the most equal
    columns that still clear `GridLayout.minColumnWidth` (48pt), so the track
    is always tiled edge to edge and **no column is ever drawn half-cut at the
    right margin** — which is what "the values are truncated" meant. Below that
    floor the grid scrolls, exactly as before; it never shrinks a column into
    illegibility, because unreadable hour numbers defeat the screen's purpose.

    The floor is measured, not chosen, and the binding constraint is not the
    hour digits. `05:45` is ~40pt of Inter at 15pt, but the per-row date label
    (`Wed 28`, 9pt, rule 6) needs ~36pt *including its 4pt inset* and clips
    from the right with no ellipsis — so a 40pt column would quietly print
    `Wed 2` and hand the user a wrong calendar date that looks deliberate. 48
    clears both and is also Material's minimum tap target, which every cell is.

    **What this does and does not promise.** Thirty slots at the floor need a
    1440pt track — 1620pt of grid box once the pinned column is paid for, and
    about **1860pt of window** on a desktop, where the expanded rail takes
    another 240. A phone still scrolls, and always will. That is arithmetic, not a
    compromise: no arrangement of a 375pt screen shows a day at a legible size.
    What changed at every width is that the track is *filled* — a 1280pt window
    went from 14 columns with the fifteenth sliced through, to 17 whole ones.

13. **Initial scroll position centres on now.** Opening the grid puts the
    current instant in the middle of the viewport, not at column 0. On a screen
    wide enough to hold the whole window this resolves to offset 0 and does
    nothing, which is the rule working rather than failing: there is no
    scrolling to do when every hour is already on screen.

14. **A row whose zone is unresolved renders greyed with no cells**
    (locations rule 11), keeping its position so the board order is stable.

15. **A resize moves hours, never the hour.** The track's scroll position is
    converted to fractional columns before a relayout and back to pixels after
    it (`GridLayout.columnOf` / `offsetOfColumn`), so dragging a window edge
    changes how many hours are on screen and not *which* hour the user is
    looking at. A `ScrollPosition` stores pixels, and a pixel stopped meaning a
    fixed hour the moment the column width became a function of the viewport.

    Numbered 15 rather than slotted in beside rule 12 on purpose: rules 13 and
    14 are cited by name from six places in `lib/`, and renumbering a spec to
    keep it tidy is how those citations quietly start pointing at the wrong
    rule.

    The published offset is also re-broadcast unconditionally in that same
    post-frame callback, as a guard rather than as the main event: when a
    relayout shrinks `maxScrollExtent`, Flutter clamps the position through
    `correctPixels`, which assigns the field and notifies no listener, so a
    page relying on the controller's own notifications could keep a stale
    offset while the header painted at the corrected one. In practice the
    rescale gets there first and notifies for it; the guard costs an
    assignment and removes the need to reason about the ordering.

---

## Presentation Contract

```dart
/// One fully-resolved cell, produced by the domain layer. The widget layer
/// renders these and computes nothing.
GridCell {
  instant:      DateTime  (required, UTC: the slot this cell represents)
  localTime:    DateTime  (required, wall-clock time in the row's zone)
  band:         HourBand  (required, good | fair | poor | night)
  isDayStart:   bool      (required, this cell begins a new local date)
  dateLabel:    String?   (nullable, present only when isDayStart)
  hasTransition: bool     (required, a DST change happens inside this slot)
  hasOffsetMinutes: bool  (getter, localTime.minute != 0: render hh:mm, rule 5)
}

GridRow {
  location:       SavedLocationEntity (required)
  zoneState:      ZoneState?          (nullable, resolved for one instant
                                       inside the visible window; null exactly
                                       when isUnresolved)
  isHome:         bool                (required)
  isUnresolved:   bool                (required, the saved zone id matches no
                                       tzdata entry, rule 14)
  cells:          List<GridCell>      (required, aligned index for index with
                                       slots; empty when, and only when,
                                       isUnresolved)
  relativeToHome: Duration            (offset(row) - offset(home) at the
                                       instant zoneState describes; zero when
                                       isUnresolved, and zero for the home row)
}

GridViewModel {
  referenceDate:      DateTime       (required, local date in the home zone)
  slots:              List<DateTime> (required, the shared UTC instants,
                                      ascending)
  rows:               List<GridRow>  (required, board order, unresolved rows
                                      included)
  nowInstant:         DateTime       (required, UTC)
  cursorInstant:      DateTime?      (nullable)
  homeZoneUnresolved: bool           (required, the home zone resolves against
                                      no tzdata entry so the columns fell back
                                      to UTC; the page banners it)
}
```

`GridRow.relativeToHome` lives on the row rather than being subtracted in a
widget, because the home zone is not required to be a row of its own (locations
rule 3), so a widget would have nothing to subtract from. It is resolved
pairwise for one instant, never as the difference of two stored offsets
(engine rule 10).

`GridViewModel.copyWith` takes a `clearCursor` flag: passing
`cursorInstant: null` cannot say "drop the cursor", being indistinguishable from
"leave it alone".

`BuildGridUseCase` produces the whole `GridViewModel` from
`(board, workingHours, referenceDate, nowInstant, cursorInstant?, localeTag)`.
It takes `nowInstant` rather than a `Clock` so every rule above is pinnable by a
unit test at a real historical transition. It is pure and synchronous, which
makes it the natural place for every one of the rules to be tested without a
widget.

---

## State Machine

### TimeGridCubit

Page-scoped. Depends on `BoardCubit` (read-only), `PreferencesCubit`
(read-only), `BuildGridUseCase`, `TimeZoneEngine` and `Clock`. Not
`TickerService`: a minute tick that re-emitted the model would rebuild every row
once a minute, which is what the marker's `CustomPainter` exists to avoid
(Performance, below).

Subscribing is `start()`, called after construction rather than from it, so a
test can observe the very first emission: a cubit that emitted from its own
constructor would have finished before anything could listen.

```dart
sealed class TimeGridState extends Equatable
TimeGridLoading
TimeGridEmpty                                    // board has no locations
TimeGridReady({ model: GridViewModel })
TimeGridError({ failure: Failure })
```

**Transitions:**

```
TimeGridLoading ──board loaded, non-empty──→ TimeGridReady(model)
                ──board loaded, empty──────→ TimeGridEmpty
                ──board failed─────────────→ TimeGridError(failure)

TimeGridReady ──setReferenceDate(d)─→ TimeGridReady(rebuilt, cursor time-of-day kept)
              ──stepDate(±1)────────→ setReferenceDate(current ± whole days)
              ──goToToday()─────────→ setReferenceDate(todayInHomeZone)
              ──setCursor(instant)──→ TimeGridReady(cursorInstant updated)
              ──clearCursor()───────→ TimeGridReady(cursorInstant: null)
              ──tick(now)───────────→ TimeGridReady(nowInstant updated)
              ──board changed───────→ TimeGridReady(rebuilt) | TimeGridEmpty
              ──board failed────────→ TimeGridError(failure)
              ──preferences changed─→ TimeGridReady(rebuilt)
```

The cubit subscribes to `BoardCubit.stream` and `PreferencesCubit.stream` and
rebuilds the model on any change. It never writes to either. Any preference can
repaint the grid, so the whole stream is watched rather than one field: the
working window decides every band (rule 7) and the locale decides every date
label (rule 6).

A board state that is neither loaded nor failed leaves a grid already on screen
alone, and only falls back to `TimeGridLoading` when no board has ever arrived.
A refresh re-emits `BoardLoaded`, so holding the last grid beats blanking a
screen the user is reading.

`tick` only replaces `nowInstant`; it does not rebuild rows or cells, and emits
nothing when now has not moved. The full rebuild happens on date, board or
preference changes.

`setCursor` snaps to the slot holding the instant it is given and ignores an
instant outside the window, so a drag across the cells and a tap on one cell
produce the same value and every row highlights the same column. Every rebuild
re-snaps the stored cursor against the new `slots` and drops it when the window
no longer holds it, which is what keeps `cursorInstant` a member of `slots` for
the widgets that rely on it.

Two derived values the state does not carry, because both are pure functions of
the board: `referenceZoneId` (the home zone, or `UTC` when it does not resolve)
and `todayInHomeZone` (rule 11, never the device's date).

---

## Interaction

| Input | Result |
|---|---|
| Tap a cell | Sets the cursor to that slot |
| Drag horizontally on the cells area | Moves the cursor continuously |
| Drag horizontally on the header strip | Scrolls the track |
| Tap a row label | Opens row actions: set as home, replace zone, remove |
| Long-press a row label (touch) | Lifts the row to reorder the board |
| Drag a row label (pointer) | Lifts the row to reorder the board |
| Left / right arrow | Moves the cursor one slot |
| `Home` key | Cursor back to now |
| Swipe left / right on the date pill | Steps the reference date |

**The pinned label column owns both row gestures, and the hour cells own
none of them.** That split is the whole design, and it is what lets a row be
draggable on a screen where a horizontal drag already means something:
`_slotAt` answers `null` left of `labelWidth`, so the cursor drag and the row
lift never compete for a pixel. Moving the lift onto the cells — or onto the
whole row — would put it in the same arena as the cursor.

**Which lift gesture depends on the pointer**, matching what
`ReorderableListView`'s own default handles do: a mouse drags immediately,
because a hold before a drag on a desktop reads as the app being slow; a finger
must press and hold, because an immediate lift would steal every vertical
scroll of the grid that began over a label. Neither claims a pointer that never
moved, so the tap survives on both.

The label column also suppresses tooltips (`TooltipVisibility`). The
unresolved-zone glyph in `LocationRow` carries one, and its long-press
recognizer sits deeper than the lift's — it would win those fourteen pixels and
give the drag a dead spot that appears and disappears as rows resolve. The
glyph keeps its `semanticLabel`, and the repair the tooltip only described is
now one tap away in the actions sheet.

Reordering writes through `BoardCubit.reorder` and row actions through
`board_actions.dart`; the grid holds no order of its own.

**The grid has one mode.** It carried a Compare / Plan toggle in its app bar
that turned the same rows and columns into the meeting planner; the toggle and
the mode are gone, along with the planner provider, the selection overlay and
the summary panel slot. What is left is the comparison grid this spec
describes, and it is simpler for it — the `Stack` that held the panel is a
plain `Column`, and the `GlobalKey` that existed only to reparent the grid when
the planner provider appeared above it is gone with them.

**This table used to describe a screen that did not exist.** Row actions and
drag-to-reorder were specified in M2, deferred, and listed in
[roadmap.md](../roadmap.md) as shipped-elsewhere: they lived on a Cities page
instead, and `t.grid.rowAction*` were strings with no call site. The Cities page
is gone and the grid is where the board is edited, so the promise and the code
finally agree. `t.grid.rowAction*` stay unused — the sheet is the board's, and
speaks `t.locations.*`, so one gesture does not teach two vocabularies.

---

## Geometry, and why it grew

`GridMetrics` was retuned on 2026-08-20 after the owner said the grid was
uncomfortable to read — "tudo muito pequeno e valores truncados". It was, and
the numbers say why: an hour column was **44pt** holding an 11pt digit, and a
half-hour zone's `05:45` was shrunk to **9pt** to fit. The rows that most need
explaining — Kolkata `+05:30`, Kathmandu `+05:45`, Chatham `+12:45` — were the
hardest ones on the screen to read.

| | before | now |
| --- | --- | --- |
| `hourColumnWidth` | 44 | **60** |
| `rowHeight` | 64 | **72** |
| `labelColumnWidth` | 132 | **180** |
| `headerHeight` | 40 | **48** |
| dense label column | 96 | **128** |
| cell digits | 11pt, 9pt with minutes | **15pt, always** |
| band fill alpha | 0.12 | **0.16** |

**The trade was explicit at the time: at a fixed 60pt column, a 1400pt track
showed about 22 hours instead of 30.** That was the direction the owner picked
from three, and it was the right one for this screen — a readable half-day
beats an unreadable full one, and the track scrolls.

> **Superseded in part.** The column stopped being fixed (rule 12): the same
> 1400pt track now holds 29 columns at ~48pt, because the width is resolved per
> surface rather than declared. What survives from this section is the *type* —
> 15pt digits for every cell, minutes included — and the reason the reference
> width is 60 rather than 44. `GridMetrics.hourColumnWidth` is no longer read
> by any grid widget; it is the settings preview's cell and the size the type
> scale was chosen against.

Three things changed shape along with the size, and each removes a box:

- **The cell is flat and edge to edge.** It had 4pt of inset and an
  `AppRadius.sm` corner, so a row was twenty floating pills; now neighbouring
  hours meet and a row reads as one continuous day. `HourCell.compact` keeps
  the old chip for the settings preview, whose 24 cells share one card and can
  be as narrow as 26pt.
- **The cursor is a wash, not a ring.** A 2pt border was a fifth edge on a
  screen that already had eighty; a filled column reads as "here" from across
  the row.
- **The digits are tinted by their band**, lerped 55% toward `onBackground` so
  it stays legible on all twenty palettes rather than being a hardcoded light
  tint. A row read out of the corner of the eye now says which band it is in.
  The compact chip keeps the plain foreground — at 11pt a tinted digit loses
  contrast before it gains meaning.

A row hairline (`surfaceVariant`) was added underneath each row, and it is
load-bearing rather than decoration: contiguous fills with no rule between them
read as one block of colour instead of four cities.

**No legend was added to the grid**, although the direction artboard carried
one. On the artboard the grid was a fixed four-row block with room beneath it;
here the rows are a scrolling list under a floating bar and a FAB, so a legend
would have to be pinned and would cost vertical space on every screen. The
bands are already named in Settings → Working hours.

---

## Responsive

- **< 600px:** no rail. Pinned label column narrows to 128px and drops the
  country line, keeping the city label and offset badge. The date pill renders
  on the page.
- **600–900px:** the rail is on screen but **collapsed to 80px of icons**, and
  the page keeps drawing its own date pill because an 80px strip cannot hold a
  stepper. Full 180px label column.
- **>= 900px:** the rail expands to 240px with labels and takes the date pill.
  The grid gets the full window width (`maxContentWidth` does not apply,
  design_system §7).
- Row height is constant across breakpoints. Vertical scrolling is a normal
  `ListView.builder` over rows.

### Why the rail collapses, with the arithmetic

The middle band existed and was the worst place in the app to read this
screen. A 240px rail plus a 180px label column is 420px of chrome, so a 600px
window left the hours 180px — **three columns, where a 599px phone showed
nine**. Every window from 600 to 890 was a regression against the phone
layout, and widening one was how a user discovered it.

Moving the breakpoint to 900 would only have relocated that cliff, because the
drop is the chrome's width and not the breakpoint's position. Collapsing the
rail attacks the cause: the step across 600 is now the 80px icon rail, about
two columns, and the step across 900 is the 160px the rail gains when it
expands — which it does exactly where the screen can afford it.

| window | rail | label | track | columns | before |
| --- | --- | --- | --- | --- | --- |
| 375 | 0 | 128 | 247 | 5 | 4 |
| 599 | 0 | 128 | 471 | 9 | 7 |
| 601 | 80 | 180 | 341 | 7 | **3** |
| 768 | 80 | 180 | 508 | 10 | 5 |
| 899 | 80 | 180 | 639 | 13 | 7 |
| 900 | 240 | 180 | 480 | 10 | 8 |
| 1280 | 240 | 180 | 860 | 17 | 14 |
| 1920 | 240 | 180 | 1500 | 30 (all) | 25 |

`ResponsiveLayout.showsSidebar` and `sidebarIsExpanded` are what the chrome
reads. **`isMobile` deliberately stays at 600 and keeps meaning "is this a
phone"** — the grid's dense label column and the settings row's stacking are
content decisions about a 360pt screen, and a 700pt tablet is *wider* than a
phone once the rail is 80pt, not narrower.

---

## Performance

- One horizontal `ScrollController`, owned by the header strip, which is the
  grid's only horizontal `Scrollable`. Its offset is republished as a
  `ValueListenable<double>` that every row and the "now" marker read. One
  controller attached to several viewports would give each its own position and
  sync nothing, which is the bug this removes rather than papers over.
- Each row draws only the columns that offset puts inside the viewport, so a
  20-row board with a 30-slot window builds roughly the 8 visible columns per
  row instead of 600.
- `GridViewModel` is rebuilt only on the triggers listed in the state machine.
  A cursor move and a tick each replace one field through `copyWith` and leave
  every row and cell object identical, so no row is recomputed.
- The "now" marker repaints from a `CustomPainter` fed by the 1/60 Hz ticker, so
  it never rebuilds a widget subtree.

---

## Edge Cases

- **Reference day is a DST transition day** → 23 or 25 columns, rule 2. The
  skipped hour simply has no column; the repeated hour has two columns with the
  same local label and different instants, and the column the clocks move in
  carries `hasTransition`, which the cell renders as a `warning` dot.
- **A row's zone transitions on a day the reference zone does not** → that row
  shows a duplicated or missing local hour while the columns stay whole. Rule 4
  is what makes this render correctly.
- **Lord Howe's 30-minute DST shift** → its transition moves the row's minutes
  mid-row, `:30` to `:00` going forward in October and back again in April.
  Rule 5 already asks the question per cell, so no special case is needed.
- **Row across the date line** → its date label appears at a different column
  than every other row's, rule 6.
- **All rows in the same zone** → impossible, locations rule 2 rejects it.
- **Board is empty** → `TimeGridEmpty` renders `FeatureEmptyState`, not a grid
  with only a header.
- **Board has exactly one location and it is home** → renders one row. Valid.
- **Home zone unresolved** → the grid falls back to `UTC` as reference and shows
  a banner prompting the user to fix their home city. It does not go blank.
- **The reference date does not exist in the home zone at all** → `dayIn`
  reports `hourCount 0` and the day contributes no columns of its own, so the
  window is the six flanking slots from the neighbouring days and the grid still
  draws. `Pacific/Apia` has no 2011-12-30: Samoa dropped that date outright
  when it crossed the date line. `BuildGridUseCase` also defends against the
  slot list coming out empty altogether, resolving each row's `zoneState` and
  `relativeToHome` against `nowInstant` rather than against the middle of the
  window, because `slots[slots.length ~/ 2]` on an empty list is a crash on a
  day the user is allowed to step onto. **Known rough edge:** the engine
  reports an absent day by handing back a `ZoneDay` with no hours rather than by
  saying so, which leaves every caller to notice the empty list for itself. An
  explicit answer from the engine is worth revisiting.
- **Reference date far in the future** (a year out) → allowed. Offsets are
  resolved per instant, so scheduled future transitions apply automatically
  (engine rule 2).
- **User's device clock is wrong** → the "now" marker is wrong and nothing else
  is. Documented, not corrected: correcting it would need a time server and the
  app is not a clock authority.

---

## i18n

Copy under `t.grid.*`: `title`, `today`, `emptyTitle`, `emptyMessage`,
`emptyCta`, `homeBadge`, `sameTime`, `dstOn`, `dstTransitionHere`,
`dstExplainTitle`, `dstExplainBody`, `unresolvedRow`, `homeZoneBrokenBanner`,
`rowActionSetHome`, `rowActionRemove`, `rowActionReplaceZone`, `cursorHint`.
Band names live under `t.bands.*`, because the day/night indicator and the grid
read the same four words.

Date labels (`Tue 24`) and hour labels go through `intl` with the app locale, not
through hardcoded strings.

---

## Testing

`test/features/time_grid/domain/build_grid_usecase_test.dart` is where the rules
live. It is a pure-function test pinned to real IANA transitions, so every case
below is cheap:

- **Rule 1:** column `n` is the same instant in every row, and Tokyo opens the
  window on the following calendar day while sharing column 0; the home row is
  flagged, including when the board stored a legacy alias (`Brazil/East`) of the
  home zone; rows keep board order.
- **Rule 2:** a plain day is 24 day slots and 30 total, the 2024-11-03 New York
  fall-back day 25 and 31, the 2024-03-10 spring-forward day 23 and 29. That
  spring-forward row has no `02:00` column at all, and the fall-back row reads
  `01:00` twice at two different instants, with `hasTransition` on the second.
- **Rule 3:** the window opens three hours before local midnight and closes
  three after; the flanks come from the neighbouring days on both DST days;
  `America/Santiago` on 2024-09-08, a day that begins on its own transition and
  has no midnight, still gets its three flanks; consecutive slots are always
  exactly one real hour apart.
- **Rule 4:** New York repeats `01:00` on the fall-back day while a Sao Paulo
  reference row does not, and the transition is flagged on the row that has it
  rather than across the grid.
- **Rule 5:** `Asia/Kolkata` reads `:30` and `Asia/Kathmandu` `:45` in every
  cell against a Sao Paulo reference, with `relativeToHome` carrying the
  minutes; `Australia/Lord_Howe` loses its `:30` mid-window on 2024-10-06,
  which is what a per-row minute would get wrong.
- **Rule 6:** `Pacific/Kiritimati` and `Pacific/Niue` turn the date on different
  columns of the same window; a UTC row marks both midnights; the first cell
  never opens a day; `dateLabel` is present exactly when `isDayStart` is set;
  labels are formatted under the locale tag (`pt-BR` gives `ter`).
- **Rule 7:** a night-shift working window makes 23:00 `good` where the default
  makes it `night`, the default window bands 17:00 `fair` and 19:00 `poor`, and
  a band follows the row's local hour rather than the reference hour.
- **Rule 14:** an unresolved row carries no cells, no `zoneState` and a zero
  `relativeToHome`, and the rows around it keep their cells and their order.
- **Unresolved home zone:** `homeZoneUnresolved` is set, the columns fall back
  to UTC hours, and the board still renders every row; the flag is clear for a
  home zone that resolves.
- **Zone state and offsets:** they answer for the reference day and not for
  `nowInstant` (a January reference day reads `EST` and `-2h` while now is in
  July), and the home row carries a zero relative offset.
- **Model plumbing:** `nowInstant` and `cursorInstant` are carried through
  untouched, there is no cursor unless one is passed, `referenceDate` is reduced
  to the local date it names, and an empty board still produces the column
  window.

`test/features/time_grid/presentation/cubit/time_grid_cubit_test.dart` covers the
state machine: the first state before `start()`, opening on today in the home
zone rather than on the device date, holding the last grid through a transient
board state, stopping after `close()`, rebuild on board change (row added, board
emptied, new home zone, unresolvable home zone) and on a preference change,
cursor snapping and clearing, rule 10 across the 25-hour fall-back day and
across `goToToday`, and `tick` moving now without rebuilding a row.

`test/features/time_grid/presentation/pages/time_grid_page_test.dart` covers:
the pinned label column does not move with the hours, the cursor lights the same
instant in every row, a half-hour zone renders its minutes while home does not,
the empty board invites a first city with no grid behind it, the placeholder
holds until the board resolves, the home-zone banner appears only when the zone
did not resolve, and the last row scrolls clear of the FAB.

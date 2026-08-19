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
  Scrolls horizontally, all rows locked to one shared `ScrollController`.
- **Header strip**: the reference row's hour numbers plus the date label.
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

5. **Half-hour and 45-minute zones render their minutes.** When
   `relativeOffset(home, row, instant)` is not a whole number of hours, the cell
   shows `hh:mm` (`05:30`) rather than `hh`. The column stays aligned to the
   reference hour: the row is genuinely offset, and hiding that would be a lie.
   Cell width does not change; the type scale drops from `labelSmall` to a
   compact variant for these rows.

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

12. **The grid is horizontally scrollable, never horizontally squeezed.** Column
    width is fixed by `GridMetrics.hourColumnWidth`. On a narrow phone the user
    scrolls; the app never shrinks columns to fit, because unreadable hour
    numbers defeat the screen's purpose.

13. **Initial scroll position centres on now.** Opening the grid puts the current
    instant in the middle of the viewport, not at column 0.

14. **A row whose zone is unresolved renders greyed with no cells**
    (locations rule 11), keeping its position so the board order is stable.

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
}

GridRow {
  location:  SavedLocationEntity (required)
  zoneState: ZoneEntity          (required, resolved for the reference instant)
  isHome:    bool                (required)
  cells:     List<GridCell>      (required, same length for every row)
}

GridViewModel {
  referenceDate: DateTime      (required, local date in the home zone)
  slots:         List<DateTime> (required, the shared UTC instants, ascending)
  rows:          List<GridRow>  (required, board order)
  nowInstant:    DateTime       (required, UTC)
  cursorInstant: DateTime?      (nullable)
}
```

`BuildGridUseCase` produces the whole `GridViewModel` from
`(board, preferences, referenceDate, nowInstant)`. It is pure and synchronous,
which makes it the natural place for every one of the rules above to be tested
without a widget.

---

## State Machine

### TimeGridCubit

Page-scoped. Depends on `BoardCubit` (read-only), `PreferencesCubit`
(read-only), `TimeZoneEngine`, `Clock` and `TickerService`.

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

TimeGridReady ──stepDate(±1)───────→ TimeGridReady(rebuilt, cursor time-of-day kept)
              ──goToToday()────────→ TimeGridReady(rebuilt)
              ──setCursor(instant)─→ TimeGridReady(cursorInstant updated)
              ──clearCursor()──────→ TimeGridReady(cursorInstant: null)
              ──tick(now)──────────→ TimeGridReady(nowInstant updated)
              ──board changed──────→ TimeGridReady(rebuilt) | TimeGridEmpty
              ──preferences changed→ TimeGridReady(rebuilt)
```

The cubit subscribes to `BoardCubit.stream` and `PreferencesCubit.stream` and
rebuilds the model on any change. It never writes to either.

`tick` only replaces `nowInstant`; it does not rebuild rows or cells. The full
rebuild happens on date, board or preference changes.

---

## Interaction

| Input | Result |
|---|---|
| Tap a cell | Sets the cursor to that slot |
| Drag horizontally on the cells area | Moves the cursor continuously |
| Drag horizontally on the header strip | Scrolls the track |
| Tap the cursor's header chip | Opens the meeting planner seeded with that hour ([meeting_planner.md](meeting_planner.md)) |
| Long-press a row label | Opens row actions: set as home, remove, replace zone |
| Drag a row label vertically | Reorders the board |
| Left / right arrow | Moves the cursor one slot |
| `Home` key | Cursor back to now |
| Swipe left / right on the date pill | Steps the reference date |

Reordering writes through `BoardCubit.reorder`; the grid holds no order of its
own.

---

## Responsive

- **< 600px:** pinned label column narrows to 96px and drops the country line,
  keeping the city label and offset badge. The date pill renders on the page.
- **600–900px:** full label column, sidebar owns the date pill.
- **>= 900px:** same, plus the grid gets the full window width
  (`maxContentWidth` does not apply, design_system §7).
- Row height is constant across breakpoints. Vertical scrolling is a normal
  `ListView.builder` over rows.

---

## Performance

- One shared horizontal `ScrollController` for the header and all rows. Rows do
  not each own a controller.
- Cells are built lazily per row with a `ListView.builder` on the horizontal
  axis, so a 20-row board with a 30-slot window does not build 600 widgets when
  8 columns are visible.
- `GridViewModel` is rebuilt only on the four triggers listed in the state
  machine. Cursor movement mutates one field and repaints via a
  `ValueListenable`, not by rebuilding the model.
- The "now" marker repaints from a `CustomPainter` fed by the 1/60 Hz ticker, so
  it never rebuilds a widget subtree.

---

## Edge Cases

- **Reference day is a DST transition day** → 23 or 25 columns, rule 2. The
  skipped hour simply has no column; the repeated hour has two columns with the
  same local label and different instants, distinguished by the `DstBadge`.
- **A row's zone transitions on a day the reference zone does not** → that row
  shows a duplicated or missing local hour while the columns stay whole. Rule 4
  is what makes this render correctly.
- **Lord Howe's 30-minute DST shift** → after its transition the row's minutes
  change from `:00` to `:30` mid-row. Rule 5 already renders minutes per cell, so
  no special case is needed.
- **Row across the date line** → its date label appears at a different column
  than every other row's, rule 6.
- **All rows in the same zone** → impossible, locations rule 2 rejects it.
- **Board is empty** → `TimeGridEmpty` renders `FeatureEmptyState`, not a grid
  with only a header.
- **Board has exactly one location and it is home** → renders one row. Valid.
- **Home zone unresolved** → the grid falls back to `UTC` as reference and shows
  a banner prompting the user to fix their home city. It does not go blank.
- **Reference date far in the future** (a year out) → allowed. Offsets are
  resolved per instant, so scheduled future transitions apply automatically
  (engine rule 2).
- **User's device clock is wrong** → the "now" marker is wrong and nothing else
  is. Documented, not corrected: correcting it would need a time server and the
  app is not a clock authority.

---

## i18n

Copy under `t.grid.*`: `title`, `today`, `emptyTitle`, `emptyMessage`,
`emptyCta`, `homeBadge`, `dstOn`, `dstTransitionHere`, `unresolvedRow`,
`homeZoneBrokenBanner`, `rowActionSetHome`, `rowActionRemove`,
`rowActionReplaceZone`.

Date labels (`Tue 24`) and hour labels go through `intl` with the app locale, not
through hardcoded strings.

---

## Testing

`test/features/time_grid/domain/build_grid_usecase_test.dart` is where the rules
live. It is a pure-function test, so every case below is cheap:

- Column count is 25 on a US fall-back reference day and 23 on the spring-forward
  one (rule 2).
- Window includes 3 slots before and after the day (rule 3).
- A row in `Asia/Kolkata` against a `America/Sao_Paulo` reference produces `:30`
  minutes in every cell (rule 5).
- A row whose zone transitions mid-window shows the local hour repeating, while
  the reference row does not (rule 4).
- `isDayStart` and `dateLabel` land on different columns for `Pacific/Kiritimati`
  and `Pacific/Niue` (rule 6).
- Band assignment respects a custom working window from preferences (rule 7).
- An unresolved zone yields a row with an empty cell list and `isUnresolved`
  (rule 14).

`test/features/time_grid/presentation/time_grid_cubit_test.dart` covers the state
machine, including cursor time-of-day preservation across `stepDate` (rule 10)
and rebuild-on-board-change.

Widget tests cover: pinned column does not scroll horizontally, cursor highlights
the same instant across rows, and the empty state renders.

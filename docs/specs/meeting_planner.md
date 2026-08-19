# Meeting Planner Spec

Selecting a range of hours on the grid and turning it into something a user can
paste into a message: "Tue 24 Sep, 14:00 to 15:00 in Sao Paulo (18:00 London,
10:00 Los Angeles)".

It is a mode of the grid, not a separate page. Same rows, same columns, same
engine; what changes is that the cursor becomes a selectable range and a summary
panel appears.

---

## Business Rules

1. **A selection is a contiguous range of grid slots**, expressed as
   `{ startInstant, endInstant }` in UTC. It is never stored as a local hour,
   because "14:00" is meaningless without a zone and a date.

2. **Selection is made in the reference zone's columns** and applies to every
   row. Dragging across columns 14 through 16 selects a two-hour block; every row
   shows what that block is locally.

3. **Minimum selection is one slot; maximum is 12.** Beyond half a day the
   "meeting" framing stops meaning anything and the summary becomes unreadable.
   Dragging past the cap stops at the cap rather than refusing the gesture.

4. **A selection may cross the reference day's midnight** and therefore the
   window's edges. When it does, the summary carries explicit dates for every
   row, not just times.

5. **The summary lists home first, then board order.** Each line is
   `label, weekday date, start to end` formatted under the user's 12h/24h
   preference. A line is marked when its local date differs from home's.

6. **Each row in the summary carries its band verdict**: `good`, `fair` or
   `poor` for the selected range, derived from the band of every slot in the
   range for that row. The verdict is the **worst** band in the range: a meeting
   is only as good as its worst hour for that person.

7. **The planner surfaces the best alternative** when at least one row is `poor`:
   the nearest range of the same length, within the same reference day, that
   minimizes the count of `poor` rows and then of `fair` rows. Ties break toward
   the earlier start. This is a pure function
   (`FindBestSlotUseCase`), testable without any UI.

8. **A selection that spans a DST transition is flagged.** Its real duration is
   not what the column count suggests: three columns can be two or four hours. The
   summary shows the actual elapsed duration from the instants, and a `DstBadge`
   explains it.

9. **The copyable text is plain text, built by a use case**, not by string
   interpolation in a widget. It has two shapes: a compact one line per location,
   and a verbose one with UTC offsets. The user picks; the choice persists in
   preferences.

10. **Copy uses the clipboard only.** No share sheet, no link generation, no
    server. A shareable link would need a backend endpoint and public data; that
    is a v2 decision recorded in the roadmap, not a v1 feature.

11. **The planner never mutates the board.** It is a read-only consumer of it.

---

## Entity Contract

```dart
MeetingSelection {
  startInstant: DateTime (required, UTC, inclusive)
  endInstant:   DateTime (required, UTC, exclusive)
  slotCount:    int      (required, 1..12: grid slots, not necessarily hours)
}

MeetingLine {
  location:     SavedLocationEntity (required)
  localStart:   DateTime (required, wall-clock in that zone)
  localEnd:     DateTime (required)
  dayDelta:     int      (required, relative to the home local date)
  verdict:      HourBand (required, the worst band across the range, rule 6)
  crossesDst:   bool     (required)
}

MeetingSummary {
  selection:  MeetingSelection  (required)
  duration:   Duration          (required, real elapsed time, rule 8)
  home:       MeetingLine       (required)
  lines:      List<MeetingLine> (required, board order)
  suggestion: MeetingSelection? (nullable, present only when a row is poor, rule 7)
}
```

---

## Use Cases

```dart
/// Turns a selection into the full summary. Pure, synchronous.
class BuildMeetingSummaryUseCase {
  MeetingSummary call({
    required BoardEntity board,
    required MeetingSelection selection,
    required WorkingHours workingHours,
  });
}

/// The alternative-range search of rule 7. Pure, synchronous.
class FindBestSlotUseCase {
  MeetingSelection? call({
    required BoardEntity board,
    required List<DateTime> daySlots,
    required int slotCount,
    required WorkingHours workingHours,
  });
}

/// Renders the summary as pasteable text. Pure.
class FormatMeetingTextUseCase {
  String call({
    required MeetingSummary summary,
    required MeetingTextStyle style,   // compact | verbose
    required HourFormat hourFormat,
    required Locale locale,
  });
}
```

---

## State Machine

### MeetingPlannerCubit

Page-scoped, created by the grid page when planner mode is entered.

```dart
sealed class MeetingPlannerState extends Equatable
PlannerIdle                                        // mode on, nothing selected
PlannerSelecting({ selection: MeetingSelection })  // drag in progress
PlannerSelected({ summary: MeetingSummary })
```

```
PlannerIdle ──startSelection(slot)───→ PlannerSelecting(1 slot)
PlannerSelecting ──extendTo(slot)────→ PlannerSelecting(clamped to 12, rule 3)
PlannerSelecting ──endSelection()────→ PlannerSelected(summary)

PlannerSelected ──startSelection(slot)→ PlannerSelecting(1 slot)   [restart]
PlannerSelected ──applySuggestion()───→ PlannerSelected(summary of the suggestion)
PlannerSelected ──clear()─────────────→ PlannerIdle
PlannerSelected ──copy(style)─────────→ PlannerSelected + clipboard write + snack
PlannerSelected ──board/prefs changed→ PlannerSelected(recomputed summary)
PlannerSelected ──reference date changed→ PlannerIdle   [the selection's day is gone]
```

Exiting planner mode disposes the cubit; the grid's normal cursor returns.

---

## UI

- Entering the mode: a `TimeBuddyPillToggle` in the grid app bar (Compare /
  Plan), or tapping the cursor chip (time_grid interaction table).
- Selected columns render with a `primary` overlay at 16% alpha across all rows,
  with rounded caps at the range ends.
- The summary is a bottom sheet on mobile (`TimeBuddyPickerSheet` chrome,
  draggable) and a right-hand panel at >= 900px.
- Each summary line is a `TimeBuddySection` row: `LocationRow` on the left,
  `StaticTimeText` range on the right, verdict as the row's left accent dot.
- The suggestion renders as a muted card with a single "Use this instead" action.
- Copy is a `TimeBuddySubmitBar` with the compact/verbose toggle beside it.

---

## Edge Cases

- **Selection of one slot** → valid; duration is that slot's real length, which
  on a transition day may be 0 or 2 hours.
- **Selection spanning a spring-forward gap** → duration is shorter than the slot
  count suggests; rule 8 flag applies.
- **Selection spanning a fall-back repeat** → duration is longer. Same flag, and
  the summary's local times legitimately repeat for the affected rows.
- **Every row is `poor`** → no suggestion is offered if no better range exists in
  the day; the panel says so instead of showing an equally bad alternative.
- **Board has only the home location** → the summary is one line. Valid, if not
  very useful; the empty-state CTA suggests adding a city.
- **Reference date changes while a selection is active** → the selection is
  cleared (state machine), because its instants are no longer on screen.
- **A location is removed while a selection is active** → the summary recomputes
  without that line.
- **Clipboard unavailable** (rare on web without user gesture) → the copy action
  falls back to selectable text in the panel and a snackbar explaining it.

---

## i18n

Copy under `t.planner.*`: `modeCompare`, `modePlan`, `selectHint`,
`durationLabel(duration)`, `verdictGood`, `verdictFair`, `verdictPoor`,
`suggestionTitle`, `suggestionApply`, `noSuggestion`, `copyCompact`,
`copyVerbose`, `copied`, `crossesDst`, `dayTomorrow`, `dayYesterday`.

The pasteable text itself is localized through `FormatMeetingTextUseCase` with
the app locale, so a pt-BR user pastes Portuguese weekday names.

---

## Testing

`test/features/meeting_planner/`:

- `BuildMeetingSummaryUseCase`: verdict is the worst band in the range (rule 6),
  `dayDelta` per line, real duration across a spring-forward and a fall-back
  selection (rule 8).
- `FindBestSlotUseCase`: prefers the range with fewest `poor` rows, then fewest
  `fair`, then the earlier start; returns `null` when nothing improves (rule 7).
- `FormatMeetingTextUseCase`: compact and verbose shapes, 12h and 24h, pt-BR and
  en, a line that carries a date because `dayDelta != 0`.
- `MeetingPlannerCubit`: drag clamps at 12 slots, reference-date change clears
  the selection, board change recomputes.

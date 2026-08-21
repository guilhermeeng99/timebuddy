# Time Converter Spec

"It is 15:00 on 12 March in Lisbon. What time is that everywhere else?"

The converter answers one point-in-time question: one instant, not a range, and
unlike the grid it is not anchored to today. Its whole value is correctness on
dates far from now, where DST rules differ from the current ones. (The meeting
planner, which this spec used to contrast itself with, has been deleted.)

---

## Business Rules

1. **The input is a zone plus local calendar fields**, never an instant. The user
   thinks "15:00 in Lisbon", not "14:00 UTC". The conversion to an instant is the
   first thing the use case does, through `instantFor` (engine rule 5).

2. **The source zone defaults to home**, and the source date-time defaults to the
   next round half hour from now, in that zone. Opening the converter and
   immediately reading a useful answer is the common case.

3. **Targets are the board, minus the source zone.** The user does not select
   targets; they curate their board once and every feature uses it. A one-off
   target is added through the same add-location flow.

4. **A nonexistent local time is resolved forward and disclosed.** If the user
   picks 02:30 on a spring-forward date, `instantFor` returns
   `shiftedForward` (engine rule 6) and the UI says so above the results: "02:30
   does not exist in Lisbon on this date; showing 03:00". It never silently
   answers a different question.

5. **An ambiguous local time resolves to the first occurrence and is disclosed**
   the same way (engine rule 7), with a toggle to switch to the second
   occurrence. On a fall-back date both are legitimate answers and only the user
   knows which they meant.

6. **Every result is computed from the resolved instant**, so a target zone whose
   own DST state differs on that date is handled with no special code.

7. **Results show the local date when it differs from the source's**, with the
   same `Tomorrow` / `Yesterday` treatment as the world clock.

8. **The date range is bounded to +/- 10 years** from now. Beyond that, tzdata's
   future projections are guesses and presenting them as answers is
   overconfident. The picker enforces the bound.

9. **The result set is copyable — unbuilt.** There is no
   `FormatConversionTextUseCase`, no clipboard call in the page, and
   `t.converter.copy` / `copied` are orphaned strings. The rule is kept because
   the feature is still wanted; what is dropped is its old justification, which
   pointed at the deleted planner's `FormatMeetingTextUseCase` for a house
   style that no longer exists. Whoever builds this now sets the format rather
   than matching one.

10. **The converter holds no persisted state, and that now includes the source
    zone.** Its inputs live in the cubit and die with the page.

    This rule used to promise that the last-used source zone was remembered in
    preferences. It is not: `PreferencesEntity` has no such field, and the
    cubit re-derives the source from the board's home zone on every visit
    (rule 2). Unbuilt rather than abandoned — retyping it is still friction —
    but a spec claiming a persisted field that does not exist is worse than one
    that admits the default.

---

## Entity Contract

```dart
ConversionInput {
  sourceZoneId: String   (required)
  year:  int, month: int, day: int  (required)
  hour:  int, minute: int           (required, 0..23 / 0..59)
  ambiguousPick: AmbiguousPick      (required, first | second, rule 5, default first)
}

ConversionLine {
  location:   SavedLocationEntity (required)
  localTime:  DateTime (required)
  dayDelta:   int      (required, relative to the source's local date)
  offsetFromSource: Duration (required)
  offsetFromUtc:    Duration (required)
  band:       HourBand (required)
  isDst:      bool     (required)
  abbreviation: String (required)
}

ConversionResult {
  input:      ConversionInput (required)
  instant:    DateTime (required, UTC: the resolved instant)
  resolution: TimeResolution (required, exact | shiftedForward | ambiguousFirst)
  source:     ConversionLine (required)
  lines:      List<ConversionLine> (required, board order minus the source zone)
}
```

`offsetFromUtc` is carried so the copy path (rule 9) and any absolute badge do
not re-ask the engine for something the result already holds. It is a snapshot
of `(zone, instant)`, never an identity — nothing may cache it past this
result.

`ConversionResult` exposes two derived predicates rather than making the page
re-read the enum: `isDisclosed` (`resolution != exact`, so the page owes a
banner, rules 4 and 5) and `isAmbiguous` (`resolution == ambiguousFirst`, so
the banner carries the toggle). `resolution` describes the *local time*, not
which occurrence was picked: `input.ambiguousPick` says that. The engine's enum
deliberately has no `ambiguousSecond`, because it would make every caller
handle a value that answers a different question.

---

## Use Case

```dart
/// Pure and synchronous. All the rules above are testable here.
class ConvertTimeUseCase {
  ConversionResult call({
    required BoardEntity board,
    required ConversionInput input,
    required WorkingHours workingHours,
  });
}
```

---

## State Machine

### TimeConverterCubit

Page-scoped.

```dart
sealed class TimeConverterState extends Equatable
ConverterPreparing
ConverterReady({ result: ConversionResult })
ConverterError({ failure: Failure })
```

**There is no loading state for a conversion**: every input change recomputes
synchronously from in-memory data, and a spinner for a microsecond of
arithmetic is worse than none. `ConverterPreparing` is not that state and the
distinction is worth keeping. It covers the frames before the *board* has
resolved — a document that really may still be arriving — and the page renders
a shimmer for it exactly as the grid and the world clock do. **No setter ever
emits it**, which is what stops a later change quietly turning it into a
spinner over a keystroke.

```
(init) ──────────────────────────────────────→ ConverterPreparing
ConverterPreparing ──board loaded─────────────→ ConverterReady(result)
                   ──board failed─────────────→ ConverterError(failure)

(init) ──defaults from home + next half hour──→ ConverterReady(result)

ConverterReady ──setSourceZone(zoneId)──→ ConverterReady(recomputed)
               ──setDate(y, m, d)───────→ ConverterReady(recomputed)
               ──setTime(h, m)──────────→ ConverterReady(recomputed)
               ──setAmbiguousPick(p)────→ ConverterReady(recomputed)
               ──stepDay(±1)────────────→ ConverterReady(recomputed)
               ──resetToNow()───────────→ ConverterReady(defaults)
               ──board changed──────────→ ConverterReady(recomputed)
               ──copy()─────────────────→ unbuilt (rule 9); no such method
```

`setDate` and `stepDay` return a `bool` rather than emitting: `false` is rule
8's refusal, and the page turns it into the out-of-range snackbar. A refusal is
not a state.

`ConverterError` is reachable only if the board itself failed to load; the page
then shows `ErrorView`.

---

## UI

Written against the shipped widgets. `TimeBuddyDateField`, `TimeBuddyTimeField`,
`StaticTimeText` and `TimeBuddySubmitBar` are all still `planned` in
[design_system.md](design_system.md) §6 and none of them exists; an earlier
draft of this section named them as though they did.

- Source block: **one `TimeBuddySection`** holding three
  `TimeBuddyPickerField`s — zone, date and time. One widget for all three
  because they are the same thing in a form: a tap-to-open row holding a value
  the user picked. The date and time pickers are Material's own, opened from
  the field's `onTap`.
- Day stepper chevrons flank the date field, so "same time tomorrow" is one
  tap. Stepping past rule 8's bound is a no-op with the `outOfRange` snackbar,
  never a chevron that silently does nothing.
- The section's `trailing` slot carries the `resetToNow` button.
- A disclosure banner above the results when `resolution != exact` (rules 4 and
  5), carrying a `TimeBuddyPillToggle` between `ambiguousFirst` and
  `ambiguousSecond` when the local time is ambiguous.
- Results are `ConversionResultList`: one row per line, `LocationRow` on the
  left, the wall clock through `formatClock` plus its date on the right, and
  the row background tinted from `hourBandColor` — the same band-to-token table
  the grid's cells use.
- A board holding only the source renders the `needMoreCities` note instead of
  an empty list.
- No copy affordance: rule 9 is unbuilt.

---

## Edge Cases

- **Source zone is not on the board** → allowed. The picker searches the whole
  city catalog, and the source line is rendered from the catalog entry rather
  than a `SavedLocationEntity`.
- **Source zone is the only board entry** → results list is empty; the page shows
  a muted "add another city to compare" note rather than an error.
- **Chosen local time does not exist** → rule 4.
- **Chosen local time is ambiguous** → rule 5, with the toggle.
- **Date at the +/- 10 year bound** → the picker clamps; stepping past it is a
  no-op with a snackbar.
- **A target zone abolished DST between now and the chosen date** (or adopted it)
  → handled by rule 6 with no special case, and worth an explicit test since this
  is the converter's whole reason to exist.
- **Feb 29 on a non-leap year** → the date picker cannot produce it. Stepping a
  day from Feb 28 lands on Mar 1 where applicable.
- **Source and a target share a zone** → the target is excluded (rule 3); it
  cannot happen for board rows anyway (locations rule 2).

---

## i18n

Copy under `t.converter.*`, all rendered: `title`, `sourceLabel`, `dateLabel`,
`timeLabel`, `resultTitle`, `shiftedForwardNotice(requested, shown)`,
`ambiguousNotice(zone)`, `ambiguousFirst`, `ambiguousSecond`, `resetToNow`,
`outOfRange(years)`, `needMoreCities`.

`copy` and `copied` also exist in the JSON and are **orphaned**: they are rule
9's copy, waiting for rule 9.

---

## Testing

`test/features/time_converter/`:

- `ConvertTimeUseCase`: a target that is on DST while the source is not, on a
  date six months out (rule 6).
- Spring-forward nonexistent input returns `shiftedForward` and the 03:00 instant
  (rule 4).
- Fall-back ambiguous input returns the earlier instant by default and the later
  one with `AmbiguousPick.second` (rule 5).
- `dayDelta` of +1 for a target across the date line.
- Half-hour offset target renders `:30` minutes.
- A conversion for a 2018 Sao Paulo date applies the DST rules of that year,
  while the same calendar date in 2025 does not (the abolition case).
- `TimeConverterCubit`: defaults on init, recompute on every setter,
  `stepDay` across a month boundary, board change recompute.

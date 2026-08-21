# Preferences Spec

Everything the user can tune, in one document that syncs with the board. Theme,
palette, hour format, working hours, week start and locale.

Working hours deserve special attention: they are not a cosmetic setting. They
drive `hourBandFor`, which drives every color in the grid and the planner's
verdicts.

---

## Entity Contract

```dart
PreferencesEntity {
  themeMode:    ThemeMode    (required, system | light | dark, default system)
  lightPalette: LightPalette (required, default indigoCloud)
  darkPalette:  DarkPalette  (required, default midnightIndigo)
  hourFormat:   ClockFormat  (required, h24 | h12, default from locale)
  workingHours: WorkingHours (required, default 09:00–17:00)
  weekStartsOn: WeekStart    (required, monday | sunday, default from locale)
  showSeconds:  bool         (required, default false)
  localeTag:    String?      (nullable, null means follow the device: 'pt-BR' | 'en')
  revision:     int          (required, see sync.md)
  updatedAt:    DateTime     (required, UTC)

  // Planned. Each field lands with the feature that reads it, so nothing
  // carries a value no screen can set:
  // lastSourceZoneId: String?          (the converter's remembered source, time_converter.md)
}

WorkingHours {
  startHour: int (required, 0..23, inclusive)
  endHour:   int (required, 1..24, exclusive, see rule 4)
}
```

Equatable by all fields, plus `copyWith`. `copyWith` carries one extra flag,
`clearLocaleTag`, because `localeTag: null` cannot express "follow the device
again": passing null is indistinguishable from "leave this field alone".

The clock-format enum is `ClockFormat`, **not** `HourFormat`
(`lib/core/time/time_formats.dart`). Flutter's `material` library already
exports a top-level `HourFormat`, so that name collides in every file importing
both, which is a compile error rather than a matter of taste. Do not "fix" it
back.

The week-start enum is `WeekStart { monday, sunday }`, not a `Weekday`. The
field answers which column a week opens on, and only two answers are legal; a
seven-value weekday enum would let a caller store a Wednesday that no strip and
no picker can render.

The entity field is `localeTag` because it holds a BCP-47 string (`'pt-BR'`,
`'en'`), not a `dart:ui` `Locale`, and calling it `locale` next to a real
`Locale` parameter is how one gets passed where the other belongs. The
persisted JSON key stays `"locale"`, the name the Firestore document already
uses (CLAUDE.md, Firestore Collections): renaming the wire field to match the
Dart field would orphan every stored document to save one word.

---

## Business Rules

1. **Every preference has a default that works with no input.** A user who never
   opens settings gets a coherent app. Defaults are declared once, in the named
   factory constructor `PreferencesEntity.defaults(now:, deviceLocale:)`, and
   are the same values the provisioning path writes (sync.md). A named factory
   constructor rather than a static helper: building the defaults *is* building
   the entity, so there is no second construction path to keep in step. Both
   inputs are parameters so first-launch seeding is deterministic under test
   instead of reading an ambient clock and locale.

2. **Locale-derived defaults are computed at first launch only.** `hourFormat`
   and `weekStartsOn` are seeded from the device locale (a `pt-BR` device gets
   24h and Monday; an `en-US` one gets 12h and Sunday) and then belong to the
   user. Changing the device locale later does not silently rewrite them. One
   predicate seeds both fields from a deliberately tiny country set (`US`,
   `CA`, `PH`): it only has to be a good guess on first launch, both settings
   are one tap away, and a full CLDR table would be hundreds of rows of
   maintenance for a value the user can correct in a second.

3. **`localeTag: null` means follow the device.** It is a real value, not a
   missing one: a user who explicitly picks Portuguese on an English phone must
   keep Portuguese, and a user who never chose must follow the phone. Going back
   to the device is `setLocaleTag(null)`, which reaches the entity as
   `copyWith(clearLocaleTag: true)`.

4. **`workingHours` is half-open, and `endHour` may be less than `startHour`.**
   `startHour` is inclusive, `endHour` is exclusive: `09:00` to `17:00` is
   `WorkingHours(startHour: 9, endHour: 17)` and covers the hours 9 through 16.
   A night-shift window of 22:00 to 06:00 is `start: 22, end: 6` and wraps past
   midnight. Every member is wrap-aware precisely so no caller special-cases the
   wrap: `contains(hour)` is `(hour - startHour) % 24 < lengthInHours`, one
   distance rather than a pair of comparisons, and it takes the hour modulo 24
   so a caller may pass `(hour + 23) % 24` for the previous hour without
   guarding. `lengthInHours` is `endHour - startHour`, plus 24 when that is not
   positive. Midnight as an end is written `24`, never `0`; `isValid` rejects an
   end of `0` so the two spellings never coexist in stored data. `hourBandFor`
   inherits all of this; nothing else needs to know.

5. **The working window must be at least 1 hour and at most 16.** Below that the
   grid is a wall of `poor`; above it the color coding stops discriminating.
   `WorkingHours.isValid` checks that both ends are in range *before* doing the
   span arithmetic, so a wild persisted value never reaches it. A window whose
   start equals its end fails too: `lengthInHours` reads that pair as a full day
   (24) rather than as an empty one, and 24 is past the cap.

   Enforced in the parser and in the form, differently on purpose. The parser
   and `setWorkingHours` go through `WorkingHours.clamped()`, which returns the
   whole default 09:00 to 17:00 window; there is deliberately no partial repair,
   since a pair that survived a bad parse carries no reliable intent and nudging
   one end hands the user a window they never chose. The settings form does not
   clamp at all: it refuses the invalid pair with a message and leaves the
   current window standing, because a user who picks a 20-hour window would
   otherwise watch their choice silently become someone else's.

6. **Changing a preference is immediate and global.** `PreferencesCubit` is a
   singleton; grid, clocks, planner and converter subscribe and rebuild. There is
   no save button in settings.

7. **Theme and palette changes apply without a restart, and without a cubit of
   their own.** There is no `ThemeCubit`, no `LightPaletteCubit` and no
   `DarkPaletteCubit`: theme mode and both palette ids are fields of this
   document, and two cubits persisting the same field are two sources of truth
   for it, which drift the moment one of them writes and the other does not.
   `PreferencesCubit` is the only writer. `lib/app/app_widget.dart` reads its
   state, assigns `AppColors.light = LightPalettes.colorsFor(...)` and
   `AppColors.dark = DarkPalettes.colorsFor(...)`, and only then builds
   `MaterialApp`; the theme builders read those statics at call time, so the
   whole runtime switch is two assignments and one rebuild (design_system §2).

8. **Preferences sync with the board but independently of it** (sync.md rule 7):
   changing the theme on the phone does not bump the board's revision.

9. **An unknown persisted enum value degrades to the default**, through
   `enumByName(values, raw, orElse:)`. A palette removed in a future version must
   not brick the app for someone who had it selected.

10. **`showSeconds` changes the ticker rate**, not just the display
    (world_clock rule 4). Turning it on is the only way to get a 1 Hz ticker.
    The app widget applies it once, through `TickerService.setNeedsSeconds`, as
    a side effect of the preference change: a per-widget claim on the rate would
    need reference counting, and one widget forgetting to release it would pin
    the whole app at 1 Hz.

---

## Contract

```dart
abstract class PreferencesRepository {
  Future<Either<Failure, PreferencesEntity>> load({
    required Locale deviceLocale,
  });

  Future<Either<Failure, PreferencesEntity>> save(
    PreferencesEntity preferences,
  );
}
```

`load` reads the stored document and, when nothing has ever been written, seeds
the locale-derived defaults *and persists them in the same call* (rules 1 and
2). Leaving the seeds unwritten would re-derive them from whatever locale the
device reports next launch, which is exactly what rule 2 forbids.
`deviceLocale` is consulted on that first seeding only.

There is no `userId` parameter yet: there is no auth until M3 (auth.md), so
there is exactly one preferences document per install, and threading an id no
caller can supply would be ceremony rather than a contract.

`save` writes what it is given. Bumping `revision` and stamping `updatedAt` is
the caller's job, so a re-save during sync reconciliation does not inflate the
revision it is trying to reconcile.

Same local-first, write-through, revision-based contract as the board. The
current implementation is local only (`shared_preferences` is both the read path
and the durability path); the Firestore mirror, the dirty flag and the passive
indicator land with the sync layer. See [sync.md](sync.md).

---

## State Machine

### PreferencesCubit

Singleton, provided app-wide, holds the loaded preferences after startup.

```dart
sealed class PreferencesState extends Equatable
PreferencesLoading
PreferencesReady(PreferencesEntity preferences)
```

```
PreferencesLoading ──load(deviceLocale:) resolves──→ PreferencesReady(stored | seeded | defaults)

PreferencesReady ──setThemeMode(m)─────────────→ PreferencesReady(updated) + persist
                 ──setLightPalette(p)──────────→ PreferencesReady(updated) + persist
                 ──setDarkPalette(p)───────────→ PreferencesReady(updated) + persist
                 ──setClockFormat(f)───────────→ PreferencesReady(updated) + persist
                 ──setWorkingHours(w)──────────→ PreferencesReady(updated) + persist   [clamped, rule 5]
                 ──setWeekStart(d)─────────────→ PreferencesReady(updated) + persist
                 ──setShowSeconds(value: b)────→ PreferencesReady(updated) + persist
                 ──setLocaleTag(t)─────────────→ PreferencesReady(updated) + persist
                 ──adoptFromSync(p)────────────→ PreferencesReady(p)
```

The setter names follow the types they move, not the field names they land on:
`setClockFormat` takes a `ClockFormat`, `setLocaleTag` takes a BCP-47 string.
`setShowSeconds` takes a **named required** `bool value` rather than a
positional flag, because `setShowSeconds(true)` at a call site says nothing
about what is being turned on, and the lint set bans positional booleans for
exactly that reason.

Every setter funnels through one private `_mutate`, which bumps `revision` and
restamps `updatedAt` from the injected `Clock`, emits, and only then persists.
The emit comes first on purpose: the UI must not wait on a disk write to repaint
a theme. The save result is then dropped, also on purpose: a failed write is
never shown as an error (sync.md rule 4), the in-memory value stays
authoritative, and durability is the dirty flag's problem.

A mutation that arrives while the state is still `PreferencesLoading` is
ignored: nothing is emitted and nothing is persisted. Settings are unreachable
before the startup load resolves, so a setter landing there means a caller
jumped the gun, and inventing a document to mutate would hand that invention
back to the user as if they had chosen it.

There is no error state. A persistence failure is handled by sync.md rule 4
(dirty flag, passive indicator); the in-memory value always applies. A `load`
that fails falls back to the same defaults a first launch would produce, so a
device that cannot read its own storage still gets a coherent app.

`adoptFromSync` is how a remote-wins reconciliation reaches the UI without the
cubit knowing about Firestore. It deliberately does not persist: the sync layer
has already written both sides, and saving here would bump the revision again
and bounce a fresh write back at the document it just adopted.

---

## Settings page

One page, grouped with `TimeBuddySection`:

| Group | Controls |
|---|---|
| Appearance | Theme mode pill (System / Light / Dark), light palette row, dark palette row |
| Time | 12h / 24h pill toggle, show seconds switch, week starts on pill |
| Working hours | Two hour dropdowns (inclusive start `0..23`, exclusive end `1..24`) with a live preview strip of the 24 bands |
| Language | System / Portugues / English |
| Account (planned, lands with auth in M3) | Name, email, photo, sign out, delete account |
| About | App version, tzdata version (engine rule 12), licenses |

The Account group is the one row of that table the page does not render. There
is no authentication yet (auth.md), and the page omits the group rather than
stubbing it: a "not signed in" row with a dead sign-out button promises a
feature the build cannot deliver. Its copy keys already exist, so the group is
one section widget away once sign-in lands.

The working-hours preview is not decoration: it is the only place a user can see
what the bands will look like before committing, and it renders with the real
`HourCell` widget.

The two palette rows open a bottom sheet listing the whole catalog, each row
previewing its *own* primary, background, surface and good-hour green rather
than the active theme's, since the active theme is what the user is choosing to
leave. Row labels come from the catalog entry
(`LightPaletteOption.label` / `DarkPaletteOption.label`), not from slang: a
palette name is a product name, the same in every language, and routing it
through translations invites ten translated names for one product.

The tzdata row renders a dash until the engine can report its real release
(timezone_engine.md rule 12). An honest dash beats a hardcoded release string
that goes stale silently and is believed anyway.

---

## Model Serialization

Same dual-encoding JSON as the board (sync.md). Enum fields serialize as
`enum.name` and parse through `enumByName(..., orElse:)` (rule 9).

`workingHours` is a nested map `{ start, end }`. A malformed or out-of-range pair
falls back to the default window rather than to a partial one, because a window
with a valid start and an invalid end is worse than the default.

`localeTag` is written under the key `"locale"`, the name the synced document
uses (Entity Contract above), and a null tag is written as a **present null**
rather than omitted, so "follow the device" survives the round trip as a value
instead of coming back as a missing field (rule 3).

`updatedAt` is written as ISO-8601 and read back from either an ISO-8601 string
or a millisecond epoch int, so one document copied between the local store and
Firestore never needs a conversion pass. An unreadable stamp falls back to the
epoch, never to "now": a timestamp nobody can read must lose every tie it enters
(sync.md), not win them by looking freshly written.

---

## Edge Cases

- **First launch on a `pt-BR` device** → 24h, week starts Monday, `localeTag`
  null (follows device, resolves to Portuguese).
- **First launch on an `en-US` device** → 12h, week starts Sunday.
- **Device locale changes later** → nothing changes (rule 2).
- **User picks a locale the app does not ship** → falls back to English; the
  stored value is kept, so shipping that locale later just works.
- **Working window wrapping midnight** (22 to 6) → valid, rule 4.
- **Working window of 1 hour** → valid, the minimum.
- **Working window where start equals end** → reads as a full 24-hour day, so it
  fails `isValid`: the form refuses it with a message and keeps the current
  window, while a parsed value like that falls back to the whole default window.
- **A setter called before the first load resolves** → dropped, with no state
  emitted and no write (State Machine).
- **A palette enum value that no longer exists** → default palette, rule 9.
- **Preferences document missing remotely** → provisioned from defaults
  (sync.md, Provisioning).
- **Theme set to `system` and the OS switches at sunset** → follows immediately,
  since `MaterialApp` watches the platform brightness.

---

## i18n

Copy under `t.settings.*`: `title`, `groupAppearance`, `groupTime`,
`groupWorkingHours`, `groupLanguage`, `groupAccount`, `groupAbout`, `themeMode`,
`themeSystem`, `themeLight`, `themeDark`, `lightPalette`, `darkPalette`,
`hourFormat`, `hourFormat12`, `hourFormat24`, `showSeconds`, `showSecondsHint`,
`weekStartsOn`, `weekStartsMonday`, `weekStartsSunday`, `workingHoursStart`,
`workingHoursEnd`, `workingHoursSummary`, `workingHoursPreview`,
`workingHoursInvalid`, `languageSystem`, `languagePortuguese`,
`languageEnglish`, `notSignedIn`, `signOut`, `deleteAccount`, `appVersion`,
`tzDataVersion`, `licenses`.

`workingHoursInvalid` takes `min` and `max` parameters instead of spelling out
1 and 16, so the message cannot drift from `WorkingHours.minLength` /
`maxLength` when the bounds move.

The Account keys ship ahead of the group that renders them (Settings page
above): they are finished copy for a section that lands with auth, and writing
them in one pass is cheaper than sending the translator back for four strings.
Palette names are the deliberate exception to routing copy through slang: they
live in the catalog, because a palette name is a product name.

---

## Testing

`test/features/preferences/`:

- Defaults are coherent and match the provisioning values (rule 1).
- Locale-derived seeding for `pt-BR` and `en-US` (rule 2), and that a stored
  document comes back untouched, which is what keeps a later device-locale
  change from rewriting it.
- Every setter moves exactly its own field, bumps `revision`, restamps
  `updatedAt` and persists once. Table-driven: the setters share one contract,
  so the part worth reading is which field each one moves.
- `setWorkingHours` falls back to the default window for a span past 16 hours
  and for a start equal to its end (rule 5).
- A mutation arriving before the first load resolves emits nothing and persists
  nothing (State Machine).
- A failed save emits exactly one state, the optimistic one: a rollback or an
  error state would show up here as a second emission (sync.md rule 4).
- Unknown palette / clock-format strings degrade to defaults (rule 9), and a
  window with a valid start and a broken end is discarded whole.
- `adoptFromSync` replaces state without persisting again (no write loop).

The contracts this spec leans on but does not own are tested next to the code
that does. `test/core/time/working_hours_test.dart` pins the half-open
window, the midnight wrap and the length bounds (rules 4 and 5), and
`test/core/time/hour_band_test.dart` pins the bands a wrapping window produces,
since that is the contract that matters. The ticker rate `showSeconds` drives
(rule 10) belongs to `test/core/time/ticker_service_test.dart`; the app widget
is the piece that connects the preference to it.

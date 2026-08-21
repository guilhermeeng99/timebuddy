# Design System Spec

The shared visual language of TimeBuddy: tokens, typography, layout rules, and
the reusable `TimeBuddy*` widget library. This is the contract every new screen
must follow so the app reads as one product, not a pile of pages.

**Read this before building any new screen or widget.** When a screen needs
something not covered here, prefer extending a token or a shared widget over
inventing a one-off, then update this spec.

> **Provenance.** This system is ported from the Financo project so the two apps
> share one visual identity. Color values, the type scale and the Material theme
> wiring are identical. What changed: the money tokens (`income` / `expense`)
> became time-band tokens (§2), the `Financo*` prefix became `TimeBuddy*`, and
> the spacing/radius scale is promoted to real constants from day one (it was an
> open backlog item in Financo, see §10).

> Scope: visual and interaction system only. Feature behavior lives in the
> per-feature specs (`time_grid.md`, `world_clock.md`, …). UI copy lives in slang
> (`lib/gen/i18n/`). Code conventions live in `CLAUDE.md`.

---

## 1. Where things live

```
lib/app/theme/
├── app_colors.dart        # AppColorsData (semantic color tokens) + AppColors (active light/dark)
├── app_typography.dart    # AppTypography.textTheme (the type scale) + AppTypography.clock()
├── app_spacing.dart       # AppSpacing + AppRadius + GridMetrics constants
├── app_theme.dart         # AppTheme.light()/dark(): Material 3 ThemeData wiring
├── light_palettes.dart    # catalog of selectable light palettes
└── dark_palettes.dart     # catalog of selectable dark palettes

lib/core/extensions/context_extensions.dart  # context.appColors / textTheme / screenSize / isDarkMode / showSnack

lib/app/widgets/           # the shared component library (TimeBuddy* + system widgets)
```

There is no theme cubit and no palette cubit in this folder, by design. Theme
mode and the two selected palettes are fields of the preferences document, so
`PreferencesCubit` owns them and `lib/app/app_widget.dart` applies them (§2 and
preferences.md rule 7).

**Access rule:** never read raw theme objects ad hoc. Always go through the
`BuildContext` extensions:

```dart
final colors = context.appColors;   // AppColorsData: semantic colors
final text   = context.textTheme;   // the type scale
context.isDarkMode;                  // bool
context.screenSize;                  // Size
```

---

## 2. Color tokens

Colors are **semantic**, never literal. The full token set (`AppColorsData`,
`lib/app/theme/app_colors.dart`):

| Token | Role |
|-------|------|
| `primary` / `primaryLight` / `primaryDark` | Brand accent: CTAs, active nav, selection, the hour cursor, focus ring |
| `secondary` | Secondary accent (currently green, same value as `hourGood`) |
| `background` | App/scaffold backdrop (darkest layer) |
| `surface` | Card / sheet / app-bar fill (one layer above background) |
| `surfaceVariant` | Input fill, dividers, subtle chips, hover/track (between bg and surface) |
| `onBackground` | Primary text/icon on background or surface |
| `onBackgroundLight` | Muted text: labels, captions, placeholders, section headers, inactive nav |
| `hourGood` | Comfortable hour band (inside working hours), green |
| `hourFair` | Borderline hour band (shoulder hours), amber |
| `hourPoor` | Bad hour band (outside waking hours), red |
| `warning` | Caution copy and badges, amber |
| `success` | Confirmation, green |
| `error` | Validation/destructive, red |

Several tokens are **computed getters**, not palette fields, for the same reason
Financo computes `onPrimary`: they are fully determined by other fields, and
making all 20 catalog palettes hand-pick them invites 20 chances to get it wrong.

| Getter | Definition | Use |
|--------|-----------|-----|
| `onPrimary` | `foregroundOn(primary)` | Foreground on a `primary` fill: filled button label, selected chip icon, hour-cursor label |
| `hourNight` | `Color.lerp(surfaceVariant, onBackgroundLight, 0.35)` | The sleeping-hours band. Must read as "dimmed", not as a fourth accent color, in both light and dark |
| `scrim` | Always `0xFF000000` | Modal dim, tooltip backdrop. Callers choose the alpha |
| `primaryInk` | `inkFor(primary)` | The accent as **text**: the `Today` pill, the `Tomorrow` word, a section's count badge, the `Home` badge |
| `primaryGlyph` | `inkFor(primary, minRatio: 3)` | The accent as a **meaningful graphic**: the "now" line, a selected row's check, the splash's progress track |
| `warningInk` / `successInk` / `errorInk` | `inkFor(token, minRatio: 3)` | A status color as a glyph: the banner triangle, the DST dot, the sync icons |

`foregroundOn(background)` stays as the shared helper for arbitrary backdrops the
theme does not own, such as a user-picked location color. **It picks whichever
of black and white measures better, and that is a correction made in the M5
accessibility pass**: it used to be a luminance threshold of `0.55`, which put
white on the primary of 14 of the 20 palettes whose primary should carry black,
as low as `1.81:1` against a 4.5 bar. Since `onPrimary` labels every filled
button and the selected nav destination, those were the app's least readable
pixels on most palettes.

### The accessibility floor, and the repair

Two constants on `AppColorsData` name the WCAG 2.1 AA thresholds the app holds
itself to, so no call site has to remember a number:

* `minTextRatio` = **4.5** — anything below 18pt that is read.
* `minGlyphRatio` = **3.0** — icons that carry meaning, markers, tracks.

`inkFor(accent, {minRatio})` returns `accent` **unchanged** when it already
clears the bar against `background`, and otherwise pulls it 40% toward
`onBackground`. Three properties matter and are pinned by
`test/app/theme/palette_contrast_test.dart`:

1. **The repair is rare.** 13 of the 20 palettes never trigger it. A blend
   applied unconditionally would mute the accent everywhere for no measured
   gain, which is a design change wearing an accessibility argument.
2. **The catalog is not edited.** A palette keeps the exact color the user
   picked for every fill, disc and wash; only the places that draw the accent
   *as content* take the darker one.
3. **The blend goes toward `onBackground`**, not toward black or white, so the
   result stays in the palette's own ink family and a repaired accent on a dark
   palette lightens rather than turning muddy. It is the move `HourCell` already
   makes on its digits.

The one place the catalog *was* edited is `onBackgroundLight`, on four light
palettes (Indigo Cloud, Mint Fresh, Slate Modern, Cyan Pop), by between 3% and
10% toward the foreground. Muted text is text and there is no derived token
between it and its hundreds of call sites, so the fix belongs to the value.

### Hour band rule

The band of an hour is **derived, never stored**: `hourBandFor(localHour,
workingHours)` in `lib/core/time/hour_band.dart` maps a local hour to
`HourBand.good | fair | poor | night`, and `hourBandColor(band, colors)` in
`lib/app/widgets/hour_cell.dart` is the single mapping from that band to exactly
one token.

The order of the checks is part of the contract, not an implementation detail:

1. Inside the user's working hours → `good`
2. One hour on either side of the working window, wrap-aware → `fair`
3. Otherwise, 23:00 through 06:59 local → `night`
4. Everything else, awake but outside the window → `poor`

Working-hours membership is tested **before** the fixed night window on purpose.
A night-shift user with a 22:00 to 06:00 window is awake and available at 23:00,
so that hour must read `good`; letting the night window win first would paint
their whole shift as asleep, and shift workers are exactly the population this
app must not get wrong. The shoulder check sits ahead of the night window for
the same reason: 06:00 next to a 07:00 start is `fair`, not `night`.

Cells are painted with the token at **16% alpha** for the fill and the full token
for the text when emphasis is needed. No screen hand-picks these colors: every
hour surface goes through `HourCell`.

**A band is never carried by colour alone.** Every cell also announces
`"{hour}, {band}"` — `t.common.hourInBand` over the four `t.bands.*` names — so
the answer the screen exists to give survives a screen reader and does not
depend on telling green from amber. `HourCell.bandLabel(band)` is the one
mapping from a band to its word, the way `hourBandColor` is the one mapping to
its colour; a caller that draws marks *over* a cell (the grid's day boundary and
DST dot) passes a fuller `semanticLabel` rather than composing a fifth
vocabulary. Pinned by `test/app/accessibility_test.dart`.

What this does **not** solve is the sighted colour-blind reader: the four bands
are still four hues, and the only non-colour cue on screen is the hour itself.
Adding a per-band shape would put a second mark in every one of six hundred
cells, so it is a deliberate open question rather than an oversight — recorded
under Open questions in [time_grid.md](time_grid.md).

### Palette system (runtime-switchable)

> **The settings page no longer offers a palette picker.** Both catalogs still
> exist and `PreferencesEntity` still carries the two fields — the machinery is
> intact and synced — but Appearance is one theme toggle now. Twenty options
> behind two sheets was a decision the screen asked for and almost nobody has
> a reason to make; `palette_picker_sheet.dart` stays for a future entry point
> rather than being deleted.


`AppColors.light` / `AppColors.dark` are **mutable** statics. The user picks a
palette from `light_palettes.dart` / `dark_palettes.dart` at runtime, and the
choice is a field of the preferences document rather than the state of a cubit
of its own: there is no `ThemeCubit`, `LightPaletteCubit` or
`DarkPaletteCubit`, because two cubits persisting the same field are two sources
of truth for it (preferences.md rule 7).

`PreferencesCubit` holds theme mode and both palette ids.
`lib/app/app_widget.dart` reads that state and, before building `MaterialApp`,
assigns:

```dart
AppColors.light = LightPalettes.colorsFor(preferences.lightPalette);
AppColors.dark = DarkPalettes.colorsFor(preferences.darkPalette);
```

`AppTheme.light()` / `AppTheme.dark()` read those statics at call time, not at
import time, so the two assignments plus the rebuild are the entire runtime
switch. `MaterialApp.themeMode` decides which brightness renders, and
`context.appColors` returns the active palette for it.

**Implication:** any new palette must define the entire `AppColorsData` field
set, and every screen inherits palette changes for free **as long as it uses the
tokens**.

The catalog ships 10 light and 10 dark palettes, ported from Financo. The two
enums are **separate id sets**, not one set reused for both brightnesses: a dark
palette is a designed counterpart, not a darkened light one, and sharing ids
would promise a pairing the hexes do not honor. `LightPalette` and `DarkPalette`
are also persisted independently, so a user can run Indigo Cloud by day and
Pure Black by night.

- `LightPalette`: `indigoCloud` (default, "Indigo Cloud"), `mintFresh`,
  `sunsetCoral`, `oceanBreeze`, `lavenderSoft`, `forestSage`, `roseGold`,
  `slateModern`, `amberWarm`, `cyanPop`.
- `DarkPalette`: `midnightIndigo` (default, "Midnight Indigo"), `forestNight`,
  `crimsonEmber`, `deepOcean`, `royalPurple`, `oliveNight`, `roseNoir`,
  `pureBlack`, `honeyDusk`, `cyanNeon`.

Both are persisted by `enum.name` (preferences.md rule 9), so renaming a value
silently resets everyone who had picked it: append new palettes at the end. The
picker label lives on the catalog entry (`LightPaletteOption.label`), not in
slang, because a palette name is a product name and reads the same in every
language.

Default light palette values (Indigo Cloud), for reference:

```dart
primary: 0xFF5B5FEF, primaryLight: 0xFF7C83FF, primaryDark: 0xFF3F43C9,
secondary: 0xFF22C55E,
background: 0xFFF6F7FB, surface: 0xFFFFFFFF, surfaceVariant: 0xFFEEF0F6,
onBackground: 0xFF1A1B1F, onBackgroundLight: 0xFF6B7280,
hourGood: 0xFF22C55E, hourFair: 0xFFF59E0B, hourPoor: 0xFFEF4444,
warning: 0xFFF59E0B, success: 0xFF22C55E, error: 0xFFEF4444,
```

Default dark palette (Midnight Indigo):

```dart
primary: 0xFF7C83FF, primaryLight: 0xFFA5ABFF, primaryDark: 0xFF5B5FEF,
secondary: 0xFF22C55E,
background: 0xFF0F1117, surface: 0xFF181C24, surfaceVariant: 0xFF212632,
onBackground: 0xFFE6E9F0, onBackgroundLight: 0xFF9AA3B2,
hourGood: 0xFF22C55E, hourFair: 0xFFFBBF24, hourPoor: 0xFFF87171,
warning: 0xFFFBBF24, success: 0xFF22C55E, error: 0xFFF87171,
```

### Hard rule

Never write a `Color(0x…)` literal or a `Colors.<name>` in feature/UI code. The
only sanctioned literals live in `lib/app/theme/`. A new literal anywhere else is
a design-system bug.

---

## 3. Typography

Two families, wired in `app_typography.dart`, exposed as the Material `TextTheme`
(`context.textTheme`). **Poppins** for display, branding and numbers (geometric,
characterful). **Inter** for everything textual (legible at small sizes).

| Style | Font / Size / Weight | Typical use |
|-------|----------------------|-------------|
| `displayLarge` | Poppins 32 bold | Hero clock on the world-clock header |
| `displayMedium` | Poppins 28 bold | Large clock digits |
| `displaySmall` | Poppins 24 / 600 | Converter result time |
| `headlineLarge` | Poppins 22 / 600 | Large app-bar title |
| `headlineMedium` | Poppins 20 / 600 | Page/section titles |
| `headlineSmall` | Poppins 18 / 600 | Card headline |
| `titleLarge` | Poppins 16 / 600 | Card titles, city name in a clock row |
| `titleMedium` | Inter 16 / 500 | App-bar title, emphasis rows, button text |
| `titleSmall` | Inter 14 / 500 | List-row titles |
| `bodyLarge` | Inter 16 / 400 (h1.5) | Long-form body |
| `bodyMedium` | Inter 14 / 400 (h1.5) | Default body |
| `bodySmall` | Inter 12 / 400 (h1.5) | Captions, hints, offset subtitles |
| `labelLarge` | Inter 14 / 500 | Chip labels |
| `labelMedium` | Inter 12 / 500 | Secondary labels, day-of-week strip |
| `labelSmall` | Inter 11 / 500 | Section headers (uppercased), pills, grid hour numbers |

- **Clock digits** use `AppTypography.clock({required Color color, double
  fontSize = 18})` (Poppins 600, `FontFeature.tabularFigures()`), not the text
  scale. Both parameters are named and the color is required, since a clock
  style with no color would inherit whatever the ambient `DefaultTextStyle`
  happens to be. Tabular figures are mandatory: proportional digits make a
  ticking clock jitter horizontally every second. Wrapped by `ClockText`.
- **Section headers** are `labelSmall` + `FontWeight.w600` + `letterSpacing 0.8`
  + `.toUpperCase()` + `onBackgroundLight`, encapsulated by `TimeBuddySection`.
- Color is applied by the theme (`bodyColor` / `displayColor = onBackground`);
  use `.copyWith(color: …)` only to deviate (muted text, band colors, accents).

---

## 4. Spacing & radius scale

Unlike Financo, these are **real constants** from the start
(`lib/app/theme/app_spacing.dart`). Inline numeric spacing in feature code is a
review blocker.

```dart
abstract class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;   // standard page gutter
  static const double xl = 20;   // gap between form/content sections
  static const double xxl = 24;  // large block separation
}

abstract class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;   // inputs, buttons, small tiles (most common)
  static const double lg = 16;   // cardTheme default, medium containers
  static const double xl = 20;   // content cards, sheets, pill chips
}
```

They are `abstract class` holders rather than instantiable ones: these are
namespaces for constants, and nothing should ever hold an `AppSpacing`.

Grid geometry is its own named set, because those values are layout math, not
generic spacing (see [time_grid.md](time_grid.md)):

```dart
abstract class GridMetrics {
  static const double hourColumnWidth = 60;   // reference only, see below
  static const double labelColumnWidth = 180;
  static const double rowHeight = 72;
  static const double headerHeight = 48;
}
```

All four grew when the grid's type scale did: 44/132/64/40 was the first pass,
and at 44 a half-hour zone's `05:45` had to shrink to 9pt to fit, which made
Kolkata, Kathmandu and Chatham — the rows that most need explaining — the
hardest ones on the screen to read. [time_grid.md](time_grid.md) carries the
same table with the per-value reasoning; this block is the copy, not the
source.

**`hourColumnWidth` is a reference value, not the grid's column width.** The
grid resolves its column at layout time through `GridLayout.resolve`
(`lib/features/time_grid/presentation/grid_layout.dart`), which divides the
available track into a whole number of equal columns bounded by
`GridLayout.minColumnWidth` (48) and `maxColumnWidth` (96); `GridHeaderStrip`
and `GridRowView` both take that resolved width as a required parameter. 60 is
what a cell takes when nothing constrains it and the size the type scale was
chosen against — `HourCell` still names it as its own unconstrained width — but
no grid surface reads it to lay a column out, and a spec or a widget that
treats it as the column width is describing the 44pt era
([time_grid.md](time_grid.md) rule 12).

**Hairlines and dividers:** `1px`, color `surfaceVariant` (or the theme
`Divider`). The grid's day-boundary line is `1px` in `onBackgroundLight` at 40%
alpha.

---

## 4b. Icons

**Font Awesome, through `package:font_awesome_flutter`, rendered with
`FaIcon`.** Ported from Financo, which is where the look came from.

| Rule | Why |
| --- | --- |
| **`AppIcon(...)`, never a bare `FaIcon` and never `Icon`** | `FaIcon` is Flutter's `Icon` with the `SizedBox` and the `Center` deliberately removed, so a glyph lays out at its own intrinsic width. That is right for the package — Font Awesome glyphs are often wider than they are tall and a fixed square clips them — but it means every icon inside a fixed-size parent sits wherever its advance width leaves it. It shipped once as a brand mark pinned to the corner of its disc and date-stepper chevrons drifting out of their tap targets. `AppIcon` puts the square and the centring back *around* the glyph. |
| `FaIconData`, never `IconData`, on a widget's icon parameter | `FaIconData` **wraps** an `IconData` rather than extending it, precisely so the plain `Icon` widget cannot be handed a Font Awesome glyph. The type is the guard; do not reach for `.data` to get around it. `find.byIcon` in a test is the one legitimate `.data` call site. |
| A widget's icon parameter is typed `FaIconData` | Same guard, one level up: it is what stops a Material glyph landing in a screen that is otherwise all Font Awesome. |
| Row icons are 15pt on a 36pt disc; chevrons are 12pt; nav icons are 20pt on the rail's brand mark and 22pt on a destination, in both nav surfaces | Font Awesome glyphs are optically lighter than Material's at the same nominal size. |
| Nav destinations carry **one** glyph, not an outline/fill pair | The free set has a regular weight for `clock` but none for `tableCells`, `rightLeft` or `gear`, so half the nav would swap shape on selection and half would not. Selection is carried by colour, by the tinted pill and by the accent bar — three signals that work for every destination. |

**Icon tree-shaking has to be off, and this is not a performance oversight.**
`flutter build` scans the compiled constants for `IconData` and rewrites each
bundled font to hold only the code points it found. It does not see through
`FaIconData`: a release build of this app kept **22** of the 38 icons it uses
and silently dropped the other **16**, which then rendered as empty boxes. It
is silent because a missing glyph is not a build error — the app compiles, runs
and draws tofu.

Every web build therefore passes `--no-tree-shake-icons`, and CI runs
`scripts/check_glyphs.py` afterwards, which parses the `cmap` of each bundled
`.otf` and fails if any icon the source references is absent. The cost is
roughly 500 KB of font against a bundle whose CanvasKit alone is 7 MB.

**A second, local-only trap worth naming.** `flutter build` copies the package
fonts preserving their original mtime, so a dev server answering
`If-Modified-Since` will send `304` and a browser will keep serving a
*previously tree-shaken* copy for as long as its cache lives. Symptom: the
glyph check passes, the file on disk is correct, and the page still shows tofu.
`touch build/web/assets/**/*.otf` is the fix; it is not a defect in the app.

Glyphs are also chosen for legibility at the size they are drawn, which is not
the same as choosing them for meaning. The sun — in either weight — puts eight
triangular rays around a disc that merge into it below roughly 20pt and read as
a cog: `DayNightDot` uses a filled circle and `DstBadge` a circled up arrow for
exactly that reason, both measured on screen rather than assumed.

The Material set is gone from `lib/` apart from framework-supplied glyphs
(`Switch`, `DropdownButton`, `showDatePicker`). It was not ugly so much as
*generic*: at 15pt inside a tinted disc, Material's rounded variants lose their
silhouette, and a settings screen becomes twenty grey blobs the eye cannot use
as a column.

---

## 5. Material theme defaults

`AppTheme._buildTheme` (Material 3) sets these so you rarely style raw Material
widgets by hand. Values are identical to Financo:

- **Inputs** (`InputDecorationTheme`): filled with `surfaceVariant`, radius
  `AppRadius.md`, no resting border, focused border = `primary` width `2`, error
  border = `error`, content padding `16 x 14`.
- **ElevatedButton / OutlinedButton**: full width (`minimumSize ∞ x 52`), radius
  `AppRadius.md`, `primary` fill / outline, `titleMedium` 600 label.
- **Card**: `surface`, elevation `1`, radius `AppRadius.lg`.
- **Chip**: `surfaceVariant` background, `primary` when selected, radius
  `AppRadius.xl`.
- **AppBar**: `surface` background, flat (elevation 0), centered title. Most
  pages use the custom `TimeBuddyLargeAppBar` instead (see §6).
- **BottomNavigationBar**: `surface`, `primary` selected, `onBackgroundLight`
  unselected. The shell actually uses the custom floating `TimeBuddyBottomBar`.
- **Divider**: `surfaceVariant`, thickness 1.

---

## 6. Component library (`lib/app/widgets/`)

Prefer these over raw Material widgets. Each is documented with a `///` intent
comment in its source.

The **Status** column separates what exists today from what is committed but not
yet built. `planned` is a design decision already taken, not a suggestion: when
the feature that needs it lands, it lands as this widget with this contract. It
is still not an import you can write yet, which is the whole reason the column
exists.

### Time display (the domain layer of the design system)

| Status | Widget | Purpose / contract |
|--------|--------|--------------------|
| shipped | `ClockText` | Ticking wall-clock digits for one zone. Subscribes to the app's single `TickerService` and converts each tick's UTC instant through `TimeZoneEngine`, never by adding a stored offset. Formats through `formatClock()` under the user's `ClockFormat`, watched from `PreferencesCubit` so a 12h/24h switch repaints between ticks. `zoneId` (required), `showSeconds`, `fontSize`, `color`, plus `ticker` / `engine` / `clock` test overrides that fall back to `GetIt`. `showSeconds` renders the seconds but does **not** speed the ticker up: that rate is global (preferences.md rule 10). **Always use for a live time.** Never build a `Timer.periodic` in a page. |
| planned | `StaticTimeText` | The same visual for a non-ticking instant, such as a converter result row. Same formatter, no stream subscription. (The planner that was the other caller has been deleted.) |
| shipped | `OffsetBadge` | The `+05:30` / `-03:00` pill, plus an optional relative form (`+4h`). `offset`, `relativeToHome`, `dense`, and an assert that at least one of the two durations arrives. It takes `Duration`s and formats them through `offsetLabel()` / `relativeOffsetLabel()`; it never receives a pre-formatted string, because a call site interpolating `'${d.inHours}h'` drops the minutes for India, Nepal and Chatham. `relativeToHome: Duration.zero` is a real answer and renders `t.grid.sameTime`; `null` means no comparison was asked for. `dense` shows one chip instead of the pair, and the relative offset wins that slot. |
| shipped | `DayNightDot` | The sun/moon indicator on a clock row. Takes the `HourBand` (`band`, `size`), never an hour, so the working-hours rule stays in `hourBandFor` and the colour in `hourBandColor`. It answers "is this person likely awake", not "is the sun up": a night-shift user's 23:00 is `good` and draws a sun. |
| shipped | `HourCell` | One hour surface in the grid: band fill at 16% alpha, hour number, optional minute suffix for half-hour zones, optional cursor and selection overlays. `hour` and `band` (required), plus `minute`, `isCursor`, `isSelected`, `height` (defaults to `GridMetrics.rowHeight`) and `compact`. Takes the band already computed by `hourBandFor`, so it decides nothing about time. **It carries no `onTap`**: the grid's cells are a read surface so the horizontal drag over them can pan the track, and the one pointer path to the cursor is the ruler above ([time_grid.md](time_grid.md) rule 8). `compact` is the rounded 11pt chip form for the settings working-hours preview, whose 24 cells share whatever width the card can spare; the grid's own form is flat, edge to edge and 15pt, so a row of them reads as one timeline rather than as twenty pills. Both forms take their fill from the same `hourBandColor`, which is why this is one widget and not two. **Every colored hour in the app goes through it.** Ships with `hourBandColor(band, colors)`, the one band-to-token table. |
| shipped | `DstBadge` | Two forms of one marker: `DstBadge` for a zone observing DST at the instant on screen, `DstBadge.transition` for the slot the clocks actually move in. `onTap`, `size`; `onTap: null` renders a non-interactive glyph for a context that already owns the gesture, which today is the location detail sheet — the grid's own DST mark is a dot painted by `GridRowView`, not this badge. It **never navigates**: it reports the tap and the page decides what to open, so the same badge works in a clock row, a sheet or a settings preview. |
| shipped | `LocationRow` | A saved location's identity block: city label, country line, zone abbreviation, home chip or dense `OffsetBadge`. `location` (required), `abbreviation`, `relativeToHome`, `isHome`, `isUnresolved`, `dense`. Used as the pinned first column of the grid **and** as the identity half of a saved-cities row, because they state the same four facts and two widgets are how one screen ends up saying `Sao Paulo · BRT` while the other says `Sao Paulo (BR)`. Every value arrives resolved for the instant on screen; the widget decides nothing about time. `dense` drops the country line for the grid's `GridLayout.denseLabelColumnWidth` (128px) mobile column without shrinking the type. |

**The formatters these widgets share** live in
`lib/core/utils/time_formatter.dart` and all take a value that is *already*
wall-clock time in the zone being shown: `formatClock(localTime, format,
{showSeconds})`, `formatDayMonth(localTime, localeTag)`, `offsetLabel(offset)`
and `relativeOffsetLabel(offset)`. No screen writes an inline `DateFormat`.

`formatGridHour(localTime)` is the one sanctioned exception to "every time goes
through `formatClock()`". It renders the grid's hour label — `14`, or `14:30`
in a zone whose offset is not a whole hour — and is **always 24-hour,
regardless of the user's `ClockFormat`**. A 24-column ruler in 12h prints `03`
twice with no room for an am/pm marker in a 48–60pt column, so the honest
choices were a duplicated label or an unreadable one. `HourCell` and
`GridHeaderColumn` both route through it, which is what stops the ruler and the
cells below it from padding their digits differently
([time_grid.md](time_grid.md) rules 8 and 16).

### Forms & inputs

| Status | Widget | Purpose / contract |
|--------|--------|--------------------|
| planned | `TimeBuddyTextField` | App text field (wraps the input theme). `controller`, `label`, `hintText`, `onChanged`, `subdued`. |
| shipped | `TimeBuddySearchField` | App-wide search input used by every search-as-you-type sheet, most importantly the city picker. `hintText` and `onChanged` (required), `controller`, `autofocus`, `clearTooltip`. **Debouncing is the caller's business**: the field reports every keystroke immediately, because filtering an in-memory catalogue wants no delay while a networked query wants the 200ms `LocationSearchCubit` applies. An injected `controller` is read once on mount and never disposed by the field. |
| planned | `TimeBuddyDateField` | Read-only date tile (`InputDecorator` look) that opens a picker on tap. `label`, `value`, `onTap`. |
| planned | `TimeBuddyTimeField` | The same shape for a time-of-day value, honoring the 12h/24h preference. |
| shipped | `TimeBuddyPickerField` | Tap-to-open row selector: leading icon, label, value/placeholder, chevron. `icon`, `label`, `placeholder`, `onTap` (all required) and `value`. Backs the location and zone pickers. It wears the input look (`surfaceVariant`, `AppRadius.md`) rather than a button's, because in a form it is one: it holds a value the user picked. `placeholder` is required even for a field that always ends up filled, since every such field renders empty for the frame between mount and the first load. |
| shipped | `TimeBuddyPickerSheet` | Design-system chrome for modal picker bottom sheets: rounded surface, drag handle, left-aligned title, optional `header` (usually a `TimeBuddySearchField`). The default constructor is **draggable**: `bodyBuilder(context, scrollController)` plus `initialSize` / `minSize` / `maxSize` (0.7 / 0.4 / 0.95). Attach that controller to the scroll view, or dragging the list stops resizing the sheet. `TimeBuddyPickerSheet.fixed` shrink-wraps a short body up to 70% of the screen. Open both through `showTimeBuddyPickerSheet<T>(context, builder:)`, which is where `isScrollControlled`, the rounded top and the safe-area inset are set: forget the first and the sheet caps at half the screen, putting a focused search field under the keyboard. |
| shipped | `TimeBuddyPickerRow` | One selectable row inside a `TimeBuddyPickerSheet`: `title` and `onTap` (required), optional `leading` **widget** (a swatch, a flag, an icon), `subtitle`, `isSelected` (tinted `primary` at 8% + check mark + w600 title) and `indent`. Do not hand-roll a `Material > InkWell > Row` for the next picker: it is a `Material` so the ink is not swallowed, and it holds `kMinInteractiveDimension` so a one-line row stays tappable. |
| shipped | `TimeBuddyPickerSheetEmpty` | Centered muted placeholder for picker bodies with nothing to list (no data or no search hits). `message`, plus the optional `scrollController` from a draggable sheet's `bodyBuilder`: pass it and the placeholder stays draggable, since an empty list is exactly when the user wants to pull the sheet back down. Deliberately smaller than `FeatureEmptyState`, which owns a whole screen. |
| shipped | `TimeBuddyPillToggle<T>` | Segmented control (Grid / Clocks, 12h / 24h). `options` (a list of `PillOption<T>`, each carrying finished localized copy), `selected`, `onChanged`, `disabled`. |
| planned | `TimeBuddySubmitBar` | Sticky bottom bar with the primary action. `label`, `isLoading`, `isEnabled`, `onSubmit`. |

`palette_picker_sheet.dart` is outside this table because it is **parked, not
shipped**: the file still compiles and still carries the local chrome it was
written with before `TimeBuddyPickerSheet` existed, but it has zero references
anywhere in `lib/` — Appearance is one theme toggle now and nothing opens it.
See [preferences.md](preferences.md) for why the picker was removed and why the
machinery behind it was kept. It is a parked screen rather than a deleted one,
so nothing new may copy its local chrome; a future entry point rebuilds it on
the shared sheet.

### Structure & navigation

| Status | Widget | Purpose |
|--------|--------|---------|
| shipped | `TimeBuddyLargeAppBar` | iOS-style large left-aligned title app bar (default page header). Left-aligned because city and feature names differ wildly in length, and a centered title truncates from both ends once an action sits beside it. |
| shipped | `AppIcon` | Every icon in the app: a Font Awesome glyph centred in a square of its own nominal size. The one icon widget; see §4b for why a bare `FaIcon` is not. |
| shipped | `TimeBuddyRowGroup` | A surface card holding rows edge to edge, hairline-separated (0.5pt, inset 64 = `AppSpacing.lg` + 36 disc + `AppSpacing.md`, so the rule divides the labels rather than cutting the icon column). The counterpart to `TimeBuddySection`'s own card, not a replacement: that one pads its body, which is right for a field cluster; this one pads nothing, because a row has to reach both edges of the card for its pressed state to look like a row rather than a rectangle floating inside one. Use it as the body of a section with `card: false`. |
| shipped | `TimeBuddySettingsRow` | One row of a `TimeBuddyRowGroup`: a 36pt tinted icon disc, title, optional `subtitle` and `value`, and a trailing widget defaulting to a chevron. `accent` tints the disc; `destructive` carries it into the title. `control` holds a toggle or switch — inline and capped at the end of the title's line above the breakpoint, stacked under it below. `onTap` and `control` are mutually exclusive (asserted): a row with a control is operated by the control. The disc is what makes twenty rows scannable — a bare leading icon disappears into the text beside it at these sizes. |
| shipped | `SidebarProfileTile` | The settings destination at the foot of the rail, wearing the user's photo. Avatar 36pt at `AppRadius.sm`, name over the literal `t.nav.settings`, 11pt chevron. The fallback (initial, or a person glyph for a guest) is the avatar's **background** with the photo painted over it, because `Image.network` shows nothing while a request is in flight and a Google photo URL is refused cross-origin often enough to matter — the rail is on every screen, so a blank-then-pop there is the most-seen flicker in the app. A guest gets the glyph and not a `?`: a question mark reads as an avatar that failed to load. |
| shipped | `TimeBuddySidebar` | Web/tablet navigation rail (>= 600px): brand, destinations, date stepper, profile. It has **two widths and no `width` parameter** — `expandedWidth` 240 from 900px up, `collapsedWidth` 80 in the 600–900 band, and `TimeBuddySidebar.widthFor(context)` for anything that has to reason about the leftover content box (it returns `0` below 600). The narrow form exists for the grid: 240pt of chrome on a 700pt window was 34% of the screen, so widening a phone past the breakpoint used to show *fewer* hour columns than the phone did. Collapsed, the rail also hands the date stepper back to the page, because an 80pt strip cannot hold one. **The rail draws `settings` as the profile tile and skips it in the nav list**; the bottom bar still shows it as an ordinary item, because a floating pill has no bottom edge to pin anything to. `currentRoute` and `onSelect` (required), plus the `datePill` and `profile` slots. **Renders nothing below 600px**, so the shell places it unconditionally and the breakpoint is decided here instead of at the call site. The stepper arrives as a widget rather than as a date plus a callback, because the reference day belongs to the grid's cubit and screens without one have no date to hand over; the rail hides that slot while a `SubPageScope` is open. The destinations themselves are `TimeBuddyNavDestination`, declared here and imported by the bottom bar so the two surfaces cannot disagree on an icon, a label or the order. |
| shipped | `TimeBuddyBottomBar` | Floating pill bottom nav for mobile (< 600px); the active item expands to a label, the other three carry no information their icons do not. **`TimeBuddyNavDestination` has four values** — grid, clocks, converter, settings — so three collapse: `3 x 44 = 132` of the pill's `327` on a 375pt phone, leaving the expanded item `195` and its label `141` after its own `54` of chrome. **Five is still the recorded ceiling**, and it is what the width was measured against before the Cities destination was removed: at five, the four collapsed items take `176`, the expanded one gets `151` and its label `97`, which is where pt-BR's `Configurações` (~94pt at `labelLarge`) stops fitting. The arithmetic is written out at `TimeBuddyBottomBar.collapsedItemWidth`; `test/app/responsive_layout_test.dart` counts the items off `TimeBuddyNavDestination.values` and reads their rectangles back at 375, so the next change to the nav is measured rather than argued. A sixth destination is a "More" sheet, not a sixth icon. `currentRoute`, `onSelect`. **Renders nothing at >= 600px or on a sub-page**, so both halves of the §7 rule live in the widget. It floats over the page instead of taking a `bottomNavigationBar` slot so the grid keeps the full window height; the price is that scroll views pad for it, which is what `reservedHeight` (`16 + 64 + 16 = 96`) exists to be read from. |
| shipped | `TimeBuddyDatePill` | Compact day stepper for the grid's reference day: chevrons, the date, a horizontal swipe, and a Today reset that shows only when the day is not today. `value`, `today`, `todayLabel`, `onChanged` (required), plus `previousDayLabel`, `nextDayLabel` and `localeTag`. It does not own the date, and `today` is a parameter because "today" is a question about the home zone, not about the device. Steps are rebuilt from calendar fields, never by adding 24 hours. It takes the place Financo's month-filter pill held, stepping days rather than months. Lives in the sidebar at >= 600px and on the page itself below that, never both. |
| shipped | `LiftedFab` | Wraps a FAB so it floats above the mobile bottom bar (see §7). `child` only: it reads `subPageDepth` itself, because the FAB's owner is the page *under* any pushed sub-page and has no way to know one is there. |
| shipped | `SubPageScope` | Marks a pushed sub-page so the shell hides its bottom bar and date pill and `LiftedFab` stops lifting (see §7). Wrap the pushed page's body; it renders `child` unchanged and contributes only its lifetime. It publishes into the app-scoped `subPageDepth` (a `ValueListenable<int>`, not an `InheritedWidget`) because every consumer sits *above* the pushed route, and `preferredSize` has no `BuildContext` to look anything up with. A counter and not a bool, since sub-pages stack. Call `subPageDepth.reset()` in test teardown. |
| planned | `TimeBuddyAppBarIconButton` | Circular tinted icon button for app-bar actions. |

### Display & feedback

| Status | Widget | Purpose |
|--------|--------|---------|
| shipped | `TimeBuddySection` | **The one section widget.** `label` (passed in sentence case, rendered uppercased) and `child`, plus an optional `dot` (6x6 accent dot), `count` pill, `trailing` slot, and `card` flag. Financo shipped three overlapping variants that drifted apart; this is the merged shape (see §10). Its card is a `Material`, not a coloured box: `ListTile` and `InkWell` paint their ink on the nearest `Material` ancestor, so a card that is not one swallows every ripple inside it, and the row only looks dead under the finger. Flutter asserts on it, and `timebuddy_section_test.dart` pins it. |
| planned | `TimeBuddyDialog` | App dialog: icon badge, title, message, weighted action buttons (`TimeBuddyDialogAction`). Use `showTimeBuddyConfirmDialog` for confirms. |
| shipped | `FeatureEmptyState` | Shared first-impression empty state: tinted icon disc, headline, message, optional muted example chip, full-width primary CTA and footer. `icon`, `title`, `message` (required), `example`, `ctaLabel` + `onCta` (asserted to arrive together or not at all), `footer`. An empty board is a valid state, not an error, so it gets the product's voice instead of `ErrorView`'s apology. Name the feature's subject in the icon, never its absence: a crossed-out glyph reads as a failure and nothing failed. |
| shipped | `LoadingShimmer` | Standard loading placeholder: `rowCount` pulsing blocks of `rowHeight`. Show while a cubit is in its loading state, sized to the rows it stands in for, so nothing jumps when the real content lands. |
| shipped | `ErrorView` | Full-screen error and retry from a domain `Failure`. Standard error state. The failure picks the icon and is never rendered as text: `Failure.message` is a developer string for logs. |
| shipped | `context.showSnack(message)` | Extension on `BuildContext`, the default feedback channel for plain-text snackbars. Dismisses the current bar first, so a burst of feedback shows the newest message instead of queueing behind a stale one. |

---

## 7. Layout & responsive rules

### Content width

`ResponsiveLayout.maxContentWidth` (600) is for **prose**, and after the
Financo pass onboarding is the only screen still using it.

Settings, the profile page, the world clock and the converter are
**deliberately uncapped**: they are lists of rows, and a row is read from both
ends — an icon and a label on the left, a value on the right. A 600pt column of
them floating in the middle of a 1600pt window is what the user called "too
narrow", and they were right: capping there does not shorten a line anyone
reads, it just moves the value away from the edge the eye is already tracking.
The time grid was never capped, for its own reason: its value *is* showing as
many hour columns as the screen fits.

What *is* capped is any **control** inside a row —
`TimeBuddySettingsRow._controlMaxWidth` (420). Removing the page cap without
this produces the opposite defect: a three-way segmented toggle 1300pt wide,
which is a row of enormous buttons and no faster to read than a small one.
Below the mobile breakpoint the control stacks under the title instead, because
360pt has no room for two columns.

Financo is the reference here but not the authority: its own `ResponsiveLayout`
has **zero call sites**, so its pages are full-bleed by accident rather than by
decision. What was worth copying is the card-of-rows, not the absence of a
number.

### Breakpoints (`ResponsiveLayout`)

- **Mobile** `< 600` · **Tablet** `600–900` · **Desktop** `>= 900`.
- `ResponsiveLayout.isMobile/isTablet/isDesktop(context)` answer "how wide is
  the window". `ResponsiveLayout.showsSidebar(context)` and
  `sidebarIsExpanded(context)` answer "which nav chrome is on screen", and they
  stopped being the same question when the rail grew a collapsed form: a 700pt
  tablet is *wider* than a phone once the rail is 80pt, not narrower. Anything
  reasoning about chrome — the FAB lift, the two clearance helpers, who draws
  the date pill — asks the second pair.
- `maxContentWidth = 600` is the **prose cap**, and onboarding is the only
  screen that applies it. See the Content width section above: pages that are
  lists of rows are deliberately uncapped, and `settings_page.dart` says so at
  its own call site. The grid is uncapped for a different reason than the rest
  of them — its value *is* showing as many hour columns as the screen fits —
  but it is no longer the exception, it is the majority.

### Shell chrome

- **600-900px:** left `TimeBuddySidebar`, collapsed to 80px of icons. The page
  keeps its own date pill, because an 80px strip cannot hold a stepper. No
  bottom bar.
- **>= 900px:** left `TimeBuddySidebar` (nav + date stepper + profile). No bottom
  bar; pages must not render their own date pill (the sidebar owns it).
- **< 600px:** floating `TimeBuddyBottomBar` and the page surfaces its own
  `TimeBuddyDatePill` since there is no sidebar. The bar carries all four
  `TimeBuddyNavDestination` entries; five is the ceiling, see §6 for the width
  it is measured against.
- **Sub-pages** wrap in `SubPageScope`, which hides the bottom bar and date
  pill for their depth. **The add-location route is the only one today**, and
  the router applies the scope rather than the sheet doing it. Settings is a
  shell branch, not a sub-page, so it keeps the bar; there is no converter
  detail page.
- `TimeBuddyLargeAppBar` renders its back chevron only when `showBack` **and**
  `Navigator.canPop()`. Pages reached with `go` replace the stack, so an
  unconditional chevron renders dead.

### FAB & bottom clearance

- The floating mobile bar is `16 + 64 + 16 = 96px`, read from
  `TimeBuddyBottomBar.reservedHeight` and never retyped. `LiftedFab` lifts the
  FAB by `reservedHeight - kFloatingActionButtonMargin` (`80`) only on mobile
  and only at `SubPageScope` depth 0, which is exactly when the bar is on
  screen. Deriving the lift means retuning the bar moves the FAB with it.
- The bar and the FAB both float **over** the content, so neither reserves
  layout space and a list that stops at its own last pixel hands the user a
  final row they can see and cannot tap. Every scroll view under either one pads
  its bottom through `lib/app/widgets/fab_safe_area.dart`. Both helpers add the
  unconsumed bottom system inset (`MediaQuery.paddingOf`, so they read zero
  under a `SafeArea` and stay self-correcting), and both take `isSubPage` as a
  parameter rather than reading `subPageDepth`, because the page knows the
  answer statically and a listenable read there would go stale without
  rebuilding anything:

| Helper | Use it when | Returns on mobile at depth 0 | Elsewhere |
|---|---|---|---|
| `bottomSafeForFab(context, isSubPage: …)` | the page hosts a FAB (the grid, the saved cities list) | `168` = `96` bar + `56` FAB + `16` | `88` = `16` margin + `56` FAB + `16` |
| `bottomSafeForBar(context, isSubPage: …)` | the page is a primary destination with no FAB (settings) | `96`, the bar block alone | the system inset alone |

A sub-page has no bar over it, and at `>= 600px` the sidebar takes its own column
and nothing off the bottom, which is why both helpers collapse there. This is the
helper Financo listed as backlog item 4; it lands with the first FAB rather than
after the third one, and a per-page magic number is not an acceptable stand-in in
the meantime.

---

## 8. Recurring patterns

### Sections

One widget, three configurations:

| Configuration | Wraps a card? | Use for |
|---------------|---------------|---------|
| `TimeBuddySection(card: true)` | yes (radius `xl`, pad `lg`) | Field clusters and settings groups |
| `TimeBuddySection(card: false)` | no, header only | Headers over a list of separate cards |
| `TimeBuddySection(card: true, trailing: …)` | yes | Data cards with a trailing badge or action |

### Forms

Compose `TimeBuddySection`s separated by `AppSpacing.xl`, fields inside separated
by `AppSpacing.md`. The primary action goes in a `TimeBuddySubmitBar` as the
Scaffold `bottomNavigationBar`. Gate submit on a cubit `isValid`; show
`isLoading` during submit.

### State screens

- Loading → `LoadingShimmer`. Error → `ErrorView(failure, onRetry)`.
- Empty → `FeatureEmptyState`. Inside picker sheets use
  `TimeBuddyPickerSheetEmpty`.
- Drive all three from the cubit state in a single `BlocBuilder`.

### Pickers

Selecting a city or zone opens a **bottom sheet** built on
`TimeBuddyPickerSheet`, with search-as-you-type via a `TimeBuddySearchField` in
the `header` slot. Each row is a `TimeBuddyPickerRow`; the trigger on the form is
a `TimeBuddyPickerField`. Empty and no-hit bodies render
`TimeBuddyPickerSheetEmpty`.

---

## 9. Conventions (do / don't)

**Do**

- Use tokens (`context.appColors`) and the type scale (`context.textTheme`).
- Use the `TimeBuddy*` widget for the job; extend it if it is close.
- Render live times with `ClockText` and offsets with `OffsetBadge`.
- Derive hour colors from `HourBand`, never by comparing hours inline in a widget.
- Route every user-facing string through slang (`t.section.key`).
- Use `AppSpacing` / `AppRadius` / `GridMetrics`; apply `const`; keep widgets small.

**Don't**

- Hardcode `Color(0x…)`, `Colors.<name>`, or a hex value in UI code.
- Write a raw number for padding, gap or radius in feature code.
- Start a `Timer` in a widget. Subscribe to `TickerService`.
- Format a time with an inline `DateFormat` or string interpolation.
- Render a date pill on a page when the sidebar is *expanded* (>= 900px). Below
  that the page owns it, collapsed rail included — `ResponsiveLayout
  .sidebarIsExpanded`, never `isMobile`.
- Let a FAB crop the last list item.

---

## 10. Deliberate deviations from Financo

Financo's design system spec ends with an honest backlog. Since TimeBuddy starts
from zero, four of those items are fixed up front rather than inherited:

1. **Spacing and radius are tokens** (`AppSpacing`, `AppRadius`) instead of
   inline values. Financo backlog item 1.
2. **One section widget** (`TimeBuddySection`) instead of three overlapping ones
   that drifted on label padding. Financo backlog item 2.
3. **No stray radii.** Only the five `AppRadius` values exist. Financo backlog
   item 3.
4. **FAB clearance is a helper** (`bottomSafeForFab`) instead of a per-page magic
   number of 96 / 120 / 160. Financo backlog item 4.

Item 5 in Financo's list (`secondary` equals `income`) carries over unchanged:
`secondary` and `hourGood` are the same green. If a true secondary accent is ever
needed they will have to diverge.

---

## 11. Checklist for a new screen

- [ ] Colors via `context.appColors`; text via `context.textTheme`. Zero literals.
- [ ] Reused `TimeBuddy*` widgets (section, fields, submit bar, app bar, pickers).
- [ ] Live times via `ClockText`; offsets via `OffsetBadge`; hour colors via `HourBand`.
- [ ] No `Timer` in the widget tree; only `TickerService`.
- [ ] Strings via slang.
- [ ] Spacing and radius from `AppSpacing` / `AppRadius`; page gutter `lg`, section gap `xl`.
- [ ] Loading / error / empty states handled.
- [ ] Responsive: works < 600 (bottom bar, own date pill), 600-900 (collapsed rail, own date pill) and >= 900 (expanded rail, no pill); sub-pages wrap in `SubPageScope`.
- [ ] If it has a scroll view, the list clears whatever floats over it: `bottomSafeForFab` with a FAB, `bottomSafeForBar` without one.
- [ ] Looks right in **both** light and dark, and survives a palette switch.
- [ ] Digits do not jitter while ticking (tabular figures).

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

Three tokens are **computed getters**, not palette fields, for the same reason
Financo computes `onPrimary`: they are fully determined by other fields, and
making all 20 catalog palettes hand-pick them invites 20 chances to get it wrong.

| Getter | Definition | Use |
|--------|-----------|-----|
| `onPrimary` | `foregroundOn(primary)` | Foreground on a `primary` fill: filled button label, selected chip icon, hour-cursor label |
| `hourNight` | `Color.lerp(surfaceVariant, onBackgroundLight, 0.35)` | The sleeping-hours band. Must read as "dimmed", not as a fourth accent color, in both light and dark |
| `scrim` | Always `0xFF000000` | Modal dim, tooltip backdrop. Callers choose the alpha |

`foregroundOn(background)` (black or white by luminance, threshold `0.55`) stays
as the shared helper for arbitrary backdrops the theme does not own, such as a
user-picked location color.

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

Cells are painted with the token at **12% alpha** for the fill and the full token
for the text when emphasis is needed. No screen hand-picks these colors: every
hour surface goes through `HourCell`.

### Palette system (runtime-switchable)

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
  static const double hourColumnWidth = 44;   // two digits plus a ':30' suffix
  static const double labelColumnWidth = 132;
  static const double rowHeight = 64;
  static const double headerHeight = 40;
}
```

**Hairlines and dividers:** `1px`, color `surfaceVariant` (or the theme
`Divider`). The grid's day-boundary line is `1px` in `onBackgroundLight` at 40%
alpha.

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
| planned | `StaticTimeText` | The same visual for a non-ticking instant (converter result, planner summary). Same formatter, no stream subscription. |
| planned | `OffsetBadge` | The `+05:30` / `-03:00` pill, plus an optional relative form ("+4h from you"). Resolves through `offsetLabel()` / `relativeOffsetLabel()`; never receives a pre-formatted string. |
| planned | `DayNightDot` | The small sun/moon indicator on a clock row, derived from `HourBand`. |
| shipped | `HourCell` | One hour surface in the grid: band fill at 12% alpha, hour number, optional minute suffix for half-hour zones, optional cursor and selection overlays. Takes the band already computed by `hourBandFor`, so it decides nothing about time. **Every colored hour in the app goes through this widget**, including the settings working-hours preview. Ships with `hourBandColor(band, colors)`, the one band-to-token table. |
| planned | `DstBadge` | Marks a row whose zone is currently observing DST, and a column where a transition happens. Tapping opens the explanation sheet. |
| planned | `LocationRow` | A saved location's identity block: city label, country, zone abbreviation, `OffsetBadge`. Used as the pinned first column of the grid and as the leading block of a clock row. |

### Forms & inputs

| Status | Widget | Purpose / contract |
|--------|--------|--------------------|
| planned | `TimeBuddyTextField` | App text field (wraps the input theme). `controller`, `label`, `hintText`, `onChanged`, `subdued`. |
| planned | `TimeBuddySearchField` | App-wide search input used by every search-as-you-type sheet, most importantly the city picker. |
| planned | `TimeBuddyDateField` | Read-only date tile (`InputDecorator` look) that opens a picker on tap. `label`, `value`, `onTap`. |
| planned | `TimeBuddyTimeField` | The same shape for a time-of-day value, honoring the 12h/24h preference. |
| planned | `TimeBuddyPickerField` | Tap-to-open row selector: leading icon, label, value/placeholder, chevron. Backs the location and zone pickers. |
| planned | `TimeBuddyPickerSheet` | Design-system chrome for modal picker bottom sheets: rounded surface, drag handle, left-aligned title. The draggable variant takes a `bodyBuilder(scrollController)` plus optional `header` widgets (for example a search field); `TimeBuddyPickerSheet.fixed` is a shrink-wrapped column for short content. |
| planned | `TimeBuddyPickerRow` | One selectable row inside a `TimeBuddyPickerSheet`: optional `leading` widget, `title`, optional `subtitle`, `isSelected` (tinted `primary` at 8% + check mark + w600 title), `onTap`. Do not hand-roll a `Material > InkWell > Row` for the next picker. |
| planned | `TimeBuddyPickerSheetEmpty` | Centered muted placeholder for picker bodies with nothing to list (no data or no search hits). `message`. |
| shipped | `TimeBuddyPillToggle<T>` | Segmented control (Grid / Clocks, 12h / 24h). `options` (a list of `PillOption<T>`, each carrying finished localized copy), `selected`, `onChanged`, `disabled`. |
| planned | `TimeBuddySubmitBar` | Sticky bottom bar with the primary action. `label`, `isLoading`, `isEnabled`, `onSubmit`. |

The settings palette sheet is the one deliberate exception to this table: it
carries its own local chrome until the city picker exists to be the second
caller. Shipping a shared `TimeBuddyPickerSheet` designed against a single
caller would fix the wrong shape, so the sheet is scheduled to migrate onto the
shared chrome when the second caller lands.

### Structure & navigation

| Status | Widget | Purpose |
|--------|--------|---------|
| shipped | `TimeBuddyLargeAppBar` | iOS-style large left-aligned title app bar (default page header). Left-aligned because city and feature names differ wildly in length, and a centered title truncates from both ends once an action sits beside it. |
| planned | `TimeBuddySidebar` | Web/tablet navigation rail (>= 600px): brand, nav, date stepper, profile. |
| planned | `TimeBuddyBottomBar` | Floating pill bottom nav for mobile (< 600px); the active item expands to a label. |
| planned | `TimeBuddyDatePill` | Compact date stepper for the grid's reference day. Lives in the sidebar at >= 600px and on the page itself below that. Mirrors Financo's month-filter pill. |
| planned | `LiftedFab` | Wraps a FAB so it floats above the mobile bottom bar (see §7). |
| planned | `SubPageScope` | Marks a pushed sub-page so the shell hides its bottom bar and date pill (see §7). |
| planned | `TimeBuddyAppBarIconButton` | Circular tinted icon button for app-bar actions. |

### Display & feedback

| Status | Widget | Purpose |
|--------|--------|---------|
| shipped | `TimeBuddySection` | **The one section widget.** `label` (passed in sentence case, rendered uppercased) and `child`, plus an optional `dot` (6x6 accent dot), `count` pill, `trailing` slot, and `card` flag. Financo shipped three overlapping variants that drifted apart; this is the merged shape (see §10). Its card is a `Material`, not a coloured box: `ListTile` and `InkWell` paint their ink on the nearest `Material` ancestor, so a card that is not one swallows every ripple inside it, and the row only looks dead under the finger. Flutter asserts on it, and `timebuddy_section_test.dart` pins it. |
| planned | `TimeBuddyDialog` | App dialog: icon badge, title, message, weighted action buttons (`TimeBuddyDialogAction`). Use `showTimeBuddyConfirmDialog` for confirms. |
| planned | `FeatureEmptyState` | Shared first-impression empty state: tinted icon disc, headline, message, optional muted example chip, primary CTA and footer. |
| shipped | `LoadingShimmer` | Standard loading placeholder: `rowCount` pulsing blocks of `rowHeight`. Show while a cubit is in its loading state, sized to the rows it stands in for, so nothing jumps when the real content lands. |
| shipped | `ErrorView` | Full-screen error and retry from a domain `Failure`. Standard error state. The failure picks the icon and is never rendered as text: `Failure.message` is a developer string for logs. |
| shipped | `context.showSnack(message)` | Extension on `BuildContext`, the default feedback channel for plain-text snackbars. Dismisses the current bar first, so a burst of feedback shows the newest message instead of queueing behind a stale one. |

---

## 7. Layout & responsive rules

### Breakpoints (`ResponsiveLayout`)

- **Mobile** `< 600` · **Tablet** `600–900` · **Desktop** `>= 900`.
- `ResponsiveLayout.isMobile/isTablet/isDesktop(context)`.
- `maxContentWidth = 600` for **form and list pages**: content is centered and
  width-capped on large screens.
- **The grid is the exception**: it consumes the full available width, because
  its value is showing as many hour columns as the screen allows. It is the only
  page allowed to ignore `maxContentWidth`.

### Shell chrome

- **>= 600px:** left `TimeBuddySidebar` (nav + date stepper + profile). No bottom
  bar; pages must not render their own date pill (the sidebar owns it).
- **< 600px:** floating `TimeBuddyBottomBar` and the page surfaces its own
  `TimeBuddyDatePill` since there is no sidebar.
- **Sub-pages** (add location, settings, converter detail) wrap in
  `SubPageScope`, which hides the bottom bar and date pill for their depth.
- `TimeBuddyLargeAppBar` renders its back chevron only when `showBack` **and**
  `Navigator.canPop()`. Pages reached with `go` replace the stack, so an
  unconditional chevron renders dead.

### FAB & bottom clearance

- The floating mobile bar is `16 + 64 + 16 = 96px`. `LiftedFab` lifts the FAB by
  `80` only on mobile and only at `SubPageScope` depth 0.
- Because the FAB floats over scrolling content, every scroll view that has a FAB
  must pad its bottom so the last row clears it. Use
  `bottomSafeForFab(context, isSubPage: …)` from `lib/app/widgets/fab_safe_area.dart`.
  This is the helper Financo listed as backlog item 4; it lands with the first
  FAB rather than after the third one, and a per-page magic number is not an
  acceptable stand-in in the meantime.

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
- Render a date pill on a page when the sidebar is showing (>= 600px).
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
- [ ] Responsive: works < 600 (bottom bar, own date pill) and >= 600 (sidebar, no pill); sub-pages wrap in `SubPageScope`.
- [ ] If it has a FAB and a scroll view, the list clears the FAB.
- [ ] Looks right in **both** light and dark, and survives a palette switch.
- [ ] Digits do not jitter while ticking (tabular figures).

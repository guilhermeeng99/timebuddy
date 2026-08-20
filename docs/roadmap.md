# Roadmap

Last reviewed: 2026-08-19.

Three states: **Done**, **In progress**, **Planned**. Planned items are ordered
by priority and each links to the spec that defines it. An item is only Done when
its spec, its tests and its code all exist and `flutter analyze` is clean.

---

## Done

- 2026-08-19: Project conventions written ([CLAUDE.md](../CLAUDE.md)).
- 2026-08-19: Design system ported from Financo, with the four backlog fixes
  applied up front ([specs/design_system.md](specs/design_system.md)).
- 2026-08-19: Feature specs written for the whole v1 surface: timezone engine,
  locations, grid, world clock, meeting planner, converter, auth, startup,
  preferences, sync.

### M1: Foundations

- 2026-08-19: Flutter scaffold: `pubspec.yaml`, `analysis_options.yaml`
  (`very_good_analysis`), Android and Web targets, `flutter_launcher_icons`.
- 2026-08-19: Theme layer: `AppColorsData`, `AppTypography`, `AppSpacing` /
  `AppRadius` / `GridMetrics`, `AppTheme`, and the 10 light plus 10 dark
  palettes ported verbatim from Financo.
  → [specs/design_system.md](specs/design_system.md)
- 2026-08-19: `TimeZoneEngine` with the full contract, a test suite pinned to
  real historical and scheduled transitions, and the roughly 250 entry alias map
  the shipped tz database turns out to require.
  → [specs/timezone_engine.md](specs/timezone_engine.md)
- 2026-08-19: `Clock`, `TickerService`, `hourBandFor`, `WorkingHours`, the
  formatter (`offsetLabel`, `relativeOffsetLabel`, `formatClock`,
  `formatDayMonth`) and the parsing utilities (`enumByName`,
  `normalizeForSearch`).
- 2026-08-19: DI container, the `go_router` app shell, `LocalStore` over
  `shared_preferences`. The router carries two plain routes: the `ShellRoute`
  that keeps the sidebar and bottom bar mounted waits for the pages it would
  wrap, in M2.
- 2026-08-19: slang set up with pt-BR and en.
- 2026-08-19: Preferences end to end (entity, model, local datasource,
  repository, `PreferencesCubit`), a real settings page and the working-hours
  preview. → [specs/preferences.md](specs/preferences.md)
- 2026-08-19: First slice of the widget library: `ClockText`, `HourCell`,
  `TimeBuddySection`, `TimeBuddyLargeAppBar`, `TimeBuddyPillToggle`,
  `ResponsiveLayout`, `LoadingShimmer`, `ErrorView`.
  → [specs/design_system.md](specs/design_system.md)
- 2026-08-19: Home placeholder page showing the device zone on live digits,
  which is the visible proof that tzdata, the ticker, the theme and the
  preferences are all wired together. 257 tests passing, `flutter analyze`
  clean.

Two planned M1 items did not ship, on purpose:

- **The three theme cubits.** `ThemeCubit`, `LightPaletteCubit` and
  `DarkPaletteCubit` were folded into `PreferencesCubit`. Theme mode and both
  palettes are fields of the one synced preferences document, and two cubits
  persisting the same field are two sources of truth for it, which is one bad
  merge away from resetting a palette the user chose. `app_widget` reads the
  preferences state, reassigns `AppColors`, and only then builds `MaterialApp`.
- **The tzdata version in Settings → About**
  ([specs/timezone_engine.md](specs/timezone_engine.md) rule 12). The `timezone`
  package does not expose the release it embeds, and features may not import it
  directly, so the row honestly shows a dash rather than a hardcoded `2026a`
  that goes stale without anyone noticing. It waits on a `TimeZoneEngine` that
  can report the loaded release, which the M2 catalog work needs anyway.

One item moved forward. The **preferences document, settings page and
working-hours preview** were M3 item 16 and shipped in M1 instead: the theme
layer has nowhere to live without them, since a palette catalog with no picker
and nowhere to persist the choice cannot be reviewed on screen or exercised by
hand. M3 keeps only the syncing of that document.

- 2026-08-19: Published at <https://github.com/guilhermeeng99/timebuddy> and
  deployed to <https://guilhermeeng99.github.io/timebuddy/>.

  Hosting is **GitHub Pages, not Firebase Hosting** as M5 originally assumed.
  Nothing in the app depends on the choice: the web build is a static bundle,
  and the Firebase work in M3 is Auth and Firestore, which are reachable from
  any origin once the domain is authorised. Revisit only if the app ever needs
  a server-side redirect or a rewrite rule, which a hash-routed SPA does not.

  Two constraints the pipeline had to respect, recorded so they are not
  rediscovered: the build needs `--base-href /timebuddy/`, because a project
  page is not served from the domain root and a bundle built for `/` asks for
  its assets where nothing answers; and Pages cannot be served from the `/docs`
  folder here, because that folder holds the specs, which is why the deploy
  goes through Actions. Routing stays on the default hash strategy, so a deep
  link needs no 404 fallback.

### M2: Board and grid

- 2026-08-19: City catalog end to end: `scripts/build_city_catalog.dart`, the
  curated table in `scripts/city_seeds.dart`, the generated
  `lib/app/assets/data/cities.json` (**500 cities**), `CityCatalogRepository`
  over the asset, and ranked search across name, country, admin area, aliases
  and raw IANA id, accent- and case-folded on both sides.
  → [specs/locations.md](specs/locations.md)
- 2026-08-19: `BoardCubit` and the board document: add, remove with a 5 second
  undo, reorder, set home and replace a row's zone, every mutation optimistic
  and persisted behind the emit, with a rejected write rolled back and its
  failure returned once to the caller rather than parked in the state.
  Locations whose zone no longer resolves are kept and flagged, never dropped.
  → [specs/locations.md](specs/locations.md)
- 2026-08-19: `BuildGridUseCase` and its test suite: the column set comes from
  the home zone's own day, so a 23 or 25 hour day is ordinary rather than a
  special case, and every cell is derived from its instant.
  → [specs/time_grid.md](specs/time_grid.md)
- 2026-08-19: Grid page: pinned label column; one horizontal controller, owned
  by the header strip, whose offset every row and the now marker track, so
  nothing scrolls out of step; the hour cursor by tap, drag, arrow keys and
  `Home`; the date stepper; the empty state; and the unresolved-home banner.
  → [specs/time_grid.md](specs/time_grid.md)
- 2026-08-19: App shell: `StatefulShellRoute.indexedStack` with one branch per
  destination (grid, cities, settings), so each keeps its own navigator and
  scroll position; the floating bottom bar below `600px` and the sidebar at and
  above it; and the add-location sheet as a real URL under `/locations/add`.
  Settings became a primary destination instead of a pushed sub-page.
- 2026-08-19: Component library, continued: `OffsetBadge`, `LocationRow`,
  `TimeBuddyDatePill`, `TimeBuddySearchField`, the picker family
  (`TimeBuddyPickerField`, `TimeBuddyPickerRow`, `TimeBuddyPickerSheet`),
  `FeatureEmptyState`, `LiftedFab`, `SubPageScope`, `bottomSafeForFab` /
  `bottomSafeForBar`, the bottom bar and the sidebar.
  → [specs/design_system.md](specs/design_system.md)
- 2026-08-19: 474 tests passing, `flutter analyze` clean.

Four M2 details did not ship, and are named here rather than left to be
rediscovered as bugs:

- **Row actions and reordering from the grid**
  ([specs/time_grid.md](specs/time_grid.md), Interaction). Both live on the
  cities page instead, where a row is a list item with room for a drag handle
  and a tap target. On the grid the label column is 96px on a phone and the
  vertical drag already belongs to the row list. `t.grid.rowAction*` is
  therefore unused copy: the board's own `t.locations.*` says the same three
  things.
- **The DST explanation sheet** (`t.grid.dstExplainTitle` /
  `dstExplainBody`). A transition hour is marked in the grid with a dot and a
  tooltip, which is the whole of it today. `DstBadge` exists as a widget with
  an `onTap` waiting for the sheet, and `DayNightDot` waits on the M4 world
  clock; neither has a call site yet.
- **A dedicated home-city picker** (`t.locations.pickHome*`). An unresolved
  home zone raises the grid banner, which navigates to the cities page where
  "set as home" is one row action. One repair path is easier to keep correct
  than two.
- **The tzdata version in Settings → About**, still a dash, for the reason M1
  recorded: the `timezone` package does not expose the release it embeds.

None of the four blocks M3. The first two are grid polish and are best picked up
with M4, when the planner reopens the grid's interaction surface; the third
stays declined while one repair path is enough; the fourth still waits on a
`TimeZoneEngine` that can report the release it loaded.

---

## In progress

- **M3: account and sync.** M2 is done, so the next milestone is Firebase,
  Google sign-in and the revision-based reconciliation of the two documents the
  app already writes locally. Both shapes exist and are exercised today, which
  is the point: sync has real data to argue about instead of a schema. The
  `StartupCubit` and the splash route land with it, and they take over the board
  load `AppShell` performs today.

---

## Planned

Numbering continues from M2's items 1 to 5, which are now under Done, so an
item number still points at the piece of work it always did.

### M3: Account and sync (target: 2026-09-23)

The same board on the phone and in the browser. This is the milestone that
justifies having a login at all.

6. Firebase project, `flutterfire configure`, Firestore rules restricting
   `users/{userId}` to its owner.
7. Google sign-in on both platforms, onboarding page, profile page.
   → [specs/auth.md](specs/auth.md)
8. `SyncService` with revision-based reconciliation, dirty flags and the passive
   status indicator, covering the board and the preferences document alike.
   → [specs/sync.md](specs/sync.md)
9. `StartupCubit` and the splash route. → [specs/startup.md](specs/startup.md)

The preferences document, the settings page and the working-hours preview were
this milestone's item 16. They shipped in M1 (see Done), so all that is left of
them here is their syncing, which item 8 covers.

### M4: Planning tools (target: 2026-10-07)

10. World clock page. → [specs/world_clock.md](specs/world_clock.md)
11. Meeting planner mode, summary panel, best-slot suggestion, copy to clipboard.
    → [specs/meeting_planner.md](specs/meeting_planner.md)
12. Time converter page. → [specs/time_converter.md](specs/time_converter.md)

### M5: Release (target: 2026-10-21)

13. PWA manifest, install prompt and offline shell, plus deep-link routes
    verified against the published site. The hosting itself is already done
    (see Done), so what remains here is the app-level polish.
14. Android release build, adaptive icon, Play Store listing assets.
15. Empty, loading and error states audited on every page.
16. Light and dark checked against all 20 palettes.
17. Accessibility pass: contrast on every hour band, screen-reader labels for the
    grid (a table of colored cells is the hardest part of this app to make
    accessible, and it needs its own decision before release).

---

## Deferred decisions

Recorded here so they are not re-litigated in every review.

- **Guest mode (no account).** Considered and declined for v1
  ([specs/auth.md](specs/auth.md) rule 1): it needs a local-to-cloud migration
  path with its own conflict rules. Revisit if sign-in friction shows up as the
  main drop-off.
- **Shareable event links** (the worldtimebuddy feature where a URL encodes a
  meeting). Needs a public read path and either a backend or a very long URL.
  Deliberately out of v1 ([specs/meeting_planner.md](specs/meeting_planner.md)
  rule 10).
- **Calendar integration** (create an event from a planned meeting). Depends on
  the planner shipping first and on platform-specific permissions.
- **Location groups** ("Work team", "Family"). The board is a flat ordered list
  in v1; the shape is noted in
  [specs/locations.md](specs/locations.md) so nothing hardcodes the assumption.
- **Airport codes in the catalog** (`GRU`, `LHR` as search aliases). Cheap, but
  after v1.
- **The tzdata dataset is a decision, not a default.** Measured, not assumed:
  `package:timezone/data/latest.dart` embeds 341 locations and drops every IANA
  `Link` line, so `Europe/Oslo`, `Asia/Kuala_Lumpur`, `Africa/Accra` and roughly
  two hundred other current ids do not exist in it, and neither does a plain
  `UTC`. The engine therefore imports `data/latest_all.dart` (598 names, 185 KB
  more bundle). M2 was built under the constraint that follows from it, and kept
  it: `build_city_catalog.dart` derives its rows from the database the app
  actually ships rather than from the IANA list, resolves every id through
  `zoneOrNull`, stores the canonical result and aborts the build on a miss.
  That is what stops the catalog offering cities whose clocks quietly fall back
  to UTC, which reads as a plausible time and is wrong by an hour for half the
  year.
- **Full vs trimmed tzdata on web.** Roughly 500 KB of bundle against pre-1970
  historical accuracy. Must be decided before the M5 web deploy
  ([specs/timezone_engine.md](specs/timezone_engine.md), Open questions).
- **Widgets / complications** (home-screen clock on Android). Different runtime,
  different design system, its own project phase.
- **RTK tooling.** The Financo repo carries an RTK instructions block in its
  `CLAUDE.md`. It is not copied here; run `rtk init` in this repository if you
  want the same token-saving command conventions.

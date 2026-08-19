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

---

## In progress

- **M2: board and grid.** M1 is done, so the next milestone is the city catalog,
  the board and the comparison grid. Its first constraint is already known and
  recorded under Deferred decisions: the shipped tz database carries canonical
  zones only, so the catalog cannot be built from the IANA list.

---

## Planned

### M2: Board and grid (target: 2026-09-09)

The app is useful, offline, signed out.

1. City catalog: `scripts/build_city_catalog.dart`, the asset, the repository and
   the ranked search. → [specs/locations.md](specs/locations.md)
2. `BoardCubit`, add / remove / reorder / set home, local persistence only.
3. `BuildGridUseCase` and its full test suite (the rules live here, not in the
   widget). → [specs/time_grid.md](specs/time_grid.md)
4. Grid page: pinned column, shared scroll, hour cursor, now marker, date pill,
   responsive chrome.
5. Component library, continued: `OffsetBadge`, `LocationRow`, the pickers, the
   floating bottom bar and the sidebar, plus the `ShellRoute` that keeps the
   last three mounted across navigation instead of rebuilding them per page.
   `ClockText`, `HourCell`, `TimeBuddySection` and the app bar shipped in M1.

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

13. Web deploy on Firebase Hosting, PWA manifest, deep-link routes verified.
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
  more bundle). The constraint on M2 stands either way: the city catalog must
  resolve every id through `zoneOrNull` and store the canonical result, and
  `build_city_catalog.dart` must be verified against the database the app
  actually ships instead of against the IANA list.
  Skip that and the catalog offers cities whose clocks quietly fall back to UTC,
  which reads as a plausible time and is wrong by an hour for half the year.
- **Full vs trimmed tzdata on web.** Roughly 500 KB of bundle against pre-1970
  historical accuracy. Must be decided before the M5 web deploy
  ([specs/timezone_engine.md](specs/timezone_engine.md), Open questions).
- **Widgets / complications** (home-screen clock on Android). Different runtime,
  different design system, its own project phase.
- **RTK tooling.** The Financo repo carries an RTK instructions block in its
  `CLAUDE.md`. It is not copied here; run `rtk init` in this repository if you
  want the same token-saving command conventions.

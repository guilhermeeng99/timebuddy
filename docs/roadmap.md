# Roadmap

Last reviewed: 2026-08-20.

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

### M3: Account and sync

- 2026-08-20: Firebase project `timebuddy-app-2026` provisioned: Google as the
  only sign-in provider, Firestore created in `southamerica-east1`, and
  `flutterfire configure` run for Android and web, so the generated
  `lib/firebase_options.dart` and `android/app/google-services.json` are in the
  repository.
  → [firebase_setup.md](firebase_setup.md)
- 2026-08-20: `firestore.rules` written and deployed: one `isOwner(userId)`
  condition, a match on `users/{userId}` and a recursive match on everything
  under it, plus an explicit deny-all block that documents Firestore's own
  default and also refuses a collection-group query over `settings`.
  `firestore.indexes.json` is empty on purpose: every read is by document id,
  so there is nothing to index.
- 2026-08-20: Google sign-in end to end: `AuthBloc` with its four events, the
  repository and the remote datasource under it, and the platform split
  [specs/auth.md](specs/auth.md) rule 2 requires: on web a popup first,
  because it is the only flow whose result lands in the app origin's own
  storage, with `signInWithRedirect` as the fallback when the browser refuses
  it; on Android the `google_sign_in` plugin. A dismissed dialog is not an
  error (rule 5), a Firestore outage during sign-in still lets the user in on
  their local board (rule 4), and sign-out wipes the local documents (rule 7).
- 2026-08-20: Onboarding: three slides, the last of them holding the Google
  button, and a skip that goes *to* that slide rather than past it. There is
  deliberately no `SignInPage`: the app is Google-only, so a screen whose whole
  content is one button would be a second stop on the way to the same tap.
  → [specs/auth.md](specs/auth.md)
- 2026-08-20: `SyncService` / `SyncServiceImpl` over `RemoteSettingsDataSource`:
  the conflict ladder (revision, then `updatedAt`, then the remote as a stable
  arbitrary), a missing or unreadable remote `revision` scored `-1` so first
  sign-in provisioning is a case of reconciliation rather than a code path of
  its own, the two dirty flags, and a `SyncStatus` stream that replays its last
  value so an indicator mounting after a failed startup sync does not show
  "idle" over an offline session. → [specs/sync.md](specs/sync.md)
- 2026-08-20: The passive sync indicator (`SyncStatusRow`) on the profile page,
  and the `AppLifecycleState.resumed` hook in `app_widget` that flushes whatever
  a failed remote write left behind. A failed remote write is never a banner
  ([specs/sync.md](specs/sync.md) rule 4), and the profile page is the only
  place it is mentioned at all.
- 2026-08-20: `StartupCubit` and the `/startup` splash: tzdata and the city
  catalog first and unconditionally, auth second, the first sync third inside a
  5 second box, and a terminal state the page turns into `/` or `/onboarding`.
  The router redirect holds every other route until startup has answered, and
  bounces a signed-in user who lands on `/onboarding` back through it.
  `AppShell` still owns `BoardCubit` and is only built after the router leaves
  `/startup`, so its load reads the document sync already reconciled;
  `PreferencesCubit`, a singleton loaded before the router exists, is handed the
  reconciled copy through `adoptFromSync`.
  → [specs/startup.md](specs/startup.md)
- 2026-08-20: 559 tests passing, `flutter analyze` clean, and the signed-in
  build deployed to <https://guilhermeeng99.github.io/timebuddy/>.

Four M3 items did not ship. None of them is quietly folded into the list above,
because each is a promise the specs still make:

- **Android Google sign-in cannot work yet: no SHA-1 is registered on the
  project.** `android/app/google-services.json` carries exactly one OAuth
  client and it is `client_type: 3`, the web one; there is no `client_type: 1`
  entry and no `certificate_hash` anywhere in the file, which is what Firebase
  writes once a signing fingerprint exists. A real Android build therefore
  fails the Google flow with `ApiException: 10 (DEVELOPER_ERROR)`, an error
  that says nothing about fingerprints. Web sign-in does not check an app
  signature, which is exactly why the deployed build works and this stayed
  invisible. The fix is console-side and takes a minute:
  `cd android && ./gradlew signingReport`, add the debug SHA-1 (and the release
  keystore's before publishing) under Project settings → Your apps → Android,
  then re-download the file ([firebase_setup.md](firebase_setup.md) step 5).
- **The tzdata release in Settings → About is still a dash**
  ([specs/timezone_engine.md](specs/timezone_engine.md) rule 12), for the third
  milestone running and still for M1's reason: the `timezone` package does not
  expose the release it embeds, and features may not import it directly. The
  constant in `settings_page.dart` carries the `TODO` and an honest `, ` rather
  than a hardcoded `2026a` that goes stale without anyone noticing. It waits on
  a `TimeZoneEngine` that can report the release it loaded.
- **The profile page has no in-app entry point.** `/profile` exists as a route
  and renders correctly, but nothing navigates to it: `TimeBuddySidebar` takes
  a `profile` slot and `AppShell` passes nothing into it, and the settings page
  still carries an M2-era comment saying its Account group is absent "until
  M3". So the identity block, the sign-out button and the passive sync
  indicator are reachable only by typing the URL. One line in the shell and one
  row in settings close it.
- **Account deletion is a confirmation dialog with nothing behind it.**
  `ProfilePage` takes an optional `deleteAccount` callback and the route builds
  the page without one, so a user who works through the deliberately harder
  confirmation ends at `t.auth.deleteAccountFailed`. `ProfileRepository`
  ([specs/auth.md](specs/auth.md), Repository Contract) has no implementation in
  the tree, and inventing one under the page would be guessing at an API;
  failing honestly beats hiding a row the spec promises.

One more thing worth naming rather than rediscovering.
[specs/sync.md](specs/sync.md) rules 2 and 3 describe a push after every
*ordinary* local write, and rule 9 lists three trigger points for a full sync.
What is verified in the tree at this entry is the startup sync and the
`flushDirty` on resume; the write-through path that carries rules 2 and 3 lands
with this milestone's integration, and there is no pull-to-refresh control on
any page yet.

### Guest mode

- 2026-08-20: **Sign-in stopped being a gate.** A visitor now uses the whole
  app against local-only documents and signs in when they want the board to
  survive the device. New: `GuestSession` (`lib/core/session/`) over one
  versioned key, a `continue without an account` control on every onboarding
  slide, a real signed-out body on the profile page, and the Account group in
  Settings — which is also the first in-app path to `/profile`, a route that
  had none since M3.
  → [specs/guest_mode.md](specs/guest_mode.md)

  The migration rule is the part worth knowing: at sign-in the **account wins
  whenever it already has documents**, and the guest's documents are adopted
  upward only into an account that has none. That call
  (`sync(adoptGuestDocuments: true)`) deliberately bypasses the conflict
  ladder — a guest at revision 6 would otherwise beat a real account at
  revision 3 on rung 2 and replace a board other devices also hold.
  Sign-out keeps `clearAll()` and re-enters guest mode *after* the wipe, so the
  user lands on an empty board rather than on a tour they have already read.

  This reverses [specs/auth.md](specs/auth.md) rule 1 and the "Guest mode"
  entry under Deferred decisions, both of which now record what changed.
  765 tests passing, `flutter analyze` clean.

### The grid took over the board

- 2026-08-20: **The Cities destination is gone, and the grid is where the board
  is edited.** Drag a row's pinned label to reorder it; tap it for set as home,
  replace time zone and remove-with-undo. The nav is four destinations again.
  → [specs/time_grid.md](specs/time_grid.md), [specs/locations.md](specs/locations.md)

  This closes two M2 deferrals that had been carried for three milestones:
  "row actions and reordering from the grid" and the strings `t.grid.rowAction*`
  that shipped in both locales with no call site. M2 declined them because the
  label column is 96px on a phone and the vertical drag belonged to the row
  list; what changed is that the lift is a **long press** on touch (a mouse
  drags immediately), so it costs no pixels and resolves on a criterion the
  cursor's horizontal drag does not share.

  Three things found while doing it, none of them the feature itself:

  - The undo snackbar rendered **underneath** the floating bottom bar on a
    phone, Undo button included. Pre-existing on the world clock; it stopped
    being cosmetic the moment the grid became the only place a removal happens.
    Fixed once, in `board_actions.dart`, with the clearance derived from
    `TimeBuddyBottomBar.reservedHeight`.
  - The unresolved-zone glyph's `Tooltip` won the long press on its own
    fourteen pixels, giving the drag a dead spot that moved as rows resolved.
  - The world clock carried its own copy of the board mutations. Both screens
    now call one library, so the undo window cannot drift between them.

  `/locations/add` became `/add`: a path whose first segment named a page the
  app no longer has is worse than a broken bookmark. The board's cap moved from
  the removed page's header to the add sheet, which is where it is about to
  matter. 759 tests passing, `flutter analyze` clean.

### The Financo design pass

- 2026-08-20: **Three ports from the Financo project**, which is where this
  app's theme layer came from in M1.
  -> [specs/design_system.md](specs/design_system.md)

  1. **Settings became the rail's foot, wearing the user's photo**
     (`SidebarProfileTile`). It is still a `TimeBuddyNavDestination`, so the
     phone's bottom bar keeps it as an ordinary item — a floating pill has no
     bottom edge to pin anything to — but the rail skips it in the nav list and
     draws identity instead. The page itself leads with an identity card, which
     replaced the Account *row* that M3 had added two thirds of the way down:
     a hero block and a row were two places answering one question.
  2. **The 600pt content cap came off the row-and-list screens.** Settings, the
     profile page, the world clock and the converter now fill the window;
     `maxContentWidth` is left to onboarding, which is prose. Removing it alone
     produced the opposite defect — a 1300pt-wide segmented toggle — so controls
     inside a row are capped at 420 and stack under the title on a phone.
  3. **Font Awesome replaced the Material icon set** (`font_awesome_flutter`,
     rendered with `FaIcon`), 51 glyphs across 24 files. The rows carry them on
     36pt tinted discs, which is what makes a long settings screen scannable.

  Financo was the reference but not the authority: its own `ResponsiveLayout`
  turns out to have zero call sites, so its pages are full-bleed by accident.
  What was worth copying is the card-of-rows and the icon language, not the
  absence of a number.

  Two defects found while porting, both in code written earlier in this
  session: the sidebar avatar rendered blank while a photo loaded (the fallback
  was only an `errorBuilder`, so it flickered on every launch), and its initial
  was taken with `substring(0, 1)`, which slices a name starting outside the
  BMP through its surrogate pair. 761 tests passing, `flutter analyze` clean.

### Icon fallout, and what it cost to find

- 2026-08-20: Four fixes on top of the Financo pass, three of them defects that
  pass `flutter analyze` and `flutter test` and only show up on screen.

  1. **`AppIcon`**, and every icon in `lib/` now goes through it.
     `FaIcon` is Flutter's `Icon` with the `SizedBox` and `Center` removed on
     purpose — Font Awesome glyphs are often wider than they are tall — so
     every icon inside a fixed-size parent sat wherever its advance width left
     it. Visible as the brand mark pinned to the corner of its disc and the
     date-stepper chevrons drifting out of their tap targets.
  2. **Icon tree-shaking is off**, and CI now runs
     `scripts/check_glyphs.py`. The shaker cannot see through `FaIconData`: a
     release build kept 22 of the 38 icons the app uses and dropped the other
     16, which rendered as empty boxes. Nothing failed — a missing glyph is not
     a build error. The check parses each bundled font's `cmap` and compares it
     against every `FontAwesomeIcons.*` in the source. ~500 KB of font, against
     7 MB of CanvasKit.
  3. **Glyphs are now chosen for legibility at their drawn size.** The sun, in
     either weight, has eight triangular rays that merge into its disc below
     about 20pt and read as a cog. `DayNightDot` is a filled circle and
     `DstBadge` a circled up arrow.
  4. **Settings lost the two palette rows and the licenses link.** Appearance
     is one theme toggle. Both palette catalogs and `palette_picker_sheet.dart`
     stay — the machinery is intact and synced, it just has no entry point.

  One trap that is *not* an app defect but cost real time, recorded so it is
  not rediscovered: `flutter build` copies the package fonts preserving their
  original mtime, so a dev server answering `If-Modified-Since` returns `304`
  and the browser keeps a previously tree-shaken copy. The glyph check passes,
  the file on disk is right, and the page still draws tofu.
  `touch build/web/assets/**/*.otf`. 758 tests passing, `flutter analyze`
  clean.

### The grid compares, and only compares

- 2026-08-20: **The Compare / Plan toggle is gone from the grid's app bar**, at
  the owner's request — the planner was not something they reached for, and a
  switch offering a mode nobody enters costs an app-bar action and a decision
  on every visit.
  -> [specs/time_grid.md](specs/time_grid.md), [specs/meeting_planner.md](specs/meeting_planner.md)

  Removed with it: `_GridMode`, the planner `BlocProvider`, the selection
  overlay, the summary-panel slot, the plan branches in the two drag handlers
  and the cell tap, and the plan-mode FAB and padding rules. Two things fell
  out that were only there to serve the mode — the `Stack` around the grid
  became a plain `Column`, and the `GlobalKey` that existed to reparent the
  grid when the planner provider appeared above it is gone.

  **`lib/features/meeting_planner/` stays**, intact and still green at 47
  tests: two use cases, the cubit, the summary panel and the overlay. It has no
  entry point, which its spec now says at the top. That is a deliberate
  half-measure — deleting a tested feature on a request to remove a switch
  would be reading more into it than was said — and it is one command away if
  the answer is that it should go.

  Only two strings were orphaned (`t.planner.modeCompare` / `modePlan`) and
  both were deleted: a future entry point will want its own words.
  758 tests passing, `flutter analyze` clean.

### The grid grew up

- 2026-08-20: **`GridMetrics` retuned and the hour cell redrawn**, after three
  direction artboards were put up and the owner picked the one that scales the
  existing grid rather than replacing it.
  -> [specs/time_grid.md](specs/time_grid.md)

  The complaint was precise — everything too small, values truncated — and so
  was the cause: a 44pt column held an 11pt digit, and a half-hour zone's
  `05:45` was squeezed to **9pt** to fit, making Kolkata, Kathmandu and Chatham
  the hardest rows on the screen. Columns are 60pt now and every cell renders
  at 15pt, minutes or not.

  Three shape changes came with the size, each of them removing a box: the cell
  lost its inset and its rounding so a row reads as one continuous day instead
  of twenty floating pills; the cursor became a wash instead of a 2pt ring; and
  the digits are tinted by their band, lerped toward `onBackground` so it holds
  on light palettes too. A hairline under each row is what keeps four
  contiguous rows reading as four cities.

  The trade is on the record: a 1400pt track shows ~22 hours instead of 30.
  `HourCell.compact` keeps the old 11pt chip for the settings preview, whose
  24 cells share one card.

  One thing from the artboard did **not** ship: the colour legend. On the
  artboard the grid was a fixed block with room under it; in the app the rows
  scroll beneath a floating bar and a FAB, so a legend would have to be pinned
  and would cost height on every screen. The bands are named in
  Settings → Working hours already.

  The three directions are kept as a design canvas rather than in the tree.
  759 tests passing, `flutter analyze` clean.

---

## In progress

- **M4: planning tools.** M3 is done and deployed, so the next milestone is the
  three pages the board and the grid were built to feed: the world clock, the
  meeting planner and the converter. Two of M2's deferred grid details belong
  here rather than to a polish pass: row actions and reordering from the grid,
  and the DST explanation sheet behind `DstBadge`'s waiting `onTap`: because
  the planner reopens the grid's interaction surface anyway, and `DayNightDot`
  has been waiting for the world clock since M2.

---

## Planned

Numbering continues from M2's and M3's items 1 to 9, which are now under Done,
so an item number still points at the piece of work it always did.

### M4: Planning tools (target: 2026-10-07)

10. World clock page. → [specs/world_clock.md](specs/world_clock.md)
11. Meeting planner mode, summary panel, best-slot suggestion, copy to clipboard.
    → [specs/meeting_planner.md](specs/meeting_planner.md)
12. Time converter page. → [specs/time_converter.md](specs/time_converter.md)

### M5: Release (target: 2026-10-21)

13. PWA manifest, install prompt and offline shell, plus deep-link routes
    verified against the published site. The hosting itself is already done
    (see Done), so what remains here is the app-level polish.
14. Android release build, adaptive icon, Play Store listing assets. The release
    keystore's SHA-1 has to reach the Firebase console with it, or the signed
    build's Google sign-in fails the way the debug one does today (see M3).
15. Empty, loading and error states audited on every page.
16. Light and dark checked against all 20 palettes.
17. Accessibility pass: contrast on every hour band, screen-reader labels for the
    grid (a table of colored cells is the hardest part of this app to make
    accessible, and it needs its own decision before release).

---

## Deferred decisions

Recorded here so they are not re-litigated in every review.

- **Firestore lives in `southamerica-east1`, and that is permanent.** A
  Firestore database's location is fixed at creation: changing region means a
  new project and a migration of every document, so this is the one Firebase
  choice that cannot be revisited cheaply
  ([firebase_setup.md](firebase_setup.md) step 4 says so at the point of no
  return). It was picked deliberately and not by default: the owner is the
  app's primary user and is in Brazil, and the whole remote payload is two
  documents per account, read whole exactly once per launch and written after a
  change the user already sees applied locally.
  Region therefore buys latency on two reads and nothing else: a user in Tokyo
  pays a few hundred extra milliseconds once, on a screen that is already
  showing their local board, because local is the read path
  ([specs/sync.md](specs/sync.md) rule 1). Recorded here so "shouldn't this be
  `us-central1` or multi-region?" is not re-asked in every review.
- **Guest mode (no account).** ~~Declined for v1~~ — **built**, see
  [specs/guest_mode.md](specs/guest_mode.md). It is left here rather than
  deleted because the reasoning that declined it was sound and worth keeping
  next to what changed: the objection was that a local-only mode needs a
  local-to-cloud migration path with its own conflict rules. It does. The
  migration turned out to be **one rule**, not a system — the account wins
  whenever it already has documents, and the guest's documents are adopted
  upward only into an account that has none. No merge, no field-level
  reconciliation, no prompt, and the conflict ladder untouched.

  What is **still** deferred is the interesting half: **prompting the user when
  both sides have a board.** Today the account silently wins, which is the safe
  direction (the guest's data never left the device; the account's is on other
  devices too) but not the kind one. A "keep the cities from this session /
  use my account's" dialog is the right v2 and needs a decision about what
  "keep both" would even mean given the 20-city cap.
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

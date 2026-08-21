# Roadmap

Last reviewed: 2026-08-21.

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
because each is a promise the specs still make. The fourth was **Android Google
sign-in, which had no signing fingerprint on the Firebase project**; it was
closed on 2026-08-20 by the keystore work recorded under Done below, so it has
left this list rather than sitting here struck through — the entry that closed
it says what it was.

- **The tzdata release in Settings → About is still a dash**
  ([specs/timezone_engine.md](specs/timezone_engine.md) rule 12), for the third
  milestone running and still for M1's reason: the `timezone` package does not
  expose the release it embeds, and features may not import it directly. The
  constant in `settings_page.dart` carries the `TODO` and an honest em dash
  rather than a hardcoded `2026a` that goes stale without anyone noticing. It waits on
  a `TimeZoneEngine` that can report the release it loaded.
- ~~**The profile page has no in-app entry point.**~~ **Closed** — see the
  guest-mode entry below, which added the Account group in Settings, and the
  Financo design pass, which turned the rail's foot into `SidebarProfileTile`
  and the settings entry into an identity card. Both navigate to `/profile`.
  The original wording is kept because it is what the milestone shipped
  knowing: `/profile` existed as a route and rendered correctly, but nothing
  navigated to it — `TimeBuddySidebar` took a `profile` slot and `AppShell`
  passed nothing into it, and the settings page still carried an M2-era comment
  saying its Account group was absent "until M3", so the identity block, the
  sign-out button and the passive sync indicator were reachable only by typing
  the URL.
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
The write-through path that carries rules 2 and 3 **is** in the tree:
`SyncCoordinator` is a constructor argument of both `BoardRepositoryImpl` and
`PreferencesRepositoryImpl`, so an ordinary local write pushes behind itself
and marks the document dirty when it cannot. What is still open of rule 9's
three trigger points is the narrower half, and both are about **pulling**. The
`AppLifecycleState.resumed` hook in `app_widget` calls `flushDirty`, which
pushes what a failed write left behind and reads nothing, so a resume does not
notice a change another device made while the app was backgrounded. And there
is **no pull-to-refresh control on any page** — no `RefreshIndicator` anywhere
in `lib/` — so a user who suspects the other device has moved ahead can only
relaunch.

### M4: Planning tools

- 2026-08-20 (`1ac4d32`): **The three pages the board and the grid were built
  to feed.** The world clock, the time converter and a meeting planner all
  shipped together, with the nav growing to five destinations to hold them.
  → [specs/world_clock.md](specs/world_clock.md),
  [specs/time_converter.md](specs/time_converter.md)

  The **world clock** is the glance view to the grid's compare view: the home
  clock as a hero block, then the board in board order, every tile carrying its
  relative offset from home, a day/night dot off `hourBandFor` and a
  `Tomorrow` / `Yesterday` marker when the local date differs from the user's.
  It is the first screen `DayNightDot` has had since M2. The **converter**
  answers one point-in-time question — "15:00 on 12 March in Lisbon" against
  the whole board — and its value is entirely in the dates far from now, where
  today's DST rules do not apply: a local time that does not exist on a
  spring-forward date, or happens twice on a fall-back one, is disclosed above
  the results with a toggle for the second occurrence, never silently answered
  as a different question. The **meeting planner** is described in the entry
  below that deletes it; it never gained an entry point that outlived the
  milestone.

  Shipped in the same commit and not a planning tool: the **web sign-in
  banner**. A blocked popup and a browser that drops third-party storage both
  used to fail silently; both are now named, because one is something the user
  can allow and the other something they work around by switching browsers. A
  deliberately cancelled dialog still says nothing (auth.md rule 5).

  Two things found while doing it, and in both the spec was wrong and the code
  won:

  - `world_clock.md` asked for a `TickerService` subscriber count of **1**,
    which contradicts its own Performance section: `ClockText` subscribes per
    set of digits by design, so a hero over N tiles is N+1 subscribers. The
    invariant that is actually true and worth pinning is that the app runs
    exactly **one `Timer`** and `TickerService` owns it — which `flutter_test`'s
    pending-timer check enforces for free, at no cost in test code.
  - `design_system.md` still described a three-item bottom bar. Five was
    *measured* to fit at 375px (327 for the pill, 176 collapsed, 151 expanded)
    and a test now measures it rather than asserting a number someone typed.

  723 tests passing, `flutter analyze` clean.

### Android release signing

- 2026-08-20 (`1ac4d32`, `f36fb77`, `10da8da`): **Android Google sign-in works,
  and a release build is a shippable artifact.** This closes the first of M3's
  four unshipped items, which said no SHA-1 was registered on the Firebase
  project and that a real Android build therefore failed the Google flow with
  `ApiException: 10 (DEVELOPER_ERROR)` — an error naming neither fingerprints
  nor the file they live in.
  → [android_release.md](android_release.md),
  [firebase_setup.md](firebase_setup.md) step 5

  It took three commits because it is three separate facts. The **debug**
  keystore's SHA-1 was registered with M4, which is what unblocked sign-in on a
  development build. Then the release build type turned out to still be signing
  with the debug key — the `TODO` the Flutter scaffold leaves behind — so
  `f36fb77` wired release signing to a gitignored `android/key.properties`,
  falling back to debug only when that file is absent so a fresh clone and CI
  still build; the fallback is documented as a convenience and never a shipping
  path. Finally `10da8da` generated the release keystore and registered *its*
  fingerprint, verified with `apksigner` against the built APK
  (`CN=TimeBuddy`, SHA-1 `44e42a6d…`). `android/app/google-services.json` now
  carries two `client_type: 1` entries with a `certificate_hash` each, which is
  what Firebase writes once a fingerprint exists.

  The keystore and its passphrase are deliberately not in this repository:
  `android/.gitignore` excludes `*.jks` and `key.properties`, and only the
  regenerated `google-services.json` is committed, which holds no secret.

  **What is still outstanding is the step that matters most**, and it is in M5
  rather than here: Play App Signing. Google re-signs uploaded apps with a key
  it holds, so neither fingerprint above is what an installed app presents, and
  sign-in works in a local release build while failing for everyone who installs
  from the store. `android_release.md` leads with it for that reason.

  726 tests passing, `flutter analyze` clean. This was also the project's first
  end-to-end Android build.

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

  This closes the M2 deferral that had been carried for three milestones: "row
  actions and reordering from the grid". It did **not** close the other half
  of that entry at the time — `t.grid.rowActionSetHome`, `rowActionRemove` and
  `rowActionReplaceZone` went on shipping in both locales with no call site,
  while the sheet that finally does the job renders `t.locations.setAsHome`,
  `t.locations.replaceZone` and `t.common.remove` instead. The audit of
  2026-08-21 deleted the three orphans. The reason they were never wired is
  recorded on `row_actions_sheet.dart` itself: the copy is the board's
  whichever screen opened the sheet, because one sheet that renamed its own
  actions depending on its caller would be two vocabularies for three
  operations. The three `t.grid.*` strings are therefore dead and should be
  deleted from both locale files. M2 declined the feature because the
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
  -> [specs/time_grid.md](specs/time_grid.md), `specs/meeting_planner.md` (since deleted)

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

- 2026-08-21: **`lib/features/meeting_planner/` is deleted**, and the
  half-measure above is closed. The owner confirmed the feature was finished
  with, so the folder, its 47 tests and `specs/meeting_planner.md` are gone.

  A folder with green tests and no entry point is not an asset in reserve. It
  is a second answer to "what does this screen do" that every future reader has
  to open and rule out, a set of DI registrations built on every launch for
  nobody, and — since the grid's hour column stopped being a constant — a
  `CustomPainter` that would have drawn its selection band on the wrong hours
  at every width but one.

  Removed with it: three `registerLazySingleton` calls, the `planner` i18n
  block in both locales (15 strings each), and the doc comments in
  `app_routes`, `app_router`, `timebuddy_sidebar` and `injection_container`
  that explained why the planner had no route, no branch and no nav
  destination. Nothing in `lib/` names it now.

  What did *not* move: `HourCell.isSelected` stays, unset by anything, because
  the distinction it draws — a picked cell versus the cursor's — is real and
  costs one wash. The roadmap's older entries keep their prose and lose only
  their links to the deleted spec; a log that edits its own history is not a
  log. 731 tests passing (778 minus the planner's 47), `flutter analyze` clean.

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

### The cells scroll, the ruler points

- 2026-08-21: **A horizontal drag over the grid pans the hour track, and the
  cursor moved onto the header's columns**, at the owner's request: the drag
  was the gesture a timeline most needs and it was being spent on a marker
  nobody had asked to move, so the hours past the right edge were reachable
  only by widening the window.
  -> [specs/time_grid.md](specs/time_grid.md) rule 16

  The rows are still not `Scrollable`s — each would get its own
  `ScrollPosition` and the board would tear into N independently scrolled
  timelines, which is the bug the single-controller design exists to prevent.
  The page hands its drag to the header's position through
  `ScrollPosition.drag`, the same call `Scrollable` makes internally, so the
  cells inherit the platform's physics whole: the fling after the finger
  lifts, the clamp at both ends, the overscroll indicator. A `jumpTo` loop
  would have been four lines shorter and would have stopped dead on release.

  Two things found while doing it, neither of them the feature:

  - `dragCancelCallback` is not a place to cancel the drag. It runs from
    inside `ScrollDragController.dispose`, so ending the drag there re-enters
    the disposal it was called from; the first run of the new tests died on a
    `StackOverflowError` twenty frames deep. It only forgets the reference,
    exactly as `Scrollable._disposeDrag` does.
  - Making the ruler's columns tappable put a tap in the header's gesture
    arena, so its drag recognizer now waits out the touch slop and — being
    `DragStartBehavior.start` — discards it. Ordinary Flutter behaviour for a
    scrollable with tappable children, but it silently shortened every
    `tester.drag` on the strip by 20px, which the resize test noticed because
    it was written to land on a *fractional* column and suddenly landed on a
    different one.

  `GridLayout.columnAt` went with the change: mapping a pointer to an hour was
  the cursor drag's, and nothing in `lib/` asked for it afterwards. The
  cells carry no tap handler at all now, which also means no ink response —
  an affordance that splashes and does nothing is worse than one that does
  not splash. 732 tests passing, `flutter analyze` clean.

  **What this does not fix, and it is worth being precise.** The window is the
  reference day plus three hours either side (rule 3), so on a 1920pt screen
  all thirty columns already fit and there is nothing to pan to. Panning is
  what a narrower window needed; reaching *further into tomorrow* on a wide
  one is `flankSlots`, and that number has not moved.

### The audit

- 2026-08-21: **A full-project audit in four parallel passes** — documentation
  freshness, test health, code cleanliness, and dependency status. It is
  recorded here because most of what it found was in the documents rather than
  in the code, and a log that only notes code changes would leave the reader
  wondering why three files moved at once.

  The documents had drifted a milestone behind the tree. `CLAUDE.md` still said
  Firebase was not in `pubspec.yaml`, still predicted `AuthBloc` and
  `StartupCubit` "joining the singletons in M3" and `WorldClockCubit` and
  `TimeConverterCubit` "joining the page-scoped cubits in M4", and still
  described a `main` that warmed the city catalog it does not touch. Its
  architecture tree listed four of the nine feature modules. `README.md` still
  called the world clock and the converter unbuilt and still carried the
  Android sign-in caveat that had been closed the day before. This file still
  named the meeting planner as in-flight work a hundred lines after recording
  its deletion. All three are now reconciled against the tree, and the one
  genuinely new thing in `CLAUDE.md` is the **web build command**: the
  mandatory `--no-tree-shake-icons` existed only inside a comment in the CI
  workflow, so a local release build silently rendered empty boxes with nothing
  to read about why.

  Four changes in code came out of it, all small and all recorded so the
  reasoning survives the diff:

  - **`zoneOrHome(id, home)` is deleted.** It silently substituted the home zone
    for an id that did not resolve, which [specs/locations.md](specs/locations.md)
    rule 11 forbids: an unresolved row is kept and flagged, never quietly
    replaced. A board row showing someone else's clock and no sign of it is
    exactly the plausible-looking wrong answer the timezone rules exist to
    prevent. `zoneOrNull(id)` stays and is the one sanctioned lookup.
  - **`context.popOrGo` is wired up.** It had been written, documented and
    tested with zero call sites since M1. `TimeBuddyLargeAppBar` now takes an
    optional `fallbackRoute`, and with one set it renders the back chevron even
    on an empty navigator stack and closes through `popOrGo` — which is the
    deep-linked case the helper was written for and the case that had no user.
  - **`formatGridHour` is extracted**, and with it the grid's 24-hour rule
    stops being an accident of where the code sits and becomes something
    written down. The grid's cells and its header ruler are **always 24h**: a
    24-column ruler in 12h prints `03` twice and a 48-60pt column has nowhere
    to put the am/pm that would tell them apart. Everywhere else the user's
    preference still wins through `formatClock`.
  - `ZoneRef.requestedId` and `wasAliased` are **kept and re-documented
    honestly**. The intent was that a caller rewrite a stale stored id instead
    of paying for the same alias lookup every launch. No caller does. They stay
    because the information is free where it is known and unrecoverable later,
    but `CLAUDE.md` no longer implies anyone uses them.

  **The one thing the audit could not fix is the tzdata gap**, which has a date
  on it and is now recorded under Open risks below rather than in a report
  nobody re-reads.

### The front door, and the release audits

- 2026-08-21: **The published site grew a landing page, and three of M5's four
  audits ran.** One commit, because the audits are what the landing page has to
  be honest about.
  → [specs/design_system.md](specs/design_system.md),
  [specs/time_grid.md](specs/time_grid.md)

  **`site/` is a Vite + Tailwind static page at the Pages root**, with the
  Flutter app one level down at `/timebuddy/app/`. The same arrangement the
  Financo repo uses, built by the same `deploy-pages` job rather than a second
  one: a Pages deployment carries exactly one artifact, and two jobs racing to
  publish would leave a site pointing at an app that had not landed yet. The
  app's `--base-href` moved with it, and old bookmarks still work — the landing
  page forwards any hash beginning with `#/` to `./app/`, which is the one thing
  a URL change owes the people who saved the old one.

  The hero is a **working miniature of the grid**, not a screenshot of one: the
  columns are real instants, every cell resolves through the browser's own IANA
  database, the first row is the visitor's own zone, and `hourBandFor` and
  `relativeOffsetLabel` are ported from `lib/` rather than approximated. Kolkata
  is in the fixed city list on purpose — at `+05:30` a demo built on
  `hour + offset` arithmetic prints the wrong thing where anyone can see it.

  The GitHub repository now carries a description and the site as its homepage,
  which is how the Financo repo reads.

  **Item 16, the 20-palette check, is a test now** rather than a review that
  happened once. `test/app/theme/palette_contrast_test.dart` walks both
  catalogs, reproduces the composites the widgets actually paint — the hour
  cell's 16% wash under its 55%-blended digits, the cursor's own wash, a status
  glyph on its banner — and measures each against the WCAG ratio its role owes.
  240 judgements is not a thing anyone reviews correctly by eye, and the
  failures are exactly the ones a designer with good eyesight does not notice.

  It found four, and the first is the worst thing this project has shipped:

  - **`foregroundOn` put white on the primary of 14 of the 20 palettes**, as
    low as **1.81:1** on Deep Ocean and Cyan Neon against a bar of 4.5. It
    picked by a luminance threshold of `0.55`, justified in a comment claiming
    mid-tone brand colors "read better with white than `0.5` predicts"; measured
    against the catalog, the opposite is true by a wide margin. Since
    `onPrimary` is what labels every filled button and the selected nav
    destination, those were the app's least readable pixels on most palettes.
    It now picks whichever candidate measures better, which cannot be worse than
    any threshold because the threshold was an approximation of that comparison.
    All fourteen land between 4.63:1 and 11.62:1; the six that were right do not
    move.
  - **Six light palettes drew the accent as text below the bar**, down to
    2.39:1 on Mint Fresh — the `Today` pill, the `Tomorrow` word, the `Home`
    badge. Repaired with derived tokens (`primaryInk`, `primaryGlyph`,
    `warningInk`, `successInk`, `errorInk`) rather than by editing the catalog:
    a palette keeps the exact colour the user picked for every fill, disc and
    wash, and only the places that draw an accent *as content* take the darker
    one. The repair is a fixed 40% blend toward `onBackground` and is skipped
    entirely on the 13 palettes that never needed it, because a blend applied
    unconditionally is a design change wearing an accessibility argument.
  - **Muted text missed on four light palettes**, between 4.06:1 and 4.42:1.
    That one *is* a catalog edit — `onBackgroundLight` has hundreds of call
    sites and no derived token between it and them — of between 3% and 10%
    toward the foreground, which is invisible and enough.
  - **`AppColors.defaultLight` had already drifted from the catalog entry it
    duplicates.** `app_colors.dart` cannot import the catalogs, because the
    catalogs import `AppColorsData` from it, so the two copies are the one pair
    of values in the theme layer with no compiler holding them together. A test
    holds them now.

  **Item 17, the accessibility pass**, found what the M2 entry predicted it
  would: the grid is the hard part. What shipped:

  - Every hour cell announces `"{hour}, {band}"`. The band was carried by
    colour and by nothing else, so a screen reader got a line of bare numbers
    and no answer to the question the screen exists to answer. Where the grid
    draws marks *over* a cell, the row passes a fuller label carrying the same
    facts the marks carry.
  - **Three icon-only controls had no name at all**: the app bar's back
    chevron, and the converter's two day steppers — a mirrored pair, where an
    unnamed control is worse than usual because the user cannot tell which way
    either goes. The date pill's two chevrons had *declared parameters* for
    their labels and **no caller passing them**, in the same shape the
    2026-08-21 audit found `popOrGo` in. They are resolved inside the widget
    now; there was never a caller who wanted different words.
  - `LoadingShimmer` published no semantics, so a loading page and an empty one
    sounded identical. It announces `t.common.loading` as a live region.
  - `HourCell.cursorInkBlend` moved from `0.45` to `0.50`: at `0.45` the
    cursor's digits measured `4.31:1` on Mint Fresh.

  `test/app/accessibility_test.dart` pins all of it, because every one of these
  was a property somebody believed was already true.

  **Item 15, the empty/loading/error audit, found nothing to fix**, and that is
  worth recording rather than leaving as an absence. Every page has all three
  states, and each of the four apparent gaps turns out to be a decision with its
  reason already written down: preferences has no error state because a storage
  failure is surfaced passively by sync (sync.md rule 4) and there is always a
  usable in-memory document; the converter answers an empty board with a muted
  note rather than an empty state, because a board holding only the source zone
  is a valid answer; the world clock puts its invitation *under* the home clock
  rather than in place of it (world_clock.md rule 11); and `AuthError` on the
  profile page holds a shimmer rather than the signed-out panel, because on
  that page it means a failed *sign-out* and the user is still signed in. The
  one change was the shimmer's semantics, above.

  1002 tests passing, `flutter analyze` clean.

  **What item 17 did not settle, and it is a design question rather than a
  bug:** by eye the band is still a colour. Four hues at a 16% wash, with the
  digits tinted from the same token — for a reader with deuteranopia the good
  and poor bands are close, and the only non-colour cue is the hour itself. The
  options are costed in [specs/time_grid.md](specs/time_grid.md) under
  Accessibility; the cheapest is a hairline along the bottom edge of the
  working window, which is one mark rather than four and answers the question
  the user actually has.

---

## In progress

- **M5: release.** Items 15, 16 and 17 ran on 2026-08-21 (see The front door,
  and the release audits, under Done), so what is left is **item 13**, the PWA
  work, and the **Play App Signing** step from
  [android_release.md](android_release.md) that item 14 reduces to. Item 17
  leaves one open question behind it rather than a task: whether the hour bands
  need a non-colour cue, and which one.
- **The app's own web shell is still Flutter's scaffold**, and the landing page
  made that visible: `web/index.html` is titled `timebuddy` in lower case,
  `web/manifest.json` still carries Flutter's default `#0175C2` blue as its
  theme and background colour, and `web/icons/` holds the stock Flutter logo in
  all four sizes. `flutter_launcher_icons` is in `dev_dependencies` with **no
  configuration block in `pubspec.yaml`** and has therefore never run. None of
  it is visible inside the app — `MaterialApp.title` sets the tab title once the
  first frame lands, and the icons only show in a bookmark, an install prompt or
  a task switcher — which is exactly why it survived four milestones. It belongs
  to item 13.
- **The DST explanation sheet** (`t.grid.dstExplainTitle` / `dstExplainBody`),
  the last of M2's four deferred details still open. `DstBadge` has carried an
  `onTap` with nothing behind it since M2 and the strings have shipped in both
  locales just as long. Its original reason for waiting — that the planner
  would reopen the grid's interaction surface anyway — is gone with the
  planner, so it is now an ordinary piece of grid polish.

---

## Planned

Numbering continues from M2's and M3's items 1 to 9, which are now under Done,
so an item number still points at the piece of work it always did.

### M4: Planning tools — closed 2026-08-20, ten weeks early

10. ~~World clock page.~~ **Done**, see M4 under Done.
11. ~~Meeting planner mode, summary panel, best-slot suggestion, copy to
    clipboard.~~ **Dropped.** It shipped with the rest of M4 and was deleted the
    next day; the two entries under Done say why. Marked rather than removed,
    because the number is what older entries and commit messages cite.
12. ~~Time converter page.~~ **Done**, see M4 under Done.

### M5: Release (target: 2026-10-21)

13. PWA manifest, install prompt and offline shell, plus deep-link routes
    verified against the published site. The hosting itself is already done
    (see Done), so what remains here is the app-level polish.
14. Adaptive icon and Play Store listing assets. The signing half of this item
    is done — release signing is wired and both the debug and the release
    fingerprints are registered on the Firebase project (see Android release
    signing under Done) — so what is left of it is **Play App Signing**: Google
    re-signs an uploaded app with a key it holds, so the fingerprint the
    installed app presents is Google's and not the one registered today. Sign-in
    then works in a local release build and fails for every store install, which
    is the worst possible time to find out.
    → [android_release.md](android_release.md) step 5
15. ~~Empty, loading and error states audited on every page.~~ **Done**
    (2026-08-21). The audit found nothing to fix: every page carries all three
    states and each apparent gap is a decision with its reason already written
    down. The Done entry lists the four.
16. ~~Light and dark checked against all 20 palettes.~~ **Done** (2026-08-21),
    and it is a test rather than a review —
    `test/app/theme/palette_contrast_test.dart`. It found four defects, one of
    them the worst thing the project has shipped: `foregroundOn` put white on
    the primary of 14 of the 20 palettes, down to 1.81:1 on the label of every
    filled button.
17. ~~Accessibility pass.~~ **Mostly done** (2026-08-21): contrast on every
    hour band and on every accent drawn as content, screen-reader labels for the
    grid's cells, and names for the five icon-only controls that had none.
    Pinned by `test/app/accessibility_test.dart`.

    **One question survives, and it is the one M2 predicted would be hard.** By
    eye, an hour's band is still carried by colour and nothing else: four hues
    at a 16% wash, digits tinted from the same token, no shape or weight
    separating them. The screen-reader path is fixed; the colour-blind reader's
    is not, and the only non-colour cue on screen is the hour itself. Three
    options are costed in [specs/time_grid.md](specs/time_grid.md) under
    Accessibility — a per-band glyph, a pinned legend (declined once already,
    for height), or a hairline along the bottom edge of the working window,
    which is one mark rather than four and answers the question the user
    actually has. **Decide before release.**

---

## Open risks

Unlike a deferred decision, an item here has a date attached and gets worse if
it is left alone.

### The shipped tzdata is 2025c, and Morocco breaks on 2026-09-20

**This is the only finding in the repository with a deadline.** All of it is
measured rather than assumed.

`timezone: ^0.11.1` resolves to **0.11.1**, which is the latest published
release (2026-06-29), and it embeds IANA tzdata **2025c** — the package's own
`lib/data/latest_all.dart` says so on line 2. Upstream IANA is at **2026c**
(2026-07-08). There is no upgrade to take: the newest version of the package
carries the old data, so `flutter pub upgrade` changes nothing here.

What the gap costs, in cities that are in the shipped catalog:

| Zone | Change | Effect |
|---|---|---|
| `Africa/Casablanca`, `Africa/El_Aaiun` | Morocco goes to permanent UTC on **2026-09-20** | The app reads **one hour off, indefinitely**, from that date on |
| `America/Vancouver` | British Columbia went permanent −07 (2026b) | Wrong across the transition dates 2025c still believes in |
| `America/Edmonton` | Alberta went permanent −06 (2026c) | Same |
| `Europe/Chisinau` | Moldova's transition times corrected (2026a) | Wrong at the transition |

The Morocco one is the reason this is a risk rather than a chore: it is not a
twice-a-year edge, it is a permanent one-hour error starting on a known date,
and it looks entirely plausible on screen — which is the same failure mode rule
4 of [specs/timezone_engine.md](specs/timezone_engine.md) exists to prevent, one
layer further up.

Two options, and only two:

1. **Wait for a `timezone` release carrying 2026c.** Free, and it may well
   arrive before September. It is a bet on someone else's release cadence, with
   no fallback if it does not land.
2. **Stop depending on the embedded dataset.** The package ships the tooling to
   build one: `tool/get.dart` fetches a release and `tool/encode_tzf.dart`
   encodes it, and the result is a `.tzf` shipped as an ordinary asset and
   loaded through the **public** `initializeDatabase(Uint8List)` instead of
   `latest_all.dart`'s `initializeTimeZones()`. This is more work once and
   removes the dependency permanently — and it also hands rule 12 the thing it
   has been waiting on since M1, because a dataset we generate is a release we
   know the name of and can print in Settings → About.

Decide before **2026-09-20**. If option 1 has not paid off by early September,
option 2 is the one that meets the date.

**Re-measured 2026-08-21, thirty days out: nothing has moved.** `flutter pub
outdated` reports no newer `timezone`, and the resolved package's
`lib/data/latest_all.dart` still says `Timezone data version: 2025c` on line 2.
Option 1 has one month left to pay off, and option 2 — generating the `.tzf`
with the package's own `tool/get.dart` and loading it through the public
`initializeDatabase` — is a day of work that has to start before it is due,
not on the day.

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
  Deliberately out of v1 (`specs/meeting_planner.md`, since deleted
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
- **Full vs trimmed tzdata on web.** ~~Must be decided before the M5 web
  deploy~~ — **decided, and the spec is where it lives now.**
  [specs/timezone_engine.md](specs/timezone_engine.md), Open questions, opens
  with "Decided, kept here for the record" and measures all three datasets:
  `latest_10y.dart` (~65 KB) keeps about a decade of transitions and therefore
  answers historical converter queries wrong, which rules it out for a tool
  whose converter advertises dates far from now; `latest.dart` (~250 KB, 341
  zones) drops the `Link` lines; the engine ships `latest_all.dart` (~435 KB,
  598 names). Revisit only if the web bundle becomes a real constraint, and
  measure before touching it. What is *not* settled is which **release** that
  dataset carries — see Open risks below.
- **Widgets / complications** (home-screen clock on Android). Different runtime,
  different design system, its own project phase.
- **RTK tooling.** The Financo repo carries an RTK instructions block in its
  `CLAUDE.md`. It is not copied here; run `rtk init` in this repository if you
  want the same token-saving command conventions.

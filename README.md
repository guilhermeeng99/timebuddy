# TimeBuddy

Real-time world clock and timezone comparison for Android and Web. See what time
it is in every city you care about, and find an hour that works for all of them.

**Live build: <https://guilhermeeng99.github.io/timebuddy/>**

> Status: milestones 1, 2 and 3 are implemented. M1 shipped the theme layer, the
> timezone engine, the core time utilities, local storage, preferences and the
> settings page. M2 shipped the 500-city catalog and its search, the saved board
> (add, remove with undo, reorder, set home, replace a zone), the comparison
> grid and the shell chrome that carries them. M3 shipped the account: Google
> sign-in, the Firestore documents behind it and the revision-based sync that
> keeps them in step. The planning tools described below are still
> documentation. See [docs/roadmap.md](docs/roadmap.md).
>
> **Sign-in is optional.** What a visitor meets is a splash while tzdata loads,
> then a three-slide tour. Every slide carries *continue without an account*,
> and the last one also carries *Sign in with Google* — there is no
> email/password either way. A guest gets the whole app against local-only
> documents; signing in starts the sync and carries their board up, except that
> **an account which already has a board keeps it** (see
> [docs/specs/guest_mode.md](docs/specs/guest_mode.md)). Once the Google popup
> (or the redirect the browser falls back to) comes back, the app opens on the
> grid. Anyone with a Google account can sign in; there is no
> allowlist. Google sign-in currently works on the web build only:
> the Android app has no signing fingerprint registered on the Firebase project
> yet, which the roadmap records as unfinished rather than buried.

## What it does

Shipped:

- **Time grid**: one row per saved city, one column per hour, colored by how
  reasonable that hour is locally. Drag the cursor and read the same instant
  everywhere at once. Handles half-hour zones, the date line, and days that have
  23 or 25 hours.
- **Your cities**: search 500 cities by name, country or IANA id, accents
  optional, and keep up to 20 on the board. Reorder them, pick the one you
  measure everything else from, and undo a removal you did not mean.
- **Theming**: light and dark, 10 selectable palettes each, shared with the
  Financo project.
- **Your account**: sign in with Google and the same board and preferences show
  up on the phone and in the browser. Two documents per user in Firestore,
  reconciled by revision number. A write that cannot reach the server is never
  an error the user has to read: it is remembered and retried later, and the
  profile page carries a passive synced / syncing / offline indicator that says
  so. That page lives at `/profile` and nothing links to it yet, see the
  roadmap's list of what M3 left open.

Specified, not built yet:

- **World clock** (M4): a live list of your cities with the current time, the
  offset from home, and whether it is tomorrow there.
- **Meeting planner** (M4): select a range on the grid and get a pasteable
  summary with the local time for every participant, plus a suggested better
  slot when someone is stuck at 03:00.
- **Time converter** (M4): "15:00 on 12 March in Lisbon" resolved everywhere,
  including dates far enough out that today's DST rules do not apply.

## Architecture

[Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
with feature-first organization:

```
lib/
├── app/          # App shell: DI, routing, theme, widgets, city asset
├── core/         # Time engine, storage, sync, errors, extensions, utils
├── features/     # auth, locations, time_grid, preferences, profile,
│                 #   settings, startup
│                 #   (each: data / domain / presentation)
└── gen/          # Generated code (slang i18n)

docs/specs/       # Per-feature contracts (entities, business rules, state machines)
scripts/          # build_city_catalog.dart + city_seeds.dart: regenerate the
                  #   city asset. Build tooling, not shipped in the app
test/
└── harness/      # Centralized mocks, factories, helpers, FakeClock
```

Each `features/<x>/` module follows:

- `domain/`: entities, repository interfaces, use cases
- `data/`: models, datasources, repository implementations
- `presentation/`: cubits/blocs, pages, widgets

Three modules are presentation only, and deliberately so. `settings/` is a
screen over the preferences feature, because giving it a domain of its own would
put two owners on one document; `profile/` is a screen over `auth` and the sync
status; `startup/` is a cubit that composes four collaborators it does not own.
Sync itself lives in `core/sync/` rather than in a feature: it is the one place
that reconciles *both* documents against one account, and a copy of the conflict
rules per feature would be two owners of one rule.

### The one architectural rule worth stating up front

`package:timezone` is importable **only** from `lib/core/time/`. Every feature
asks `TimeZoneEngine` and renders the answer. Timezone logic scattered across
widgets is how apps end up an hour wrong twice a year.

## Tech stack

| Concern | Tool |
|---|---|
| State management | `flutter_bloc` (Cubits mostly; `AuthBloc` is the one Bloc) |
| DI | `get_it` |
| Routing | `go_router` (hash URLs on web; `StatefulShellRoute`, one branch per destination) |
| Timezones | `timezone` (IANA tzdata) + `flutter_timezone` |
| Local storage | `shared_preferences` (two JSON documents, no database) |
| Remote sync | `cloud_firestore`: two documents per user, revision-based last-write-wins, no listeners and no timers |
| Auth | `firebase_auth` + `google_sign_in` (Google only; popup with a redirect fallback on web, the plugin on Android) |
| Error model | `dartz` `Either<Failure, T>` |
| i18n | `slang` (type-safe, generated), pt-BR and en |
| Fonts | `google_fonts` (Poppins + Inter) |
| Lints | `very_good_analysis` (strict) |
| Testing | `flutter_test`, `bloc_test`, `mocktail`, plus `fake_cloud_firestore` and `firebase_auth_mocks` at the auth boundary |

### Why there is no local database

The whole persisted state is a list of at most 20 locations plus a preferences
map: roughly 3 KB of JSON, always read whole, never queried by field. A
relational cache would add a codegen step, a migration surface and a web WASM
worker for zero benefit. Details in [docs/specs/sync.md](docs/specs/sync.md).

## Spec-driven development

Every feature has a contract at `docs/specs/<feature>.md` covering entities,
business rules, repository interfaces, state machines and edge cases. Tests are
written against the spec; code follows. See [CLAUDE.md](CLAUDE.md) for the full
conventions.

Start here:

| Spec | What it defines |
|---|---|
| [design_system.md](docs/specs/design_system.md) | Tokens, typography, spacing, the `TimeBuddy*` widget library |
| [timezone_engine.md](docs/specs/timezone_engine.md) | Every conversion, offset and DST rule |
| [locations.md](docs/specs/locations.md) | The board, the city catalog, search |
| [time_grid.md](docs/specs/time_grid.md) | The main screen |
| [world_clock.md](docs/specs/world_clock.md) | The live clock list |
| [meeting_planner.md](docs/specs/meeting_planner.md) | Range selection and summaries |
| [time_converter.md](docs/specs/time_converter.md) | Point-in-time conversion |
| [auth.md](docs/specs/auth.md) | Google sign-in, profile |
| [guest_mode.md](docs/specs/guest_mode.md) | Using the app without an account, and what signing in does to that data |
| [sync.md](docs/specs/sync.md) | Local storage, Firestore, conflict resolution |
| [preferences.md](docs/specs/preferences.md) | Settings, working hours, theme |
| [startup.md](docs/specs/startup.md) | Boot sequence and the splash gate |

Android release signing, including the Play App Signing step that silently
breaks Google sign-in for everyone who installs from the store if it is
skipped: [docs/android_release.md](docs/android_release.md).

Backend setup (run once, per Firebase project):
[docs/firebase_setup.md](docs/firebase_setup.md). It covers creating the
project, enabling Google as the only sign-in provider, creating Firestore and
deploying the security rules, plus the authorised-domain step that Google
sign-in fails on in production without saying so, and the Android signing
fingerprint that it fails on with an error naming neither.

## Running locally

Prerequisites: Flutter 3.47 or newer, Dart >= 3.13 (the SDK constraint in
`pubspec.yaml`).

```bash
# 1. Install deps and generate code
flutter pub get
dart run slang

# 2. Run
flutter run -d chrome   # web
flutter run             # connected Android device
```

That is the whole setup for the project's own Firebase project: both
`lib/firebase_options.dart` and `android/app/google-services.json` are
committed, and they are safe to commit: a Firebase API key identifies a project
and authorises nothing, which is why `firestore.rules` is what actually protects
the data.

A fork needs its own project, because sign-in is checked against the Firebase
project's authorised domains and the data lives under its Firestore instance:
follow [docs/firebase_setup.md](docs/firebase_setup.md), then
`flutterfire configure --project=<your-project-id> --platforms=android,web` to
rewrite both files. Two things that bite in a fresh project and are documented
there rather than left to be diagnosed: the deployment origin has to be an
authorised domain, and Android sign-in needs the debug (and later release) SHA-1
registered or it fails with `ApiException: 10`.

## Quality bar

```bash
flutter analyze   # must be zero errors, warnings and info issues
flutter test      # must be green
```

Both run before every commit, and again in CI: the Pages workflow
(`.github/workflows/deploy-pages.yml`) analyses and tests before it builds, so a
red `main` never reaches the published site. See the post-change checklist in
[CLAUDE.md](CLAUDE.md).

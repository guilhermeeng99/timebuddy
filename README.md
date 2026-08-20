# TimeBuddy

Real-time world clock and timezone comparison for Android and Web. See what time
it is in every city you care about, and find an hour that works for all of them.

**Live build: <https://guilhermeeng99.github.io/timebuddy/>**

> Status: milestones 1 and 2 are implemented. M1 shipped the theme layer, the
> timezone engine, the core time utilities, local storage, preferences and the
> settings page. M2 shipped the 500-city catalog and its search, the saved board
> (add, remove with undo, reorder, set home, replace a zone), the comparison
> grid and the shell chrome that carries them. Sync, sign-in and the planning
> tools described below are still documentation. See
> [docs/roadmap.md](docs/roadmap.md).
>
> The live build is therefore the app offline and signed out: add the cities you
> care about and read one instant across all of them. Everything it stores stays
> on the device, because there is no account yet.

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

Specified, not built yet:

- **World clock** (M4): a live list of your cities with the current time, the
  offset from home, and whether it is tomorrow there.
- **Meeting planner** (M4): select a range on the grid and get a pasteable
  summary with the local time for every participant, plus a suggested better
  slot when someone is stuck at 03:00.
- **Time converter** (M4): "15:00 on 12 March in Lisbon" resolved everywhere,
  including dates far enough out that today's DST rules do not apply.
- **Sync** (M3): sign in with Google and the same board and preferences follow
  you between the phone and the browser.

## Architecture

[Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
with feature-first organization:

```
lib/
├── app/          # App shell: DI, routing, theme, widgets, city asset
├── core/         # Time engine, storage, errors, extensions, utils
├── features/     # locations, time_grid, preferences, settings
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

`settings/` is the one exception: presentation only, a screen over the
preferences feature, because giving it a domain of its own would put two owners
on one document.

### The one architectural rule worth stating up front

`package:timezone` is importable **only** from `lib/core/time/`. Every feature
asks `TimeZoneEngine` and renders the answer. Timezone logic scattered across
widgets is how apps end up an hour wrong twice a year.

## Tech stack

| Concern | Tool |
|---|---|
| State management | `flutter_bloc` (Cubits mostly; the auth Bloc arrives with M3) |
| DI | `get_it` |
| Routing | `go_router` (hash URLs on web; `StatefulShellRoute`, one branch per destination) |
| Timezones | `timezone` (IANA tzdata) + `flutter_timezone` |
| Local storage | `shared_preferences` (two JSON documents, no database) |
| Remote sync | Firebase Firestore, revision-based last-write-wins. Arrives with M3; nothing Firebase is in `pubspec.yaml` yet |
| Auth | Firebase Auth + `google_sign_in` (Google only). Arrives with M3 |
| Error model | `dartz` `Either<Failure, T>` |
| i18n | `slang` (type-safe, generated), pt-BR and en |
| Fonts | `google_fonts` (Poppins + Inter) |
| Lints | `very_good_analysis` (strict) |
| Testing | `flutter_test`, `bloc_test`, `mocktail` (`fake_cloud_firestore` joins them with M3) |

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
| [sync.md](docs/specs/sync.md) | Local storage, Firestore, conflict resolution |
| [preferences.md](docs/specs/preferences.md) | Settings, working hours, theme |
| [startup.md](docs/specs/startup.md) | Boot sequence and the splash gate |

## Running locally

Prerequisites: Flutter 3.47 or newer, Dart >= 3.13 (the SDK constraint in
`pubspec.yaml`). Nothing else: there is no backend to configure yet.

```bash
# 1. Install deps and generate code
flutter pub get
dart run slang

# 2. Run
flutter run -d chrome   # web
flutter run             # connected Android device
```

There is deliberately no `flutterfire configure` step. The app has no Firebase
dependency and no `lib/firebase_options.dart`, because everything it persists
today lives on the device. That step joins this list with milestone 3, together
with sign-in and sync ([docs/specs/sync.md](docs/specs/sync.md)).

## Quality bar

```bash
flutter analyze   # must be zero errors, warnings and info issues
flutter test      # must be green
```

Both run before every commit. See the post-change checklist in
[CLAUDE.md](CLAUDE.md).

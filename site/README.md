# TimeBuddy — landing site

The static page presenting the app, served at the GitHub Pages root
(`/timebuddy/`) with the Flutter web build one level down at `/timebuddy/app/`.

Stack: **Vite + Tailwind v4**, no framework, one page, no backend.

## Why it is not part of the Flutter build

It is a separate bundle with its own toolchain, deployed by the same workflow
(`.github/workflows/deploy-pages.yml`) in the same job. Keeping it out of
`web/` means the marketing copy never ships inside the app, and a page rebuild
never invalidates the app's CanvasKit cache.

## Design tokens are not the site's own

`src/styles.css` copies its palette from `lib/app/theme/app_colors.dart`:
`AppColors.defaultLight`, the app's Indigo Cloud, and its type families are the
two the app loads through `google_fonts`. A
landing page that picks its own indigo is a second brand, and the two drift the
first time either is retuned. If a palette value changes in the app, change it
here too.

**The page is light only**, following the Financo site rather than the app. The
app ships both brightnesses because it is a tool someone keeps open all day; a
landing page is read once, and one committed surface is a page that looks the
same in every screenshot and link preview. Nothing reads `prefers-color-scheme`
and no utility class in `index.html` is theme-aware, so restoring a dark set is
a matter of redefining the tokens in one place.

## The hero grid is real

`src/live-grid.ts` is a working miniature of the app's main screen: the columns
are actual instants, every cell is resolved through the browser's own IANA
database with `Intl.DateTimeFormat`, and the first row is the visitor's own time
zone. `bandFor` and `relativeOffsetLabel` are ports of
`lib/core/time/hour_band.dart` and `lib/core/utils/time_formatter.dart` — if
either rule changes in the app, it changes here.

Kolkata is in the fixed city list on purpose: at `+05:30` it prints `18:30`, so
a demo built on `hour + offset` arithmetic would visibly print the wrong thing.

## Commands

Run from inside `site/`:

```bash
npm install     # first time
npm run dev     # local preview on http://localhost:5173
npm run build   # static output → dist/
npm run typecheck
```

`npm`, not `pnpm` as in the Financo repo: `actions/setup-node` already carries
it, so the workflow needs no extra action for a page with four dev
dependencies.

## Old app bookmarks

Until this page existed the Flutter build was served from the Pages root, so
existing bookmarks look like `…/timebuddy/#/settings`. `src/main.ts` forwards
any hash beginning with `#/` to `./app/`, which is why the page's own anchors
(`#features`, `#time`, `#start`) never use a leading slash.

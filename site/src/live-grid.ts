/**
 * The hero's live time grid.
 *
 * It is a working miniature of the app's main screen rather than a picture of
 * one: the columns are real instants, every cell is resolved through the
 * browser's own IANA database with `Intl.DateTimeFormat`, the bands come from
 * the app's `hourBandFor` rule, and the first row is the visitor's own zone.
 * Nothing is hardcoded except the four cities, so the page cannot show an hour
 * the product would disagree with.
 *
 * The rules it inherits from lib/, and why each is worth the code:
 *
 *  - **A column is one instant, not one local hour** (time_grid.md rule 1).
 *    Every row formats the *same* `Date`, which is the entire point of the
 *    screen.
 *  - **Half-hour zones render their minutes** (rule 5). Kolkata is in the list
 *    on purpose: at `+05:30` it prints `18:30`, and a demo built on
 *    `hour + offset` would print `18`.
 *  - **Day boundaries are marked per row** (rule 6). At one instant two cities
 *    are on different dates, so the date label belongs to the cell, never to
 *    the screen.
 *  - **Offsets are resolved for the instant in question** (CLAUDE.md rule 2),
 *    which is what `longOffset` asks the platform for rather than caching a
 *    number per zone.
 *
 * The markup is a real `<table>` with row and column headers: the colour is
 * decoration, and the time in each cell is the information.
 */

/** One row of the demo. `zoneId` is an IANA id, as everywhere in the app. */
interface DemoCity {
  readonly label: string;
  readonly zoneId: string;
}

/**
 * The four fixed rows, chosen to spread across the date line and to include a
 * zone whose offset is not a whole number of hours.
 */
const CITIES: readonly DemoCity[] = [
  { label: "San Francisco", zoneId: "America/Los_Angeles" },
  { label: "London", zoneId: "Europe/London" },
  { label: "Bengaluru", zoneId: "Asia/Kolkata" },
  { label: "Tokyo", zoneId: "Asia/Tokyo" },
];

/** The app's first-launch working window: start inclusive, end exclusive. */
const WORK_START = 9;
const WORK_END = 17;

/**
 * Columns drawn before and after the current hour.
 *
 * Fourteen in total, which at 62px plus the 150px label column fills the hero
 * card on a desktop and scrolls on anything narrower — the same trade the app
 * makes, where the track holds as many whole columns as the width allows.
 */
const SLOTS_BEFORE = 3;
const SLOTS_AFTER = 10;

const HOUR_MS = 60 * 60 * 1000;

/** Redraw cadence. The grid shows hours, so a minute is granular enough. */
const REFRESH_MS = 30_000;

type Band = "good" | "fair" | "poor" | "night";

/** `WorkingHours.contains`, wrap-aware, from lib/core/time/working_hours.dart. */
function withinWorkingHours(hour: number): boolean {
  const length = (WORK_END - WORK_START + 24) % 24 || 24;
  return (((hour - WORK_START) % 24) + 24) % 24 < length;
}

/**
 * `hourBandFor`, ported verbatim from lib/core/time/hour_band.dart — including
 * the order of the checks, which is part of that function's contract: a night
 * shift is inside its own working window and must not read as asleep.
 */
function bandFor(hour: number): Band {
  if (withinWorkingHours(hour)) return "good";
  if (withinWorkingHours((hour + 1) % 24) || withinWorkingHours((hour + 23) % 24)) {
    return "fair";
  }
  if (hour >= 23 || hour < 7) return "night";
  return "poor";
}

/** What one row reads at one instant. */
interface CellParts {
  readonly hour: number;
  readonly minute: number;
  readonly day: number;
  readonly month: string;
  readonly weekday: string;
}

const partsCache = new Map<string, Intl.DateTimeFormat>();

function formatterFor(zoneId: string): Intl.DateTimeFormat {
  let formatter = partsCache.get(zoneId);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-GB", {
      timeZone: zoneId,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
      day: "numeric",
      month: "short",
      weekday: "short",
    });
    partsCache.set(zoneId, formatter);
  }
  return formatter;
}

/** The wall clock a person in `zoneId` reads at `instant`. */
function partsAt(instant: Date, zoneId: string): CellParts {
  const parts = formatterFor(zoneId).formatToParts(instant);
  const read = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return {
    hour: Number(read("hour")),
    minute: Number(read("minute")),
    day: Number(read("day")),
    month: read("month"),
    weekday: read("weekday"),
  };
}

/**
 * The zone's offset from UTC **at that instant**, in minutes.
 *
 * Asked of the platform every time rather than cached per zone, for the reason
 * CLAUDE.md rule 2 gives: an offset is a function of (zone, instant), and a
 * cached one is wrong on the far side of the next transition.
 */
function offsetMinutesAt(instant: Date, zoneId: string): number {
  const formatted = new Intl.DateTimeFormat("en-GB", {
    timeZone: zoneId,
    timeZoneName: "longOffset",
  }).formatToParts(instant);
  const name = formatted.find((part) => part.type === "timeZoneName")?.value ?? "";
  // "GMT+05:30", "GMT-03:00", or a bare "GMT" at zero.
  const match = /GMT([+-])(\d{2}):(\d{2})/.exec(name);
  if (!match) return 0;
  const sign = match[1] === "-" ? -1 : 1;
  return sign * (Number(match[2]) * 60 + Number(match[3]));
}

/** `relativeOffsetLabel`, from lib/core/utils/time_formatter.dart. */
function relativeOffsetLabel(minutes: number): string | null {
  if (minutes === 0) return null;
  const magnitude = Math.abs(minutes);
  const sign = minutes < 0 ? "-" : "+";
  const rest = magnitude % 60;
  const hours = Math.floor(magnitude / 60);
  return rest === 0 ? `${sign}${hours}h` : `${sign}${hours}h${String(rest).padStart(2, "0")}`;
}

/**
 * `formatGridHour`: `14`, or `14:30` where the offset carries minutes.
 *
 * Always 24-hour, like the app's grid and for the app's reason — a ruler of
 * contiguous columns that prints `03` twice cannot say which one it means.
 */
function gridHour({ hour, minute }: CellParts): string {
  const padded = String(hour).padStart(2, "0");
  return minute === 0 ? padded : `${padded}:${String(minute).padStart(2, "0")}`;
}

function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

/**
 * Width of one hour column and of the pinned label column, in px.
 *
 * Applied as an inline style rather than as a Tailwind class, deliberately:
 * the opening scroll offset is arithmetic over both numbers, and Tailwind
 * resolves its classes by scanning the source for literals, so a class name
 * built by template interpolation compiles to nothing at all — and a
 * hand-written `w-[62px]` beside a constant is two places to change one width.
 */
const CELL_W = 62;
const LABEL_W = 150;

const CELL_CLASS =
  "hour-cell relative h-14 shrink-0 border-r border-canvas/60 " +
  "text-center align-middle font-body text-body-lg font-semibold tabular-nums";

/** The visitor's own zone, or UTC when the platform refuses to name one. */
function viewerZone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

function render(host: HTMLElement): void {
  const home = viewerZone();
  const rows: DemoCity[] = [
    { label: "Your time", zoneId: home },
    // A visitor already sitting in one of the four would otherwise get the
    // same clock twice, which is the one thing the board itself forbids
    // (locations.md rule 2).
    ...CITIES.filter((city) => city.zoneId !== home),
  ];

  const now = new Date();
  const anchor = new Date(Math.floor(now.getTime() / HOUR_MS) * HOUR_MS);
  const slots: Date[] = [];
  for (let i = -SLOTS_BEFORE; i <= SLOTS_AFTER; i++) {
    slots.push(new Date(anchor.getTime() + i * HOUR_MS));
  }
  const nowIndex = SLOTS_BEFORE;
  const homeOffset = offsetMinutesAt(now, home);

  const table = element("table", "w-max border-collapse");
  table.setAttribute("aria-live", "off");

  const caption = element(
    "caption",
    "sr-only",
    "Live local time in each city over the next few hours, from your own time zone. " +
      "Each column is the same moment.",
  );
  table.append(caption);

  // --- header: one column per instant ---
  const head = document.createElement("thead");
  const headRow = document.createElement("tr");
  const corner = element("th", "sticky left-0 z-10 bg-surface");
  corner.style.width = `${LABEL_W}px`;
  corner.scope = "col";
  corner.append(element("span", "sr-only", "City"));
  headRow.append(corner);

  slots.forEach((slot, index) => {
    const cell = element(
      "th",
      "h-9 shrink-0 border-r border-canvas/60 bg-canvas-deep text-center " +
        "font-body text-body font-semibold tabular-nums " +
        (index === nowIndex ? "text-indigo" : "text-ink-soft"),
    );
    cell.style.width = `${CELL_W}px`;
    cell.scope = "col";
    const parts = partsAt(slot, home);
    cell.textContent = gridHour(parts);
    if (index === nowIndex) {
      cell.append(element("span", "sr-only", " (now)"));
    }
    headRow.append(cell);
  });
  head.append(headRow);
  table.append(head);

  // --- one row per city ---
  const body = document.createElement("tbody");
  for (const city of rows) {
    const row = document.createElement("tr");
    const isHome = city.zoneId === home;

    const label = element(
      "th",
      "sticky left-0 z-10 border-r border-hairline bg-surface px-3 py-2 " +
        "text-left align-middle",
    );
    label.style.width = `${LABEL_W}px`;
    label.style.minWidth = `${LABEL_W}px`;
    label.scope = "row";
    label.append(
      element("span", "block font-body text-body-lg font-semibold text-ink truncate", city.label),
    );

    const offset = relativeOffsetLabel(offsetMinutesAt(now, city.zoneId) - homeOffset);
    const badge = element(
      "span",
      "mt-0.5 inline-block rounded-control bg-canvas-deep px-2 py-0.5 font-body text-caption " +
        "font-semibold text-ink-soft",
      // `t.grid.homeBadge` / `t.grid.sameTime`, the two things the app's own
      // label column says when there is no offset to show.
      offset ?? (isHome ? "Home" : "Same time"),
    );
    label.append(badge);
    row.append(label);

    let previousDay: number | null = null;
    slots.forEach((slot, index) => {
      const parts = partsAt(slot, city.zoneId);
      const cell = element(
        "td",
        `${CELL_CLASS} band-${bandFor(parts.hour)}${index === nowIndex ? " hour-now" : ""}`,
      );
      cell.style.width = `${CELL_W}px`;
      cell.textContent = gridHour(parts);

      // The date turns over inside this row, at this column and no other.
      if (previousDay !== null && parts.day !== previousDay) {
        // The separator is its own node so the cell reads as "00, Sat 22"
        // rather than "00Sat 22" when announced.
        cell.append(element("span", "sr-only", ", "));
        const flag = element(
          "span",
          "absolute inset-x-0 top-0.5 font-body text-[10px] font-semibold uppercase " +
            "tracking-wide opacity-70",
          `${parts.weekday} ${parts.day}`,
        );
        cell.append(flag);
        cell.classList.add("border-l-2", "border-l-ink-soft/40");
      }
      previousDay = parts.day;
      row.append(cell);
    });
    body.append(row);
  }
  table.append(body);

  host.replaceChildren(table);
}

/**
 * Puts the current hour on screen, the way the app's grid opens centred on now
 * (time_grid.md rule 13).
 *
 * Only meaningful on a narrow window — a desktop fits all fourteen columns and
 * this is a no-op. It has to run *after* layout: setting `scrollLeft` on a
 * container whose content has not been measured yet clamps to 0, which is
 * exactly what a `requestAnimationFrame` immediately after the first render
 * did, silently, at every width below about 1000px.
 *
 * Reading `scrollWidth` first is what forces that measurement.
 */
function scrollToNow(host: HTMLElement): void {
  const scroller = host.closest<HTMLElement>("[data-grid-scroller]");
  if (!scroller) return;
  if (scroller.scrollWidth <= scroller.clientWidth) return;

  // A cell at index `i` starts at `LABEL_W + i * CELL_W` in content
  // coordinates, and the pinned label covers the first `LABEL_W` of the
  // viewport — so `scrollLeft = i * CELL_W` puts that cell flush against the
  // label. One column short of that leaves the hour before it visible too,
  // which is the context the marker is worth having.
  const target = Math.max(0, (SLOTS_BEFORE - 1) * CELL_W);
  scroller.scrollLeft = target;
}

/**
 * Mounts the live grid into `#live-grid` and keeps it current.
 *
 * ```ts
 * mountLiveGrid();
 * ```
 */
export function mountLiveGrid(): void {
  const host = document.getElementById("live-grid");
  if (!host) return;

  const draw = () => render(host);
  draw();
  scrollToNow(host);

  let timer = window.setInterval(draw, REFRESH_MS);
  // A backgrounded tab does not need a redraw a minute, and it wakes up owing
  // one — the same trade `TickerService` makes on `AppLifecycleState.paused`.
  document.addEventListener("visibilitychange", () => {
    window.clearInterval(timer);
    if (document.visibilityState === "visible") {
      draw();
      timer = window.setInterval(draw, REFRESH_MS);
    }
  });

  // Re-centred on a resize, but never on a redraw: a tick that yanked the
  // track back would fight a visitor who had scrolled it themselves.
  window.addEventListener("resize", () => scrollToNow(host));
}

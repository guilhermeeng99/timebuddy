import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/time_grid/domain/entities/grid_view_model.dart';

/// Turns a board plus a reference date into the grid's whole view model.
///
/// Pure and synchronous, and deliberately takes `nowInstant` rather than a
/// `Clock`: every rule in docs/specs/time_grid.md is then pinnable by a unit
/// test at a real historical transition instead of by a widget test, which is
/// what makes covering all fourteen of them cheap.
///
/// The reference zone is the board's home zone (rule 1). It defines the
/// columns; every other row answers the *same* instant in its own zone.
///
/// ```dart
/// final model = BuildGridUseCase(engine: engine)(
///   board: board,
///   workingHours: preferences.workingHours,
///   referenceDate: referenceDate,
///   nowInstant: clock.nowUtc(),
///   localeTag: preferences.localeTag ?? 'en',
/// );
/// ```
class BuildGridUseCase {
  const BuildGridUseCase({required TimeZoneEngine engine}) : _engine = engine;

  /// Slots rendered on each side of the reference day (rule 3), so the user
  /// sees the tail of yesterday and the head of tomorrow without changing the
  /// date. They come from the neighbouring days, never from adding an hour to
  /// an edge, so a day that starts on its own transition still lines up.
  static const int flankSlots = 3;

  /// One column is one real hour. It is not one *local* hour: on a fall-back
  /// day two adjacent columns show the same wall clock, which is the point.
  static const Duration slotDuration = Duration(hours: 1);

  /// Safety stop for the per-row transition scan. A window of roughly thirty
  /// hours cannot legitimately hold more than one change, and a second is
  /// already generous; the bound is what keeps a pathological zone from
  /// spinning the loop.
  static const int _maxTransitionsPerWindow = 2;

  final TimeZoneEngine _engine;

  /// Builds the model for [referenceDate] in the home zone of [board].
  ///
  /// [workingHours] colours the cells through `hourBandFor` (rule 7),
  /// [nowInstant] and [cursorInstant] are carried through untouched for the
  /// markers, and [localeTag] formats the per-row date labels (rule 6).
  GridViewModel call({
    required BoardEntity board,
    required WorkingHours workingHours,
    required DateTime referenceDate,
    required DateTime nowInstant,
    DateTime? cursorInstant,
    String localeTag = 'en',
  }) {
    // zoneOrNull rather than the engine: the engine degrades an unknown zone
    // to UTC silently, and the banner exists to say that out loud.
    final home = zoneOrNull(board.homeZoneId);
    final referenceZoneId = home?.id ?? utcZoneId;
    final referenceDay = _engine.dayIn(
      zoneId: referenceZoneId,
      localDate: referenceDate,
    );
    final slots = _windowSlots(referenceZoneId, referenceDay);

    return GridViewModel(
      referenceDate: referenceDay.date,
      slots: slots,
      rows: _rowsFor(
        locations: board.locations,
        referenceZoneId: referenceZoneId,
        slots: slots,
        fallbackStateInstant: nowInstant,
        workingHours: workingHours,
        localeTag: localeTag,
      ),
      nowInstant: nowInstant,
      cursorInstant: cursorInstant,
      homeZoneUnresolved: home == null,
    );
  }

  /// The visible window: the reference day's own slots with [flankSlots] from
  /// the day before and after (rules 2 and 3).
  ///
  /// The count falls out of the engine, so a DST day yields 23 or 25 day
  /// slots and nothing here ever iterates `0..23`.
  List<DateTime> _windowSlots(String zoneId, ZoneDay referenceDay) {
    final before = _engine.dayIn(
      zoneId: zoneId,
      localDate: _dateShifted(referenceDay.date, -1),
    );
    final after = _engine.dayIn(
      zoneId: zoneId,
      localDate: _dateShifted(referenceDay.date, 1),
    );
    final tailStart = before.hourCount > flankSlots
        ? before.hourCount - flankSlots
        : 0;

    return List.unmodifiable([
      ...before.hours.skip(tailStart),
      ...referenceDay.hours,
      ...after.hours.take(flankSlots),
    ]);
  }

  List<GridRow> _rowsFor({
    required List<SavedLocationEntity> locations,
    required String referenceZoneId,
    required List<DateTime> slots,
    required DateTime fallbackStateInstant,
    required WorkingHours workingHours,
    required String localeTag,
  }) {
    // An offset belongs to an instant (engine rule 2), so the row badge has
    // to name one. The middle of the window is local midday in the reference
    // zone: resolving at local midnight would describe the two hours before a
    // 02:00 transition and mislabel the other twenty-two. The fallback covers
    // a reference date that has no slots at all, which is rare but real
    // (Pacific/Apia skipped 30 December 2011 outright).
    final stateInstant = slots.isEmpty
        ? fallbackStateInstant
        : slots[slots.length ~/ 2];

    return List.unmodifiable([
      for (final location in locations)
        _rowFor(
          location: location,
          referenceZoneId: referenceZoneId,
          slots: slots,
          stateInstant: stateInstant,
          workingHours: workingHours,
          localeTag: localeTag,
        ),
    ]);
  }

  GridRow _rowFor({
    required SavedLocationEntity location,
    required String referenceZoneId,
    required List<DateTime> slots,
    required DateTime stateInstant,
    required WorkingHours workingHours,
    required String localeTag,
  }) {
    final zone = zoneOrNull(location.zoneId);
    if (zone == null) return _unresolvedRow(location);

    return GridRow(
      location: location,
      isHome: zone.id == referenceZoneId,
      isUnresolved: false,
      zoneState: _engine.stateAt(zoneId: zone.id, instant: stateInstant),
      relativeToHome: _engine.relativeOffset(
        fromZoneId: referenceZoneId,
        toZoneId: zone.id,
        instant: stateInstant,
      ),
      cells: _cellsFor(
        zoneId: zone.id,
        slots: slots,
        workingHours: workingHours,
        localeTag: localeTag,
      ),
    );
  }

  /// Rule 14 and locations rule 11: the row keeps its board position and
  /// carries no cells, because dropping it on a tzdata upgrade would delete a
  /// location the user never asked to remove.
  GridRow _unresolvedRow(SavedLocationEntity location) => GridRow(
    location: location,
    isHome: false,
    isUnresolved: true,
    cells: const [],
  );

  List<GridCell> _cellsFor({
    required String zoneId,
    required List<DateTime> slots,
    required WorkingHours workingHours,
    required String localeTag,
  }) {
    final transitions = _transitionsWithin(zoneId, slots);
    final cells = <GridCell>[];
    DateTime? previousLocalTime;

    for (final slot in slots) {
      // Rule 4: every cell is derived from its own instant. Adding an hour to
      // the previous cell's local time would break on this row's transition,
      // which need not fall on the reference zone's.
      final localTime = _engine.wallTimeAt(zoneId: zoneId, instant: slot);
      final isDayStart = _startsNewDate(localTime, previousLocalTime);
      cells.add(
        GridCell(
          instant: slot,
          localTime: localTime,
          band: hourBandFor(localTime.hour, workingHours),
          isDayStart: isDayStart,
          dateLabel: isDayStart ? formatDayMonth(localTime, localeTag) : null,
          hasTransition: _slotHoldsTransition(transitions, slot),
        ),
      );
      previousLocalTime = localTime;
    }

    return List.unmodifiable(cells);
  }

  /// Rule 6: the boundary is where *this row's* local date changes, so rows
  /// near the date line mark it in different columns. The first cell of the
  /// window is never a boundary: there is no earlier cell to have changed
  /// from, and marking it would draw a rule down every row's column 0.
  bool _startsNewDate(DateTime localTime, DateTime? previousLocalTime) {
    if (previousLocalTime == null) return false;
    return localTime.day != previousLocalTime.day ||
        localTime.month != previousLocalTime.month ||
        localTime.year != previousLocalTime.year;
  }

  /// The instants at which this row's clocks move, inside the visible window.
  ///
  /// Gathered once per row rather than probed per cell: `nextTransition` is a
  /// binary search over tzdata, and asking it thirty times per row for an
  /// answer that changes at most once is work the grid does on every rebuild.
  List<DateTime> _transitionsWithin(String zoneId, List<DateTime> slots) {
    if (slots.isEmpty) return const [];
    final windowEnd = slots.last.add(slotDuration);
    final found = <DateTime>[];
    var cursor = slots.first;

    while (found.length < _maxTransitionsPerWindow) {
      final next = _engine.nextTransition(zoneId: zoneId, instant: cursor);
      if (next == null || !next.atUtc.isBefore(windowEnd)) break;
      found.add(next.atUtc);
      // The search is inclusive of its start, so step past the change found.
      cursor = next.atUtc.add(const Duration(milliseconds: 1));
    }

    return found;
  }

  /// Whether a change falls in `[slot, slot + 1h)`.
  ///
  /// The arithmetic is on the UTC instant, never on the cell's wall clock: an
  /// hour added to a local time is 0, 1 or 2 real hours on the very days this
  /// flag exists to mark (Time & Timezone rule 3).
  bool _slotHoldsTransition(List<DateTime> transitions, DateTime slot) {
    if (transitions.isEmpty) return false;
    final slotEnd = slot.add(slotDuration);
    return transitions.any(
      (at) => !at.isBefore(slot) && at.isBefore(slotEnd),
    );
  }

  /// [date] shifted by whole calendar days.
  ///
  /// The engine returns its dates as `DateTime.utc` field carriers, and UTC
  /// has no DST, so this is calendar arithmetic rather than the local-time
  /// arithmetic Time & Timezone rule 3 forbids. The result goes straight back
  /// to `dayIn`, which resolves that date's real midnight in the zone.
  DateTime _dateShifted(DateTime date, int days) =>
      DateTime.utc(date.year, date.month, date.day).add(Duration(days: days));
}

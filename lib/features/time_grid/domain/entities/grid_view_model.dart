import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// One cell of the grid: one shared instant, seen from one row's zone.
///
/// Produced by `BuildGridUseCase` and rendered verbatim. The widget layer
/// computes nothing from a cell (docs/specs/time_grid.md, presentation
/// contract): what time it is here, how reachable that hour is, whether the
/// date turns over and whether the clocks move are all already answered.
///
/// ```dart
/// final cell = row.cells[column];
/// Text(formatClock(cell.localTime, preferences.hourFormat));
/// ```
class GridCell extends Equatable {
  const GridCell({
    required this.instant,
    required this.localTime,
    required this.band,
    required this.isDayStart,
    required this.hasTransition,
    this.dateLabel,
  });

  /// The UTC instant this column stands for, shared by every row.
  ///
  /// Rule 1: a column is one instant, never one local hour. Two rows reading
  /// different clocks at the same [instant] is the entire screen.
  final DateTime instant;

  /// The wall clock a person in the row's zone reads at [instant].
  ///
  /// A field carrier, like everything `TimeZoneEngine.wallTimeAt` returns:
  /// read its fields, never its epoch value, never do arithmetic on it.
  final DateTime localTime;

  /// How reachable this hour is, from `hourBandFor` (rule 7). No widget
  /// decides an hour colour.
  final HourBand band;

  /// This cell begins a new local date **for its own row** (rule 6).
  final bool isDayStart;

  /// The new date's short label (`Tue 24`), present only when [isDayStart].
  final String? dateLabel;

  /// A DST change falls inside this slot, so the row is on one offset when
  /// the hour begins and another when it ends.
  final bool hasTransition;

  /// Whether this cell has to render `05:30` rather than `05` (rule 5).
  ///
  /// Derived from [localTime] rather than stored, and asked per cell rather
  /// than per row: India, Nepal and Chatham carry their minutes all day, but
  /// Australia/Lord_Howe grows them mid-row when its 30-minute DST starts.
  bool get hasOffsetMinutes => localTime.minute != 0;

  GridCell copyWith({
    DateTime? instant,
    DateTime? localTime,
    HourBand? band,
    bool? isDayStart,
    String? dateLabel,
    bool? hasTransition,
  }) {
    return GridCell(
      instant: instant ?? this.instant,
      localTime: localTime ?? this.localTime,
      band: band ?? this.band,
      isDayStart: isDayStart ?? this.isDayStart,
      dateLabel: dateLabel ?? this.dateLabel,
      hasTransition: hasTransition ?? this.hasTransition,
    );
  }

  @override
  List<Object?> get props => [
    instant,
    localTime,
    band,
    isDayStart,
    dateLabel,
    hasTransition,
  ];
}

/// One board row, resolved against the grid's shared column set.
///
/// [cells] is aligned index for index with [GridViewModel.slots], so column
/// `n` of every row is the same instant. The only row that breaks that shape
/// is an unresolved one, which carries no cells at all (rule 14).
class GridRow extends Equatable {
  const GridRow({
    required this.location,
    required this.isHome,
    required this.isUnresolved,
    required this.cells,
    this.zoneState,
    this.relativeToHome = Duration.zero,
  });

  final SavedLocationEntity location;

  /// The zone's abbreviation, offset and DST flag, resolved for one instant
  /// inside the visible window. `null` when [isUnresolved].
  ///
  /// A snapshot, never an identity (timezone_engine rule 2): it answers "what
  /// is true on the day being shown", so stepping the date changes it.
  final ZoneState? zoneState;

  /// This row's zone is the reference the columns were built from.
  final bool isHome;

  /// The saved zone id matches no entry in the shipped tzdata (rule 14). The
  /// row keeps its board position and renders greyed, because dropping it
  /// would delete a location the user never asked to remove.
  final bool isUnresolved;

  /// One cell per slot, in [GridViewModel.slots] order. Empty when, and only
  /// when, [isUnresolved].
  final List<GridCell> cells;

  /// `offset(this row) - offset(home)` at the instant [zoneState] describes:
  /// the `+4h` badge in the label column.
  ///
  /// Carried here because the home zone is not required to be a row of its
  /// own (locations rule 3), so a widget would have nothing to subtract from.
  /// Resolved pairwise for one instant, never as the difference of two stored
  /// offsets (timezone_engine rule 10). `Duration.zero` when [isUnresolved].
  final Duration relativeToHome;

  GridRow copyWith({
    SavedLocationEntity? location,
    ZoneState? zoneState,
    bool? isHome,
    bool? isUnresolved,
    List<GridCell>? cells,
    Duration? relativeToHome,
  }) {
    return GridRow(
      location: location ?? this.location,
      zoneState: zoneState ?? this.zoneState,
      isHome: isHome ?? this.isHome,
      isUnresolved: isUnresolved ?? this.isUnresolved,
      cells: cells ?? this.cells,
      relativeToHome: relativeToHome ?? this.relativeToHome,
    );
  }

  @override
  List<Object?> get props => [
    location,
    zoneState,
    isHome,
    isUnresolved,
    cells,
    relativeToHome,
  ];
}

/// Everything one paint of the grid needs, and nothing else.
///
/// Rebuilt only when the board, the preferences or the reference date change
/// (time_grid.md, performance): a tick replaces [nowInstant] through
/// [copyWith] and a cursor move replaces [cursorInstant], and neither touches
/// a cell.
///
/// ```dart
/// final model = BuildGridUseCase(engine: engine)(
///   board: board,
///   workingHours: preferences.workingHours,
///   referenceDate: referenceDate,
///   nowInstant: clock.nowUtc(),
/// );
/// ```
class GridViewModel extends Equatable {
  const GridViewModel({
    required this.referenceDate,
    required this.slots,
    required this.rows,
    required this.nowInstant,
    required this.homeZoneUnresolved,
    this.cursorInstant,
  });

  /// The local calendar date in the home zone whose day the columns cover.
  /// Date fields only; its epoch value means nothing.
  final DateTime referenceDate;

  /// The shared UTC instants, ascending, one per column.
  ///
  /// Its length is the reference day's real hour count plus the flanking
  /// slots, so 29, 30 or 31 (rules 2 and 3). Never assume 24.
  final List<DateTime> slots;

  /// One row per saved location, in board order, unresolved rows included.
  final List<GridRow> rows;

  /// The current instant, in UTC. Drives the "now" marker only.
  final DateTime nowInstant;

  /// The instant the cursor sits on, or `null` when there is no cursor.
  final DateTime? cursorInstant;

  /// The board's home zone resolves against no tzdata entry, so the columns
  /// fell back to UTC. The page banners that instead of going blank.
  final bool homeZoneUnresolved;

  /// Pass `clearCursor: true` to drop the cursor; passing
  /// `cursorInstant: null` cannot say that, being indistinguishable from
  /// "leave it alone".
  GridViewModel copyWith({
    DateTime? referenceDate,
    List<DateTime>? slots,
    List<GridRow>? rows,
    DateTime? nowInstant,
    DateTime? cursorInstant,
    bool? homeZoneUnresolved,
    bool clearCursor = false,
  }) {
    return GridViewModel(
      referenceDate: referenceDate ?? this.referenceDate,
      slots: slots ?? this.slots,
      rows: rows ?? this.rows,
      nowInstant: nowInstant ?? this.nowInstant,
      cursorInstant: clearCursor ? null : cursorInstant ?? this.cursorInstant,
      homeZoneUnresolved: homeZoneUnresolved ?? this.homeZoneUnresolved,
    );
  }

  @override
  List<Object?> get props => [
    referenceDate,
    slots,
    rows,
    nowInstant,
    cursorInstant,
    homeZoneUnresolved,
  ];
}

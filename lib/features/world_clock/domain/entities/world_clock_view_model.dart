import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// One live clock: a saved place, and everything that is true of it at one
/// instant.
///
/// Produced by `BuildWorldClockUseCase` and rendered verbatim. The widget
/// layer computes nothing from a tile (docs/specs/world_clock.md, Presentation
/// Contract): what time it is there, how far it is from home, whether it is on
/// another calendar day, how reachable the hour is and whether the clocks are
/// currently shifted are all already answered.
///
/// Every field is an answer about [WorldClockViewModel.nowInstant] and nothing
/// else. None of them may be cached across instants: an offset is a function
/// of `(zone, instant)` (CLAUDE.md, Time & Timezone rule 2), and a band
/// outlives the working window that produced it.
///
/// ```dart
/// Text(formatDayMonth(tile.localTime, localeTag));
/// OffsetBadge(relativeToHome: tile.offsetFromHome);
/// ```
class WorldClockTile extends Equatable {
  const WorldClockTile({
    required this.location,
    required this.localTime,
    required this.offsetFromUtc,
    required this.offsetFromHome,
    required this.dayDelta,
    required this.band,
    required this.isDst,
    required this.abbreviation,
    required this.isHome,
    required this.isUnresolved,
  });

  /// The board row this clock stands for.
  ///
  /// The home hero of a board whose home zone has no row of its own carries a
  /// stand-in row instead; `WorldClockViewModel.homeHasBoardRow` is the flag
  /// that says so, never this object's shape.
  final SavedLocationEntity location;

  /// The wall clock a person in [location]'s zone reads at `nowInstant`.
  ///
  /// A field carrier, like everything `TimeZoneEngine.wallTimeAt` returns:
  /// read its fields, never its epoch value, never do arithmetic on it.
  final DateTime localTime;

  /// Distance from UTC at that instant, e.g. `+05:45`. Rendered by
  /// `OffsetBadge` / `offsetLabel`, which handle the non-whole-hour zones a
  /// hand-rolled `'${d.inHours}h'` silently truncates.
  final Duration offsetFromUtc;

  /// Distance from the board's home zone at that instant (rule 5).
  ///
  /// Resolved pairwise through `TimeZoneEngine.relativeOffset`, never as the
  /// difference of two stored offsets: London is 4 hours from New York for two
  /// weeks each spring and 5 hours the rest of the year. May be negative and
  /// may carry minutes. [Duration.zero] is a real answer and renders
  /// "same time".
  final Duration offsetFromHome;

  /// This clock's local calendar date minus the home zone's, in whole days
  /// (rule 6).
  ///
  /// `+1` renders "Tomorrow" and `-1` "Yesterday", which is the single most
  /// confusing fact on a board that crosses the date line and must not require
  /// arithmetic from the user.
  ///
  /// Usually `-1`, `0` or `+1`, but **not clamped to them**: Pacific/Kiritimati
  /// (`+14:00`) and Pacific/Niue (`-11:00`) are 25 hours apart and really do
  /// land two calendar days apart for one hour a day. The widget names only
  /// `±1` and shows the bare date otherwise, which is honest; clamping would
  /// print "Yesterday" for a day before yesterday.
  final int dayDelta;

  /// How reachable this hour is, from `hourBandFor` (rule 7). No widget
  /// decides an hour colour.
  final HourBand band;

  /// The zone is shifted off its normal time at that instant (rule 8).
  final bool isDst;

  /// The short name in force at that instant: `IST`, `CEST`, `-03`.
  final String abbreviation;

  /// This clock's zone is the board's reference zone. True of the hero, and
  /// also of the list tile for it when home has a row of its own.
  final bool isHome;

  /// The stored zone id resolves against no entry in the shipped tzdata
  /// (locations.md rule 11), so the clock below is UTC standing in for it.
  ///
  /// The tile keeps its board position and renders greyed rather than being
  /// dropped: deleting a user's city because a tzdata upgrade retired its id
  /// would be deleting their data without consent.
  final bool isUnresolved;

  WorldClockTile copyWith({
    SavedLocationEntity? location,
    DateTime? localTime,
    Duration? offsetFromUtc,
    Duration? offsetFromHome,
    int? dayDelta,
    HourBand? band,
    bool? isDst,
    String? abbreviation,
    bool? isHome,
    bool? isUnresolved,
  }) {
    return WorldClockTile(
      location: location ?? this.location,
      localTime: localTime ?? this.localTime,
      offsetFromUtc: offsetFromUtc ?? this.offsetFromUtc,
      offsetFromHome: offsetFromHome ?? this.offsetFromHome,
      dayDelta: dayDelta ?? this.dayDelta,
      band: band ?? this.band,
      isDst: isDst ?? this.isDst,
      abbreviation: abbreviation ?? this.abbreviation,
      isHome: isHome ?? this.isHome,
      isUnresolved: isUnresolved ?? this.isUnresolved,
    );
  }

  @override
  List<Object?> get props => [
    location,
    localTime,
    offsetFromUtc,
    offsetFromHome,
    dayDelta,
    band,
    isDst,
    abbreviation,
    isHome,
    isUnresolved,
  ];
}

/// Everything one paint of the world clock needs, and nothing else.
///
/// There is deliberately no "empty" shape: a board with no saved cities is a
/// valid model with an empty [tiles] list and a present [home] (rule 11). The
/// hero is never blank, because the home zone always resolves — to UTC in the
/// worst case, which [homeZoneUnresolved] says out loud.
///
/// ```dart
/// final model = BuildWorldClockUseCase(engine: engine)(
///   board: board,
///   workingHours: preferences.workingHours,
///   nowInstant: clock.nowUtc(),
///   homeFallbackLabel: t.locations.homeLabel,
/// );
/// ```
class WorldClockViewModel extends Equatable {
  const WorldClockViewModel({
    required this.nowInstant,
    required this.home,
    required this.tiles,
    required this.homeHasBoardRow,
    required this.homeZoneUnresolved,
  });

  /// The instant every tile answers for, in UTC.
  final DateTime nowInstant;

  /// The hero clock at the top of the page (rule 1).
  ///
  /// Its [WorldClockTile.isHome] is always true and its
  /// [WorldClockTile.dayDelta] always zero: it is what every other tile is
  /// measured against.
  final WorldClockTile home;

  /// One tile per saved location, in board order (rule 2), unresolved rows
  /// included. Empty is a valid value.
  final List<WorldClockTile> tiles;

  /// The home zone has a row on the board, so [home] carries that row.
  ///
  /// `false` means the hero is standing in for a zone the user never saved —
  /// home is a zone id, not a row (locations.md rule 3) — and the detail sheet
  /// hides "remove", because there is nothing to remove.
  final bool homeHasBoardRow;

  /// The board's home zone resolves against no tzdata entry, so every clock on
  /// the page is measured from UTC. The page banners that rather than quietly
  /// pretending the user lives on the meridian.
  final bool homeZoneUnresolved;

  WorldClockViewModel copyWith({
    DateTime? nowInstant,
    WorldClockTile? home,
    List<WorldClockTile>? tiles,
    bool? homeHasBoardRow,
    bool? homeZoneUnresolved,
  }) {
    return WorldClockViewModel(
      nowInstant: nowInstant ?? this.nowInstant,
      home: home ?? this.home,
      tiles: tiles ?? this.tiles,
      homeHasBoardRow: homeHasBoardRow ?? this.homeHasBoardRow,
      homeZoneUnresolved: homeZoneUnresolved ?? this.homeZoneUnresolved,
    );
  }

  @override
  List<Object?> get props => [
    nowInstant,
    home,
    tiles,
    homeHasBoardRow,
    homeZoneUnresolved,
  ];
}

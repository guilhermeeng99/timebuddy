import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/world_clock/domain/entities/world_clock_view_model.dart';

/// Turns a board plus one instant into the world clock's whole view model.
///
/// Pure and synchronous, and deliberately takes `nowInstant` rather than a
/// `Clock`: every rule in docs/specs/world_clock.md is then pinnable by a unit
/// test at a real transition or a real date-line crossing, which is what makes
/// covering all of them cheap.
///
/// Only `nowInstant` changes between two consecutive runs, so re-running it is
/// three engine lookups per row on a board capped at 20 rows (locations rule
/// 4). `WorldClockCubit` still filters ticks down to one a minute, because
/// nothing this produces changes inside one.
///
/// ```dart
/// final model = BuildWorldClockUseCase(engine: engine)(
///   board: board,
///   workingHours: preferences.workingHours,
///   nowInstant: clock.nowUtc(),
///   homeFallbackLabel: t.locations.homeLabel,
/// );
/// ```
class BuildWorldClockUseCase {
  const BuildWorldClockUseCase({required TimeZoneEngine engine})
    : _engine = engine;

  /// The row id carried by the hero when the home zone has no board row.
  ///
  /// Empty rather than a generated uuid: the hero is not something the user
  /// saved, and an invented id would read as a board row that went missing.
  /// Callers ask `WorldClockViewModel.homeHasBoardRow`, never this value.
  static const String homeWithoutRowId = '';

  /// The [SavedLocationEntity.sortIndex] of that same stand-in row. Negative
  /// because it sits off the board, not at the head of it.
  static const int homeWithoutRowSortIndex = -1;

  final TimeZoneEngine _engine;

  /// Builds the model for [nowInstant].
  ///
  /// [workingHours] colours every tile through `hourBandFor` (rule 7).
  /// [homeFallbackLabel] names the hero on a board whose home zone has no row
  /// of its own; it arrives localized, because the domain has no catalog to
  /// look a city up in and `America/Sao_Paulo` is an identifier rather than a
  /// label (CLAUDE.md, UI & Formatting).
  WorldClockViewModel call({
    required BoardEntity board,
    required WorkingHours workingHours,
    required DateTime nowInstant,
    required String homeFallbackLabel,
  }) {
    // zoneOrNull rather than the engine: the engine degrades an unknown zone
    // to UTC silently, and the banner exists to say that out loud.
    final home = zoneOrNull(board.homeZoneId);
    final homeZoneId = home?.id ?? utcZoneId;
    final homeLocalDate = _localDateIn(homeZoneId, nowInstant);
    // Asked with the stored id rather than the resolved one: the lookup
    // canonicalises both sides anyway, so `Brazil/East` still finds the
    // `America/Sao_Paulo` row, and a home zone the tzdata dropped matches the
    // row that carries the same dropped id instead of any UTC row.
    final homeRow = board.locationForZone(board.homeZoneId);

    return WorldClockViewModel(
      nowInstant: nowInstant,
      home: _tileFor(
        location:
            homeRow ??
            _standInHomeRow(
              // The id the board actually stores, not the resolved one: a
              // home zone the tzdata dropped then takes the same unresolved
              // path as any other row, so the hero is marked rather than
              // quietly presenting UTC as the user's own city.
              zoneId: board.homeZoneId,
              label: homeFallbackLabel,
              nowInstant: nowInstant,
            ),
        homeZoneId: homeZoneId,
        homeLocalDate: homeLocalDate,
        nowInstant: nowInstant,
        workingHours: workingHours,
      ),
      tiles: List.unmodifiable([
        for (final location in board.locations)
          _tileFor(
            location: location,
            homeZoneId: homeZoneId,
            homeLocalDate: homeLocalDate,
            nowInstant: nowInstant,
            workingHours: workingHours,
          ),
      ]),
      homeHasBoardRow: homeRow != null,
      homeZoneUnresolved: home == null,
    );
  }

  WorldClockTile _tileFor({
    required SavedLocationEntity location,
    required String homeZoneId,
    required DateTime homeLocalDate,
    required DateTime nowInstant,
    required WorkingHours workingHours,
  }) {
    final zone = zoneOrNull(location.zoneId);
    // The same fallback the engine would apply, made explicit so the tile can
    // be greyed instead of quietly presenting UTC as the user's city.
    final zoneId = zone?.id ?? utcZoneId;
    final zoneState = _engine.stateAt(zoneId: zoneId, instant: nowInstant);
    final localTime = _engine.wallTimeAt(zoneId: zoneId, instant: nowInstant);

    return WorldClockTile(
      location: location,
      localTime: localTime,
      offsetFromUtc: zoneState.offset,
      // Rule 5: resolved pairwise for this instant, never as the difference of
      // two stored offsets.
      offsetFromHome: _engine.relativeOffset(
        fromZoneId: homeZoneId,
        toZoneId: zoneId,
        instant: nowInstant,
      ),
      dayDelta: _dayDeltaFrom(homeLocalDate, localTime),
      band: hourBandFor(localTime.hour, workingHours),
      isDst: zoneState.isDst,
      abbreviation: zoneState.abbreviation,
      isHome: zoneId == homeZoneId,
      isUnresolved: zone == null,
    );
  }

  /// The row the hero borrows when the home zone is not on the board.
  ///
  /// Home is a zone id and not a row (locations.md rule 3), so this is the
  /// ordinary case for a user who has never added their own city — and rule 11
  /// says their clock still leads the page.
  SavedLocationEntity _standInHomeRow({
    required String zoneId,
    required String label,
    required DateTime nowInstant,
  }) {
    return SavedLocationEntity(
      id: homeWithoutRowId,
      zoneId: zoneId,
      label: label,
      // No catalog entry backs this row, so there is no country to claim.
      countryCode: '',
      sortIndex: homeWithoutRowSortIndex,
      addedAt: nowInstant,
    );
  }

  /// Whole calendar days between the home zone's date and [localTime]'s.
  ///
  /// Both sides are UTC-flagged midnight field carriers, so the subtraction is
  /// exact calendar arithmetic and never the 23-or-25-hour local kind
  /// CLAUDE.md rule 3 forbids.
  int _dayDeltaFrom(DateTime homeLocalDate, DateTime localTime) => DateTime.utc(
    localTime.year,
    localTime.month,
    localTime.day,
  ).difference(homeLocalDate).inDays;

  /// [instant] as a calendar date in [zoneId], date fields only.
  DateTime _localDateIn(String zoneId, DateTime instant) {
    final wall = _engine.wallTimeAt(zoneId: zoneId, instant: instant);
    return DateTime.utc(wall.year, wall.month, wall.day);
  }
}

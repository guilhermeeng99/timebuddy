import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/location_search_state.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/locations/presentation/cubit/location_search_state.dart';

/// Search state of the add-location sheet, and nothing else.
///
/// Page-scoped: created by the sheet, disposed with it (CLAUDE.md, Lifecycle).
/// It reads the catalog and never touches the board — a selection is written
/// through `BoardCubit`, which is the single source of truth for what the user
/// is watching (docs/specs/locations.md).
///
/// ```dart
/// final cubit = LocationSearchCubit(repository: sl<CityCatalogRepository>());
/// TimeBuddySearchField(onChanged: cubit.search);
/// ```
class LocationSearchCubit extends Cubit<LocationSearchState> {
  LocationSearchCubit({
    required CityCatalogRepository repository,
    Duration debounce = defaultDebounce,
  }) : _repository = repository,
       _debounce = debounce,
       super(const LocationSearchInitial());

  /// How long the cubit waits for the typing to settle before it searches.
  ///
  /// 200 ms (docs/specs/locations.md, State Machine): long enough that a
  /// touch-typist's "sao paulo" is one search instead of nine, short enough
  /// that a deliberate typist never notices the wait. Injectable so a test
  /// can pass [Duration.zero] instead of sleeping.
  static const Duration defaultDebounce = Duration(milliseconds: 200);

  final CityCatalogRepository _repository;
  final Duration _debounce;

  Timer? _debounceTimer;

  /// Guards against an older read winning the race.
  ///
  /// "sao" and "sao p" can be in flight together, and the catalog is a memory
  /// list whose completion order is not guaranteed to be its start order. Each
  /// read carries the generation it started in and drops its result if a newer
  /// one has begun since.
  int _generation = 0;

  /// The curated default list, computed once per sheet.
  ///
  /// The repository caches the parsed catalog, but not this grouping of it.
  /// Empty means "not computed yet"; a catalog that genuinely yields nothing
  /// is a broken catalog, and recomputing an empty answer costs a map walk
  /// over a list that is already in memory.
  List<CityEntity> _defaultCities = const [];

  /// Loads the list the sheet shows before anything is typed.
  ///
  /// Not debounced: the sheet calls it as it opens, and there is nothing to
  /// wait for.
  Future<void> loadDefaults() => _resolve('');

  /// Handles one keystroke. Debounced by [defaultDebounce].
  ///
  /// An empty or whitespace-only query resolves to the same curated default
  /// list as [loadDefaults], so clearing the field restores a useful sheet
  /// rather than an empty one.
  void search(String query) {
    final trimmed = query.trim();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(_resolve(trimmed)));
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    // Cleared as well as cancelled: nothing may be scheduled after a close,
    // so the handle should not outlive the timer it points at.
    _debounceTimer = null;
    return super.close();
  }

  Future<void> _resolve(String query) async {
    if (isClosed) return;
    final generation = ++_generation;
    emit(const LocationSearchLoading());
    final result = query.isEmpty
        ? await _curatedDefaults()
        : await _repository.search(query);
    // The sheet may have closed, or a newer keystroke may have overtaken this
    // read, while the future was pending.
    if (isClosed || generation != _generation) return;
    emit(
      result.fold(
        (failure) => LocationSearchError(failure: failure),
        (cities) => cities.isEmpty
            ? LocationSearchEmpty(query: query)
            : LocationSearchResults(query: query, cities: cities),
      ),
    );
  }

  Future<Either<Failure, List<CityEntity>>> _curatedDefaults() async {
    if (_defaultCities.isNotEmpty) return Right(_defaultCities);
    final result = await _repository.load();
    // The type argument is written out rather than inferred: the two branches
    // return different `Either` subtypes, and letting inference pick the join
    // is how a `Left`/`Right` pair silently widens to `Object`.
    return result.fold<Either<Failure, List<CityEntity>>>(
      Left<Failure, List<CityEntity>>.new,
      _rememberDefaults,
    );
  }

  Either<Failure, List<CityEntity>> _rememberDefaults(
    List<CityEntity> catalog,
  ) {
    final defaults = _largestCityPerRegion(catalog);
    _defaultCities = defaults;
    return Right(defaults);
  }
}

/// The most prominent city of each IANA region, most prominent first.
///
/// The spec asks for "the largest city per continent" and no catalog field
/// carries a continent — but the first segment of an IANA id already is one
/// (`America/Sao_Paulo`, `Europe/Oslo`, `Pacific/Auckland`). Deriving the
/// grouping from the id keeps the default list correct for free when the
/// catalog is regenerated, and avoids a hand-maintained continent table that
/// would be a second place to be wrong about where a city is.
List<CityEntity> _largestCityPerRegion(List<CityEntity> catalog) {
  final bestPerRegion = <String, CityEntity>{};
  for (final city in catalog) {
    final region = _regionOf(city.zoneId);
    final incumbent = bestPerRegion[region];
    if (incumbent == null || _rankedBefore(city, incumbent)) {
      bestPerRegion[region] = city;
    }
  }
  return List.unmodifiable(
    bestPerRegion.values.toList()..sort(_byProminenceThenName),
  );
}

String _regionOf(String zoneId) {
  final separator = zoneId.indexOf('/');
  // Region-less ids (`UTC`) are their own group rather than being dropped: a
  // catalog that ships one should still be able to offer it.
  return separator < 0 ? zoneId : zoneId.substring(0, separator);
}

bool _rankedBefore(CityEntity candidate, CityEntity incumbent) =>
    _byProminenceThenName(candidate, incumbent) < 0;

/// Descending prominence, then name, so the list is stable across runs even
/// where the catalog holds several entries with the derived prominence of 0.
int _byProminenceThenName(CityEntity a, CityEntity b) {
  final byProminence = b.prominence.compareTo(a.prominence);
  if (byProminence != 0) return byProminence;
  return a.name.compareTo(b.name);
}

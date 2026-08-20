import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';

/// State of `LocationSearchCubit`, the add-location sheet's view state.
///
/// It holds no board data whatsoever. Everything the user *selects* here is
/// written through `BoardCubit`; this cubit only answers "which cities match
/// what is currently typed" (docs/specs/locations.md, State Machine).
sealed class LocationSearchState extends Equatable {
  const LocationSearchState();

  @override
  List<Object?> get props => const [];
}

/// Before the sheet has asked for anything. Rendered as a loading body, so no
/// screen ever has to distinguish it from [LocationSearchLoading].
final class LocationSearchInitial extends LocationSearchState {
  const LocationSearchInitial();
}

/// A catalog read is in flight, either the default list or a query.
final class LocationSearchLoading extends LocationSearchState {
  const LocationSearchLoading();
}

/// Ranked hits for [query].
///
/// [query] is empty for the curated default list the sheet shows before the
/// user types anything, which is why the sheet reads the query from the state
/// rather than from its own controller: the two are only equal between
/// debounces.
final class LocationSearchResults extends LocationSearchState {
  const LocationSearchResults({required this.query, required this.cities});

  final String query;
  final List<CityEntity> cities;

  @override
  List<Object?> get props => [query, cities];
}

/// The catalog holds nothing for [query]. Distinct from an empty
/// [LocationSearchResults] so the sheet can name the query in its copy.
final class LocationSearchEmpty extends LocationSearchState {
  const LocationSearchEmpty({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// The catalog itself could not be read.
///
/// Beyond the four states docs/specs/locations.md lists, and deliberately so:
/// the same spec's "catalog asset missing or corrupt" edge case requires the
/// add-location sheet, and only the sheet, to show the error. Folding it into
/// [LocationSearchEmpty] would tell a user that their query matched nothing
/// when in fact nothing was searched, and the suggested fix ("try a time zone
/// id") would never work.
final class LocationSearchError extends LocationSearchState {
  const LocationSearchError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

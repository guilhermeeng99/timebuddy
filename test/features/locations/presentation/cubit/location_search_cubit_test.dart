import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/utils/string_normalize.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/location_search_cubit.dart';

/// The catalog boundary under the cubit.
///
/// Private to this file: the harness mocks the boundaries milestone 1 owns,
/// and a second declaration of the same name imported alongside it would not
/// compile.
class _MockCityCatalogRepository extends Mock
    implements CityCatalogRepository {}

/// Tokyo, the most prominent entry in the fixture and the only Asian one.
const CityEntity _tokyo = CityEntity(
  zoneId: 'Asia/Tokyo',
  name: 'Tokyo',
  countryCode: 'JP',
  countryName: 'Japan',
  prominence: 99,
);

/// Carries an alias, so an alias-only query can be told from a name query.
const CityEntity _newYork = CityEntity(
  zoneId: 'America/New_York',
  name: 'New York',
  countryCode: 'US',
  countryName: 'United States',
  prominence: 95,
  admin1: 'New York',
  aliases: ['NYC'],
);

/// The accented-spelling case: the catalog holds the plain form, and a query
/// typed with the tilde has to fold onto it.
const CityEntity _saoPaulo = CityEntity(
  zoneId: 'America/Sao_Paulo',
  name: 'Sao Paulo',
  countryCode: 'BR',
  countryName: 'Brazil',
  prominence: 90,
  admin1: 'Sao Paulo',
);

const CityEntity _paris = CityEntity(
  zoneId: 'Europe/Paris',
  name: 'Paris',
  countryCode: 'FR',
  countryName: 'France',
  prominence: 88,
);

/// The second European entry, and the less prominent one: it exists so
/// "one city per region" can fail by picking the wrong city, not only by
/// picking the wrong count.
const CityEntity _lisbon = CityEntity(
  zoneId: 'Europe/Lisbon',
  name: 'Lisbon',
  countryCode: 'PT',
  countryName: 'Portugal',
  prominence: 40,
);

const CityEntity _auckland = CityEntity(
  zoneId: 'Pacific/Auckland',
  name: 'Auckland',
  countryCode: 'NZ',
  countryName: 'New Zealand',
  prominence: 30,
);

/// The region-less id. `UTC` has no `/` in it, so it is its own group, and a
/// grouping that split on the separator without guarding would drop it.
/// `ZZ` is the ISO 3166 user-assigned code the catalog gives a non-country.
const CityEntity _utc = CityEntity(
  zoneId: 'UTC',
  name: 'UTC',
  countryCode: 'ZZ',
  countryName: 'Coordinated Universal Time',
  prominence: 0,
);

/// The catalog every test in this file searches.
///
/// Five IANA regions, one of them holding two cities, plus one region-less
/// id. Deliberately not in prominence order: a default list that came back
/// sorted by accident would pass over a catalog that was already sorted.
const List<CityEntity> _catalog = [
  _paris,
  _auckland,
  _tokyo,
  _lisbon,
  _newYork,
  _utc,
  _saoPaulo,
];

/// The list the sheet must show before anything is typed: the most prominent
/// city of each region, most prominent first.
const List<CityEntity> _expectedDefaults = [
  _tokyo,
  _newYork,
  _paris,
  _auckland,
  _utc,
];

/// A stand-in for the repository's ranked search.
///
/// A substring match over the same folded key the real index uses, and
/// nothing more: ranking, the `limit` and the raw-zone-id rule are the
/// repository's contract and are pinned by its own test. All these tests need
/// from a search is that the typed text reached it verbatim and that whatever
/// came back is what the state carries.
List<CityEntity> _matchesFor(String query) {
  final needle = normalizeForSearch(query);
  return _catalog
      .where((city) => _searchKeysOf(city).any((key) => key.contains(needle)))
      .toList();
}

Iterable<String> _searchKeysOf(CityEntity city) sync* {
  yield normalizeForSearch(city.name);
  yield normalizeForSearch(city.countryName);
  yield normalizeForSearch(city.zoneId);
  yield* city.aliases.map(normalizeForSearch);
}

void main() {
  late _MockCityCatalogRepository repository;

  /// Reads this test wants to hold open, by query.
  ///
  /// The default stub answers in a microtask, which is exactly what makes a
  /// race invisible; a completer per query is how one read is made to finish
  /// after a later one.
  late Map<String, Completer<Either<Failure, List<CityEntity>>>> stalled;

  setUp(() {
    repository = _MockCityCatalogRepository();
    stalled = {};
    when(repository.load).thenAnswer(
      (_) async => const Right<Failure, List<CityEntity>>(_catalog),
    );
    when(() => repository.search(any())).thenAnswer((invocation) {
      final query = invocation.positionalArguments.first as String;
      return stalled[query]?.future ??
          Future<Either<Failure, List<CityEntity>>>.value(
            Right(_matchesFor(query)),
          );
    });
  });

  LocationSearchCubit buildCubit() =>
      LocationSearchCubit(repository: repository);

  /// Draws one frame, so `tester.pump(duration)` has a tree to pump.
  ///
  /// These are cubit tests hosted in a `testWidgets` body on purpose: the
  /// tester's clock is fake, so the 200 ms debounce elapses instantly and
  /// deterministically. A `Future.delayed` in a plain `test` would be a real
  /// 200 ms of wall time per case, and a flaky one on a loaded machine.
  Future<void> mountFakeClock(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// Fires whatever the debounce scheduled, then lets the read it started
  /// resolve.
  Future<void> settleDebounce(WidgetTester tester) async {
    await tester.pump(LocationSearchCubit.defaultDebounce);
    await tester.pump();
  }

  testWidgets('collapses a burst of keystrokes into a single catalog read', (
    tester,
  ) async {
    await mountFakeClock(tester);
    final cubit = buildCubit();
    addTearDown(cubit.close);

    // Three keystrokes, each landing inside the window the one before it
    // opened: 240 ms of typing, and the catalog has not been touched.
    cubit.search('s');
    await tester.pump(const Duration(milliseconds: 120));
    cubit.search('sa');
    await tester.pump(const Duration(milliseconds: 120));
    cubit.search('sao');
    verifyNever(() => repository.search(any()));

    await settleDebounce(tester);

    verify(() => repository.search('sao')).called(1);
    expect(
      cubit.state,
      const LocationSearchResults(query: 'sao', cities: [_saoPaulo]),
    );
  });

  test(
    'answers an empty query with the curated default list, not an empty state',
    () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      final observed = expectLater(
        cubit.stream,
        emitsInOrder(<LocationSearchState>[
          const LocationSearchLoading(),
          const LocationSearchResults(query: '', cities: _expectedDefaults),
        ]),
      );

      await cubit.loadDefaults();
      await observed;

      // The default list is derived from the whole catalog, so an empty
      // query must never reach the ranked search.
      verifyNever(() => repository.search(any()));
    },
  );

  testWidgets('clearing the field restores the default list', (tester) async {
    await mountFakeClock(tester);
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await cubit.loadDefaults();

    cubit.search('tokyo');
    await settleDebounce(tester);
    expect(
      cubit.state,
      const LocationSearchResults(query: 'tokyo', cities: [_tokyo]),
    );

    // Whitespace only: the field reads as empty to the user, so it has to
    // behave as empty.
    cubit.search('   ');
    await settleDebounce(tester);

    expect(
      cubit.state,
      const LocationSearchResults(query: '', cities: _expectedDefaults),
    );
    verifyNever(() => repository.search(''));
    // The grouping is cached, so restoring it costs no second catalog read.
    verify(repository.load).called(1);
  });

  testWidgets('drops a slow read that a newer one has overtaken', (
    tester,
  ) async {
    await mountFakeClock(tester);
    final cubit = buildCubit();
    addTearDown(cubit.close);
    final slowSaoPaulo = Completer<Either<Failure, List<CityEntity>>>();
    stalled['sao'] = slowSaoPaulo;

    cubit.search('sao');
    await settleDebounce(tester);
    cubit.search('tokyo');
    await settleDebounce(tester);
    expect(
      cubit.state,
      const LocationSearchResults(query: 'tokyo', cities: [_tokyo]),
    );

    // The catalog is a list in memory, so nothing orders two reads of it. The
    // stale answer has to be dropped rather than painted over the fresh one.
    slowSaoPaulo.complete(
      const Right<Failure, List<CityEntity>>([_saoPaulo]),
    );
    await tester.pump();

    expect(
      cubit.state,
      const LocationSearchResults(query: 'tokyo', cities: [_tokyo]),
    );
  });

  testWidgets('keeps the query on a search that matched nothing', (
    tester,
  ) async {
    await mountFakeClock(tester);
    final cubit = buildCubit();
    addTearDown(cubit.close);

    cubit.search('atlantis');
    await settleDebounce(tester);

    expect(cubit.state, const LocationSearchEmpty(query: 'atlantis'));
  });

  test('reports a broken catalog as an error, not as no results', () async {
    when(repository.load).thenAnswer(
      (_) async => const Left<Failure, List<CityEntity>>(ServerFailure()),
    );
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.loadDefaults();

    // The no-hits copy tells the user to try a zone id, which would never
    // work when nothing was searched at all.
    expect(cubit.state, const LocationSearchError(failure: ServerFailure()));
  });

  testWidgets('a debounce still pending at close never reaches the catalog', (
    tester,
  ) async {
    await mountFakeClock(tester);
    // The search is folded into the declaration so the close below is the
    // only statement on the cubit, which is what the debounce test is about.
    final cubit = buildCubit()..search('sao');

    await cubit.close();
    await settleDebounce(tester);

    // The sheet can be dismissed mid-keystroke, and a read landing after that
    // would emit on a closed cubit.
    verifyNever(() => repository.search(any()));
  });
}

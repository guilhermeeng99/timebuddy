import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/utils/string_normalize.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/locations/presentation/cubit/location_search_cubit.dart';
import 'package:timebuddy/features/locations/presentation/pages/add_location_sheet.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

/// The board boundary the sheet writes through.
class _MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

/// The catalog boundary the sheet reads through.
class _MockCityCatalogRepository extends Mock
    implements CityCatalogRepository {}

/// Room for the sheet at full height plus the rows inside it.
const Size _tallSurface = Size(900, 1600);

/// Label of the host page's button, which stands in for the FAB.
const String _openSheetLabel = 'open-picker';

const CityEntity _tokyo = CityEntity(
  zoneId: 'Asia/Tokyo',
  name: 'Tokyo',
  countryCode: 'JP',
  countryName: 'Japan',
  prominence: 99,
);

/// The most prominent American entry, so it is in the default list and can be
/// selected without typing.
const CityEntity _saoPaulo = CityEntity(
  zoneId: 'America/Sao_Paulo',
  name: 'Sao Paulo',
  countryCode: 'BR',
  countryName: 'Brazil',
  prominence: 95,
  admin1: 'Sao Paulo',
);

/// Reachable only through its alias, so an alias hit cannot be a name hit in
/// disguise.
const CityEntity _newYork = CityEntity(
  zoneId: 'America/New_York',
  name: 'New York',
  countryCode: 'US',
  countryName: 'United States',
  prominence: 90,
  admin1: 'New York',
  aliases: ['NYC'],
);

const CityEntity _paris = CityEntity(
  zoneId: 'Europe/Paris',
  name: 'Paris',
  countryCode: 'FR',
  countryName: 'France',
  prominence: 88,
);

const CityEntity _auckland = CityEntity(
  zoneId: 'Pacific/Auckland',
  name: 'Auckland',
  countryCode: 'NZ',
  countryName: 'New Zealand',
  prominence: 30,
);

const List<CityEntity> _catalog = [
  _paris,
  _tokyo,
  _newYork,
  _auckland,
  _saoPaulo,
];

/// A stand-in for the repository's ranked search.
///
/// It folds both sides through [normalizeForSearch], which is the same key the
/// real index is built on, and stops there: ranking, the `limit` and the
/// raw-zone-id rule belong to the repository's own test. What these tests need
/// is that the typed text arrives unfolded and that a hit reaches the sheet.
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

/// The row a "replace zone" repair is opened for.
final SavedLocationEntity _brokenRow = SavedLocationEntity(
  id: 'row-enderbury',
  zoneId: 'Pacific/Enderbury',
  label: 'Enderbury',
  countryCode: 'KI',
  sortIndex: 1,
  addedAt: utcDate(2024, 1, 15, 12),
);

/// A page that owns a `BoardCubit` and opens the picker over itself.
///
/// `showAddLocationSheet` captures the cubit from its caller's context, so the
/// sheet has to be opened from a host that provides one — which is also how
/// the locations page and the grid open it.
class _HostPage extends StatelessWidget {
  const _HostPage({required this.cubit, this.replaces});

  final BoardCubit cubit;
  final SavedLocationEntity? replaces;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BoardCubit>.value(
      value: cubit,
      child: Scaffold(
        body: Builder(
          builder: (innerContext) => Center(
            child: ElevatedButton(
              onPressed: () => unawaited(
                showAddLocationSheet(innerContext, replaces: replaces),
              ),
              child: const Text(_openSheetLabel),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() {
    initTestTimeZones();
    registerCommonFallbacks();
    registerFallbackValue(_tokyo);
  });

  late _MockBoardCubit cubit;
  late _MockCityCatalogRepository repository;

  setUp(() {
    cubit = _MockBoardCubit();
    repository = _MockCityCatalogRepository();
    // No board state is stubbed on purpose: the sheet reads the cubit to
    // write through it and never builds against its state, so a test that
    // fed it one would be asserting on plumbing the sheet does not use.
    when(repository.load).thenAnswer(
      (_) async => const Right<Failure, List<CityEntity>>(_catalog),
    );
    when(() => repository.search(any())).thenAnswer((invocation) async {
      final query = invocation.positionalArguments.first as String;
      return Right<Failure, List<CityEntity>>(_matchesFor(query));
    });
    when(() => cubit.addCity(any())).thenAnswer((_) async => null);
    when(
      () => cubit.replaceZone(
        locationId: any(named: 'locationId'),
        city: any(named: 'city'),
      ),
    ).thenAnswer((_) async => null);
  });

  Future<void> openSheet(
    WidgetTester tester, {
    SavedLocationEntity? replaces,
  }) async {
    await pumpApp(
      tester,
      _HostPage(cubit: cubit, replaces: replaces),
      surfaceSize: _tallSurface,
    );
    // After `pumpApp`, which resets GetIt: the sheet resolves the catalog
    // from the locator as it is built.
    GetIt.I.registerSingleton<CityCatalogRepository>(repository);
    await tester.tap(find.text(_openSheetLabel));
    await tester.pumpAndSettle();
  }

  /// Types [query] and lets the debounce elapse on the tester's fake clock.
  ///
  /// The field is found by its `EditableText` rather than by the search
  /// widget's type: what is under test is the sheet, and the input's internals
  /// are the design system's business.
  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(EditableText), query);
    await tester.pump(LocationSearchCubit.defaultDebounce);
    await tester.pumpAndSettle();
  }

  /// Lets a snackbar time out.
  ///
  /// Its dismissal is a real `Timer`, and flutter_test fails any test whose
  /// body returns with one still pending.
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the curated default list, one city per region', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.text(t.locations.addTitle), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Sao Paulo'), findsOneWidget);
    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('Auckland'), findsOneWidget);
    // The less prominent city of a region it already covers.
    expect(find.text('New York'), findsNothing);

    // A sheet that is useful before anything is typed is the whole point of
    // the default list; nothing has been searched to produce it.
    verifyNever(() => repository.search(any()));
  });

  testWidgets('finds a city typed with its accents', (tester) async {
    await openSheet(tester);

    await typeQuery(tester, 'São Paulo');

    // The query reaches the repository verbatim: folding is an index concern
    // and a cubit that folded first would break the raw-zone-id rule.
    verify(() => repository.search('São Paulo')).called(1);
    expect(find.text('Sao Paulo'), findsOneWidget);
    // The list is the query's answer, not the default list still standing.
    expect(find.text('Tokyo'), findsNothing);
  });

  testWidgets('finds a city by an alias it is better known by', (tester) async {
    await openSheet(tester);

    await typeQuery(tester, 'nyc');

    expect(find.text('New York'), findsOneWidget);
    expect(find.text('Sao Paulo'), findsNothing);
  });

  testWidgets('adds the selected city and closes', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('Tokyo'));
    await tester.pumpAndSettle();

    verify(() => cubit.addCity(_tokyo)).called(1);
    expect(find.byType(AddLocationSheet), findsNothing);
  });

  testWidgets('names the row that already covers the zone and stays open', (
    tester,
  ) async {
    when(() => cubit.addCity(any())).thenAnswer(
      (_) async => const DuplicateZoneFailure(
        zoneId: 'America/Sao_Paulo',
        existingLabel: 'Sao Paulo',
      ),
    );
    await openSheet(tester);

    await tester.tap(find.text('Sao Paulo'));
    await tester.pumpAndSettle();

    // Rule 2: the rejection has to say which of up to twenty rows collided,
    // and it is feedback rather than a broken screen — so the sheet stays up
    // and the user picks something else without reopening it.
    expect(
      find.text(t.locations.duplicateZone(city: 'Sao Paulo')),
      findsOneWidget,
    );
    expect(find.byType(AddLocationSheet), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);

    await drainSnackBar(tester);
  });

  testWidgets('refuses a city past the cap with the limit spelled out', (
    tester,
  ) async {
    when(() => cubit.addCity(any())).thenAnswer(
      (_) async => const BoardFullFailure(max: BoardEntity.maxLocations),
    );
    await openSheet(tester);

    await tester.tap(find.text('Tokyo'));
    await tester.pumpAndSettle();

    // Rule 4: the control stays live and the refusal explains itself, rather
    // than the add button going dead at twenty with no reason given.
    expect(
      find.text(t.locations.boardFull(max: BoardEntity.maxLocations)),
      findsOneWidget,
    );
    expect(find.byType(AddLocationSheet), findsOneWidget);

    await drainSnackBar(tester);
  });

  testWidgets('says the search found nothing without blaming the catalog', (
    tester,
  ) async {
    await openSheet(tester);

    await typeQuery(tester, 'atlantis');

    expect(find.text(t.locations.searchNoResults), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
  });

  testWidgets('reports a broken catalog inside the sheet, as an error', (
    tester,
  ) async {
    when(repository.load).thenAnswer(
      (_) async => const Left<Failure, List<CityEntity>>(ServerFailure()),
    );
    await openSheet(tester);

    // A catalog that could not be read is not "no city matches that": the
    // no-hits copy suggests a fix that would never work.
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(t.locations.searchNoResults), findsNothing);
  });

  testWidgets('repoints the row it was opened for instead of adding one', (
    tester,
  ) async {
    await openSheet(tester, replaces: _brokenRow);

    expect(find.text(t.locations.replaceZone), findsOneWidget);
    await tester.tap(find.text('Tokyo'));
    await tester.pumpAndSettle();

    // Rule 11's repair keeps the row's id and its position; a replace that
    // added a row would leave the broken one behind.
    verify(
      () => cubit.replaceZone(locationId: _brokenRow.id, city: _tokyo),
    ).called(1);
    verifyNever(() => cubit.addCity(any()));
    expect(find.byType(AddLocationSheet), findsNothing);
  });
}

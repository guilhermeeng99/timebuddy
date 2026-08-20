import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/feature_empty_state.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/locations/presentation/pages/add_location_sheet.dart';
import 'package:timebuddy/features/locations/presentation/pages/locations_page.dart';
import 'package:timebuddy/features/locations/presentation/widgets/location_list_tile.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

/// The board boundary under the page.
///
/// Mocked rather than built for real: `BoardCubit` is session-scoped and the
/// shell provides it, so what this page owns is the calls it makes and the
/// states it draws, not how the board is persisted.
class _MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

/// The catalog behind the add-location sheet this page can open.
class _MockCityCatalogRepository extends Mock
    implements CityCatalogRepository {}

/// Tall enough that every tile, the header and the FAB are laid out.
///
/// A tile that never got built cannot be tapped, and an assertion about it
/// would fail on a missing widget rather than on a wrong one.
const Size _tallSurface = Size(900, 1600);

/// A zone the tzdata still knows.
const String _tokyoZoneId = 'Asia/Tokyo';

/// Enderbury is a real id that upstream turned into a link and that a future
/// database could drop outright, which is the case rule 11 is about.
const String _enderburyZoneId = 'Pacific/Enderbury';

/// The instant every fixture row was added at.
///
/// Fixed, because `addedAt` is part of entity equality and a factory reading
/// the wall clock would make a row unequal to itself between two frames.
final DateTime _addedAt = utcDate(2024, 1, 15, 12);

SavedLocationEntity _row({
  required String id,
  required String zoneId,
  required String label,
  required String countryCode,
  required int sortIndex,
}) {
  return SavedLocationEntity(
    id: id,
    zoneId: zoneId,
    label: label,
    countryCode: countryCode,
    sortIndex: sortIndex,
    addedAt: _addedAt,
  );
}

final SavedLocationEntity _saoPauloRow = _row(
  id: 'row-sao-paulo',
  zoneId: 'America/Sao_Paulo',
  label: 'Sao Paulo',
  countryCode: 'BR',
  sortIndex: 0,
);

/// The home row, and deliberately not the first one: a page that badged the
/// top row by position would pass on any board whose home sits at index 0.
final SavedLocationEntity _berlinRow = _row(
  id: 'row-berlin',
  zoneId: 'Europe/Berlin',
  label: 'Berlin',
  countryCode: 'DE',
  sortIndex: 1,
);

final SavedLocationEntity _tokyoRow = _row(
  id: 'row-tokyo',
  zoneId: _tokyoZoneId,
  label: 'Tokyo',
  countryCode: 'JP',
  sortIndex: 2,
);

final SavedLocationEntity _enderburyRow = _row(
  id: 'row-enderbury',
  zoneId: _enderburyZoneId,
  label: 'Enderbury',
  countryCode: 'KI',
  sortIndex: 1,
);

BoardEntity _board(List<SavedLocationEntity> locations) => BoardEntity(
  homeZoneId: _berlinRow.zoneId,
  locations: locations,
  revision: 4,
  updatedAt: _addedAt,
);

final BoardEntity _fullOrder = _board([_saoPauloRow, _berlinRow, _tokyoRow]);
final BoardEntity _withoutTokyo = _board([_saoPauloRow, _berlinRow]);
final BoardEntity _withUnresolved = _board([_saoPauloRow, _enderburyRow]);

/// Two cities, enough for the picker to render rows rather than its empty
/// body when this page opens it.
const List<CityEntity> _catalogCities = [
  CityEntity(
    zoneId: 'Pacific/Kanton',
    name: 'Kanton',
    countryCode: 'KI',
    countryName: 'Kiribati',
    prominence: 10,
  ),
  CityEntity(
    zoneId: 'Europe/Lisbon',
    name: 'Lisbon',
    countryCode: 'PT',
    countryName: 'Portugal',
    prominence: 40,
  ),
];

/// The tile of the row labelled [label], whatever position it is drawn at.
///
/// Matched on the entity the tile was handed rather than on its rendered
/// text, so these tests keep working when `LocationRow` changes how a label
/// and its country are laid out.
Finder _tileFor(String label) => find.byWidgetPredicate(
  (widget) => widget is LocationListTile && widget.location.label == label,
  description: 'LocationListTile for $label',
);

void main() {
  setUpAll(() {
    initTestTimeZones();
    registerCommonFallbacks();
    registerFallbackValue(_catalogCities.first);
  });

  late _MockBoardCubit cubit;
  late _MockCityCatalogRepository catalog;

  /// States pushed at the page after it is mounted.
  ///
  /// The mocked cubit performs no mutation, so a test that asserts a row came
  /// back has to say what the cubit would have emitted; the stub that answers
  /// the call is where that is written.
  late StreamController<BoardState> states;

  setUp(() {
    cubit = _MockBoardCubit();
    catalog = _MockCityCatalogRepository();
    states = StreamController<BoardState>.broadcast();

    when(catalog.load).thenAnswer(
      (_) async => const Right<Failure, List<CityEntity>>(_catalogCities),
    );
    when(() => catalog.search(any())).thenAnswer(
      (_) async => const Right<Failure, List<CityEntity>>(_catalogCities),
    );

    // Every call the page can make has to answer with a real future: a
    // mocked method left unstubbed returns null, and the page awaits it.
    when(cubit.load).thenAnswer((_) async {});
    when(cubit.undoRemove).thenAnswer((_) async {
      return null;
    });
    when(() => cubit.reorder(any(), any())).thenAnswer((_) async {
      return null;
    });
    when(() => cubit.setHome(any())).thenAnswer((_) async {
      return null;
    });
    when(() => cubit.removeLocation(any())).thenAnswer((_) async {
      return null;
    });
    when(() => cubit.addCity(any())).thenAnswer((_) async => null);
    when(
      () => cubit.replaceZone(
        locationId: any(named: 'locationId'),
        city: any(named: 'city'),
      ),
    ).thenAnswer((_) async => null);
  });

  tearDown(() async {
    await states.close();
  });

  /// The one place this file builds a loaded board state.
  BoardState loaded(
    BoardEntity board, {
    Set<String> unresolvedIds = const {},
  }) {
    return BoardLoaded(board: board, unresolvedIds: unresolvedIds);
  }

  Future<void> pumpBoard(WidgetTester tester, BoardState initial) async {
    whenListen(cubit, states.stream, initialState: initial);
    await pumpApp(
      tester,
      BlocProvider<BoardCubit>.value(
        value: cubit,
        child: const LocationsPage(),
      ),
      surfaceSize: _tallSurface,
    );
    // Registered after `pumpApp`, which resets GetIt: the add-location sheet
    // resolves the catalog from the locator when it opens.
    GetIt.I.registerSingleton<CityCatalogRepository>(catalog);
  }

  /// Opens the action sheet of the row labelled [label].
  Future<void> openActions(WidgetTester tester, String label) async {
    await tester.tap(_tileFor(label));
    await tester.pumpAndSettle();
  }

  testWidgets('draws one tile per saved city, in the board order', (
    tester,
  ) async {
    await pumpBoard(tester, loaded(_fullOrder));

    expect(find.text(t.locations.title), findsOneWidget);
    expect(find.byType(LocationListTile), findsNWidgets(3));
    expect(_tileFor('Sao Paulo'), findsOneWidget);
    expect(_tileFor('Berlin'), findsOneWidget);
    expect(_tileFor('Tokyo'), findsOneWidget);

    // Rule 4: the user should see the cap coming rather than meet it at the
    // twenty-first city.
    expect(
      find.text(
        t.locations.countLabel(count: 3, max: BoardEntity.maxLocations),
      ),
      findsOneWidget,
    );
  });

  testWidgets('badges the home row, and only the home row', (tester) async {
    await pumpBoard(tester, loaded(_fullOrder));

    // Home is a zone id, not a position (rule 3), so the flag has to land on
    // the row whose zone matches, wherever the user dragged it.
    expect(tester.widget<LocationListTile>(_tileFor('Berlin')).isHome, isTrue);
    expect(
      tester.widget<LocationListTile>(_tileFor('Sao Paulo')).isHome,
      isFalse,
    );
    expect(tester.widget<LocationListTile>(_tileFor('Tokyo')).isHome, isFalse);
  });

  testWidgets('holds a placeholder until the board arrives', (tester) async {
    await pumpBoard(tester, const BoardLoading());

    expect(find.byType(LoadingShimmer), findsOneWidget);
    expect(find.byType(LocationListTile), findsNothing);
  });

  testWidgets('renders an empty board as an invitation, not an error', (
    tester,
  ) async {
    await pumpBoard(tester, loaded(_board(const [])));

    // Rule 6: zero cities is a valid board.
    expect(find.byType(FeatureEmptyState), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text(t.locations.emptyTitle), findsOneWidget);
  });

  testWidgets('retries a failed load through the cubit', (tester) async {
    await pumpBoard(tester, const BoardError(failure: StorageFailure()));

    expect(find.byType(ErrorView), findsOneWidget);
    await tester.tap(find.text(t.common.retry));
    await tester.pump();

    verify(cubit.load).called(1);
  });

  testWidgets('reorders through the cubit, in final positions', (
    tester,
  ) async {
    await pumpBoard(tester, loaded(_fullOrder));
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );

    // The tile owns both drag affordances, so the list must not also stamp
    // its default handle on top of the row's controls.
    expect(list.buildDefaultDragHandles, isFalse);

    // `onReorderItem` hands over final positions in both directions, so the
    // page forwards them untouched. A row dropped where it already sits is
    // still not a write: forwarding it would bump the revision and resync the
    // board for nothing.
    list.onReorderItem!(1, 1);
    verifyNever(() => cubit.reorder(any(), any()));

    // Downward.
    list.onReorderItem!(0, 2);
    verify(() => cubit.reorder(0, 2)).called(1);

    // Upward.
    list.onReorderItem!(2, 0);
    verify(() => cubit.reorder(2, 0)).called(1);
  });

  testWidgets('removing a city offers an undo that puts the row back', (
    tester,
  ) async {
    await pumpBoard(tester, loaded(_fullOrder));
    // The cubit is what actually restores the row; the page's part is to
    // send both calls and keep the offer on screen long enough to be taken.
    when(() => cubit.removeLocation(any())).thenAnswer((_) async {
      states.add(loaded(_withoutTokyo));
      return null;
    });
    when(cubit.undoRemove).thenAnswer((_) async {
      states.add(loaded(_fullOrder));
      return null;
    });

    await openActions(tester, 'Tokyo');
    await tester.tap(find.text(t.common.remove));
    await tester.pumpAndSettle();

    // Rule 7: removal is immediate, with no confirmation dialog in front of
    // it, and the undo names the city so a mis-tap is legible.
    verify(() => cubit.removeLocation(_tokyoRow.id)).called(1);
    expect(_tileFor('Tokyo'), findsNothing);
    expect(find.text(t.locations.removed(city: 'Tokyo')), findsOneWidget);

    await tester.tap(find.text(t.locations.undo));
    await tester.pumpAndSettle();

    verify(cubit.undoRemove).called(1);
    expect(_tileFor('Tokyo'), findsOneWidget);
  });

  testWidgets('keeps an unresolved row on the board and offers the repair', (
    tester,
  ) async {
    await pumpBoard(
      tester,
      loaded(_withUnresolved, unresolvedIds: {_enderburyZoneId}),
    );

    // Rule 11: a zone the tzdata dropped costs the user a note and a repair,
    // never the row. Dropping it would delete their data on a data upgrade.
    expect(_tileFor('Enderbury'), findsOneWidget);
    expect(
      tester.widget<LocationListTile>(_tileFor('Enderbury')).isUnresolved,
      isTrue,
    );
    expect(find.text(t.locations.unresolvedZone), findsOneWidget);
    // The resolved row alongside it stays ordinary, so the greying is about
    // this zone and not about the board.
    expect(
      tester.widget<LocationListTile>(_tileFor('Sao Paulo')).isUnresolved,
      isFalse,
    );

    await openActions(tester, 'Enderbury');
    await tester.tap(find.text(t.locations.replaceZone));
    await tester.pumpAndSettle();

    // The picker opens pointed at the broken row, so picking a city repoints
    // it instead of adding a second one next to it.
    final sheet = tester.widget<AddLocationSheet>(
      find.byType(AddLocationSheet),
    );
    expect(sheet.replaces, _enderburyRow);
  });

  testWidgets('sets home from a row through the cubit', (tester) async {
    await pumpBoard(tester, loaded(_fullOrder));

    await openActions(tester, 'Tokyo');
    await tester.tap(find.text(t.locations.setAsHome));
    await tester.pumpAndSettle();

    // Home moves by zone id; the list order is untouched (rule 3).
    verify(() => cubit.setHome(_tokyoZoneId)).called(1);
    verifyNever(() => cubit.reorder(any(), any()));
  });

  testWidgets('opens the picker as an add, not as a replace', (tester) async {
    await pumpBoard(tester, loaded(_fullOrder));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final sheet = tester.widget<AddLocationSheet>(
      find.byType(AddLocationSheet),
    );
    expect(sheet.replaces, isNull);
  });
}

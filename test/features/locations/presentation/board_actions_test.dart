import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/app/widgets/timebuddy_bottom_bar.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/board_actions.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/locations/presentation/pages/add_location_sheet.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../harness/factories/board_factory.dart';
import '../../../harness/mocks.dart';
import '../../../harness/pump_app.dart';

/// A phone, where the floating bottom bar is on screen.
const Size _phoneSurface = Size(390, 844);

/// Past `ResponsiveLayout.mobileBreakpoint`, where the rail replaces the bar
/// and there is nothing for a snackbar to clear.
const Size _desktopSurface = Size(1200, 900);

void main() {
  late MockBoardCubit boardCubit;

  /// The context every helper under test is invoked with.
  ///
  /// Captured from inside the pumped tree rather than taken from a finder, so
  /// the `MediaQuery`, the `BlocProvider` and the `ScaffoldMessenger` a helper
  /// reads are exactly the ones the app would give it.
  late BuildContext hostContext;

  final saoPauloRow = aSavedLocation();
  final tokyoRow = aSavedLocation(
    id: 'row-tokyo',
    zoneId: 'Asia/Tokyo',
    label: 'Tokyo',
    countryCode: 'JP',
    sortIndex: 1,
  );

  setUpAll(() {
    registerFallbackValue(saoPauloRow);
  });

  setUp(() {
    boardCubit = MockBoardCubit();
    whenListen(
      boardCubit,
      const Stream<BoardState>.empty(),
      initialState: BoardLoaded(
        board: aBoard(locations: [saoPauloRow, tokyoRow]),
      ),
    );
    // Every mutation lands unless a test says otherwise: a refusal is the
    // interesting case, so it has to be stated at the point that means it.
    when(() => boardCubit.removeLocation(any())).thenAnswer((_) async => null);
    when(boardCubit.undoRemove).thenAnswer((_) async => null);
    when(() => boardCubit.reorder(any(), any())).thenAnswer((_) async => null);
    when(() => boardCubit.setHome(any())).thenAnswer((_) async => null);
  });

  // The depth counter is app-scoped and outlives a pumped tree, so without
  // this a sub-page test would convince every later test it was on one.
  tearDown(subPageDepth.reset);

  Future<void> pumpHost(
    WidgetTester tester, {
    Size surfaceSize = _desktopSurface,
    bool asSubPage = false,
  }) async {
    final body = Builder(
      builder: (context) {
        hostContext = context;
        return const Scaffold(body: SizedBox.expand());
      },
    );
    await pumpApp(
      tester,
      BlocProvider<BoardCubit>.value(
        value: boardCubit,
        child: asSubPage ? SubPageScope(child: body) : body,
      ),
      surfaceSize: surfaceSize,
    );
    // `SubPageScope` publishes its depth on a post-frame callback, so the
    // counter is only readable on the frame after the mount.
    await tester.pump();
  }

  /// The snackbar currently on screen.
  SnackBar visibleSnack(WidgetTester tester) =>
      tester.widget<SnackBar>(find.byType(SnackBar));

  group('boardUndoWindow', () {
    test('is five seconds', () {
      // docs/specs/locations.md rule 7. Pinned as a constant *and* observed as
      // the snackbar's duration below, because the two can drift apart: a
      // helper that passed `const Duration(seconds: 4)` at the call site would
      // satisfy neither assertion alone.
      expect(boardUndoWindow, const Duration(seconds: 5));
    });
  });

  group('removeLocationWithUndo', () {
    testWidgets('removes the row the caller named', (tester) async {
      await pumpHost(tester);

      await removeLocationWithUndo(hostContext, tokyoRow);
      await tester.pump();

      // By row id, never by index: the board can have been reordered by a
      // sync between the tap and the write.
      verify(() => boardCubit.removeLocation(tokyoRow.id)).called(1);
    });

    testWidgets('asks for no confirmation before removing', (tester) async {
      await pumpHost(tester);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();

      // Rule 7: removing a city is the most common edit on the board and it is
      // cheap to reverse, so the cost belongs on the rare mistake rather than
      // on every deliberate removal. The row is already gone by the time
      // anything is shown.
      expect(find.byType(AlertDialog), findsNothing);
      verify(() => boardCubit.removeLocation(tokyoRow.id)).called(1);
    });

    testWidgets('offers the undo for the window the spec names', (
      tester,
    ) async {
      await pumpHost(tester);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();

      expect(find.text(t.locations.removed(city: 'Tokyo')), findsOneWidget);
      expect(find.text(t.locations.undo), findsOneWidget);
      // The window the helper asked for, read off the widget rather than off
      // the constant: a call site that passed its own `Duration(seconds: 4)`
      // would satisfy the constant's own test and fail this one.
      expect(visibleSnack(tester).duration, boardUndoWindow);

      // Still reachable a beat before the window closes.
      await tester.pump(boardUndoWindow - const Duration(milliseconds: 500));
      expect(find.text(t.locations.undo), findsOneWidget);
    });

    testWidgets('and the offer is gone once it closes', (tester) async {
      await pumpHost(tester);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();

      // `persist: false` is what makes rule 7's window real. `SnackBar.persist`
      // defaults to `action != null`, so a bar with an action ignores its own
      // `duration` — and the undo bar has an action by definition. Until this
      // was set, the window was asked for and never enforced: the Undo button
      // survived a navigation away and stayed pressable minutes later, against
      // a cubit whose remembered row a sync may have moved on from.
      //
      // Asserted on the flag *and* on the elapsed behaviour, because the flag
      // alone would still pass if `duration` were dropped, and the elapsed
      // check alone would not say which of the two knobs did the work.
      expect(visibleSnack(tester).persist, isFalse);

      await tester.pump(boardUndoWindow * 4);
      await tester.pumpAndSettle();

      expect(find.text(t.locations.undo), findsNothing);
    });

    testWidgets('pressing Undo puts the row back', (tester) async {
      await pumpHost(tester);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.locations.undo));
      await tester.pumpAndSettle();

      // Through the cubit, which owns the row it removed: the helper never
      // reconstructs one from the entity it was handed, because the row's
      // position is the cubit's to restore.
      verify(boardCubit.undoRemove).called(1);
    });

    testWidgets('a refused removal offers no undo at all', (tester) async {
      when(
        () => boardCubit.removeLocation(any()),
      ).thenAnswer((_) async => const StorageFailure());
      await pumpHost(tester);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();

      // The cubit rolled the board back, so the row is still there. Offering
      // to undo a removal that never happened would put the board one accepted
      // tap away from being wrong.
      expect(find.text(t.locations.undo), findsNothing);
      expect(find.text(t.common.errorBody), findsOneWidget);
      verifyNever(boardCubit.undoRemove);
    });

    testWidgets('a refused undo says which refusal it was', (tester) async {
      // The undo window is the user's, so the board can change underneath it:
      // another device filling the board is a real answer, not a bug.
      when(
        boardCubit.undoRemove,
      ).thenAnswer((_) async => const BoardFullFailure(max: 20));
      await pumpHost(tester);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.locations.undo));
      await tester.pumpAndSettle();

      // Named, not generic: the cap message tells the user why a row they
      // already had was refused on its way back.
      expect(find.text(t.locations.boardFull(max: 20)), findsOneWidget);
    });
  });

  group('the undo snackbar clears the floating bar', () {
    testWidgets('lifted over the bar on a phone', (tester) async {
      await pumpHost(tester, surfaceSize: _phoneSurface);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();

      // `TimeBuddyBottomBar` is an Align in `AppShell`'s Stack, painted above
      // the page's own Scaffold and reserving no layout space. A default,
      // fixed snackbar therefore lands underneath the pill, taking the Undo
      // button with it — visible and unpressable, which is worse than no undo
      // at all (design_system section 9).
      final snack = visibleSnack(tester);
      expect(snack.behavior, SnackBarBehavior.floating);
      expect(
        (snack.margin! as EdgeInsets).bottom,
        greaterThanOrEqualTo(TimeBuddyBottomBar.reservedHeight),
      );
    });

    testWidgets('left alone where the rail replaces the bar', (tester) async {
      // The default surface is _desktopSurface: past the breakpoint, where the
      // rail replaces the bar.
      await pumpHost(tester);

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();

      // Above the breakpoint there is no bar, so a snackbar floating 96px off
      // the floor would be hovering over nothing.
      final snack = visibleSnack(tester);
      expect(snack.behavior, SnackBarBehavior.fixed);
      expect(snack.margin, isNull);
    });

    testWidgets('left alone on a pushed sub-page', (tester) async {
      await pumpHost(
        tester,
        surfaceSize: _phoneSurface,
        asSubPage: true,
      );

      unawaited(removeLocationWithUndo(hostContext, tokyoRow));
      await tester.pumpAndSettle();

      // A phone, but the bar is hidden while a sub-page is open. Gated on the
      // same two conditions as `LiftedFab`, because they describe the same
      // fact: whether the bar is actually on screen.
      expect(subPageDepth.value, 1);
      expect(visibleSnack(tester).behavior, SnackBarBehavior.fixed);
    });
  });

  group('reorderBoardRow', () {
    testWidgets('a downward move lands where the user dropped it', (
      tester,
    ) async {
      await pumpHost(tester);

      // The regression this helper's doc comment describes. `ReorderableList`'s
      // obsolete `onReorder` reported the insertion point with the dragged row
      // still counted in the list, so a move from 0 to 2 arrived as 3 and the
      // call site had to subtract one. `onReorderItem` hands over final
      // positions, and this helper passes them through untouched — so a
      // reintroduced correction here would be visible as an off-by-one.
      await reorderBoardRow(hostContext, oldIndex: 0, newIndex: 2);
      await tester.pump();

      verify(() => boardCubit.reorder(0, 2)).called(1);
      verifyNever(() => boardCubit.reorder(0, 1));
      verifyNever(() => boardCubit.reorder(0, 3));
    });

    testWidgets('an upward move is passed through unchanged too', (
      tester,
    ) async {
      await pumpHost(tester);

      // The direction the old bug did *not* affect, which is why it survived:
      // a correction applied to both directions would have been noticed at
      // once. Pinning this one is what stops a future fix from being
      // reintroduced as an unconditional `newIndex - 1`.
      await reorderBoardRow(hostContext, oldIndex: 2, newIndex: 0);
      await tester.pump();

      verify(() => boardCubit.reorder(2, 0)).called(1);
    });

    testWidgets('a move onto its own position writes nothing', (tester) async {
      await pumpHost(tester);

      await reorderBoardRow(hostContext, oldIndex: 1, newIndex: 1);
      await tester.pump();

      // A drag that ends where it began is not an edit, and writing it would
      // bump the revision and push a no-op document to the server.
      verifyNever(() => boardCubit.reorder(any(), any()));
    });

    testWidgets('a refused reorder is reported', (tester) async {
      when(
        () => boardCubit.reorder(any(), any()),
      ).thenAnswer((_) async => const StorageFailure());
      await pumpHost(tester);

      unawaited(reorderBoardRow(hostContext, oldIndex: 0, newIndex: 1));
      await tester.pumpAndSettle();

      // Swallowing it would leave the user looking at an order that is not
      // what got saved.
      expect(find.text(t.common.errorBody), findsOneWidget);
    });
  });

  group('setBoardHome', () {
    testWidgets('points the board at the zone it was given', (tester) async {
      await pumpHost(tester);

      await setBoardHome(hostContext, 'Asia/Tokyo');
      await tester.pump();

      // Home is a zone id, not a row (docs/specs/locations.md rule 3), so
      // nothing about the order is touched.
      verify(() => boardCubit.setHome('Asia/Tokyo')).called(1);
      verifyNever(() => boardCubit.reorder(any(), any()));
    });

    testWidgets('a refused home change is reported', (tester) async {
      when(
        () => boardCubit.setHome(any()),
      ).thenAnswer((_) async => const StorageFailure());
      await pumpHost(tester);

      unawaited(setBoardHome(hostContext, 'Asia/Tokyo'));
      await tester.pumpAndSettle();

      // Otherwise the badge moves on screen and not in storage.
      expect(find.text(t.common.errorBody), findsOneWidget);
    });
  });

  group('openLocationRowActions', () {
    /// Opens the sheet for [location] and settles it.
    Future<void> openFor(
      WidgetTester tester,
      SavedLocationEntity location, {
      required bool isHome,
    }) async {
      unawaited(
        openLocationRowActions(hostContext, location: location, isHome: isHome),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers the same three actions on every row', (tester) async {
      await pumpHost(tester);

      await openFor(tester, saoPauloRow, isHome: true);

      // Even on the row that already is home. An action list whose entries
      // move between openings is one a thumb cannot learn, so `isHome` only
      // decides how the first row is *marked*.
      expect(find.text(t.locations.setAsHome), findsOneWidget);
      expect(find.text(t.locations.replaceZone), findsOneWidget);
      expect(find.text(t.common.remove), findsOneWidget);
    });

    testWidgets('dismissing the sheet mutates nothing', (tester) async {
      await pumpHost(tester);

      await openFor(tester, tokyoRow, isHome: false);
      // Tapping the barrier is the ordinary way out of a modal sheet.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      verifyNever(() => boardCubit.setHome(any()));
      verifyNever(() => boardCubit.removeLocation(any()));
    });

    testWidgets("set as home uses the row's zone, not its id", (
      tester,
    ) async {
      await pumpHost(tester);

      await openFor(tester, tokyoRow, isHome: false);
      await tester.tap(find.text(t.locations.setAsHome));
      await tester.pumpAndSettle();

      verify(() => boardCubit.setHome(tokyoRow.zoneId)).called(1);
    });

    testWidgets('set as home on the row that already is home is a no-op', (
      tester,
    ) async {
      await pumpHost(tester);

      await openFor(tester, saoPauloRow, isHome: true);
      await tester.tap(find.text(t.locations.setAsHome));
      await tester.pumpAndSettle();

      // The sheet reports `null` for that choice, so the helper has nothing to
      // carry out. Writing it anyway would bump the revision for a change the
      // user did not make.
      verifyNever(() => boardCubit.setHome(any()));
    });

    testWidgets('remove runs the undo window, not a bare delete', (
      tester,
    ) async {
      await pumpHost(tester);

      await openFor(tester, tokyoRow, isHome: false);
      await tester.tap(find.text(t.common.remove));
      await tester.pumpAndSettle();

      verify(() => boardCubit.removeLocation(tokyoRow.id)).called(1);
      // The sheet's remove is the same removal the row's swipe performs, undo
      // window included: two entry points to one edit must not offer two
      // different amounts of forgiveness.
      expect(find.text(t.locations.undo), findsOneWidget);
    });

    testWidgets('replace zone opens the picker instead of writing', (
      tester,
    ) async {
      await pumpHost(tester);
      // The picker resolves the catalog off the service locator, so it has to
      // be there before the sheet is opened — and `pumpApp` resets `GetIt`, so
      // it has to be registered after it. An empty catalog: this test is about
      // which surface opened, not about what it found.
      final catalog = MockCityCatalogRepository();
      when(catalog.load).thenAnswer(
        (_) async => const Right<Failure, List<CityEntity>>([]),
      );
      when(() => catalog.search(any(), limit: any(named: 'limit'))).thenAnswer(
        (_) async => const Right<Failure, List<CityEntity>>([]),
      );
      GetIt.I.registerSingleton<CityCatalogRepository>(catalog);

      await openFor(tester, tokyoRow, isHome: false);
      await tester.tap(find.text(t.locations.replaceZone));
      await tester.pumpAndSettle();

      expect(find.byType(AddLocationSheet), findsOneWidget);
      // The repair for a row whose zone the tzdata dropped keeps the row's id
      // and position, so nothing is removed on the way.
      verifyNever(() => boardCubit.removeLocation(any()));
    });
  });
}

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:uuid/uuid.dart';

import '../../../../harness/factories/board_factory.dart';
import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/mocks.dart';

/// The board boundary. Mocked, so a rejected write is a stubbed answer rather
/// than a full disk.
class _MockBoardRepository extends Mock implements BoardRepository {}

/// The id generator, so a new row's id is an assertion instead of a surprise.
class _MockUuid extends Mock implements Uuid {}

/// Zone ids, all real and all canonical unless the name says otherwise.
///
/// Real ids rather than synthetic ones because every rule here is about what
/// the tzdata says: `Europe/Oslo` and `Asia/Calcutta` are the two shapes of
/// "one clock, two spellings" that rule 2 exists for, and a made-up zone
/// could not exercise either.
const String _deviceZoneId = 'America/Sao_Paulo';
const String _tokyoZoneId = 'Asia/Tokyo';
const String _berlinZoneId = 'Europe/Berlin';
const String _kolkataZoneId = 'Asia/Kolkata';

/// A link to `Europe/Berlin` since the two clocks merged.
const String _osloZoneId = 'Europe/Oslo';

/// The pre-1993 spelling of [_kolkataZoneId].
const String _calcuttaZoneId = 'Asia/Calcutta';

/// A plausible id the database has never carried, standing in for one a
/// future tzdata release retires (rule 11).
const String _unknownZoneId = 'Pacific/Atlantis';

/// Twenty distinct canonical zones, for the cap.
///
/// Hand-listed rather than taken off the database in order: the database also
/// carries link names, and two of those would canonicalise onto one zone and
/// be rejected as duplicates before the cap could be reached.
const List<String> _twentyZoneIds = [
  'America/Sao_Paulo',
  'Europe/Berlin',
  'Asia/Tokyo',
  'America/New_York',
  'Europe/London',
  'Asia/Kolkata',
  'Australia/Sydney',
  'Pacific/Auckland',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/Paris',
  'Europe/Madrid',
  'Europe/Rome',
  'Africa/Cairo',
  'Africa/Lagos',
  'Asia/Dubai',
  'Asia/Shanghai',
  'Asia/Singapore',
  'America/Mexico_City',
];

CityEntity _city({
  required String zoneId,
  required String name,
  String countryCode = 'BR',
  String countryName = 'Brazil',
}) {
  return CityEntity(
    zoneId: zoneId,
    name: name,
    countryCode: countryCode,
    countryName: countryName,
    prominence: 0,
  );
}

List<SavedLocationEntity> _rowsFor(List<String> zoneIds) => [
  for (var index = 0; index < zoneIds.length; index++)
    aSavedLocation(
      id: 'row-$index',
      zoneId: zoneIds[index],
      label: 'City $index',
      sortIndex: index,
    ),
];

void main() {
  setUpAll(() {
    // Real tzdata: `zoneOrNull` is what decides duplicates, aliases and
    // unresolved rows, and a mocked engine could only confirm the
    // assumptions these tests already made (CLAUDE.md, Testing Rules).
    initTestTimeZones();
    registerCommonFallbacks();
    registerFallbackValue(aBoard());
  });

  final nowInstant = utcDate(2024, 6, 15, 12, 30);

  late _MockBoardRepository repository;
  late MockTimeZoneEngine engine;
  late _MockUuid uuid;
  late FakeClock clock;
  late int issuedIds;

  setUp(() {
    repository = _MockBoardRepository();
    engine = MockTimeZoneEngine();
    uuid = _MockUuid();
    clock = FakeClock(nowInstant);
    issuedIds = 0;

    when(() => uuid.v4()).thenAnswer((_) => 'new-row-${issuedIds++}');
    when(engine.deviceZone).thenAnswer(
      (_) async => const DeviceZone(zoneId: _deviceZoneId, isFallback: false),
    );
    when(
      () => repository.load(
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => Right<Failure, BoardEntity>(aBoard()));
    when(() => repository.save(any())).thenAnswer(
      (invocation) async => Right<Failure, BoardEntity>(
        invocation.positionalArguments.first as BoardEntity,
      ),
    );
  });

  BoardCubit buildCubit() => BoardCubit(
    repository: repository,
    clock: clock,
    engine: engine,
    uuid: uuid,
  );

  void repositoryHolds(BoardEntity board) {
    when(
      () => repository.load(
        homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
      ),
    ).thenAnswer((_) async => Right<Failure, BoardEntity>(board));
  }

  void repositoryRefusesToSave() {
    when(() => repository.save(any())).thenAnswer(
      (_) async => const Left<Failure, BoardEntity>(StorageFailure()),
    );
  }

  /// The board the repository was last asked to persist.
  BoardEntity lastSavedBoard() =>
      verify(() => repository.save(captureAny())).captured.last as BoardEntity;

  BoardLoaded loadedWith(
    BoardEntity board, {
    Set<String> unresolvedIds = const {},
  }) {
    return BoardLoaded(board: board, unresolvedIds: unresolvedIds);
  }

  final saoPauloRow = aSavedLocation();
  final berlinRow = aSavedLocation(
    id: 'row-berlin',
    zoneId: _berlinZoneId,
    label: 'Berlin',
    countryCode: 'DE',
    sortIndex: 1,
  );
  final tokyoRow = aSavedLocation(
    id: 'row-tokyo',
    zoneId: _tokyoZoneId,
    label: 'Tokyo',
    countryCode: 'JP',
    sortIndex: 2,
  );
  final threeRowBoard = aBoard(
    locations: [saoPauloRow, berlinRow, tokyoRow],
  );

  group('load', () {
    blocTest<BoardCubit, BoardState>(
      'emits loading, then the stored board',
      build: buildCubit,
      setUp: () => repositoryHolds(threeRowBoard),
      act: (cubit) => cubit.load(),
      expect: () => [const BoardLoading(), loadedWith(threeRowBoard)],
    );

    blocTest<BoardCubit, BoardState>(
      'offers the device zone as the home fallback',
      build: buildCubit,
      act: (cubit) => cubit.load(),
      verify: (_) {
        // Only a board with no stored home zone uses it, but resolving it is
        // this cubit's job: the repository has no engine (rule 3).
        verify(
          () => repository.load(homeZoneIdFallback: _deviceZoneId),
        ).called(1);
      },
    );

    blocTest<BoardCubit, BoardState>(
      'emits an error when the board cannot be read at all',
      build: buildCubit,
      setUp: () {
        when(
          () => repository.load(
            homeZoneIdFallback: any(named: 'homeZoneIdFallback'),
          ),
        ).thenAnswer(
          (_) async => const Left<Failure, BoardEntity>(StorageFailure()),
        );
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const BoardLoading(),
        const BoardError(failure: StorageFailure()),
      ],
    );

    // Both shapes of a stale id: a rename and a merge. Left alone, the second
    // one lets the same clock onto the board twice.
    blocTest<BoardCubit, BoardState>(
      'rewrites stored ids the tzdata knows under another name',
      build: buildCubit,
      setUp: () => repositoryHolds(
        aBoard(
          homeZoneId: _calcuttaZoneId,
          locations: [
            aSavedLocation(id: 'row-oslo', zoneId: _osloZoneId, label: 'Oslo'),
          ],
        ),
      ),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        final state = cubit.state as BoardLoaded;
        expect(state.board.homeZoneId, _kolkataZoneId);
        expect(state.board.locations.single.zoneId, _berlinZoneId);
        // The label is the user's, not the catalog's (rule 12): only the id
        // is repaired.
        expect(state.board.locations.single.label, 'Oslo');
        // Nothing is written for a repair: the corrected ids ride along with
        // the next real mutation.
        verifyNever(() => repository.save(any()));
      },
    );

    // Rule 11: dropping the row would delete a location the user never asked
    // to remove, on nothing more than a tzdata upgrade.
    blocTest<BoardCubit, BoardState>(
      'keeps and flags a row whose zone no longer resolves',
      build: buildCubit,
      setUp: () => repositoryHolds(
        aBoard(
          locations: [
            saoPauloRow,
            aSavedLocation(
              id: 'row-gone',
              zoneId: _unknownZoneId,
              label: 'Atlantis',
              sortIndex: 1,
            ),
          ],
        ),
      ),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        final state = cubit.state as BoardLoaded;
        expect(state.board.locations, hasLength(2));
        expect(state.unresolvedIds, {_unknownZoneId});
      },
    );

    blocTest<BoardCubit, BoardState>(
      'flags nothing on a healthy board',
      build: buildCubit,
      setUp: () => repositoryHolds(threeRowBoard),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        expect((cubit.state as BoardLoaded).unresolvedIds, isEmpty);
      },
    );
  });

  group('addCity', () {
    blocTest<BoardCubit, BoardState>(
      'appends the city with a generated id and the injected clock',
      build: buildCubit,
      seed: () => loadedWith(aBoard(locations: [saoPauloRow])),
      act: (cubit) => cubit.addCity(
        _city(zoneId: _tokyoZoneId, name: 'Tokyo', countryCode: 'JP'),
      ),
      verify: (cubit) {
        final board = (cubit.state as BoardLoaded).board;
        final added = board.locations.last;
        expect(added.id, 'new-row-0');
        expect(added.zoneId, _tokyoZoneId);
        expect(added.label, 'Tokyo');
        expect(added.countryCode, 'JP');
        expect(added.sortIndex, 1);
        expect(added.addedAt, nowInstant);
        // Every write bumps the revision and restamps (sync.md rules 5 and 7).
        expect(board.revision, 2);
        expect(board.updatedAt, nowInstant);
        expect(lastSavedBoard(), board);
      },
    );

    blocTest<BoardCubit, BoardState>(
      'stores the canonical zone id, not the catalog spelling',
      build: buildCubit,
      seed: () => loadedWith(aBoard()),
      act: (cubit) =>
          cubit.addCity(_city(zoneId: _osloZoneId, name: 'Oslo')),
      verify: (cubit) {
        final board = (cubit.state as BoardLoaded).board;
        expect(board.locations.single.zoneId, _berlinZoneId);
        // The label still says Oslo: only the id is canonical.
        expect(board.locations.single.label, 'Oslo');
      },
    );

    // Rule 2, and the reason the comparison is canonical: Oslo and Berlin are
    // one clock, so two rows would show identical times with nothing to tell
    // them apart.
    test('rejects a zone already covered, naming the row', () async {
      final cubit = buildCubit();
      repositoryHolds(aBoard(locations: [berlinRow]));
      await cubit.load();

      final failure = await cubit.addCity(
        _city(zoneId: _osloZoneId, name: 'Oslo'),
      );

      expect(
        failure,
        const DuplicateZoneFailure(
          zoneId: _berlinZoneId,
          existingLabel: 'Berlin',
        ),
      );
      // Rejected, so nothing was written and nothing was emitted: a refusal
      // is feedback, not a state change.
      verifyNever(() => repository.save(any()));
      expect((cubit.state as BoardLoaded).board.locations, hasLength(1));
      await cubit.close();
    });

    test('rejects the twenty-first city with the cap it hit', () async {
      final cubit = buildCubit();
      repositoryHolds(aBoard(locations: _rowsFor(_twentyZoneIds)));
      await cubit.load();

      final failure = await cubit.addCity(
        _city(zoneId: 'Asia/Seoul', name: 'Seoul'),
      );

      expect(failure, const BoardFullFailure(max: 20));
      expect(BoardEntity.maxLocations, 20);
      verifyNever(() => repository.save(any()));
      await cubit.close();
    });

    test('rejects a zone the tzdata does not know', () async {
      final cubit = buildCubit();
      repositoryHolds(aBoard());
      await cubit.load();

      final failure = await cubit.addCity(
        _city(zoneId: _unknownZoneId, name: 'Atlantis'),
      );

      expect(failure, isA<ValidationFailure>());
      verifyNever(() => repository.save(any()));
      await cubit.close();
    });

    test('rejects a mutation that arrives before the load', () async {
      final cubit = buildCubit();

      final failure = await cubit.addCity(
        _city(zoneId: _tokyoZoneId, name: 'Tokyo'),
      );

      expect(failure, isA<ValidationFailure>());
      expect(cubit.state, const BoardInitial());
      await cubit.close();
    });

    // Optimistic, then rolled back: the row appears at once and disappears
    // only because the write was refused, which is what the snackbar reports.
    blocTest<BoardCubit, BoardState>(
      'rolls the board back when the local write is refused',
      build: buildCubit,
      seed: () => loadedWith(aBoard(locations: [saoPauloRow])),
      setUp: repositoryRefusesToSave,
      act: (cubit) => cubit.addCity(
        _city(zoneId: _tokyoZoneId, name: 'Tokyo'),
      ),
      expect: () => [
        isA<BoardLoaded>().having(
          (state) => state.board.locations,
          'locations',
          hasLength(2),
        ),
        loadedWith(aBoard(locations: [saoPauloRow])),
      ],
    );

    test('hands the refused write back to the caller', () async {
      final cubit = buildCubit();
      repositoryHolds(aBoard());
      await cubit.load();
      repositoryRefusesToSave();

      final failure = await cubit.addCity(
        _city(zoneId: _tokyoZoneId, name: 'Tokyo'),
      );

      // The one-shot channel: the failure reaches exactly the caller that
      // caused it, and the state that survives is the rolled-back board.
      expect(failure, isA<StorageFailure>());
      expect((cubit.state as BoardLoaded).board.locations, isEmpty);
      await cubit.close();
    });
  });

  group('removeLocation', () {
    blocTest<BoardCubit, BoardState>(
      'removes the row and re-densifies the indices',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.removeLocation(berlinRow.id),
      verify: (cubit) {
        final board = (cubit.state as BoardLoaded).board;
        expect(board.locations.map((row) => row.id), [
          saoPauloRow.id,
          tokyoRow.id,
        ]);
        // Rule 5: dense and 0-based, so the next add cannot collide.
        expect(board.locations.map((row) => row.sortIndex), [0, 1]);
        expect(lastSavedBoard(), board);
      },
    );

    // Rule 8: home is a zone id, not a row, so the relative offsets keep
    // working after the home row is dropped.
    blocTest<BoardCubit, BoardState>(
      'leaves the home zone alone when the home row is removed',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.removeLocation(saoPauloRow.id),
      verify: (cubit) {
        final board = (cubit.state as BoardLoaded).board;
        expect(board.homeZoneId, _deviceZoneId);
        expect(board.containsZone(_deviceZoneId), isFalse);
      },
    );

    blocTest<BoardCubit, BoardState>(
      'exposes the removed row so the UI can offer the undo',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.removeLocation(tokyoRow.id),
      verify: (cubit) {
        // The five-second window is the snackbar's; this cubit owns no timer
        // (rule 7), because one here would fire at a tree that may be gone.
        expect(cubit.lastRemoved, tokyoRow);
      },
    );

    blocTest<BoardCubit, BoardState>(
      'ignores a row that is not on the board',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.removeLocation('row-that-never-existed'),
      expect: () => <BoardState>[],
      verify: (_) => verifyNever(() => repository.save(any())),
    );

    test('a refused removal rolls back and forgets the undo', () async {
      final cubit = buildCubit();
      repositoryHolds(threeRowBoard);
      await cubit.load();
      repositoryRefusesToSave();

      final failure = await cubit.removeLocation(tokyoRow.id);

      expect(failure, isA<StorageFailure>());
      expect((cubit.state as BoardLoaded).board.locations, hasLength(3));
      // The row never left, so there is nothing to put back.
      expect(cubit.lastRemoved, isNull);
      await cubit.close();
    });
  });

  group('undoRemove', () {
    test('puts the row back where it was', () async {
      final cubit = buildCubit();
      repositoryHolds(threeRowBoard);
      await cubit.load();
      await cubit.removeLocation(berlinRow.id);

      final failure = await cubit.undoRemove();

      expect(failure, isNull);
      final board = (cubit.state as BoardLoaded).board;
      expect(board.locations.map((row) => row.id), [
        saoPauloRow.id,
        berlinRow.id,
        tokyoRow.id,
      ]);
      expect(board.locations.map((row) => row.sortIndex), [0, 1, 2]);
      // Two mutations, two writes, two revisions.
      expect(board.revision, threeRowBoard.revision + 2);
      expect(cubit.lastRemoved, isNull);
      await cubit.close();
    });

    blocTest<BoardCubit, BoardState>(
      'does nothing when no row was removed',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.undoRemove(),
      expect: () => <BoardState>[],
      verify: (_) => verifyNever(() => repository.save(any())),
    );

    // The undo window is the user's, so the board can move underneath it.
    test('refuses to restore a zone re-added in the meantime', () async {
      final cubit = buildCubit();
      repositoryHolds(threeRowBoard);
      await cubit.load();
      await cubit.removeLocation(berlinRow.id);
      await cubit.addCity(_city(zoneId: _osloZoneId, name: 'Oslo'));

      final failure = await cubit.undoRemove();

      expect(failure, isA<DuplicateZoneFailure>());
      expect((cubit.state as BoardLoaded).board.locations, hasLength(3));
      await cubit.close();
    });
  });

  group('reorder', () {
    blocTest<BoardCubit, BoardState>(
      'moves the row and rewrites the whole range in one write',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.reorder(2, 0),
      verify: (cubit) {
        final board = (cubit.state as BoardLoaded).board;
        expect(board.locations.map((row) => row.id), [
          tokyoRow.id,
          saoPauloRow.id,
          berlinRow.id,
        ]);
        expect(board.locations.map((row) => row.sortIndex), [0, 1, 2]);
        // Rule 5: one write for the affected range, never one per row.
        verify(() => repository.save(any())).called(1);
      },
    );

    blocTest<BoardCubit, BoardState>(
      'ignores a move that changes nothing',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) async {
        await cubit.reorder(1, 1);
        await cubit.reorder(0, 9);
        await cubit.reorder(-1, 0);
      },
      expect: () => <BoardState>[],
      verify: (_) => verifyNever(() => repository.save(any())),
    );
  });

  group('setHome', () {
    blocTest<BoardCubit, BoardState>(
      'moves the reference zone and leaves the rows untouched',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.setHome(_tokyoZoneId),
      verify: (cubit) {
        final board = (cubit.state as BoardLoaded).board;
        expect(board.homeZoneId, _tokyoZoneId);
        // Rule 3: home is independent of the list.
        expect(board.locations, threeRowBoard.locations);
        expect(board.revision, threeRowBoard.revision + 1);
      },
    );

    blocTest<BoardCubit, BoardState>(
      'stores the canonical id of an aliased zone',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.setHome(_calcuttaZoneId),
      verify: (cubit) {
        expect((cubit.state as BoardLoaded).board.homeZoneId, _kolkataZoneId);
      },
    );

    test('refuses a zone the tzdata does not know', () async {
      final cubit = buildCubit();
      repositoryHolds(threeRowBoard);
      await cubit.load();

      final failure = await cubit.setHome(_unknownZoneId);

      // Adopting it would silently make UTC the reference for every offset
      // on screen.
      expect(failure, isA<ValidationFailure>());
      expect((cubit.state as BoardLoaded).board.homeZoneId, _deviceZoneId);
      verifyNever(() => repository.save(any()));
      await cubit.close();
    });

    blocTest<BoardCubit, BoardState>(
      'writes nothing when the home zone does not change',
      build: buildCubit,
      seed: () => loadedWith(threeRowBoard),
      act: (cubit) => cubit.setHome(_deviceZoneId),
      expect: () => <BoardState>[],
      verify: (_) => verifyNever(() => repository.save(any())),
    );
  });

  group('replaceZone', () {
    final brokenRow = aSavedLocation(
      id: 'row-gone',
      zoneId: _unknownZoneId,
      label: 'Atlantis',
      sortIndex: 1,
    );
    final boardWithBrokenRow = aBoard(
      locations: [saoPauloRow, brokenRow],
    );

    test('repoints the row and clears its unresolved flag', () async {
      final cubit = buildCubit();
      repositoryHolds(boardWithBrokenRow);
      await cubit.load();
      expect((cubit.state as BoardLoaded).unresolvedIds, {_unknownZoneId});

      final failure = await cubit.replaceZone(
        locationId: brokenRow.id,
        city: _city(zoneId: _tokyoZoneId, name: 'Tokyo', countryCode: 'JP'),
      );

      expect(failure, isNull);
      final state = cubit.state as BoardLoaded;
      final repaired = state.board.locations.last;
      expect(repaired.id, brokenRow.id);
      expect(repaired.zoneId, _tokyoZoneId);
      // The one sanctioned way a stored label changes (rule 12): an explicit
      // edit, never a catalog regeneration.
      expect(repaired.label, 'Tokyo');
      expect(repaired.countryCode, 'JP');
      expect(repaired.sortIndex, 1);
      expect(state.unresolvedIds, isEmpty);
      await cubit.close();
    });

    test('refuses to repoint onto a zone another row covers', () async {
      final cubit = buildCubit();
      repositoryHolds(aBoard(locations: [berlinRow, brokenRow]));
      await cubit.load();

      final failure = await cubit.replaceZone(
        locationId: brokenRow.id,
        city: _city(zoneId: _osloZoneId, name: 'Oslo'),
      );

      expect(failure, isA<DuplicateZoneFailure>());
      verifyNever(() => repository.save(any()));
      await cubit.close();
    });

    test('refuses a row id the board does not hold', () async {
      final cubit = buildCubit();
      repositoryHolds(threeRowBoard);
      await cubit.load();

      final failure = await cubit.replaceZone(
        locationId: 'row-that-never-existed',
        city: _city(zoneId: _tokyoZoneId, name: 'Tokyo'),
      );

      expect(failure, isA<NotFoundFailure>());
      await cubit.close();
    });
  });
}

import 'package:bloc/bloc.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_state.dart';
import 'package:uuid/uuid.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/locations/presentation/cubit/board_state.dart';

/// The single source of truth for which places the user is watching.
///
/// Session-scoped: `AppShell` creates it once per session and every page
/// reads it (CLAUDE.md, Lifecycle). The grid, the world clock and the converter
/// all render from this one list, so nothing else may hold a board.
///
/// **Every mutation is optimistic.** The new state is emitted first and
/// persisted behind it, because a row that snaps back while a write is in
/// flight feels broken (docs/specs/locations.md, State Machine). A rejected
/// local write rolls the state back to exactly what it was.
///
/// **How a rejected mutation reaches the UI.** Every mutation returns
/// `Future<Failure?>`: `null` when it landed, the failure when it did not.
/// That return value is the one-shot channel, and it is deliberately not a
/// field on [BoardLoaded]. A failure parked in the state has to be cleared by
/// somebody — miss that and it re-fires on the next unrelated rebuild — and
/// every listener would show it, so two mounted pages would raise two
/// snackbars for one refused add. Returning it hands the failure exactly once
/// to the caller that caused it, and the state that follows is the rolled-back
/// board. `BoardError` stays reserved for a load that produced no board at
/// all: emitting it for a duplicate city would blank a screen the user is
/// reading.
///
/// ```dart
/// final failure = await context.read<BoardCubit>().addCity(city);
/// if (failure != null) context.showSnack(messageFor(failure));
/// ```
class BoardCubit extends Cubit<BoardState> {
  BoardCubit({
    required BoardRepository repository,
    required Clock clock,
    required TimeZoneEngine engine,
    required Uuid uuid,
  }) : _repository = repository,
       _clock = clock,
       _engine = engine,
       _uuid = uuid,
       super(const BoardInitial());

  final BoardRepository _repository;
  final Clock _clock;

  /// Used for one question only: which zone this device is in, to seed
  /// `homeZoneId` on a first launch. Every zone *resolution* goes through
  /// `zoneOrNull`, which answers `null` for an unknown id where the engine
  /// would silently degrade it.
  final TimeZoneEngine _engine;
  final Uuid _uuid;

  SavedLocationEntity? _lastRemoved;

  /// The row [removeLocation] took off the board, until [undoRemove] puts it
  /// back or a [load] replaces the board.
  ///
  /// Exposed so the UI can name the city in its undo offer. The five-second
  /// window is the snackbar's (rule 7); this cubit deliberately owns no timer,
  /// because a timer here would fire against a widget tree that may already
  /// be gone.
  SavedLocationEntity? get lastRemoved => _lastRemoved;

  /// Reads the board, seeding a fresh one from the device zone when this is a
  /// first launch. Called once per session by the shell.
  Future<void> load() async {
    emit(const BoardLoading());
    _lastRemoved = null;

    final deviceZone = await _engine.deviceZone();
    final result = await _repository.load(
      homeZoneIdFallback: deviceZone.zoneId,
    );
    if (isClosed) return;

    emit(
      result.fold<BoardState>(
        (failure) => BoardError(failure: failure),
        (board) => _loadedFor(_canonicalised(board)),
      ),
    );
  }

  /// Adds [city] as a new row at the end of the board.
  ///
  /// Rejects a city whose zone is already covered, naming the row that covers
  /// it (rule 2), and a city past the cap (rule 4). The duplicate check runs
  /// first on purpose: on a full board, "already covered by Sao Paulo" is the
  /// more actionable of the two answers.
  Future<Failure?> addCity(CityEntity city) async {
    final current = state;
    if (current is! BoardLoaded) return _notLoaded;

    final zone = zoneOrNull(city.zoneId);
    if (zone == null) return _unknownZone(city.zoneId);

    final existing = current.board.locationForZone(zone.id);
    if (existing != null) {
      return DuplicateZoneFailure(
        zoneId: zone.id,
        existingLabel: existing.label,
      );
    }
    if (current.board.isFull) {
      return const BoardFullFailure(max: BoardEntity.maxLocations);
    }

    final row = _rowFor(city, zone, current.board.locations.length);
    return _commit(current, [...current.board.locations, row]);
  }

  /// Takes the row [id] off the board, remembering it for [undoRemove].
  ///
  /// Removing the home zone's row leaves `homeZoneId` alone: home is a zone
  /// id, not a row (rules 3 and 8), so the relative offsets keep working.
  /// Removing a row that is already gone is a no-op, not a failure.
  Future<Failure?> removeLocation(String id) async {
    final current = state;
    if (current is! BoardLoaded) return _notLoaded;

    final removed = _rowById(current.board, id);
    if (removed == null) return null;

    _lastRemoved = removed;
    final failure = await _commit(current, [
      for (final location in current.board.locations)
        if (location.id != id) location,
    ]);
    // The write was refused and the board rolled back, so the row never left
    // and there is nothing to undo.
    if (failure != null) _lastRemoved = null;
    return failure;
  }

  /// Puts the last removed row back where it was.
  ///
  /// The window between the removal and the undo is the user's, so the board
  /// may have changed underneath: the same two guards as an add apply, and a
  /// restore that would exceed the cap or collide with a zone added in the
  /// meantime is refused rather than forced.
  Future<Failure?> undoRemove() async {
    final removed = _lastRemoved;
    if (removed == null) return null;

    final current = state;
    if (current is! BoardLoaded) return _notLoaded;
    if (current.board.isFull) {
      return const BoardFullFailure(max: BoardEntity.maxLocations);
    }
    final clash = current.board.locationForZone(removed.zoneId);
    if (clash != null) {
      return DuplicateZoneFailure(
        zoneId: removed.zoneId,
        existingLabel: clash.label,
      );
    }

    final rows = [...current.board.locations];
    rows.insert(_insertionIndex(removed.sortIndex, rows.length), removed);
    _lastRemoved = null;
    final failure = await _commit(current, rows);
    if (failure != null) _lastRemoved = removed;
    return failure;
  }

  /// Moves the row at [oldIndex] to [newIndex], both final positions.
  ///
  /// One write for the whole affected range, never one per row (rule 5): the
  /// indices are rewritten in memory and the board is saved once. An index
  /// outside the list, or a move that changes nothing, is dropped silently —
  /// a widget's drag convention is not something to snack at the user about.
  Future<Failure?> reorder(int oldIndex, int newIndex) async {
    final current = state;
    if (current is! BoardLoaded) return _notLoaded;

    final rows = [...current.board.locations];
    if (oldIndex < 0 || oldIndex >= rows.length) return null;
    if (newIndex < 0 || newIndex >= rows.length) return null;
    if (oldIndex == newIndex) return null;

    rows.insert(newIndex, rows.removeAt(oldIndex));
    return _commit(current, rows);
  }

  /// Points the board's reference zone at [zoneId].
  ///
  /// Leaves [BoardLoaded.board]'s rows untouched: home is independent of the
  /// list (rule 3), so this only moves which row wears the badge and what
  /// every relative offset is measured against. An id the tzdata cannot
  /// resolve is refused, because adopting it would silently reference UTC.
  Future<Failure?> setHome(String zoneId) async {
    final current = state;
    if (current is! BoardLoaded) return _notLoaded;

    final zone = zoneOrNull(zoneId);
    if (zone == null) return _unknownZone(zoneId);
    if (zone.id == current.board.homeZoneId) return null;

    return _commitBoard(current, current.board.copyWith(homeZoneId: zone.id));
  }

  /// Repoints the row [locationId] at [city]'s zone, keeping its position.
  ///
  /// The repair offered for a row whose zone the tzdata dropped (rule 11),
  /// and the one sanctioned way a saved row's label changes: the catalog is
  /// never the source of truth for a stored row (rule 12), an explicit edit
  /// is.
  Future<Failure?> replaceZone({
    required String locationId,
    required CityEntity city,
  }) async {
    final current = state;
    if (current is! BoardLoaded) return _notLoaded;

    final row = _rowById(current.board, locationId);
    if (row == null) return const NotFoundFailure('No such row on the board.');

    final zone = zoneOrNull(city.zoneId);
    if (zone == null) return _unknownZone(city.zoneId);

    final clash = current.board.locationForZone(
      zone.id,
      excludingId: locationId,
    );
    if (clash != null) {
      return DuplicateZoneFailure(
        zoneId: zone.id,
        existingLabel: clash.label,
      );
    }

    return _commit(current, [
      for (final location in current.board.locations)
        if (location.id == locationId)
          location.copyWith(
            zoneId: zone.id,
            label: city.name,
            countryCode: city.countryCode,
          )
        else
          location,
    ]);
  }

  /// [_commitBoard] for the common case of a mutation that only touched the
  /// rows.
  Future<Failure?> _commit(
    BoardLoaded previous,
    List<SavedLocationEntity> rows,
  ) {
    return _commitBoard(previous, previous.board.copyWith(locations: rows));
  }

  /// Emits [next] at once, then persists it; rolls [previous] back if the
  /// write is refused.
  ///
  /// The one place `sortIndex` density (rule 5) and the sync stamps (sync.md
  /// rules 5 and 7) are applied, so no mutation can forget either. The
  /// revision is bumped here rather than in the repository, which persists
  /// what it is given: a repository that restamped would inflate the very
  /// revision a sync is reconciling.
  Future<Failure?> _commitBoard(BoardLoaded previous, BoardEntity next) async {
    final stamped = next.copyWith(
      locations: _reindexed(next.locations),
      revision: previous.board.revision + 1,
      updatedAt: _clock.nowUtc(),
    );
    emit(_loadedFor(stamped));

    final result = await _repository.save(stamped);
    // The shell was disposed mid-write. The document is already on disk or
    // already refused; either way there is no state left to correct.
    if (isClosed) return null;

    return result.fold<Failure?>(
      (failure) {
        emit(previous);
        return failure;
      },
      (_) => null,
    );
  }

  BoardLoaded _loadedFor(BoardEntity board) => BoardLoaded(
    board: board,
    unresolvedIds: {
      for (final location in board.locations)
        if (zoneOrNull(location.zoneId) == null) location.zoneId,
    },
  );

  /// Rewrites every stored id the tzdata knows under another name.
  ///
  /// `Asia/Calcutta` became `Asia/Kolkata` and `Europe/Oslo` is now a link to
  /// `Europe/Berlin`; both still resolve, and canonicalising on the way in is
  /// what keeps a stale document from adding a second row for a zone the
  /// board already holds. An id that resolves to nothing is left exactly as
  /// it was, so rule 11 can flag it and the user can repair it. Nothing is
  /// written here: the repaired ids ride along with the next save.
  BoardEntity _canonicalised(BoardEntity board) => board.copyWith(
    homeZoneId: zoneOrNull(board.homeZoneId)?.id ?? board.homeZoneId,
    locations: [
      for (final location in board.locations)
        location.copyWith(
          zoneId: zoneOrNull(location.zoneId)?.id ?? location.zoneId,
        ),
    ],
  );

  SavedLocationEntity _rowFor(CityEntity city, ZoneRef zone, int sortIndex) {
    return SavedLocationEntity(
      id: _uuid.v4(),
      // The canonical id, not the spelling the catalog used: two spellings of
      // one clock must not become two rows (rule 2).
      zoneId: zone.id,
      // Denormalised at add time and never refreshed from the catalog
      // afterwards (rule 12).
      label: city.name,
      countryCode: city.countryCode,
      sortIndex: sortIndex,
      addedAt: _clock.nowUtc(),
    );
  }

  SavedLocationEntity? _rowById(BoardEntity board, String id) {
    for (final location in board.locations) {
      if (location.id == id) return location;
    }
    return null;
  }

  /// The list with `sortIndex` set to each row's position (rule 5).
  List<SavedLocationEntity> _reindexed(List<SavedLocationEntity> rows) => [
    for (var position = 0; position < rows.length; position++)
      rows[position].copyWith(sortIndex: position),
  ];

  /// [sortIndex] clamped to a position [length] rows can accept.
  int _insertionIndex(int sortIndex, int length) {
    if (sortIndex < 0) return 0;
    return sortIndex > length ? length : sortIndex;
  }

  /// A mutation arrived before the board was read. The pages that mutate are
  /// only reachable from a loaded board, so this covers a caller jumping the
  /// gun rather than anything a user can do.
  static const Failure _notLoaded = ValidationFailure(
    'The board has not been loaded yet.',
  );

  Failure _unknownZone(String zoneId) =>
      ValidationFailure('The time zone "$zoneId" is not in the database.');
}

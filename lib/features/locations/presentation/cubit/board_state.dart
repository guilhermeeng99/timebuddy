import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';

/// State of `BoardCubit`.
///
/// A rejected mutation is deliberately **not** a state here: the failure is
/// returned to the caller that caused it (see `BoardCubit`), because emitting
/// `BoardError` for a duplicate city would blank a screen the user is reading
/// over a message that belongs in a snackbar.
sealed class BoardState extends Equatable {
  const BoardState();

  @override
  List<Object?> get props => const [];
}

/// Before `load()` is called. Only the frame between the shell mounting and
/// its eager load sees this.
final class BoardInitial extends BoardState {
  const BoardInitial();
}

final class BoardLoading extends BoardState {
  const BoardLoading();
}

/// A board the UI can draw, empty or not: zero cities is a valid state, not
/// an error (docs/specs/locations.md rule 6).
final class BoardLoaded extends BoardState {
  const BoardLoaded({
    required this.board,
    this.unresolvedIds = const <String>{},
    this.isSyncing = false,
  });

  final BoardEntity board;

  /// The **zone ids** on the board that the loaded tzdata cannot resolve.
  ///
  /// Zone ids rather than row ids: the fact is about the zone, two rows in
  /// one dropped zone are one entry, and the consumer already has the row in
  /// hand when it asks (`unresolvedIds.contains(location.zoneId)`).
  ///
  /// Those rows are kept and flagged, never dropped (rule 11): deleting a
  /// user's city because a tzdata upgrade retired its id would be deleting
  /// their data without consent. The set is empty on a healthy board.
  final Set<String> unresolvedIds;

  /// Whether a remote sync is in flight.
  ///
  /// Always `false` in M2 and carried anyway, so the passive indicator
  /// docs/specs/sync.md rule 4 asks for can be wired without reshaping this
  /// state. M3's `SyncService` is what will ever set it.
  final bool isSyncing;

  @override
  List<Object?> get props => [board, unresolvedIds, isSyncing];
}

/// The board could not be read at all, so there is nothing to draw.
///
/// Reachable only from `load()`: a mutation that fails rolls back to the
/// previous [BoardLoaded] instead.
final class BoardError extends BoardState {
  const BoardError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

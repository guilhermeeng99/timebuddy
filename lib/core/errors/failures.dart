import 'package:equatable/equatable.dart';

/// Base type for every expected, recoverable error in the app.
///
/// Failures are the only error currency that crosses a layer boundary: they
/// travel inside `Either<Failure, T>` and are values, not control flow. Data
/// sources throw (see `exceptions.dart`); the repository that owns them
/// catches and translates into one of the subtypes below.
///
/// [message] is developer-facing and exists for logs and test output. The UI
/// switches on the failure *type* to pick a localized string and must never
/// render [message] to the user.
///
/// ```dart
/// final result = await repository.addLocation(city);
/// result.fold(
///   (failure) => switch (failure) {
///     DuplicateZoneFailure(:final existingLabel) =>
///       context.showSnack(t.locations.duplicate(city: existingLabel)),
///     BoardFullFailure(:final max) =>
///       context.showSnack(t.locations.boardFull(max: max)),
///     _ => context.showSnack(t.errors.generic),
///   },
///   (board) => emit(BoardReady(board)),
/// );
/// ```
sealed class Failure extends Equatable {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// A remote call failed: transport error, timeout, or an error response.
final class ServerFailure extends Failure {
  const ServerFailure([super.message = 'The server could not be reached.']);
}

/// Sign-in, sign-out or token refresh failed, or the session expired.
final class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed.']);
}

/// Input broke a domain invariant before anything was written.
final class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'The value is not valid.']);
}

/// The on-device store could not be read or written.
final class StorageFailure extends Failure {
  const StorageFailure([super.message = 'Local storage is unavailable.']);
}

/// The requested document or record does not exist.
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'The item was not found.']);
}

/// Adding a location whose zone is already on the board.
///
/// A location is identified by its zone, not by its city (locations.md rule
/// 2): "Rio de Janeiro" next to "Sao Paulo" would draw two rows showing the
/// identical time, and the grid has no way to distinguish them. The rejection
/// carries [existingLabel] so the UI can name the row that already covers
/// [zoneId] instead of failing generically.
final class DuplicateZoneFailure extends Failure {
  // `message` is forwarded explicitly rather than through `super.message`:
  // the base constructor takes it positionally, and a named super parameter
  // can only bind to a named one.
  const DuplicateZoneFailure({
    required this.zoneId,
    required this.existingLabel,
    String message = 'That timezone is already on the board.',
  }) : super(message);

  /// The IANA id that collided.
  final String zoneId;

  /// Display label of the row already holding [zoneId].
  final String existingLabel;

  @override
  List<Object?> get props => [message, zoneId, existingLabel];
}

/// Adding a location to a board that already holds [max] of them.
///
/// The cap exists because past roughly twenty rows the grid stops being
/// readable and the per-tick rebuild cost stops being trivial (locations.md
/// rule 4). [max] travels with the failure so the message can state the limit
/// without the presentation layer importing the domain constant.
final class BoardFullFailure extends Failure {
  const BoardFullFailure({
    required this.max,
    String message = 'The board is full.',
  }) : super(message);

  /// The limit that was hit, from `board_limits.dart`.
  final int max;

  @override
  List<Object?> get props => [message, max];
}

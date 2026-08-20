import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';

/// Local-first access to the board document (docs/specs/sync.md rule 1).
///
/// The whole board is one unit: there is no per-row endpoint, because the
/// document is under 10 KB and a partial write would need a merge strategy
/// for no gain (docs/specs/locations.md, Repository Contract).
///
/// ```dart
/// final deviceZone = await engine.deviceZone();
/// final result = await repository.load(
///   homeZoneIdFallback: deviceZone.zoneId,
/// );
/// ```
// TODO(sync): M3 adds the remote half described in docs/specs/sync.md. Both
// methods grow a `userId`, `load` grows `forceRefresh` for the reconciling
// read, and `save` keeps returning success on a failed remote write (rules 2
// to 4). The signatures stay local-only until then rather than carrying a
// `userId` no implementation can use: there is no `AuthBloc` to resolve one
// from before M3.
abstract class BoardRepository {
  /// Reads the stored board, seeding and persisting an empty one when nothing
  /// has been written yet (sync.md, Provisioning).
  ///
  /// [homeZoneIdFallback] is consulted only on that first seeding and when
  /// the stored document has no `homeZoneId` at all. It is normally the
  /// device zone; a *stored* id the tzdata cannot resolve is kept as it is,
  /// so the grid can say so and the user can repair it, rather than being
  /// silently swapped for the device's.
  Future<Either<Failure, BoardEntity>> load({
    required String homeZoneIdFallback,
  });

  /// Persists [board] as given.
  ///
  /// Bumping `revision` and stamping `updatedAt` is the caller's job, so a
  /// re-save during sync reconciliation does not inflate the revision it is
  /// trying to reconcile.
  Future<Either<Failure, BoardEntity>> save(BoardEntity board);
}

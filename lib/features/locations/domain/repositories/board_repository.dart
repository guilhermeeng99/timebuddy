import 'package:dartz/dartz.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';

/// Local-first access to the board document (docs/specs/sync.md rule 1).
///
/// The whole board is one unit: there is no per-row endpoint, because the
/// document is under 10 KB and a partial write would need a merge strategy
/// for no gain (docs/specs/locations.md, Repository Contract).
///
/// **No method here takes a `userId`, and that is a decision, not an
/// omission.** The remote write that follows a local one needs an account id
/// (rule 2), but the account is session state: `SyncCoordinator`
/// (`lib/core/sync/sync_coordinator.dart`) holds it and the implementation
/// hands it the saved document. A `userId` in these signatures would travel
/// into every caller — the cubit, the settings page, the sync service's own
/// re-save — and make each of them resolve a session from `AuthBloc`.
///
/// ```dart
/// final deviceZone = await engine.deviceZone();
/// final result = await repository.load(
///   homeZoneIdFallback: deviceZone.zoneId,
/// );
/// ```
abstract class BoardRepository {
  /// Reads the stored board, seeding and persisting an empty one when nothing
  /// has been written yet (sync.md, Provisioning).
  ///
  /// Local only: the reconciling read belongs to `SyncService`, which owns the
  /// conflict ladder for both documents (rule 5) and writes the winner back
  /// here, so a screen calling this after a sync already reads the reconciled
  /// copy.
  ///
  /// [homeZoneIdFallback] is consulted only on that first seeding and when
  /// the stored document has no `homeZoneId` at all. It is normally the
  /// device zone; a *stored* id the tzdata cannot resolve is kept as it is,
  /// so the grid can say so and the user can repair it, rather than being
  /// silently swapped for the device's.
  Future<Either<Failure, BoardEntity>> load({
    required String homeZoneIdFallback,
  });

  /// Persists [board] as given, then pushes it to the account in the
  /// background (rule 2).
  ///
  /// Answers `Right` as soon as the *local* write lands. A failed remote write
  /// is never a `Left` (rule 4): it sets a dirty flag and is retried by
  /// `SyncService` on the next start, sync or resume (rule 3). A `Left` here
  /// therefore means one thing only — the device store refused the write, and
  /// the read path every screen depends on is broken.
  ///
  /// Bumping `revision` and stamping `updatedAt` is the caller's job, so a
  /// re-save during sync reconciliation does not inflate the revision it is
  /// trying to reconcile.
  Future<Either<Failure, BoardEntity>> save(BoardEntity board);
}

/// The sync layer's contract: the passive status, the reconciliation result,
/// and the service every caller talks to.
///
/// This file lives in `core/` although it names two feature entities. Sync is
/// the one place that reconciles *both* documents against one remote account,
/// and giving each feature a copy of the conflict ladder (docs/specs/sync.md
/// rule 5) would be two owners of one rule, which is how two owners disagree.
/// The dependency runs one way only: nothing under `features/` imports this.
library;

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

/// What the passive indicator in the sidebar and the profile page shows.
///
/// Passive is the whole point (sync.md rule 4): the user reordered two cities,
/// and a red banner about Firestore is noise. This stream is the *only*
/// channel through which a failed remote write ever reaches the UI.
enum SyncStatus {
  /// Nothing is in flight and the last attempt landed.
  idle,

  /// A sync or a dirty flush is running right now.
  syncing,

  /// The last remote call could not reach Firestore. Local keeps working, and
  /// whatever could not be uploaded stays dirty until the next attempt.
  offline,

  /// The last remote call was refused for a reason retrying will not fix:
  /// permission denied on a misconfigured rule set, a revoked account, or a
  /// local store that will not accept the reconciled document.
  error,
}

/// Which side of a reconciliation won, for one document.
///
/// Reported so the UI can say "your board was updated from another device"
/// once, rather than silently swapping the user's list out from under them
/// (sync.md, Contract).
enum ConflictWinner {
  /// The device's copy won and was uploaded.
  local,

  /// The server's copy won and overwrote the device's.
  remote,

  /// Both sides already said the same thing, so nothing was written.
  none,
}

/// The reconciled state of one account, and who won each document.
///
/// Both documents are always present: reconciliation cannot end without an
/// answer for each, because a missing remote document is a case of the ladder
/// (revision `-1`) rather than an absence (sync.md, Provisioning).
///
/// ```dart
/// boardCubit.adoptFromSync(outcome.board);
/// if (outcome.boardWinner == ConflictWinner.remote) {
///   context.showSnack(t.sync.boardUpdatedElsewhere);
/// }
/// ```
class SyncOutcome extends Equatable {
  const SyncOutcome({
    required this.board,
    required this.preferences,
    required this.boardWinner,
    required this.preferencesWinner,
  });

  /// The board both sides now hold.
  final BoardEntity board;

  /// The preferences both sides now hold.
  final PreferencesEntity preferences;

  /// Which side the board came from.
  final ConflictWinner boardWinner;

  /// Which side the preferences came from. Independent of [boardWinner]:
  /// `revision` is monotonic per document, not global (sync.md rule 7), so one
  /// document can be adopted from the server while the other is uploaded.
  final ConflictWinner preferencesWinner;

  @override
  List<Object?> get props => [
    board,
    preferences,
    boardWinner,
    preferencesWinner,
  ];
}

/// Reconciles the device's two JSON documents with the account's two Firestore
/// documents, and reports which side won.
///
/// Local is the read path and remote is the durability path (sync.md rule 1):
/// nothing here is in the critical path of a frame. Sync runs at startup, on
/// an explicit pull to refresh, and on resume — never on a timer and never
/// through a snapshot listener (rule 9), because a world clock does not need a
/// live feed of its own settings, and two documents per session is cost with
/// no benefit.
abstract class SyncService {
  /// Pulls both remote documents, reconciles them against the local copies,
  /// writes each winner to the side that lost, and hands back the result so
  /// callers do not re-read.
  ///
  /// The ladder, in this order and only this order (rule 5):
  ///
  /// 1. remote `revision` > local → remote wins, local is overwritten
  /// 2. local `revision` > remote → local wins, remote is overwritten
  /// 3. equal revisions, different content → the later `updatedAt` wins
  /// 4. equal revisions, equal `updatedAt` → remote wins, arbitrarily but
  ///    stably, so two devices reach the same answer
  ///
  /// A missing remote document counts as `revision: -1`, so local always wins
  /// it and is written up. First sign-in provisioning is therefore this
  /// method, not a code path of its own (sync.md, Provisioning).
  ///
  /// Answers [Left] when the remote read failed, or when the local store
  /// refused the reconciled document — that one breaks the read path, so it
  /// is surfaced. A failed remote *write* is never an error (rule 4): the
  /// outcome still comes back, the document is marked dirty, and [status]
  /// carries the bad news.
  ///
  /// ```dart
  /// final result = await syncService.sync(userId: userId);
  /// result.fold(
  ///   (failure) => emit(
  ///     StartupAuthenticated(userId: userId, syncFailed: true),
  ///   ),
  ///   (outcome) => boardCubit.adoptFromSync(outcome.board),
  /// );
  /// ```
  Future<Either<Failure, SyncOutcome>> sync({required String userId});

  /// Uploads only the documents whose last remote write failed, and clears
  /// their flag when it lands. Called on `AppLifecycleState.resumed`.
  ///
  /// Costs zero reads and emits no status when nothing is dirty, so putting it
  /// on every resume is free. It never throws and never reports: a flush that
  /// fails again leaves the flag set for the next attempt (rules 3 and 4).
  Future<void> flushDirty({required String userId});

  /// Wipes the two local documents and both dirty flags.
  ///
  /// Called on sign-out and on account deletion (rule 10). The flags go with
  /// the documents deliberately: a pending write belonging to the account that
  /// just signed out must not be flushed into the next session, which would
  /// hand one user's cities to the next.
  Future<void> clearLocalData();

  /// The passive status, replayed to every new listener so an indicator that
  /// mounts after a failed startup sync does not sit on [SyncStatus.idle]
  /// while the app is offline.
  Stream<SyncStatus> get status;
}

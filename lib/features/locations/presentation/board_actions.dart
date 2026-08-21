/// Every way a screen may edit the saved board, in one place
/// (docs/specs/locations.md).
///
/// These used to be private methods on `LocationsPage`, which was the only
/// screen that could edit the board. It is gone: the grid owns the board now,
/// and the world clock reorders it too, so the same three mutations have two
/// callers and one of them would otherwise be a copy. A copy is how the undo
/// window ends up five seconds on one screen and four on the other.
///
/// **They take a `BuildContext` and return nothing.** Each one is a complete
/// interaction — mutate, and say so if it was refused — rather than a value a
/// caller has to remember to report on. `BoardCubit` answers a refusal as a
/// one-shot `Failure?` precisely so the screen that asked is the only one that
/// hears about it, and a helper that handed the failure back would put that
/// duty back on every call site.
///
/// ```dart
/// onTap: () => unawaited(openLocationRowActions(
///   context,
///   location: row.location,
///   isHome: row.isHome,
/// )),
/// ```
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/locations/presentation/pages/add_location_sheet.dart';
import 'package:timebuddy/features/locations/presentation/widgets/row_actions_sheet.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// How long the undo offer stays on screen after a removal.
///
/// Five seconds, and no confirmation dialog in front of it
/// (docs/specs/locations.md rule 7): removing a city is the most common edit
/// on the board and it is cheap to reverse, so the cost belongs on the rare
/// mistake rather than on every deliberate removal.
const Duration boardUndoWindow = Duration(seconds: 5);

/// Moves a row and reports a refusal.
///
/// Both indices are already final positions: `ReorderableListView`'s
/// `onReorderItem` adjusts the destination for the dragged row having been
/// lifted out, which the obsolete `onReorder` did not — it reported the
/// insertion point with the row still counted, so every downward move arrived
/// one too far and needed a correction at the call site. Taking them as they
/// are deletes the bug that correction could hide.
Future<void> reorderBoardRow(
  BuildContext context, {
  required int oldIndex,
  required int newIndex,
}) async {
  if (newIndex == oldIndex) return;
  await _write(context, (cubit) => cubit.reorder(oldIndex, newIndex));
}

/// Opens one row's action sheet and carries out what the user picked.
///
/// [isHome] only decides how "set as home" is marked; the sheet never hides a
/// row, because an action list whose entries move between openings is one a
/// thumb cannot learn.
Future<void> openLocationRowActions(
  BuildContext context, {
  required SavedLocationEntity location,
  required bool isHome,
}) async {
  final action = await showLocationRowActionsSheet(
    context,
    label: location.label,
    isHome: isHome,
  );
  if (action == null) return;
  // The sheet was open across an await; the row under it may have been
  // rebuilt away by a sync landing in the meantime.
  if (!context.mounted) return;
  switch (action) {
    case LocationRowAction.setHome:
      // Home is a zone id, not a row, so this leaves the order untouched
      // (docs/specs/locations.md rule 3) and only moves the badge.
      await _write(context, (cubit) => cubit.setHome(location.zoneId));
    case LocationRowAction.replaceZone:
      await showAddLocationSheet(context, replaces: location);
    case LocationRowAction.remove:
      await removeLocationWithUndo(context, location);
  }
}

/// Points the board at a new reference zone, and reports a refusal.
///
/// Home is a zone id, not a row (docs/specs/locations.md rule 3), so the order
/// is untouched and only what every offset is measured from moves.
Future<void> setBoardHome(BuildContext context, String zoneId) =>
    _write(context, (cubit) => cubit.setHome(zoneId));

/// Takes a row off the board and offers the undo window back.
Future<void> removeLocationWithUndo(
  BuildContext context,
  SavedLocationEntity location,
) async {
  final cubit = context.read<BoardCubit>();
  // Both resolved before the await: the row is gone by the time the write
  // returns, and with it any context lookup made from inside its subtree.
  final messenger = ScaffoldMessenger.of(context);
  final barClearance = _barClearance(context);
  final failure = await cubit.removeLocation(location.id);
  // The write was refused and the cubit rolled the board back, so the row is
  // still there. Offering to undo a removal that never happened would put the
  // board one accepted tap away from being wrong.
  if (failure != null) {
    _snack(messenger, failure);
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(t.locations.removed(city: location.label)),
        duration: boardUndoWindow,
        action: SnackBarAction(
          label: t.locations.undo,
          onPressed: () => unawaited(_restore(cubit, messenger)),
        ),
        // Floating only when there is a bar to clear, because a floating
        // snackbar on a desktop would hover for no reason.
        behavior: barClearance == null
            ? SnackBarBehavior.fixed
            : SnackBarBehavior.floating,
        margin: barClearance == null
            ? null
            : EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: barClearance,
              ),
      ),
    );
}

/// How far a snackbar has to be lifted to clear the floating bottom bar, or
/// `null` when there is no bar on screen.
///
/// A default `SnackBar` is fixed to the bottom of the *page's* `Scaffold`, and
/// `TimeBuddyBottomBar` is not in that Scaffold — it is an `Align` in
/// `AppShell`'s `Stack`, painted above it, reserving
/// `TimeBuddyBottomBar.reservedHeight`. So an unlifted snackbar lands
/// underneath the pill, and with it the **Undo** button.
///
/// That was cosmetic while the board had a page of its own to be undone from.
/// It is not any more: the grid is the only place a removal happens, and an
/// undo the user can see and cannot press is worse than no undo at all
/// (design_system §9).
///
/// Gated on the same two conditions as `LiftedFab`, because they describe the
/// same fact — whether the bar is actually on screen — and measured with
/// `bottomSafeForBar` rather than a literal, so retuning the bar moves both.
double? _barClearance(BuildContext context) {
  if (!ResponsiveLayout.isMobile(context)) return null;
  if (subPageDepth.value > 0) return null;
  return bottomSafeForBar(context, isSubPage: false);
}

/// Puts the removed row back, or says why it could not go back.
///
/// The undo window is the user's, so the board can have changed underneath:
/// `undoRemove` legitimately answers `BoardFullFailure` or
/// `DuplicateZoneFailure` if another device or another tap got there first,
/// and those are exactly the two refusals worth naming.
Future<void> _restore(
  BoardCubit cubit,
  ScaffoldMessengerState messenger,
) async {
  final failure = await cubit.undoRemove();
  if (failure != null) _snack(messenger, failure);
}

/// Runs one board mutation and reports a refusal.
///
/// Every mutation goes through `BoardCubit` and every one of them can be
/// refused by the local write; swallowing that would leave the user looking at
/// an order or a home badge that is not what got saved.
Future<void> _write(
  BuildContext context,
  Future<Failure?> Function(BoardCubit cubit) mutate,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final failure = await mutate(context.read<BoardCubit>());
  if (failure != null) _snack(messenger, failure);
}

/// Uses the messenger captured before the write rather than a context read
/// after it: the row that owned that context may no longer be mounted.
void _snack(ScaffoldMessengerState messenger, Failure failure) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(boardWriteFailureMessage(failure))),
    );
}

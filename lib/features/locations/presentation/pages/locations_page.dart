import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/feature_empty_state.dart';
import 'package:timebuddy/app/widgets/lifted_fab.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/locations/presentation/pages/add_location_sheet.dart';
import 'package:timebuddy/features/locations/presentation/widgets/location_list_tile.dart';
import 'package:timebuddy/features/locations/presentation/widgets/row_actions_sheet.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// How long the undo offer stays on screen after a removal.
///
/// Five seconds, and no confirmation dialog in front of it
/// (docs/specs/locations.md rule 7): removing a city is the most common edit
/// on the board and it is cheap to reverse, so the cost belongs on the rare
/// mistake rather than on every deliberate removal.
const Duration _undoWindow = Duration(seconds: 5);

/// Placeholder rows shown while the board is being read.
const int _loadingRowCount = 5;

/// The board: every saved city, in the order the user put them in.
///
/// A primary destination, so it renders inside the shell and carries no
/// `SubPageScope`. It holds no board state of its own — the list comes from
/// `BoardCubit` and every mutation goes back through it, which is what keeps
/// this page and the grid showing the same order (docs/specs/locations.md).
class LocationsPage extends StatelessWidget {
  const LocationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(title: t.locations.title),
      floatingActionButton: LiftedFab(
        child: FloatingActionButton(
          tooltip: t.locations.addTitle,
          onPressed: () => unawaited(showAddLocationSheet(context)),
          child: const Icon(Icons.add),
        ),
      ),
      body: BlocBuilder<BoardCubit, BoardState>(builder: _bodyFor),
    );
  }

  /// Early returns rather than a switch over `BoardState`: this page draws
  /// two of its states, and everything before the first board arrives —
  /// initial, loading, and whatever a later milestone adds — is one
  /// placeholder.
  Widget _bodyFor(BuildContext context, BoardState state) {
    if (state is BoardError) {
      return ErrorView(
        failure: state.failure,
        onRetry: () => unawaited(context.read<BoardCubit>().load()),
      );
    }
    if (state is! BoardLoaded) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: LoadingShimmer(rowCount: _loadingRowCount),
      );
    }
    // An empty board is a valid state, not an error (rule 6).
    if (state.board.locations.isEmpty) return const _EmptyBoard();
    return _BoardList(board: state.board, unresolvedIds: state.unresolvedIds);
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return FeatureEmptyState(
      icon: Icons.public_outlined,
      title: t.locations.emptyTitle,
      message: t.locations.emptyMessage,
      ctaLabel: t.locations.emptyCta,
      onCta: () => unawaited(showAddLocationSheet(context)),
    );
  }
}

class _BoardList extends StatelessWidget {
  const _BoardList({required this.board, required this.unresolvedIds});

  final BoardEntity board;

  /// Zones the tzdata no longer knows. Their rows stay on the board, greyed
  /// and repairable (rule 11).
  final Set<String> unresolvedIds;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.maxContentWidth,
        ),
        child: ReorderableListView.builder(
          // The tile supplies both drag affordances itself: the default
          // handle is an overlay pinned to the trailing edge, which would sit
          // on top of the row's own controls on desktop.
          buildDefaultDragHandles: false,
          header: _BoardHeader(count: board.locations.length),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            // The FAB floats over the list, so the last city needs room to
            // clear it (design_system §7).
            bottomSafeForFab(context, isSubPage: false),
          ),
          itemCount: board.locations.length,
          onReorderItem: (oldIndex, newIndex) =>
              _reorder(context, oldIndex, newIndex),
          itemBuilder: _tileFor,
        ),
      ),
    );
  }

  Widget _tileFor(BuildContext context, int index) {
    final location = board.locations[index];
    final isHome = location.zoneId == board.homeZoneId;
    return LocationListTile(
      // Keyed by the row's own id, not by its position: a reorder moves the
      // element, and a positional key would animate the wrong tile.
      key: ValueKey<String>(location.id),
      index: index,
      location: location,
      isHome: isHome,
      // Keyed by zone, because that is what failed to resolve: the set holds
      // zone ids, not row ids (`BoardLoaded.unresolvedIds`).
      isUnresolved: unresolvedIds.contains(location.zoneId),
      onOpenActions: () => unawaited(
        _openActions(context, location: location, isHome: isHome),
      ),
    );
  }

  void _reorder(BuildContext context, int oldIndex, int newIndex) {
    // `onReorderItem`, not the deprecated `onReorder`: it hands over the
    // destination already adjusted for the dragged row being lifted out, so
    // both indices are final positions and the board can take them as they
    // are. The old callback reported the insertion point with the row still
    // counted, which made every downward move arrive one too far and forced a
    // correction here. Deleting that correction deletes the bug it could hide.
    if (newIndex == oldIndex) return;
    unawaited(_write(context, (cubit) => cubit.reorder(oldIndex, newIndex)));
  }

  Future<void> _openActions(
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
        // Home is a zone id, not a row, so this leaves the list untouched
        // (rule 3) and only moves the badge.
        unawaited(_write(context, (cubit) => cubit.setHome(location.zoneId)));
      case LocationRowAction.replaceZone:
        unawaited(showAddLocationSheet(context, replaces: location));
      case LocationRowAction.remove:
        unawaited(_removeWithUndo(context, location));
    }
  }

  Future<void> _removeWithUndo(
    BuildContext context,
    SavedLocationEntity location,
  ) async {
    final cubit = context.read<BoardCubit>();
    // Resolved before the await: the row is gone by the time the write
    // returns, and with it any context lookup made from inside its subtree.
    final messenger = ScaffoldMessenger.of(context);
    final failure = await cubit.removeLocation(location.id);
    // The write was refused and the cubit rolled the board back, so the row
    // is still there. Offering to undo a removal that never happened would
    // put the board one accepted tap away from being wrong.
    if (failure != null) {
      _snack(messenger, failure);
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(t.locations.removed(city: location.label)),
          duration: _undoWindow,
          action: SnackBarAction(
            label: t.locations.undo,
            onPressed: () => unawaited(_restore(cubit, messenger)),
          ),
        ),
      );
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
  /// Every mutation on this page goes through `BoardCubit` and every one of
  /// them can be refused by the local write; swallowing that would leave the
  /// user looking at an order or a home badge that is not what got saved.
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
}

/// How full the board is, and how to reorder it.
///
/// The count is stated against the cap rather than on its own: a user who
/// meets `BoardFullFailure` at the twenty-first city should have been able to
/// see it coming (rule 4).
class _BoardHeader extends StatelessWidget {
  const _BoardHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.locations.countLabel(count: count, max: BoardEntity.maxLocations),
            style: context.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            t.locations.reorderHint,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.appColors.onBackgroundLight,
            ),
          ),
        ],
      ),
    );
  }
}

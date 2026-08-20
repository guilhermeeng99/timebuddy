import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// One draggable row of the locations board.
///
/// The identity block itself is the shared [LocationRow], so this row and the
/// grid's pinned label column cannot drift apart. What this widget adds is the
/// two things only the list has: the drag affordances that feed
/// `ReorderableListView`, and the tap that opens the row's action sheet.
///
/// It renders state and reports intent; it never writes the board. Every
/// mutation belongs to `BoardCubit` (docs/specs/locations.md).
///
/// ```dart
/// LocationListTile(
///   key: ValueKey(location.id),
///   index: index,
///   location: location,
///   isHome: location.zoneId == board.homeZoneId,
///   isUnresolved: unresolvedIds.contains(location.zoneId),
///   onOpenActions: () => _openActions(context, location),
/// );
/// ```
class LocationListTile extends StatelessWidget {
  const LocationListTile({
    required this.index,
    required this.location,
    required this.isHome,
    required this.isUnresolved,
    required this.onOpenActions,
    super.key,
  });

  /// Position in the list, as `ReorderableListView` numbers it. Both drag
  /// listeners need it to tell the list which row started moving.
  final int index;

  final SavedLocationEntity location;

  /// Whether this row's zone is the board's reference zone. Drawn as a badge
  /// by [LocationRow]; the row is otherwise ordinary, since home is a zone id
  /// and not a position (docs/specs/locations.md rule 3).
  final bool isHome;

  /// Whether the tzdata no longer knows this row's zone. The row stays on the
  /// board, greyed and labelled, because dropping it would delete user data
  /// without consent (rule 11).
  final bool isUnresolved;

  /// Opens the row's action sheet: set as home, replace zone, remove.
  final VoidCallback onOpenActions;

  @override
  Widget build(BuildContext context) {
    // Long-press anywhere on the row starts a drag, which is what
    // `t.locations.reorderHint` promises and what a thumb reaches for first.
    // The explicit handle below starts one immediately, for a mouse and for
    // anyone who never discovers the long press.
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpenActions,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _Identity(
                      location: location,
                      isHome: isHome,
                      isUnresolved: isUnresolved,
                    ),
                  ),
                  _DragHandle(index: index),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.location,
    required this.isHome,
    required this.isUnresolved,
  });

  final SavedLocationEntity location;
  final bool isHome;
  final bool isUnresolved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocationRow(
          location: location,
          isHome: isHome,
          isUnresolved: isUnresolved,
        ),
        // The note is the list's copy, not the grid's: this screen offers the
        // repair, so it says the zone is gone rather than only marking the row.
        if (isUnresolved) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            t.locations.unresolvedZone,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.appColors.warning,
            ),
          ),
        ],
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(
          Icons.drag_indicator,
          color: context.appColors.onBackgroundLight,
        ),
      ),
    );
  }
}

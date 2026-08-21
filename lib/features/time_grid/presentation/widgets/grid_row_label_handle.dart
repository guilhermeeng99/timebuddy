import 'package:flutter/material.dart';

/// The pinned label column, wearing the row's two gestures.
///
/// **Which lift gesture depends on the pointer, and that is not a detail.**
/// `ReorderableListView`'s own default handles make the same split: a mouse
/// drags immediately, because a long-press before a drag on a desktop reads as
/// the app being slow; a finger has to press and hold, because an immediate
/// lift would steal every vertical scroll of the grid the moment it started
/// over a label.
///
/// The tap underneath survives either one: neither drag recognizer claims a
/// pointer that never moved.
///
/// [index] is the row's position in the `ReorderableListView` the drag reports
/// to; [onTap] opens that row's actions; [child] is the label itself.
///
/// ```dart
/// GridRowLabelHandle(
///   index: rowIndex,
///   onTap: () => openRowActions(context, location),
///   child: LocationRow(location: location),
/// );
/// ```
class GridRowLabelHandle extends StatelessWidget {
  const GridRowLabelHandle({
    required this.index,
    required this.onTap,
    required this.child,
    super.key,
  });

  final int index;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `opaque`, so the whole column answers the tap rather than only the
    // pixels `LocationRow` happens to paint on.
    //
    // `TooltipVisibility(visible: false)` is what makes the lift reachable
    // everywhere on the column. `LocationRow`'s unresolved-zone mark carries a
    // `Tooltip`, whose own `LongPressGestureRecognizer` sits deeper than this
    // widget's and would therefore win the long press on exactly those 14
    // pixels — a dead spot for the drag that moves around as rows resolve and
    // stop resolving. Nothing is lost: the glyph keeps its `semanticLabel`,
    // and the repair the tooltip only described is now a tap away in the
    // actions sheet.
    final tappable = TooltipVisibility(
      visible: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
    return switch (Theme.of(context).platform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => ReorderableDragStartListener(
        index: index,
        child: tappable,
      ),
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => ReorderableDelayedDragStartListener(
        index: index,
        child: tappable,
      ),
    };
  }
}

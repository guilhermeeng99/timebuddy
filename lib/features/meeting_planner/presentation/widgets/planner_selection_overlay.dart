import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';

/// The selected hours, painted as one band across every row of the grid
/// (docs/specs/meeting_planner.md, UI).
///
/// A sibling of `GridNowMarker` and built the same way, for the same reason:
/// it sits in the grid's `Stack` over the hour track, reads the shared scroll
/// position as a [ValueListenable], and hands both to a painter as its
/// `repaint` signal. A drag that emitted `PlannerSelecting` sixty times a
/// second would otherwise rebuild every row of a twenty-city board sixty
/// times a second, and none of those rows would look any different.
///
/// **It paints one band, not one rectangle per column.** Rule 2 says the
/// selection is made in the reference zone's columns and applies to every
/// row, so a continuous band with rounded caps at the two ends is the shape
/// that says "these hours, everywhere" — a per-column fill would read as a
/// row of separate cells the user picked one by one.
///
/// It draws nothing at all when there is no selection, so the grid page can
/// leave it mounted for the whole of planner mode.
///
/// ```dart
/// Positioned(
///   left: labelWidth,
///   top: 0,
///   right: 0,
///   bottom: 0,
///   child: PlannerSelectionOverlay(
///     slots: model.slots,
///     selection: plannerState.activeSelection,
///     horizontalOffset: hourOffset,
///     color: context.appColors.primary,
///   ),
/// );
/// ```
class PlannerSelectionOverlay extends StatelessWidget {
  const PlannerSelectionOverlay({
    required this.slots,
    required this.selection,
    required this.horizontalOffset,
    required this.color,
    super.key,
  });

  /// The grid's shared column instants, ascending: `GridViewModel.slots`.
  ///
  /// The band's first column is looked up in this list rather than counted
  /// off the window's start, so a selection built against a window that has
  /// since moved paints nothing instead of painting the wrong hours.
  final List<DateTime> slots;

  /// The range to paint, or `null` for none.
  ///
  /// Takes `MeetingPlannerState.activeSelection`, which answers for a drag in
  /// progress and for a settled selection alike: the columns under the finger
  /// are the meeting either way.
  final MeetingSelection? selection;

  /// Current scroll offset of the shared hour track, in pixels.
  final ValueListenable<double> horizontalOffset;

  /// Band colour. Always `primary` in the grid; a parameter so the widget
  /// holds no palette opinion of its own.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final range = selection;
    final startColumn = range == null
        ? null
        : _columnHolding(range.startInstant);
    if (range == null || startColumn == null) return const SizedBox.shrink();

    // Never a hit target. The band lies over the cells the user is still
    // dragging across, and a gesture it swallowed would end the selection it
    // is drawing.
    return IgnorePointer(
      child: CustomPaint(
        painter: _SelectionBandPainter(
          startColumn: startColumn,
          columnCount: range.slotCount,
          horizontalOffset: horizontalOffset,
          color: color,
        ),
      ),
    );
  }

  /// The column whose hour contains [instant], or `null` when it falls
  /// outside the window.
  int? _columnHolding(DateTime instant) {
    for (var index = 0; index < slots.length; index++) {
      final slot = slots[index];
      final slotEnd = slot.add(MeetingSelection.slotDuration);
      if (!instant.isBefore(slot) && instant.isBefore(slotEnd)) return index;
    }
    return null;
  }
}

/// Paints `columnCount` columns from [startColumn], shifted by the track's
/// scroll offset.
class _SelectionBandPainter extends CustomPainter {
  _SelectionBandPainter({
    required this.startColumn,
    required this.columnCount,
    required this.horizontalOffset,
    required this.color,
  }) : super(repaint: horizontalOffset);

  /// Spec: `primary` at 16%. Above the hour cells' own 12% band fill, so the
  /// selection reads over a `good` column, and low enough that the hour
  /// digits underneath stay legible in both palettes.
  static const double _fillAlpha = 0.16;

  final int startColumn;
  final int columnCount;
  final ValueListenable<double> horizontalOffset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // STALE, and knowingly so: the grid stopped using a constant column width
    // (docs/specs/time_grid.md rule 12) and resolves one per surface through
    // `GridLayout`. This overlay has had no entry point since the Compare/Plan
    // toggle was removed, so it was left compiling rather than half-migrated —
    // but reviving the planner means taking `columnWidth` as a parameter here,
    // the way `GridNowMarker` does, or the band will sit on the wrong hours at
    // every width but one.
    final left =
        startColumn * GridMetrics.hourColumnWidth - horizontalOffset.value;
    final right = left + columnCount * GridMetrics.hourColumnWidth;
    if (right < 0 || left > size.width) return;

    canvas
      ..save()
      // A band that starts left of the viewport has to be cut off at it: the
      // canvas is not clipped by default, and the grid's pinned label column
      // is the widget immediately to the left of this one.
      ..clipRect(Offset.zero & size)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, 0, right, size.height),
          const Radius.circular(AppRadius.sm),
        ),
        Paint()..color = color.withValues(alpha: _fillAlpha),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SelectionBandPainter oldDelegate) =>
      oldDelegate.startColumn != startColumn ||
      oldDelegate.columnCount != columnCount ||
      oldDelegate.color != color ||
      oldDelegate.horizontalOffset != horizontalOffset;
}

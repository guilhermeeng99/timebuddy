import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/features/time_grid/domain/entities/grid_view_model.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The hour track of one board row: the cells to the right of the pinned
/// label column.
///
/// **It does not scroll.** The header strip owns the grid's only horizontal
/// `Scrollable`, and every row reads that position from [horizontalOffset] and
/// draws the columns the viewport can currently see. Two consequences, both
/// deliberate: the rows can never drift out of lockstep with the header, and a
/// 20-row board with a 30-slot window builds roughly the eight columns on
/// screen per visible row instead of six hundred (time_grid.md, Performance).
///
/// Dragging horizontally over the rows therefore moves the cursor rather than
/// scrolling the track, which is what the Interaction table asks for.
///
/// ```dart
/// GridRowView(
///   row: model.rows[index],
///   cursorInstant: model.cursorInstant,
///   horizontalOffset: hourOffset,
///   onCellTap: context.read<TimeGridCubit>().setCursor,
/// );
/// ```
class GridRowView extends StatelessWidget {
  const GridRowView({
    required this.row,
    required this.horizontalOffset,
    required this.onCellTap,
    this.cursorInstant,
    super.key,
  });

  final GridRow row;

  /// Scroll offset of the shared hour track, in pixels.
  final ValueListenable<double> horizontalOffset;

  /// Called with the tapped cell's UTC instant.
  final ValueChanged<DateTime> onCellTap;

  /// The slot every row highlights, or `null` when there is no cursor.
  final DateTime? cursorInstant;

  @override
  Widget build(BuildContext context) {
    // Rule 14: an unresolved zone keeps its board position and shows no hours,
    // because a greyed row is a prompt to fix it and a missing row is silent
    // data loss.
    if (row.isUnresolved) return const _UnresolvedTrack();

    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<double>(
        valueListenable: horizontalOffset,
        builder: (context, offset, _) => _CellWindow(
          cells: row.cells,
          offset: offset,
          viewportWidth: constraints.maxWidth,
          cursorInstant: cursorInstant,
          onCellTap: onCellTap,
        ),
      ),
    );
  }
}

/// The slice of [cells] the viewport can see at [offset].
class _CellWindow extends StatelessWidget {
  const _CellWindow({
    required this.cells,
    required this.offset,
    required this.viewportWidth,
    required this.cursorInstant,
    required this.onCellTap,
  });

  final List<GridCell> cells;
  final double offset;
  final double viewportWidth;
  final DateTime? cursorInstant;
  final ValueChanged<DateTime> onCellTap;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty || viewportWidth <= 0) return const SizedBox.shrink();
    const columnWidth = GridMetrics.hourColumnWidth;
    final first = math.max(0, (offset / columnWidth).floor());
    final last = math.min(
      cells.length - 1,
      ((offset + viewportWidth) / columnWidth).ceil(),
    );
    if (last < first) return const SizedBox.shrink();

    return ClipRect(
      child: Stack(
        children: [
          for (var index = first; index <= last; index++)
            Positioned(
              left: index * columnWidth - offset,
              top: 0,
              bottom: 0,
              width: columnWidth,
              child: _GridCellView(
                cell: cells[index],
                isCursor: cursorInstant == cells[index].instant,
                onTap: () => onCellTap(cells[index].instant),
              ),
            ),
        ],
      ),
    );
  }
}

/// One cell: the hour surface plus the two per-row marks that sit on top of
/// it, the day boundary and the DST change.
class _GridCellView extends StatelessWidget {
  const _GridCellView({
    required this.cell,
    required this.isCursor,
    required this.onTap,
  });

  final GridCell cell;
  final bool isCursor;
  final VoidCallback onTap;

  static const double _dayRuleWidth = 1;
  static const double _dayRuleAlpha = 0.4;
  static const double _dateFontSize = 9;
  static const double _transitionDotSize = 5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dateLabel = cell.dateLabel;

    return Stack(
      fit: StackFit.expand,
      children: [
        HourCell(
          hour: cell.localTime.hour,
          band: cell.band,
          // Passed unconditionally: `HourCell` renders the minutes only when
          // they are non-zero, and that is per cell rather than per row
          // because Lord Howe grows its `:30` halfway through a row (rule 5).
          minute: cell.localTime.minute,
          isCursor: isCursor,
          onTap: onTap,
        ),
        if (cell.isDayStart)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _dayRuleWidth,
            child: ColoredBox(
              color: colors.onBackgroundLight.withValues(alpha: _dayRuleAlpha),
            ),
          ),
        // Rule 6: the label belongs to *this row's* boundary, so rows near the
        // date line carry it in different columns and no global header could
        // stand in for it.
        if (dateLabel != null)
          Positioned(
            left: AppSpacing.xs,
            right: 0,
            top: AppSpacing.xs,
            child: Text(
              dateLabel,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: context.textTheme.labelSmall?.copyWith(
                fontSize: _dateFontSize,
                fontWeight: FontWeight.w600,
                color: colors.onBackgroundLight,
              ),
            ),
          ),
        if (cell.hasTransition)
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.sm,
            child: Center(
              child: Tooltip(
                message: t.grid.dstTransitionHere,
                child: SizedBox(
                  width: _transitionDotSize,
                  height: _transitionDotSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The track of a row whose zone the tzdata no longer knows (rule 14).
class _UnresolvedTrack extends StatelessWidget {
  const _UnresolvedTrack();

  static const double _fillAlpha = 0.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ColoredBox(
      color: colors.surfaceVariant.withValues(alpha: _fillAlpha),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            t.grid.unresolvedRow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall?.copyWith(
              color: colors.onBackgroundLight,
            ),
          ),
        ),
      ),
    );
  }
}

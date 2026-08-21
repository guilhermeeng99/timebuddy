import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
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
/// Not scrolling itself does not make it unpannable: the page's own
/// horizontal drag over these rows drives the header's `ScrollPosition`
/// directly, so a finger dragged across the hours moves the track with its
/// physics — fling included — while the rows go on painting at the offset
/// that position publishes.
///
/// The cells carry **no tap handler**, and that is the point of the trade:
/// the cursor is set from the ruler above (time_grid.md rule 8), which leaves
/// every pixel of the track free for the pan.
///
/// ```dart
/// GridRowView(
///   row: model.rows[index],
///   columnWidth: layout.hourColumnWidth,
///   cursorInstant: model.cursorInstant,
///   horizontalOffset: hourOffset,
/// );
/// ```
class GridRowView extends StatelessWidget {
  const GridRowView({
    required this.row,
    required this.columnWidth,
    required this.horizontalOffset,
    this.cursorInstant,
    super.key,
  });

  final GridRow row;

  /// Width of one hour column, resolved from the surface by `GridLayout`.
  ///
  /// Required rather than defaulted to `GridMetrics.hourColumnWidth`: every
  /// pixel-to-hour formula in the grid has to agree with the header strip's
  /// `itemExtent`, and a default is how one caller ends up half a column out
  /// of step with the ruler above it.
  final double columnWidth;

  /// Scroll offset of the shared hour track, in pixels.
  final ValueListenable<double> horizontalOffset;

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
          columnWidth: columnWidth,
          offset: offset,
          viewportWidth: constraints.maxWidth,
          cursorInstant: cursorInstant,
        ),
      ),
    );
  }
}

/// The slice of [cells] the viewport can see at [offset].
class _CellWindow extends StatelessWidget {
  const _CellWindow({
    required this.cells,
    required this.columnWidth,
    required this.offset,
    required this.viewportWidth,
    required this.cursorInstant,
  });

  final List<GridCell> cells;
  final double columnWidth;
  final double offset;
  final double viewportWidth;
  final DateTime? cursorInstant;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty || viewportWidth <= 0 || columnWidth <= 0) {
      return const SizedBox.shrink();
    }
    // Still a window rather than the whole row, even though a wide monitor now
    // fits every slot: the moment it does, `first` is 0 and `last` is the last
    // index, so the clamp costs two comparisons and keeps paying for itself on
    // every narrower screen (docs/specs/time_grid.md, Performance).
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
  const _GridCellView({required this.cell, required this.isCursor});

  final GridCell cell;
  final bool isCursor;

  static const double _dayRuleWidth = 1;
  static const double _dayRuleAlpha = 0.4;
  static const double _dateFontSize = 9;
  static const double _transitionDotSize = 5;

  /// The hour, its band, and whichever of the two marks this cell carries.
  ///
  /// Built as a list joined with ", " rather than as a sentence per case:
  /// four cases would be four strings to translate and three of them would
  /// differ only in what they append.
  String get _semanticLabel {
    final parts = <String>[
      t.common.hourInBand(
        hour: formatGridHour(cell.localTime),
        band: HourCell.bandLabel(cell.band),
      ),
      // The same words the marks carry visually: the date label the cell
      // already prints, and the tooltip on the dot.
      ?cell.dateLabel,
      if (cell.hasTransition) t.grid.dstTransitionHere,
    ];
    return parts.join(', ');
  }

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
          // The two marks below are drawn *over* the cell, so `HourCell`
          // cannot see them and cannot name them. Both are facts a sighted
          // user reads off a 1px rule and a 5px dot; a screen reader gets
          // them here or not at all.
          semanticLabel: _semanticLabel,
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
                      color: colors.warningInk,
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

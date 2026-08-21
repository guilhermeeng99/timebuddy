import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';

/// The grid's geometry for one surface width: how wide the pinned column is,
/// how wide an hour column is, and how many of them the track holds.
///
/// **The hour column is resolved at layout time, not declared as a constant.**
/// It used to be a flat `GridMetrics.hourColumnWidth`, which meant narrowing
/// the window changed nothing about the grid except how much of it was cut
/// off — the last column was sliced through the middle of its digits and the
/// rest was simply gone. Now the track is divided into a whole number of equal
/// columns, so it is always filled edge to edge and a resize *adds or removes
/// hours* instead of clipping one.
///
/// Two bounds keep that from becoming the thing this project already rejected
/// once (`GridMetrics.hourColumnWidth`, the 44pt era):
///
/// * [minColumnWidth] is the floor, and it is measured rather than chosen. The
///   binding constraint is not the hour digits (`05:45` is 40pt of Inter at
///   15pt) but the per-row date label — `Wed 28` is ~36pt at 9pt including its
///   inset, and it clips from the *right*, so a column below that silently
///   prints `Wed 2` and hands the user a wrong date that looks deliberate. 48
///   clears both and is also Material's minimum tap target, which every cell
///   is.
/// * [maxColumnWidth] only ever bites on an ultrawide monitor, where dividing
///   a 3000pt track by 30 slots would otherwise give absurd columns.
///
/// Below the floor the grid scrolls, exactly as it always has. **That part is
/// not a compromise, it is arithmetic**: thirty slots at the smallest legible
/// width need a **1440pt track** — a 1620pt grid box once the pinned column is
/// paid for, and about 1860pt of window once a desktop's 240pt rail is too —
/// so no phone will ever show a whole day at once, and a layout that claimed
/// to would be showing unreadable digits.
///
/// ```dart
/// final layout = GridLayout.resolve(
///   availableWidth: constraints.maxWidth,
///   slotCount: model.slots.length,
///   dense: ResponsiveLayout.isMobile(context),
/// );
/// SizedBox(width: layout.labelColumnWidth);
/// ```
@immutable
class GridLayout {
  const GridLayout({
    required this.labelColumnWidth,
    required this.hourColumnWidth,
    required this.visibleColumns,
    required this.trackWidth,
  });

  /// Resolves the geometry for a grid box [availableWidth] wide showing
  /// [slotCount] slots.
  ///
  /// [dense] is the phone form of the pinned column, and it stays a predicate
  /// about the *window* rather than about this box: it also drops the country
  /// line and the zone abbreviation, which are content decisions, not width
  /// arithmetic.
  factory GridLayout.resolve({
    required double availableWidth,
    required int slotCount,
    required bool dense,
  }) {
    final labelWidth = dense
        ? denseLabelColumnWidth
        : GridMetrics.labelColumnWidth;
    // The pinned column never starves the track: on a split-screen Android
    // window or a narrow desktop pane the label yields rather than the hours
    // disappearing behind a negative-width `Expanded`.
    final resolvedLabel = math.min<double>(
      labelWidth,
      math.max<double>(0, availableWidth),
    );
    final track = math.max<double>(0, availableWidth - resolvedLabel);
    if (track <= 0 || slotCount <= 0) {
      return GridLayout(
        labelColumnWidth: resolvedLabel,
        hourColumnWidth: minColumnWidth,
        visibleColumns: 0,
        trackWidth: 0,
      );
    }

    // The most whole columns that still clear the floor, then share the track
    // between exactly those. Dividing by the *floor* rather than by a target
    // width is what maximises the hours on screen; dividing the remainder back
    // in is what fills the track so no column is ever half-drawn.
    final columns = math.max(
      1,
      math.min(slotCount, track ~/ minColumnWidth),
    );
    // The lower clamp is not redundant with the `~/` above. Whenever the track
    // can afford one column, `track / columns` is at or over the floor by
    // construction — but a track *narrower* than the floor forces `columns` to
    // 1 to avoid dividing by zero, and `track / 1` is then the track itself. A
    // 700pt browser window at 400% zoom is 175 logical pixels, which leaves 47
    // for the hours; without this the grid would draw a 47pt — or, at 500%, a
    // 2pt — column, and `Wed 28` would clip to `Wed 2`. Holding the floor and
    // letting the one column overflow its clip is the documented behaviour:
    // below the floor the grid scrolls (rule 12).
    final width = math.max<double>(
      minColumnWidth,
      math.min<double>(track / columns, maxColumnWidth),
    );

    return GridLayout(
      labelColumnWidth: resolvedLabel,
      hourColumnWidth: width,
      visibleColumns: columns,
      trackWidth: track,
    );
  }

  /// Smallest hour column the grid will draw before it starts scrolling.
  ///
  /// See the class doc: the date label, not the hour, is what sets it.
  static const double minColumnWidth = 48;

  /// Widest hour column, reached only when every slot already fits.
  static const double maxColumnWidth = 96;

  /// Width of the pinned column below `600px`.
  ///
  /// Narrower than `GridMetrics.labelColumnWidth` because on a phone every
  /// pixel spent on the label is an hour column the user cannot see;
  /// `LocationRow` drops its country line at this width rather than shrinking
  /// its type.
  static const double denseLabelColumnWidth = 128;

  /// Width of the pinned first column, for this surface.
  final double labelColumnWidth;

  /// Width of one hour column, for this surface.
  final double hourColumnWidth;

  /// How many whole columns the track shows. `slotCount` when the entire
  /// window fits and the grid does not scroll at all.
  final int visibleColumns;

  /// Width left for the hours after the pinned column.
  final double trackWidth;

  /// Whether the whole window is on screen, i.e. the track does not scroll.
  bool fitsEntirely(int slotCount) => visibleColumns >= slotCount;

  /// Left edge of column [index] in track coordinates, before scrolling.
  double columnLeft(int index) => index * hourColumnWidth;

  /// Index of the column [trackDx] pixels into the scrolled track, or `null`
  /// when the pointer is left of the track or past the last slot.
  ///
  /// [scrollOffset] is the track's current horizontal offset.
  int? columnAt({
    required double trackDx,
    required double scrollOffset,
    required int slotCount,
  }) {
    if (trackDx < 0 || hourColumnWidth <= 0) return null;
    final index = ((scrollOffset + trackDx) / hourColumnWidth).floor();
    if (index < 0 || index >= slotCount) return null;
    return index;
  }

  /// The same scroll position expressed in fractional columns.
  ///
  /// **This is the unit a scroll offset has to survive a resize in.** A
  /// `ScrollPosition` stores pixels, and pixels stop meaning an hour the
  /// moment the column width is a function of the viewport: 600px is column 10
  /// at 60pt and column 12.5 at 48pt, so a user dragging their window edge
  /// would watch the grid scrub through time. Converting to columns before the
  /// relayout and back to pixels after it is what pins the view to the hour
  /// the user was actually looking at.
  double columnOf(double scrollOffset) =>
      hourColumnWidth <= 0 ? 0 : scrollOffset / hourColumnWidth;

  /// The pixel offset that puts fractional column [column] at the track's left
  /// edge, clamped to the content.
  double offsetOfColumn(double column, int slotCount) {
    final maxOffset = math.max<double>(
      0,
      slotCount * hourColumnWidth - trackWidth,
    );
    return math.min(math.max(column * hourColumnWidth, 0), maxOffset);
  }

  @override
  bool operator ==(Object other) =>
      other is GridLayout &&
      other.labelColumnWidth == labelColumnWidth &&
      other.hourColumnWidth == hourColumnWidth &&
      other.visibleColumns == visibleColumns &&
      other.trackWidth == trackWidth;

  @override
  int get hashCode => Object.hash(
    labelColumnWidth,
    hourColumnWidth,
    visibleColumns,
    trackWidth,
  );

  @override
  String toString() =>
      'GridLayout(label: $labelColumnWidth, column: $hourColumnWidth, '
      'visible: $visibleColumns of track $trackWidth)';
}

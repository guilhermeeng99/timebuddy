import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/features/time_grid/presentation/grid_layout.dart';

// The grid's geometry resolver: the thing that decides how wide an hour column
// is now that it is not a constant.
//
// These are unit tests on purpose. The widget tests in
// `time_grid_responsive_test.dart` prove the page uses this answer; what has
// to be pinned *here* is the answer itself, at every width between a small
// phone and an ultrawide monitor, because the failure mode of a layout
// formula is not an exception — it is a screen that looks plausible and shows
// the wrong number of hours.

/// The window `BuildGridUseCase` builds: a 24-hour day plus three flank slots
/// on each side (time_grid.md rule 3).
const int _slots = 30;

/// A DST day in the reference zone, which is 23 or 25 hours (rule 2). Written
/// out because nothing here may assume 24.
const int _shortDaySlots = 29;

/// Every width worth asking about, from a small phone to an ultrawide.
const List<double> _widths = <double>[
  320,
  360,
  375,
  414,
  540,
  599,
  600,
  640,
  700,
  768,
  834,
  899,
  900,
  1024,
  1280,
  1440,
  1600,
  1920,
  2560,
  3440,
];

GridLayout _at(double width, {int slots = _slots, bool dense = false}) =>
    GridLayout.resolve(
      availableWidth: width,
      slotCount: slots,
      dense: dense,
    );

void main() {
  group('GridLayout.resolve', () {
    test('fills the track with whole columns and never half of one', () {
      // The complaint this whole design answers: the old fixed column left the
      // last one sliced through the middle of its digits at almost every
      // width. A track divided into `n` equal columns cannot do that.
      for (final width in _widths) {
        final layout = _at(width);
        if (layout.visibleColumns == 0) continue;
        final covered = layout.visibleColumns * layout.hourColumnWidth;
        // The only slack allowed is on an ultrawide, where the whole window
        // already fits and `maxColumnWidth` stops the columns growing absurd.
        final capped =
            layout.fitsEntirely(_slots) &&
            layout.hourColumnWidth == GridLayout.maxColumnWidth;
        if (capped) {
          expect(covered, lessThanOrEqualTo(layout.trackWidth));
          continue;
        }
        expect(
          covered,
          closeTo(layout.trackWidth, 0.001),
          reason: 'at ${width}px the columns must tile the track exactly',
        );
      }
    });

    test('never draws a column below the legible floor', () {
      // 48 is measured, not chosen: below it the per-row date label clips from
      // the right and prints `Wed 2` instead of `Wed 28` — a wrong date that
      // looks deliberate. See the class doc.
      for (final width in _widths) {
        final layout = _at(width);
        expect(
          layout.hourColumnWidth,
          greaterThanOrEqualTo(GridLayout.minColumnWidth),
          reason: 'at ${width}px',
        );
      }
    });

    test('holds the floor even on a track too narrow for one column', () {
      // Found by review, and it was a real hole rather than a hypothetical:
      // `columns` is forced to 1 so the division below it cannot be by zero,
      // and `track / 1` is then the track itself. Reachable on the web at
      // browser zoom — logical pixels are CSS pixels, so a 700px window at
      // 400% is 175 of them and leaves the hours 47.
      for (final width in <double>[130, 150, 168, 175]) {
        final layout = _at(width, dense: true);
        expect(
          layout.hourColumnWidth,
          GridLayout.minColumnWidth,
          reason: 'at ${width}px the floor has to win, and the track scroll',
        );
        expect(layout.visibleColumns, 1);
        expect(layout.fitsEntirely(_slots), isFalse);
      }
    });

    test('widening the grid never shows fewer hours', () {
      // The regression that started this: at a fixed column width the app
      // could show *more* hours at 599px than at 600px. Within one pinned
      // column form the count has to be monotonic, and the widget tests cover
      // the two places the form itself changes.
      var previous = 0;
      for (final width in _widths) {
        final columns = _at(width).visibleColumns;
        expect(
          columns,
          greaterThanOrEqualTo(previous),
          reason: 'widening to ${width}px lost columns',
        );
        previous = columns;
      }
    });

    test('shows the entire window once the track can afford it', () {
      // 30 slots at the floor need 1440pt of track. That is the honest number
      // and the reason the grid still scrolls on a phone: no arrangement of a
      // 375pt screen fits a day at a legible size.
      const needed = _slots * GridLayout.minColumnWidth;
      final fits = _at(needed + GridMetrics.labelColumnWidth);
      expect(fits.fitsEntirely(_slots), isTrue);
      expect(fits.visibleColumns, _slots);

      final short = _at(needed + GridMetrics.labelColumnWidth - 1);
      expect(short.fitsEntirely(_slots), isFalse);
    });

    test('a phone cannot fit a day, and says so rather than shrinking', () {
      final phone = _at(375, dense: true);
      expect(phone.fitsEntirely(_slots), isFalse);
      expect(phone.hourColumnWidth, greaterThanOrEqualTo(48));
      // Still better than the fixed 60pt column it replaced, which showed 4.
      expect(phone.visibleColumns, greaterThanOrEqualTo(5));
    });

    test('a DST day is 29 or 31 columns, never 24 rounded up', () {
      final wide = _at(1920, slots: _shortDaySlots);
      expect(wide.visibleColumns, lessThanOrEqualTo(_shortDaySlots));
      expect(wide.fitsEntirely(_shortDaySlots), isTrue);
    });

    test('the pinned column yields rather than starving the track', () {
      // Reachable by an Android split-screen window or a narrow desktop pane.
      // The old code clamped the track at zero and left the label at its full
      // width, which hands `Expanded` nothing to lay out.
      final tiny = _at(100);
      expect(tiny.labelColumnWidth, lessThanOrEqualTo(100));
      expect(tiny.trackWidth, greaterThanOrEqualTo(0));

      final nothing = _at(0);
      expect(nothing.trackWidth, 0);
      expect(nothing.visibleColumns, 0);
    });

    test('the dense form spends less on the label than the full one', () {
      expect(
        _at(500, dense: true).labelColumnWidth,
        GridLayout.denseLabelColumnWidth,
      );
      expect(_at(500).labelColumnWidth, GridMetrics.labelColumnWidth);
      expect(
        _at(500, dense: true).visibleColumns,
        greaterThan(_at(500).visibleColumns),
      );
    });
  });

  group('scroll offsets', () {
    test('a resize keeps the same hour at the track edge', () {
      // The bug this prevents: a `ScrollPosition` stores pixels, so without
      // converting through columns, dragging the window edge scrubs the grid
      // through time. 600px is column 10 at 60pt and 12.5 at 48pt.
      final before = _at(1280);
      final after = _at(900);
      final column = before.columnOf(before.hourColumnWidth * 7.5);

      expect(column, closeTo(7.5, 0.001));
      final offset = after.offsetOfColumn(column, _slots);
      expect(after.columnOf(offset), closeTo(7.5, 0.001));
    });

    test('an offset is clamped to the content, both ends', () {
      final layout = _at(900);
      expect(layout.offsetOfColumn(-5, _slots), 0);

      final maxOffset = layout.offsetOfColumn(_slots.toDouble(), _slots);
      expect(
        maxOffset,
        closeTo(_slots * layout.hourColumnWidth - layout.trackWidth, 0.001),
      );
    });

    test('an offset cannot scroll a track that already fits', () {
      final wide = _at(1920);
      expect(wide.fitsEntirely(_slots), isTrue);
      expect(wide.offsetOfColumn(20, _slots), 0);
    });
  });
}

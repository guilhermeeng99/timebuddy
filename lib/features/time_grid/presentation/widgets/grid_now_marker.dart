import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';

/// The "now" line across the hour track (docs/specs/time_grid.md rule 9).
///
/// Distinct from the cursor on purpose: the cursor is where the user is
/// looking, this is where the world actually is. It sits at the *fractional*
/// position of the current instant, so at 14:20 it stands a third of the way
/// into the 14:00 column rather than snapped to its edge.
///
/// **It never rebuilds a widget.** The instant lands in a [ValueNotifier] and
/// the horizontal offset arrives as a [ValueListenable]; both are handed to
/// the painter as its `repaint` signal, so a tick or a scroll is a repaint of
/// one line and nothing else (time_grid.md, Performance). The ticker runs at
/// 1/60 Hz unless the user asked for seconds, which is right for a marker that
/// moves less than a pixel a second.
///
/// ```dart
/// Positioned(
///   left: GridMetrics.labelColumnWidth,
///   top: 0,
///   right: 0,
///   bottom: 0,
///   child: GridNowMarker(
///     firstSlot: model.slots.first,
///     slotCount: model.slots.length,
///     horizontalOffset: hourOffset,
///     color: context.appColors.primary,
///   ),
/// );
/// ```
class GridNowMarker extends StatefulWidget {
  const GridNowMarker({
    required this.firstSlot,
    required this.slotCount,
    required this.horizontalOffset,
    required this.color,
    this.ticker,
    this.clock,
    super.key,
  });

  /// UTC instant of column zero, the origin the line is measured from.
  final DateTime firstSlot;

  /// How many columns the track holds. From the model, never from `24`:
  /// a DST reference day has 23 or 25 (rule 2).
  final int slotCount;

  /// Current scroll offset of the shared hour track, in pixels.
  final ValueListenable<double> horizontalOffset;

  /// Line colour. Always `primary` in the grid; a parameter so the widget
  /// holds no palette opinion of its own.
  final Color color;

  /// Injected for tests; resolved from `GetIt` otherwise.
  final TickerService? ticker;

  /// Injected for tests; resolved from `GetIt` otherwise. Seeds the first
  /// frame so the line is in the right place before the first tick lands.
  final Clock? clock;

  @override
  State<GridNowMarker> createState() => _GridNowMarkerState();
}

class _GridNowMarkerState extends State<GridNowMarker> {
  late final ValueNotifier<DateTime> _nowInstant;
  StreamSubscription<DateTime>? _subscription;

  @override
  void initState() {
    super.initState();
    final clock = widget.clock ?? GetIt.I<Clock>();
    final ticker = widget.ticker ?? GetIt.I<TickerService>();
    _nowInstant = ValueNotifier<DateTime>(clock.nowUtc());
    // Straight into the notifier, never through setState: the whole point of
    // the marker is that a tick costs one repaint, not one rebuild.
    _subscription = ticker.stream.listen(
      (utcInstant) => _nowInstant.value = utcInstant,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _nowInstant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _NowMarkerPainter(
          nowInstant: _nowInstant,
          horizontalOffset: widget.horizontalOffset,
          firstSlot: widget.firstSlot,
          slotCount: widget.slotCount,
          color: widget.color,
        ),
      ),
    );
  }
}

class _NowMarkerPainter extends CustomPainter {
  _NowMarkerPainter({
    required this.nowInstant,
    required this.horizontalOffset,
    required this.firstSlot,
    required this.slotCount,
    required this.color,
  }) : super(repaint: Listenable.merge([nowInstant, horizontalOffset]));

  final ValueListenable<DateTime> nowInstant;
  final ValueListenable<double> horizontalOffset;
  final DateTime firstSlot;
  final int slotCount;
  final Color color;

  static const double _lineWidth = 2;
  static const double _knobRadius = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = nowInstant.value.difference(firstSlot);
    // Fractional columns, from the real elapsed microseconds: the marker has
    // to sit *inside* a column, and an integer index would snap it to the
    // hour and make the whole 1/60 Hz ticker pointless.
    final columns =
        elapsed.inMicroseconds / BuildGridUseCase.slotDuration.inMicroseconds;
    if (columns < 0 || columns > slotCount) return;

    final dx = columns * GridMetrics.hourColumnWidth - horizontalOffset.value;
    if (dx < 0 || dx > size.width) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset(dx, 0), Offset(dx, size.height), paint)
      // A knob at the top so the line reads as a marker rather than as a
      // border between two columns.
      ..drawCircle(Offset(dx, _knobRadius), _knobRadius, paint);
  }

  @override
  bool shouldRepaint(_NowMarkerPainter oldDelegate) =>
      oldDelegate.firstSlot != firstSlot ||
      oldDelegate.slotCount != slotCount ||
      oldDelegate.color != color ||
      oldDelegate.nowInstant != nowInstant ||
      oldDelegate.horizontalOffset != horizontalOffset;
}

import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The app's loading placeholder: pulsing blocks in the shape of the content
/// that is about to arrive.
///
/// Preferred over a spinner because the board and the grid load in tens of
/// milliseconds from local storage. A spinner in that window reads as a stall;
/// blocks in the right shape read as the page arriving, and they hold the
/// layout so nothing jumps when the real rows land.
///
/// Render it while a cubit sits in its loading state, and size it to the rows
/// it stands in for.
///
/// ```dart
/// BlocBuilder<BoardCubit, BoardState>(
///   builder: (context, state) => switch (state) {
///     BoardLoading() => const LoadingShimmer(rowCount: 4),
///     BoardReady(:final board) => BoardList(board: board),
///   },
/// );
/// ```
class LoadingShimmer extends StatefulWidget {
  const LoadingShimmer({
    this.rowCount = 3,
    this.rowHeight = GridMetrics.rowHeight,
    super.key,
  });

  /// How many placeholder blocks to draw.
  final int rowCount;

  /// Height of one block. Match it to the row it replaces so the real content
  /// lands without shifting the page.
  final double rowHeight;

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 1100);
  static const double _minOpacity = 0.35;
  static const double _maxOpacity = 0.85;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  )..repeat(reverse: true);

  // Driven through a CurveTween rather than a CurvedAnimation: the latter is a
  // listenable that has to be disposed, and one more disposable here buys
  // nothing.
  late final Animation<double> _opacity = _controller.drive(
    Tween<double>(
      begin: _minOpacity,
      end: _maxOpacity,
    ).chain(CurveTween(curve: Curves.easeInOut)),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blockColor = context.appColors.surfaceVariant;
    return Semantics(
      // A shimmer is a *visual* placeholder: it announced nothing at all, so
      // the page a screen reader reached while the board loaded was silence
      // with no way to tell it from an empty one. `liveRegion` is what makes
      // the announcement happen when the placeholder appears rather than only
      // when the user wanders onto it.
      label: t.common.loading,
      liveRegion: true,
      // The blocks stand in for content that does not exist yet; there is
      // nothing under here worth reading.
      excludeSemantics: true,
      child: _blocks(blockColor),
    );
  }

  Widget _blocks(Color blockColor) {
    return FadeTransition(
      // One opacity animation over the whole column rather than one per block:
      // the pulse is the only thing moving, so it costs a single repaint of an
      // already-composited layer.
      opacity: _opacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < widget.rowCount; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: widget.rowHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

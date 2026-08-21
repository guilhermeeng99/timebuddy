import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The daylight-saving marker, in its two forms.
///
/// * [DstBadge] — this zone is observing DST at the instant on screen. It
///   sits on the location's identity block.
/// * [DstBadge.transition] — the clocks actually change inside *this* slot.
///   It sits on the one hour cell that is repeated or skipped, which is the
///   only place a user can see why the day has 23 or 25 columns
///   (time_grid.md rule 2 and its DST edge cases).
///
/// Two forms of one widget rather than two widgets, because they share the
/// token, the shape and the tap target; only the icon and the sentence differ.
///
/// The badge **never navigates**. It reports the tap and the page decides
/// whether to open the explanation sheet, so the same badge works inside the
/// grid, a bottom sheet or a settings preview without any of them inheriting a
/// route the others cannot satisfy.
///
/// ```dart
/// DstBadge(onTap: () => showDstExplainSheet(context));
/// DstBadge.transition(onTap: () => showDstExplainSheet(context));
/// ```
class DstBadge extends StatelessWidget {
  /// The zone is on daylight saving time right now.
  const DstBadge({this.onTap, this.size = _defaultSize, super.key})
    : _marksTransition = false;

  /// The clocks move during the slot this badge is drawn on.
  const DstBadge.transition({this.onTap, this.size = _defaultSize, super.key})
    : _marksTransition = true;

  /// Opens the explanation. `null` renders a non-interactive marker with no
  /// ink response, for a context that already owns the gesture — an hour cell
  /// whose tap has to keep setting the cursor, for instance.
  final VoidCallback? onTap;

  /// Glyph size.
  final double size;

  final bool _marksTransition;

  static const double _defaultSize = 16;

  @override
  Widget build(BuildContext context) {
    final message = _marksTransition ? t.grid.dstTransitionHere : t.grid.dstOn;
    final glyph = AppIcon(
      // A clock with an arrow for the *moment* of the change, a circled up
      // arrow for the state of being shifted: the transition is an event, the
      // observance is a condition.
      //
      // **Not a sun, and that was measured rather than assumed.** The obvious
      // glyph for "summer time" is a sun, and at this 16pt its eight
      // triangular rays merge into the disc and it reads as a cog — in either
      // weight. The up arrow also says the one thing a sun does not: which
      // way the clocks moved.
      _marksTransition
          ? FontAwesomeIcons.clockRotateLeft
          : FontAwesomeIcons.solidCircleUp,
      size: size,
      color: context.appColors.warning,
      semanticLabel: message,
    );
    return Tooltip(
      message: message,
      child: onTap == null ? glyph : _tappable(glyph),
    );
  }

  Widget _tappable(Widget glyph) {
    return Material(
      // Transparent so the ripple paints over whatever surface the badge was
      // dropped onto instead of covering it.
      type: MaterialType.transparency,
      child: InkResponse(
        onTap: onTap,
        // The padding is the hit box. The badge is an affordance beside a
        // bigger target (the row, the cell), never the only way in, so it buys
        // touch slack without stealing height from a 64px row.
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: glyph,
        ),
      ),
    );
  }
}

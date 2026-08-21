import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// A surface card holding rows edge to edge, hairline-separated
/// (design_system §8).
///
/// The counterpart to `TimeBuddySection`'s own card, and not a replacement for
/// it. That one pads its body, which is right for a cluster of fields; this one
/// pads nothing, because a **row** has to reach both edges of the card for its
/// pressed state to look like a row rather than like a rectangle floating
/// inside one. Rows bring their own horizontal padding.
///
/// Use it as the body of a section with the card turned off, so the group is
/// not nested inside a second surface:
///
/// ```dart
/// TimeBuddySection(
///   label: t.settings.groupAccount,
///   card: false,
///   child: TimeBuddyRowGroup(children: [rowA, rowB]),
/// );
/// ```
class TimeBuddyRowGroup extends StatelessWidget {
  const TimeBuddyRowGroup({required this.children, super.key});

  final List<Widget> children;

  /// How far the hairline is inset from the left edge.
  ///
  /// Aligned with where a row's *text* starts — 16 of row padding, 36 of icon
  /// disc, 12 of gap — so the separator reads as dividing the labels rather
  /// than as a line drawn across the card. A rule that ran the full width
  /// would cut the icon column in half.
  static const double _separatorInset =
      AppSpacing.lg + _iconDiscSize + AppSpacing.md;

  static const double _iconDiscSize = 36;

  /// Half a logical pixel: a hairline at any device pixel ratio, and lighter
  /// than a `Divider`, which is a full pixel plus its own 16pt of margin.
  static const double _separatorThickness = 0.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A `Material`, not a `DecoratedBox`: `InkWell` paints its ink on the
    // nearest Material ancestor, so a plain coloured box between the row and
    // the scaffold swallows every ripple — the row still responds, it just
    // looks dead under the finger.
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _separated(children, colors.surfaceVariant),
      ),
    );
  }

  static List<Widget> _separated(List<Widget> rows, Color color) {
    if (rows.length <= 1) return rows;
    return <Widget>[
      for (var i = 0; i < rows.length; i++) ...[
        rows[i],
        if (i < rows.length - 1)
          Padding(
            padding: const EdgeInsets.only(left: _separatorInset),
            child: ColoredBox(
              color: color,
              child: const SizedBox(
                height: _separatorThickness,
                width: double.infinity,
              ),
            ),
          ),
      ],
    ];
  }
}

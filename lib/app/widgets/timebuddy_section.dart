import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// A labelled block of content: the app's only section widget.
///
/// One widget with three configurations instead of three widgets that drift
/// apart on label padding and header weight (design_system §8 and §10, Financo
/// backlog item 2):
///
/// * `card: true` — the default. Field clusters and settings groups.
/// * `card: false` — header only, over a list that owns its own cards.
/// * `trailing: …` — a data card with a badge or an action on the header row.
///
/// ```dart
/// TimeBuddySection(
///   label: t.settings.appearance,
///   dot: true,
///   count: board.locations.length,
///   trailing: TextButton(onPressed: onEdit, child: Text(t.common.edit)),
///   child: Column(children: fields),
/// );
/// ```
class TimeBuddySection extends StatelessWidget {
  const TimeBuddySection({
    required this.label,
    required this.child,
    this.dot = false,
    this.count,
    this.trailing,
    this.card = true,
    super.key,
  });

  /// Header text. Rendered uppercased; pass it in sentence case.
  final String label;

  /// The section body.
  final Widget child;

  /// Draws a small accent dot before [label], to mark the section a screen
  /// wants the eye to land on first.
  final bool dot;

  /// Optional item count, rendered as a tinted pill after [label].
  final int? count;

  /// Optional action or badge, right-aligned on the header row.
  final Widget? trailing;

  /// Whether the body sits on a surface card. Turn it off when the body is
  /// already a list of cards, which would otherwise nest two surfaces.
  final bool card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: label,
          dot: dot,
          count: count,
          trailing: trailing,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (card) _SectionCard(child: child) else child,
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.dot,
    required this.count,
    required this.trailing,
  });

  static const double _dotSize = 6;

  final String label;
  final bool dot;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        if (dot) ...[
          Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        // The label and its count share one flexible slot so the trailing
        // widget is measured first and the label ellipsizes only once it has
        // genuinely run out of room. A bare Spacer here would instead claim
        // half the free width and truncate short headers for nothing.
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: colors.onBackgroundLight,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _CountPill(count: count!),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});


  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        // The accent at low alpha, so the pill reads as a quantity rather than
        // as a second call to action next to the header.
        color: colors.primary.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          '$count',
          style: context.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A Material, not a DecoratedBox. ListTile and InkWell paint their ink on
    // the nearest Material ancestor, so a plain coloured box sitting between
    // them and the scaffold swallows every ripple: the row still responds, it
    // just looks dead under the finger. Flutter asserts on exactly this
    // ("ListTile background color or ink splashes may be invisible"), which is
    // what caught it here. clipBehavior keeps the splash inside the corners.
    return Material(
      color: context.appColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

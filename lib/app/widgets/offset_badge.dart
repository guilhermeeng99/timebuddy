import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// A zone's distance from UTC, from the user's home zone, or both.
///
/// **The only way to render an offset.** It takes [Duration]s and formats them
/// itself; it never accepts a finished string. Offsets are not whole hours —
/// India is `+05:30`, Nepal `+05:45`, Chatham `+12:45` — so a call site that
/// interpolates `'${d.inHours}h'` silently drops the minutes for a fifth of
/// the world (CLAUDE.md, Time & Timezone rule 6). Routing every offset through
/// [offsetLabel] / [relativeOffsetLabel] means that bug can only be written in
/// one place, and it is already not written there.
///
/// Both durations must be resolved for **the instant on screen**, never stored
/// on the location: an offset is a function of `(zone, instant)` and changes
/// under the widget on the zone's next transition (rule 2). Read them from
/// `ZoneState.offset` and `TimeZoneEngine.relativeOffset(...)`.
///
/// ```dart
/// OffsetBadge(
///   offset: row.zoneState?.offset,
///   relativeToHome: row.relativeToHome,
/// );
/// ```
class OffsetBadge extends StatelessWidget {
  const OffsetBadge({
    this.offset,
    this.relativeToHome,
    this.dense = false,
    super.key,
  }) : assert(
         offset != null || relativeToHome != null,
         'An OffsetBadge needs at least one of the two offsets to render.',
       );

  /// Distance from UTC at the instant being shown, rendered as `+05:30`.
  ///
  /// `null` for a caller that only cares about the comparison — the grid's
  /// label column, where the absolute offset would cost a line and answer a
  /// question nobody asked.
  final Duration? offset;

  /// Distance from the home zone at that same instant, rendered as `+4h` or
  /// `-3h30`.
  ///
  /// `null` means no comparison was asked for, **not** that the zones match. A
  /// match is [Duration.zero], and it renders `t.grid.sameTime`:
  /// [relativeOffsetLabel] answers `null` there, and a badge that vanished
  /// would read as a bug on the one row a user is most likely to double-check.
  final Duration? relativeToHome;

  /// Narrow form: one chip instead of the pair.
  ///
  /// The relative offset wins the slot whenever there is one, because in a
  /// column 132px wide at its widest the number worth the space is the
  /// difference from home, not the distance from a meridian nobody lives on.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final absolute = offset;
    final absoluteLabel = absolute == null ? null : offsetLabel(absolute);
    final relativeLabel = _relativeLabel;
    if (dense || absoluteLabel == null) {
      // The assert guarantees one of the two survived.
      return _OffsetPill(label: (relativeLabel ?? absoluteLabel)!);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OffsetPill(label: absoluteLabel),
        if (relativeLabel != null) ...[
          const SizedBox(width: AppSpacing.sm),
          // Flexible so a long "same time" sentence ellipsizes inside the
          // parent instead of pushing the pill off the row.
          Flexible(
            child: Text(
              relativeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelMedium?.copyWith(
                color: context.appColors.onBackgroundLight,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// `null` when no comparison was asked for; the localized "same time" copy
  /// when one was asked for and the two zones sit on the same offset.
  String? get _relativeLabel {
    final relative = relativeToHome;
    if (relative == null) return null;
    return relativeOffsetLabel(relative) ?? t.grid.sameTime;
  }
}

class _OffsetPill extends StatelessWidget {
  const _OffsetPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        // surfaceVariant, not a tinted accent: an offset is a fact about the
        // row, not a call to action competing with the hour colors beside it.
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onBackgroundLight,
          ),
        ),
      ),
    );
  }
}

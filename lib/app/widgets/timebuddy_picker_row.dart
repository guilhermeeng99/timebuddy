import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// Tint behind the selected row: the accent at low alpha, so the row reads as
/// "the current one" rather than as a second call to action.
const double _selectedTintAlpha = 0.08;

/// One selectable row inside a `TimeBuddyPickerSheet`.
///
/// The whole point of this widget is that nobody hand-rolls the next
/// `Material > InkWell > Row`: three pickers built by hand drift apart on
/// padding, on where the check mark sits and on how a selected row is tinted,
/// and the drift is only visible when two of them are open back to back.
///
/// [leading] is a *widget*, not an icon, because callers legitimately differ
/// there: the palette picker shows four colour swatches, the city picker a
/// flag or a zone abbreviation, a plain option nothing at all.
///
/// ```dart
/// TimeBuddyPickerRow(
///   leading: AppIcon(FontAwesomeIcons.earthAmericas),
///   title: city.name,
///   subtitle: city.countryName,
///   isSelected: city.zoneId == board.homeZoneId,
///   onTap: () => Navigator.of(context).pop(city),
/// );
/// ```
class TimeBuddyPickerRow extends StatelessWidget {
  const TimeBuddyPickerRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.isSelected = false,
    this.indent = false,
    super.key,
  });

  /// Primary label. Rendered at `w600` while [isSelected].
  final String title;

  /// Called when the row is tapped. A picker row is always actionable: a row
  /// the user may not choose belongs in the empty state, not in the list.
  final VoidCallback onTap;

  /// Optional second line: the country, the zone offset, a hint.
  final String? subtitle;

  /// Optional widget before the text block — a swatch, an icon, a flag.
  final Widget? leading;

  /// Marks this row as the value currently in effect: tinted background,
  /// heavier title and a trailing check mark. Three signals rather than one
  /// because the tint alone disappears at 8% alpha on some palettes.
  final bool isSelected;

  /// Shifts the row one step to the right, for rows hanging under a group
  /// header or lining up with rows that carry a [leading] widget.
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A Material, not a DecoratedBox with the tint colour. InkWell paints its
    // ink on the nearest Material ancestor, so a coloured box between this
    // row and the sheet swallows the ripple: the row still fires onTap, it
    // just looks dead under the finger. That bug shipped once in M1 and is
    // invisible in review, because it only shows up under a thumb.
    return Material(
      color: isSelected
          ? colors.primary.withValues(alpha: _selectedTintAlpha)
          : colors.surface,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // Material's minimum touch target. Left to its padding a one-line
          // row lands at 44 logical pixels, which is a miss often enough to
          // notice on a phone.
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              indent ? AppSpacing.lg + AppSpacing.xl : AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: _RowContent(
              title: title,
              subtitle: subtitle,
              leading: leading,
              isSelected: isSelected,
            ),
          ),
        ),
      ),
    );
  }
}

class _RowContent extends StatelessWidget {
  const _RowContent({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.isSelected,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final leadingWidget = leading;
    return Row(
      children: [
        if (leadingWidget != null) ...[
          leadingWidget,
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: _RowText(
            title: title,
            subtitle: subtitle,
            isSelected: isSelected,
          ),
        ),
        if (isSelected) ...[
          const SizedBox(width: AppSpacing.sm),
          AppIcon(FontAwesomeIcons.check, color: colors.primaryGlyph),
        ],
      ],
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({
    required this.title,
    required this.subtitle,
    required this.isSelected,
  });

  final String title;
  final String? subtitle;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final secondLine = subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : null,
          ),
        ),
        if (secondLine != null)
          Text(
            secondLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall?.copyWith(
              color: colors.onBackgroundLight,
            ),
          ),
      ],
    );
  }
}

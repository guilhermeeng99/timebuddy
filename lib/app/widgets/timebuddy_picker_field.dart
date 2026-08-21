import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// The trigger that opens a picker from a form: leading icon, label, the
/// chosen value (or a placeholder) and a chevron.
///
/// It deliberately looks like an input rather than a button — same
/// `surfaceVariant` fill and `AppRadius.md` corners as the fields it sits
/// among — because in a form it *is* one: it holds a value the user picked.
/// Pair it with `showTimeBuddyPickerSheet`; this widget only reports the tap.
///
/// ```dart
/// TimeBuddyPickerField(
///   icon: FontAwesomeIcons.earthAmericas,
///   label: t.locations.homeCity,
///   value: home?.label,
///   placeholder: t.locations.pickHomeCity,
///   onTap: _openHomePicker,
/// );
/// ```
class TimeBuddyPickerField extends StatelessWidget {
  const TimeBuddyPickerField({
    required this.icon,
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.value,
    super.key,
  });

  /// Leading glyph. An `IconData` rather than a widget: a form field's
  /// leading slot is a 24pt icon every time, and letting it be arbitrary is
  /// how a row of fields stops lining up.
  final FaIconData icon;

  /// What the value means, in muted type above it.
  final String label;

  /// Shown in place of [value] while nothing is chosen. Required even for a
  /// field that is always filled in the end, because every such field still
  /// renders empty for the frame between mount and the first load.
  final String placeholder;

  /// Opens the picker. Never null: a field the user cannot open is a label.
  final VoidCallback onTap;

  /// The chosen value, already formatted for display.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A Material, not a DecoratedBox with the fill colour. InkWell paints its
    // ink on the nearest Material ancestor, so a coloured box between this
    // field and the page swallows the ripple: the field still opens the
    // picker, it just looks dead under the finger. That bug shipped once in
    // M1 and only shows up under a thumb, never in review. clipBehavior keeps
    // the ink inside the rounded corners.
    return Material(
      color: colors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              AppIcon(icon, color: colors.onBackgroundLight),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _FieldText(
                  label: label,
                  placeholder: placeholder,
                  value: value,
                ),
              ),
              AppIcon(
                FontAwesomeIcons.chevronRight,
                color: colors.onBackgroundLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldText extends StatelessWidget {
  const _FieldText({
    required this.label,
    required this.placeholder,
    required this.value,
  });

  final String label;
  final String placeholder;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final chosen = value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.labelMedium?.copyWith(
            color: colors.onBackgroundLight,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          chosen ?? placeholder,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.titleSmall?.copyWith(
            // The placeholder stays muted so an unfilled field reads as empty
            // at a glance, the way a hint does in a text field.
            color: chosen == null ? colors.onBackgroundLight : null,
          ),
        ),
      ],
    );
  }
}

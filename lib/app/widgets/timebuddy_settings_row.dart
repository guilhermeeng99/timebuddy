import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// One row of a `TimeBuddyRowGroup`: a tinted icon disc, a title, an optional
/// subtitle, and a trailing widget that defaults to a chevron
/// (design_system §8).
///
/// **The disc is what makes a list of rows scannable.** A bare leading icon
/// disappears into the text beside it at these sizes; a 36pt square of the
/// icon's own colour at 14% alpha gives the eye a fixed left column to run
/// down, which is the whole reason a settings screen with twenty rows stays
/// readable.
///
/// [accent] tints the disc and, when [destructive], the title too — so a row
/// that ends in a confirmation dialog says so before it is tapped, without a
/// divider or a separate red section.
///
/// ```dart
/// TimeBuddySettingsRow(
///   icon: FontAwesomeIcons.palette,
///   title: t.settings.lightPalette,
///   value: option.label,
///   onTap: () => unawaited(pickPalette(context)),
/// );
/// ```
class TimeBuddySettingsRow extends StatelessWidget {
  const TimeBuddySettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.accent,
    this.trailing,
    this.destructive = false,
    this.control,
    this.onTap,
    super.key,
  }) : assert(
         control == null || onTap == null,
         'A row with a control is operated by the control. Giving it a tap '
         'target as well makes the whole cell a second, larger way to do '
         'something the control already does more precisely.',
       );

  /// A Font Awesome glyph. `FaIconData` and not `IconData`: the package
  /// carries its own subtype so `FaIcon` can pick the right font family, and
  /// widening this to `IconData` would let a Material icon in through a door
  /// the design system closed.
  final FaIconData icon;
  final String title;

  /// A second line under the title, for a row whose name does not explain it.
  final String? subtitle;

  /// The row's current setting, right-aligned before the trailing widget.
  ///
  /// Separate from [subtitle] because it answers a different question — what
  /// is this set to, rather than what does this do — and a user comparing two
  /// rows scans one column for it.
  final String? value;

  final Color? accent;
  final Widget? trailing;
  final bool destructive;

  /// A segmented toggle, switch or field belonging to this row.
  ///
  /// **Where it lands depends on the width, and that is the point.** On a
  /// phone it stacks under the title and fills the row, because 360pt has no
  /// room for two columns. Above the breakpoint it sits at the end of the
  /// title's line, capped at [_controlMaxWidth]: a three-way toggle stretched
  /// across a 1300pt window is a row of enormous buttons, no faster to read
  /// than a small one, and the eye already tracking values down the right edge
  /// finds it there.
  final Widget? control;

  /// `null` renders the row inert and drops the chevron: some rows are
  /// statements, not doors.
  final VoidCallback? onTap;

  /// How wide a control may grow before it stops looking like a control.
  ///
  /// Sized for the widest thing these rows carry — a three-segment pill whose
  /// longest pt-BR labels are `Sistema` / `Claro` / `Escuro` — with room left
  /// over, because the failure this guards against is a control that is too
  /// big rather than one that is too small.
  static const double _controlMaxWidth = 420;

  static const double _discSize = 36;
  static const double _iconSize = 15;
  static const double _chevronSize = 12;
  static const double _discTintAlpha = 0.14;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final iconColor = destructive ? colors.error : (accent ?? colors.primary);
    final titleColor = destructive ? colors.error : colors.onBackground;
    final subtitleText = subtitle;
    final valueText = value;
    final stacksControl = control != null && ResponsiveLayout.isMobile(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _IconDisc(icon: icon, color: iconColor),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: titleColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitleText != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitleText,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: colors.onBackgroundLight,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (valueText != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        valueText,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: colors.onBackgroundLight,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  if (control != null && !stacksControl)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _controlMaxWidth,
                      ),
                      child: control,
                    ),
                  // An inert row gets no chevron: the affordance has to be a
                  // promise the row can keep.
                  if (trailing != null)
                    trailing!
                  else if (onTap != null)
                    AppIcon(
                      FontAwesomeIcons.chevronRight,
                      size: _chevronSize,
                      color: colors.onBackgroundLight,
                    ),
                ],
              ),
              if (stacksControl) ...[
                const SizedBox(height: AppSpacing.md),
                control!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc({required this.icon, required this.color});

  final FaIconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: TimeBuddySettingsRow._discSize,
      height: TimeBuddySettingsRow._discSize,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: TimeBuddySettingsRow._discTintAlpha,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Center(
        child: AppIcon(
          icon,
          size: TimeBuddySettingsRow._iconSize,
          color: color,
        ),
      ),
    );
  }
}

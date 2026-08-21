import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Says out loud that everything on the page is measured from UTC rather than
/// from the user's own zone.
///
/// The grid's columns and the world clock's readings are the same claim seen
/// two ways, so both screens raise the same warning in the same words — and
/// they did it with the same class, copied line for line into each page, down
/// to the constants and this comment. One widget with a [padding] parameter is
/// the whole of what differed (time_grid.md and world_clock.md, home-zone edge
/// case).
///
/// Not a snackbar: the condition lasts until the user picks a home city, and a
/// warning they can lose by scrolling is not a warning.
///
/// It owns its copy rather than taking a message, and deliberately: two
/// screens saying the same thing in two strings is how they stop saying the
/// same thing. A second, different warning is a second widget.
///
/// ```dart
/// if (model.homeIsUnresolved)
///   const HomeZoneBanner(padding: EdgeInsets.only(bottom: AppSpacing.md)),
/// ```
class HomeZoneBanner extends StatelessWidget {
  const HomeZoneBanner({this.padding = EdgeInsets.zero, super.key});

  /// Space around the banner, which is the only thing the two callers
  /// disagreed on: the grid gutters it into a page that has none, the world
  /// clock only needs a gap under it inside a padded list.
  final EdgeInsetsGeometry padding;

  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: padding,
      child: Material(
        color: colors.warning.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.md),
        // Not tappable any more, and that is the change rather than an
        // oversight. It used to navigate to the Cities page, which was the
        // only screen that could set a home city; that page is gone and the
        // repair is now one tap on a row of the list this banner sits above.
        // A link that only re-displayed the screen you are already on would
        // be a control that does nothing.
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                FontAwesomeIcons.triangleExclamation,
                size: _iconSize,
                color: colors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  t.grid.homeZoneBrokenBanner,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onBackground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

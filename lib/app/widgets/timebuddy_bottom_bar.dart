import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/app/widgets/timebuddy_sidebar.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// The floating pill navigation shown below `600px` (design_system §7).
///
/// It floats *over* the page rather than sitting under it in a
/// `bottomNavigationBar` slot, so the grid can scroll a row beneath it and
/// keep the full window height for hour columns. The price of floating is that
/// scroll views have to pad for it, which is what `bottomSafeForFab` computes
/// from [reservedHeight].
///
/// **Renders nothing at `>= 600px` or on a sub-page**, so the shell can drop it
/// into its `Stack` unconditionally: both halves of the §7 rule live here, and
/// a shell that forgets one of them is not a way this can break.
///
/// The active destination is the only one that shows its label. Three labels
/// on a phone-width pill either truncate or shrink the type below the scale,
/// and the inactive ones carry no information the icon does not.
///
/// ```dart
/// Stack(
///   children: [
///     page,
///     Align(
///       alignment: Alignment.bottomCenter,
///       child: TimeBuddyBottomBar(
///         currentRoute: state.matchedLocation,
///         onSelect: (destination) => context.go(destination.route),
///       ),
///     ),
///   ],
/// );
/// ```
class TimeBuddyBottomBar extends StatelessWidget {
  const TimeBuddyBottomBar({
    required this.currentRoute,
    required this.onSelect,
    super.key,
  });

  /// The router's current path, used to pick the expanded destination.
  final String currentRoute;

  /// Called with the tapped destination. The shell navigates; the bar does not
  /// import the router.
  final ValueChanged<TimeBuddyNavDestination> onSelect;

  /// Height of the pill itself.
  static const double barHeight = 64;

  /// Gap between the pill and the window edge, above and below it.
  static const double edgeGap = AppSpacing.lg;

  /// Vertical space the bar occupies: `16 + 64 + 16 = 96` (design_system §7).
  ///
  /// The one number every clearance calculation starts from. Anything that has
  /// to sit clear of the bar reads it from here instead of writing `96`, which
  /// is how a per-page magic number gets minted.
  static const double reservedHeight = edgeGap + barHeight + edgeGap;

  // The bar floats over scrolling content, so it needs a real shadow: without
  // one, a row passing underneath reads as part of the bar for the frame it
  // overlaps it.
  static const double _elevation = 8;
  static const Duration _expandDuration = Duration(milliseconds: 180);

  // The expanded item needs room for an icon plus a word; the other two need
  // room for an icon. Weighted rather than equal thirds so a long label
  // ("Localizações") still fits on a 320pt phone instead of ellipsing.
  static const int _selectedFlex = 3;

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveLayout.isMobile(context)) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: subPageDepth,
      builder: (context, depth, _) =>
          depth > 0 ? const SizedBox.shrink() : _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    final colors = context.appColors;
    final selected = TimeBuddyNavDestination.forLocation(currentRoute);
    return SafeArea(
      // Only the bottom inset matters: the bar is bottom-anchored and a top
      // inset here would push it up by the height of the status bar.
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(edgeGap),
        child: Material(
          color: colors.surface,
          elevation: _elevation,
          shadowColor: colors.scrim,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: SizedBox(
            height: barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                // Stretch so every item is tappable over the bar's whole
                // height. Centred, each one would only take the height of its
                // own fill and a thumb landing near the bar's top or bottom
                // edge would hit nothing at all.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final destination in TimeBuddyNavDestination.values)
                    Flexible(
                      flex: destination == selected ? _selectedFlex : 1,
                      child: _BottomBarItem(
                        destination: destination,
                        isSelected: destination == selected,
                        onTap: () => onSelect(destination),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final TimeBuddyNavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.xl);
    final foreground = isSelected ? colors.onPrimary : colors.onBackgroundLight;
    return Semantics(
      selected: isSelected,
      child: Material(
        // Transparent so the ripple paints over the selected fill instead of
        // covering it with a second opaque surface.
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          // `widthFactor` and not a `Center`: the row measures this child to
          // size the item, and a Center would report the whole slot, turning
          // the content-sized pill into a fixed column and stranding the
          // expand animation. Height still fills, which is the point.
          child: Align(
            widthFactor: 1,
            // Outside the fill so the ink area grows with the pill as the
            // label appears, instead of splashing over the old width for one
            // frame.
            child: AnimatedSize(
              duration: TimeBuddyBottomBar._expandDuration,
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: TimeBuddyBottomBar._expandDuration,
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: isSelected ? AppSpacing.md : AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? colors.primary : null,
                  borderRadius: radius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected ? destination.selectedIcon : destination.icon,
                      size: _iconSize,
                      color: foreground,
                      // Only the selected destination renders its label, so
                      // without this the other two are unnamed buttons to a
                      // screen reader.
                      semanticLabel: isSelected ? null : destination.label,
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          destination.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

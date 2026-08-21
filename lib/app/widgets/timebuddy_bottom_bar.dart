import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
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
/// The active destination is the only one that shows its label. Five labels on
/// a phone-width pill either truncate or shrink the type below the scale, and
/// the inactive ones carry no information the icon does not.
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

  /// Width of a collapsed destination, and the number the five-item fit is
  /// measured against.
  ///
  /// Collapsed items are the row's only fixed cost, so the arithmetic closes
  /// without a layout pass. On a 375pt window the pill's gutters take
  /// `16 + 16` outside plus `8 + 8` inside, leaving `327`; the four collapsed
  /// items take `4 * 44 = 176`; the expanded item therefore gets `151`, of
  /// which its own chrome (`12` padding + `22` icon + `8` gap + `12` padding)
  /// is `54`. That leaves **97pt of label**, and the longest label either
  /// locale ships — pt-BR `Configurações` — measures roughly 94pt at
  /// `labelLarge`. Five fit.
  ///
  /// The row cannot overflow on any real phone: the label is `Flexible` with
  /// an ellipsis, so the only incompressible width is `176 + 54 = 230`, which
  /// needs a 278pt window. Below `600` is where the bar renders at all and no
  /// phone is narrower than 320.
  ///
  /// A sixth destination costs another 44 and drops the label to 53pt, under
  /// every word in the nav. That is the ceiling `TimeBuddyNavDestination`
  /// documents, and the reason this constant is public.
  ///
  /// It is also a tap target rather than the 22pt icon it centres: a collapsed
  /// item used to be sized by its content, which put the touchable area at
  /// 38pt on a control the user aims at on every visit.
  static const double collapsedItemWidth = 44;

  // The bar floats over scrolling content, so it needs a real shadow: without
  // one, a row passing underneath reads as part of the bar for the frame it
  // overlaps it.
  static const double _elevation = 8;
  static const Duration _expandDuration = Duration(milliseconds: 180);

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
                    // The expanded item is the only flexible one, and loosely
                    // so: it takes whatever the collapsed items left and then
                    // shrinks to its content, which is what keeps the
                    // expand/collapse animation on a content-sized pill
                    // instead of a fixed column. Splitting the row by flex
                    // weights instead cannot hold both ends at once — the
                    // ratio that gives the label enough room starves the
                    // collapsed icons on a 320pt phone.
                    if (destination == selected)
                      Flexible(
                        child: _BottomBarItem(
                          destination: destination,
                          isSelected: true,
                          onTap: () => onSelect(destination),
                        ),
                      )
                    else
                      SizedBox(
                        width: collapsedItemWidth,
                        child: _BottomBarItem(
                          destination: destination,
                          isSelected: false,
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
          // `widthFactor` and not a `Center`, and it does both jobs at once:
          // under the expanded item's loose `Flexible` it reports the pill's
          // own width, so the row measures content rather than freezing it
          // into a fixed column and stranding the expand animation; under a
          // collapsed item's tight `SizedBox` the same factor is clamped away
          // by the constraint, so the InkWell fills the 44pt tap target and
          // centres the icon in it. Height fills in both cases, which is what
          // makes a thumb landing near the pill's top edge hit something.
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
                    AppIcon(
                      destination.icon,
                      size: _iconSize,
                      color: foreground,
                      // Only the selected destination renders its label, so
                      // without this the other four are unnamed buttons to a
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

import 'package:flutter/material.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The app's primary destinations, in the order both nav surfaces show them.
///
/// Declared next to the sidebar rather than in a file of their own: three
/// constants read by exactly two widgets do not earn a `nav_destinations.dart`
/// you have to open to learn nothing. `TimeBuddyBottomBar` imports them from
/// here, which is the point — two hand-maintained lists would eventually
/// disagree on an icon, a label or the order, and the disagreement would only
/// be visible to a user who resizes the window.
///
/// ```dart
/// for (final destination in TimeBuddyNavDestination.values)
///   NavItem(destination: destination, isSelected: destination.matches(path));
/// ```
enum TimeBuddyNavDestination {
  /// The comparison grid. Also the start route (docs/specs/time_grid.md).
  grid(
    route: AppRoutes.grid,
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
  ),

  /// The saved board: add, reorder, remove (docs/specs/locations.md).
  locations(
    route: AppRoutes.locations,
    icon: Icons.location_city_outlined,
    selectedIcon: Icons.location_city_rounded,
  ),

  /// Preferences (docs/specs/preferences.md).
  settings(
    route: AppRoutes.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  );

  const TimeBuddyNavDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
  });

  /// The `AppRoutes` path this destination navigates to.
  final String route;

  /// Icon shown while the destination is not the active one.
  final IconData icon;

  /// Filled counterpart, shown while the destination is active.
  final IconData selectedIcon;

  /// The localized label, resolved on every read.
  ///
  /// A getter and not a field because a `const` enum value cannot hold a
  /// string that changes with the locale: the user switches language in
  /// settings and both nav surfaces have to relabel on the next build.
  String get label => switch (this) {
    TimeBuddyNavDestination.grid => t.nav.grid,
    TimeBuddyNavDestination.locations => t.nav.locations,
    TimeBuddyNavDestination.settings => t.nav.settings,
  };

  /// Whether [location] belongs to this destination.
  ///
  /// Sub-routes count, so the add-location page keeps Locations highlighted
  /// while it is open. The grid is the exception: its route is the root path,
  /// which prefixes every other path in the app, so it only matches exactly.
  bool matches(String location) {
    if (route == AppRoutes.grid) return location == route;
    return location == route || location.startsWith('$route/');
  }

  /// The destination owning [location], or `null` for a path outside the nav
  /// (a full-screen flow, an unknown deep link) so the caller can highlight
  /// nothing rather than guess.
  static TimeBuddyNavDestination? forLocation(String location) {
    for (final destination in values) {
      if (destination.matches(location)) return destination;
    }
    return null;
  }
}

/// The navigation rail shown at `>= 600px`: brand, destinations, date stepper,
/// profile slot (design_system §7).
///
/// **Renders nothing below the mobile breakpoint**, so the shell can place it
/// unconditionally at the head of its `Row` and the one breakpoint decision
/// stays here instead of being repeated at the call site.
///
/// The rail owns the date stepper at this width, which is why pages must not
/// draw their own date pill above `600px`. It arrives as a widget in the
/// [datePill] slot rather than as a date plus a callback: the reference day
/// belongs to the grid's cubit, and a rail that took it as a parameter would
/// demand one from every screen that has no reference day at all. The rail
/// hides whatever is in that slot while a [SubPageScope] is open, so the §7
/// rule holds without the shell having to re-check it.
///
/// ```dart
/// Row(
///   children: [
///     TimeBuddySidebar(
///       currentRoute: state.matchedLocation,
///       onSelect: (destination) => context.go(destination.route),
///       datePill: TimeBuddyDatePill(...),
///     ),
///     Expanded(child: page),
///   ],
/// );
/// ```
class TimeBuddySidebar extends StatelessWidget {
  const TimeBuddySidebar({
    required this.currentRoute,
    required this.onSelect,
    this.datePill,
    this.profile,
    super.key,
  });

  /// The router's current path, used to pick the highlighted destination.
  final String currentRoute;

  /// Called with the tapped destination. The shell navigates; the rail does
  /// not import the router.
  final ValueChanged<TimeBuddyNavDestination> onSelect;

  /// The reference-day stepper, normally a `TimeBuddyDatePill`. `null` on the
  /// screens that have no reference day.
  final Widget? datePill;

  /// Account block, pinned to the bottom.
  ///
  /// Empty until auth lands in M3 (docs/specs/auth.md). The slot exists and
  /// stays empty on purpose: a stubbed avatar would advertise an account the
  /// app cannot yet sign anyone into.
  final Widget? profile;

  /// Rail width. Sized around the date stepper, the widest thing it holds:
  /// below this the stepper is the first element to wrap.
  static const double width = 240;

  @override
  Widget build(BuildContext context) {
    if (ResponsiveLayout.isMobile(context)) return const SizedBox.shrink();
    final colors = context.appColors;
    final stepper = datePill;
    final account = profile;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(right: BorderSide(color: colors.surfaceVariant)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _BrandMark(),
                const SizedBox(height: AppSpacing.xxl),
                for (final destination in TimeBuddyNavDestination.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _SidebarNavItem(
                      destination: destination,
                      isSelected: destination.matches(currentRoute),
                      onTap: () => onSelect(destination),
                    ),
                  ),
                // The stepper drops out on a sub-page for the same reason the
                // bottom bar does: the add-location form has no reference day,
                // so a stepper beside it would step a value nothing on screen
                // is showing (design_system §7).
                if (stepper != null)
                  ValueListenableBuilder<int>(
                    valueListenable: subPageDepth,
                    builder: (context, depth, pill) => depth > 0
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xl),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: pill,
                            ),
                          ),
                    child: stepper,
                  ),
                const Spacer(),
                ?account,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon disc plus wordmark. Identity only, deliberately not a link: the rail
/// already offers the route a brand mark would navigate to.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  static const double _discSize = 36;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Container(
          width: _discSize,
          height: _discSize,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            Icons.public_rounded,
            size: _iconSize,
            color: colors.onPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            t.app.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleMedium?.copyWith(
              color: colors.onBackground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
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
    final radius = BorderRadius.circular(AppRadius.md);
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isSelected ? colors.primary : null,
              borderRadius: radius,
            ),
            child: Padding(
              // Taller than it is wide on purpose: `md` all round makes a
              // 46px row, and a navigation target under the 48px guideline is
              // the one control a user has to aim at on every visit.
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? destination.selectedIcon : destination.icon,
                    size: _iconSize,
                    color: foreground,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
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

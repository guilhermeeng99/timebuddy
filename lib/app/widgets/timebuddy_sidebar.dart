import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The app's primary destinations, in the order both nav surfaces show them.
///
/// Declared next to the sidebar rather than in a file of their own: a handful
/// of constants read by exactly two widgets do not earn a
/// `nav_destinations.dart` you have to open to learn nothing.
/// `TimeBuddyBottomBar` imports them from here, which is the point — two
/// hand-maintained lists would eventually disagree on an icon, a label or the
/// order, and the disagreement would only be visible to a user who resizes the
/// window.
///
/// **Five is the ceiling.** `TimeBuddyBottomBar` gives every collapsed
/// destination a fixed icon width and spends the rest on the expanded one; a
/// sixth entry puts the collapsed items under that width on a 360pt phone and
/// the pill overflows (design_system §7, and the arithmetic is written out at
/// `TimeBuddyBottomBar.collapsedItemWidth`). A sixth destination is a
/// "More" sheet, not a sixth icon.
///
/// ```dart
/// for (final destination in TimeBuddyNavDestination.values)
///   NavItem(destination: destination, isSelected: destination.matches(path));
/// ```
/// **One glyph per destination, not an outline/fill pair.** The nav used to
/// carry two Material icons each and swap them on selection; Font Awesome's
/// free set has a regular weight for `clock` but none for `tableCells`,
/// `rightLeft` or `gear`, so half the nav would have swapped shape and half
/// would not. Selection is carried by colour, by the tinted pill behind the
/// item and by the accent bar beside it — three signals that work for every
/// destination — and the icon stays the destination's name.
enum TimeBuddyNavDestination {
  /// The comparison grid, and the app's start route
  /// (docs/specs/time_grid.md).
  grid(route: AppRoutes.grid, icon: FontAwesomeIcons.tableCells),

  /// The live world clock (docs/specs/world_clock.md).
  clocks(route: AppRoutes.clocks, icon: FontAwesomeIcons.clock),

  /// The one-instant converter (docs/specs/time_converter.md).
  converter(route: AppRoutes.converter, icon: FontAwesomeIcons.rightLeft),

  /// Preferences (docs/specs/preferences.md). Rendered as the identity tile at
  /// the foot of the rail, and as an ordinary item on the phone's bottom bar.
  settings(route: AppRoutes.settings, icon: FontAwesomeIcons.gear);

  const TimeBuddyNavDestination({required this.route, required this.icon});

  /// The `AppRoutes` path this destination navigates to.
  final String route;

  /// The destination's glyph, in both states.
  ///
  /// `FaIconData` rather than `IconData`: the two carry different font
  /// families, and the type is what stops a Material glyph landing in a nav
  /// that is otherwise all Font Awesome (design_system section 4).
  final FaIconData icon;

  /// Filled counterpart, shown while the destination is active.
  /// The localized label, resolved on every read.
  ///
  /// A getter and not a field because a `const` enum value cannot hold a
  /// string that changes with the locale: the user switches language in
  /// settings and both nav surfaces have to relabel on the next build.
  String get label => switch (this) {
    TimeBuddyNavDestination.grid => t.nav.grid,
    TimeBuddyNavDestination.clocks => t.nav.clocks,
    TimeBuddyNavDestination.converter => t.nav.converter,
    TimeBuddyNavDestination.settings => t.nav.settings,
  };

  /// Whether [location] belongs to this destination.
  ///
  /// Sub-routes count, so a pushed sub-page keeps its destination highlighted
  /// while it is open. The grid is the exception twice over: its route is the
  /// root path, which prefixes every other path in the app, so it cannot use
  /// the prefix test — and it owns the add-location sheet, whose `/add` is a
  /// sibling of `/` rather than a child of it once written out. Naming that
  /// one route is what keeps Grid lit while the city picker is open, which is
  /// where the sheet is opened from.
  bool matches(String location) {
    if (route == AppRoutes.grid) {
      return location == route || location == AppRoutes.addLocation;
    }
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
/// **It has two widths, and the narrow one exists for the grid.** Between 600
/// and 900 it collapses to an 80pt strip of icons; from 900 up it shows its
/// labels. A 240pt rail is 40% of a 600pt window, which is why widening a
/// phone past the breakpoint used to *lose* the user hour columns — 599px
/// showed nine of them and 600px showed three. Collapsing turns that cliff
/// into a step of two (docs/specs/time_grid.md, Responsive).
///
/// The rail owns the date stepper only while it is expanded, because an 80pt
/// strip cannot hold one; collapsed, the page draws its own exactly as it does
/// on a phone. That is [ResponsiveLayout.sidebarIsExpanded], not
/// [ResponsiveLayout.isMobile], and the two are different questions now.
///
/// The stepper arrives as a widget in the
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

  /// The settings destination, wearing the user's face
  /// (`SidebarProfileTile`), pinned to the bottom.
  ///
  /// A slot rather than something the rail builds, so this widget stays out of
  /// `AuthBloc`: the shell already reads the session to decide other things,
  /// and a rail that imported auth would be a second reader of it.
  ///
  /// `null` leaves the foot of the rail empty, which is what a test that only
  /// cares about nav geometry wants — but the app always passes one, and
  /// **the rail drops the settings row from its nav list either way**, so a
  /// caller who forgets it loses the destination rather than showing it twice.
  final Widget? profile;

  /// Rail width with labels. Sized around the date stepper, the widest thing
  /// it holds: below this the stepper is the first element to wrap.
  static const double expandedWidth = 240;

  /// Rail width without labels: one 48pt tap target plus its gutters, which is
  /// the narrowest a nav item may be and still be aimed at.
  static const double collapsedWidth = 80;

  /// The width the rail actually occupies on this surface, `0` when it is not
  /// rendered at all.
  ///
  /// Exposed because the shell's `Row` gives the rail its width and every
  /// other page gets what is left, so anything reasoning about the content box
  /// needs the same number rather than a second copy of the rule.
  static double widthFor(BuildContext context) {
    if (!ResponsiveLayout.showsSidebar(context)) return 0;
    return ResponsiveLayout.sidebarIsExpanded(context)
        ? expandedWidth
        : collapsedWidth;
  }

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveLayout.showsSidebar(context)) {
      return const SizedBox.shrink();
    }
    final expanded = ResponsiveLayout.sidebarIsExpanded(context);
    final colors = context.appColors;
    final stepper = datePill;
    final account = profile;
    return SizedBox(
      width: expanded ? expandedWidth : collapsedWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(right: BorderSide(color: colors.surfaceVariant)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? AppSpacing.lg : AppSpacing.sm,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Scrolls rather than a `Spacer`, and measured rather than
                // assumed: brand (36) + gap (24) + four 58pt rows (232) +
                // profile tile (~64) + stepper block (~60) is ~416pt of rail,
                // which fits a portrait tablet and does not fit a landscape
                // phone at 360pt tall —
                // and the rail renders at any width >= 600, so that viewport
                // is reachable. A `Spacer` in an over-full Column is a
                // RenderFlex overflow; a scroll view is a scroll view.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BrandMark(expanded: expanded),
                        const SizedBox(height: AppSpacing.xxl),
                        // Settings is skipped here and rendered as the
                        // identity tile pinned below instead. It stays a
                        // destination — the phone's bottom bar has no bottom
                        // edge to pin anything to, so there it is one more
                        // icon — but on a rail the thing a user reaches for at
                        // the end of a nav is their account, and an avatar
                        // answers "signed in, as whom" without opening it.
                        for (final destination
                            in TimeBuddyNavDestination.values)
                          if (destination != TimeBuddyNavDestination.settings)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              child: _SidebarNavItem(
                                destination: destination,
                                isSelected: destination.matches(currentRoute),
                                expanded: expanded,
                                onTap: () => onSelect(destination),
                              ),
                            ),
                        // The stepper drops out on a sub-page for the same
                        // reason the bottom bar does: the add-location form
                        // has no reference day, so a stepper beside it would
                        // step a value nothing on screen is showing
                        // (design_system §7).
                        // Collapsed, the stepper is not hidden but handed
                        // back: `ShellDatePill` reads the same predicate and
                        // renders it on the page, so there is still exactly
                        // one stepper on screen (design_system §7).
                        if (stepper != null && expanded)
                          ValueListenableBuilder<int>(
                            valueListenable: subPageDepth,
                            builder: (context, depth, pill) => depth > 0
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.xl,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: pill,
                                    ),
                                  ),
                            child: stepper,
                          ),
                      ],
                    ),
                  ),
                ),
                // Outside the scroll view: the account block is pinned to the
                // bottom edge of the rail, which is where §7 puts it and where
                // a user reaches for it without reading the nav first.
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
  const _BrandMark({required this.expanded});

  /// Collapsed, the disc stands alone. The wordmark is the first thing to go
  /// because it is the one element on the rail that names nothing reachable.
  final bool expanded;

  static const double _discSize = 36;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final disc = Container(
      width: _discSize,
      height: _discSize,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: AppIcon(
        FontAwesomeIcons.earthAmericas,
        size: _iconSize,
        color: colors.onPrimary,
      ),
    );
    if (!expanded) return Center(child: disc);
    return Row(
      children: [
        disc,
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
    required this.expanded,
    required this.onTap,
  });

  final TimeBuddyNavDestination destination;
  final bool isSelected;

  /// Whether the label renders beside the glyph.
  ///
  /// Collapsed it becomes a `semanticLabel` and a tooltip instead of
  /// disappearing: an icon rail that is four unnamed glyphs to a screen reader
  /// is not a rail, it is a puzzle. `TimeBuddyBottomBar` solves the identical
  /// problem the identical way.
  final bool expanded;

  final VoidCallback onTap;

  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.md);
    final foreground = isSelected ? colors.onPrimary : colors.onBackgroundLight;
    final content = expanded
        ? _labelled(context, foreground)
        : Center(
            child: AppIcon(
              destination.icon,
              size: _iconSize,
              color: foreground,
              // Collapsed, nothing on screen names this destination, so the
              // glyph has to. Same move `TimeBuddyBottomBar` makes for its
              // four unexpanded items — one pattern, so an icon-only nav is
              // never four unnamed buttons to a screen reader.
              semanticLabel: destination.label,
            ),
          );
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
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? AppSpacing.md : AppSpacing.xs,
                vertical: AppSpacing.lg,
              ),
              child: expanded
                  ? content
                  : Tooltip(message: destination.label, child: content),
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelled(BuildContext context, Color foreground) {
    return Row(
      children: [
        AppIcon(destination.icon, size: _iconSize, color: foreground),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/widgets.dart';

/// The app's breakpoints and the width cap for reading content.
///
/// Named constants rather than inline comparisons because the same two numbers
/// decide three separate things — which nav chrome the shell renders, whether a
/// page draws its own date pill, and how wide its content may grow. A hardcoded
/// `600` in one of those three drifts silently from the other two.
///
/// ```dart
/// if (ResponsiveLayout.isMobile(context)) const TimeBuddyDatePill(),
/// ConstrainedBox(
///   constraints: const BoxConstraints(
///     maxWidth: ResponsiveLayout.maxContentWidth,
///   ),
///   child: form,
/// );
/// ```
abstract class ResponsiveLayout {
  /// Below this width there is no room for a sidebar: the shell switches to the
  /// floating bottom bar and pages surface their own date pill.
  static const double mobileBreakpoint = 600;

  /// At and above this width the layout stops being a scaled-up phone and can
  /// afford permanent chrome next to full-width content: this is where the
  /// rail stops being an icon strip and shows its labels ([sidebarIsExpanded]).
  ///
  /// Where the rail expands is a *taste* call, and the arithmetic says so
  /// rather than deciding it. Expanding costs the grid the rail's extra 160pt,
  /// which is a flat ~3.3 hour columns at every width until the whole window
  /// fits and the cost falls to zero — it does not grow with the screen. So
  /// expanding later would be strictly cheaper for the grid: a 1024pt laptop
  /// would keep three more columns.
  ///
  /// It expands at 900 anyway, because that is where this app already stops
  /// calling itself a phone, and a laptop showing an icon-only nav to buy the
  /// grid three columns is a worse trade than it sounds — the rail is on every
  /// screen, the grid is one of them. What the collapsed form is *for* is the
  /// 600-900 band, where 240pt of chrome was taking 40% of the window; see
  /// docs/specs/time_grid.md, Responsive.
  static const double desktopBreakpoint = 900;

  /// Width cap for form and list pages, centered on wider screens.
  ///
  /// Line length, not screen width, decides readability, so a settings page
  /// stretched across a 1600px monitor is worse, not better. The time grid is
  /// the one page allowed to ignore this: its value *is* showing as many hour
  /// columns as the screen fits (design_system §7).
  static const double maxContentWidth = 600;

  /// Phone-sized: `width < 600`.
  ///
  /// **Asks "is this a phone", not "is the rail on screen".** Those were the
  /// same question while the rail was all-or-nothing; they stopped being one
  /// when the rail grew a collapsed form, so a caller that means the second
  /// one wants [showsSidebar] or [sidebarIsExpanded]. The difference is
  /// load-bearing for anything that reasons about a 360pt screen — stacking a
  /// control under its title, dropping a country line — because a 700pt tablet
  /// is *wider* than a phone once the rail is 80pt, not narrower.
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  /// Whether the shell renders the rail at all, in either of its two widths.
  ///
  /// The inverse is "the floating bottom bar is on screen", which is what the
  /// FAB lift, the two clearance helpers and the snackbar actually mean.
  static bool showsSidebar(BuildContext context) => !isMobile(context);

  /// Whether the rail is showing its 240pt labelled form rather than the 80pt
  /// icon rail.
  ///
  /// Between 600 and 900 the rail collapses to icons, and that is the one
  /// place the grid gets its width back: a 240pt rail on a 700pt window is
  /// 34% of the screen, which is why widening a phone past 600px used to show
  /// *fewer* hours than the phone did (docs/specs/time_grid.md, Responsive).
  ///
  /// It also decides who owns the reference-day stepper: an 80pt rail cannot
  /// hold one, so the page draws its own, exactly as it does on a phone.
  static bool sidebarIsExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

}

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
  /// afford permanent chrome next to full-width content.
  static const double desktopBreakpoint = 900;

  /// Width cap for form and list pages, centered on wider screens.
  ///
  /// Line length, not screen width, decides readability, so a settings page
  /// stretched across a 1600px monitor is worse, not better. The time grid is
  /// the one page allowed to ignore this: its value *is* showing as many hour
  /// columns as the screen fits (design_system §7).
  static const double maxContentWidth = 600;

  /// Phone-sized: `width < 600`.
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  /// Tablet-sized: `600 <= width < 900`.
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= mobileBreakpoint && width < desktopBreakpoint;
  }

  /// Desktop-sized: `width >= 900`.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;
}

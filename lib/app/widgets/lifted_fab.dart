import 'package:flutter/material.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/sub_page_scope.dart';
import 'package:timebuddy/app/widgets/timebuddy_bottom_bar.dart';

/// Floats a FAB clear of the mobile bottom bar (design_system §7).
///
/// Wrap the widget handed to `Scaffold.floatingActionButton`, not the page.
/// The lift applies **only on mobile and only at [SubPageScope] depth 0**,
/// which is exactly when [TimeBuddyBottomBar] is on screen: at `>= 600px` the
/// sidebar replaces the bar, and on a sub-page the bar is hidden, so lifting
/// in either case would strand the FAB in empty space.
///
/// It reads the depth through [subPageDepth] rather than taking a flag,
/// because the FAB's owner is the page *under* the sub-page and has no way to
/// know one was pushed on top of it.
///
/// ```dart
/// Scaffold(
///   floatingActionButton: LiftedFab(
///     child: FloatingActionButton(onPressed: addLocation, child: addIcon),
///   ),
///   body: body,
/// );
/// ```
class LiftedFab extends StatelessWidget {
  const LiftedFab({required this.child, super.key});

  /// The FAB itself.
  final Widget child;

  /// How far the FAB rises on mobile: `96 - 16 = 80`.
  ///
  /// Derived rather than written as `80`, because the number is a consequence
  /// of two other numbers. The Scaffold already parks a FAB
  /// `kFloatingActionButtonMargin` above the bottom edge, and the bar occupies
  /// [TimeBuddyBottomBar.reservedHeight] there, so the lift is whatever closes
  /// the gap between them. Retune the bar and the FAB follows it.
  static const double mobileLift =
      TimeBuddyBottomBar.reservedHeight - kFloatingActionButtonMargin;

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveLayout.isMobile(context)) return child;
    return ValueListenableBuilder<int>(
      valueListenable: subPageDepth,
      builder: (context, depth, fab) => Padding(
        padding: EdgeInsets.only(bottom: depth > 0 ? 0 : mobileLift),
        child: fab,
      ),
      // Passed as the builder's `child` so a depth change repositions the FAB
      // without rebuilding it.
      child: child,
    );
  }
}

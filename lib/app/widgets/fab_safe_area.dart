import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_bottom_bar.dart';

/// Bottom clearance for a scroll view that sits under a floating FAB.
///
/// The chrome at the bottom of a TimeBuddy page floats *over* the content: the
/// bar so the grid keeps the full window height for hour columns, the FAB
/// because that is what a FAB is. Neither reserves layout space, so a list
/// that stops at its own last pixel hands the user a final row they can see
/// and cannot tap. This is the helper design_system §10 item 4 promises, and
/// it lands with the first FAB precisely so nobody has to invent a per-page
/// `96` / `120` / `160` in the meantime.
///
/// **What it returns**, before the system inset described below:
///
/// | Where | Value | Why |
/// |---|---|---|
/// | Mobile, depth 0 | `168` | `96` bar block + `56` FAB + `16` breathing |
/// | Mobile, sub-page | `88` | `16` FAB margin + `56` FAB + `16` breathing |
/// | `>= 600px` | `88` | Sidebar instead of a bar; the FAB is not lifted |
///
/// The `96` is [TimeBuddyBottomBar.reservedHeight] and the `16` is
/// `kFloatingActionButtonMargin`, both read rather than retyped, so retuning
/// the bar moves the clearance with it.
///
/// [isSubPage] is a parameter and not a read of `subPageDepth` because the
/// page knows the answer statically — a page either is pushed on top of the
/// shell or it is not — and a listenable read here would be a value that goes
/// stale without rebuilding anything.
///
/// The unconsumed bottom system inset (`MediaQuery.paddingOf`, not
/// `viewPaddingOf`) is added on top. Using the consumed-aware getter makes the
/// helper self-correcting: under a `SafeArea` it reads zero and adds nothing,
/// without this function having to know how the shell was assembled.
///
/// ```dart
/// ListView.builder(
///   padding: EdgeInsets.only(
///     bottom: bottomSafeForFab(context, isSubPage: false),
///   ),
///   itemCount: locations.length,
///   itemBuilder: ...,
/// );
/// ```
double bottomSafeForFab(BuildContext context, {required bool isSubPage}) {
  final systemInset = MediaQuery.paddingOf(context).bottom;
  const fabBlock = _regularFabDiameter + AppSpacing.lg;
  // No bar on screen means no lift either, so the FAB sits at the Scaffold's
  // own margin. LiftedFab decides this from the same two conditions.
  if (isSubPage || !ResponsiveLayout.isMobile(context)) {
    return systemInset + kFloatingActionButtonMargin + fabBlock;
  }
  return systemInset + TimeBuddyBottomBar.reservedHeight + fabBlock;
}

/// Bottom clearance for a scroll view under the floating bar but with no FAB.
///
/// Settings is the case: a primary destination, so the bar floats over it,
/// but nothing on it wants a FAB. Returns `96`
/// ([TimeBuddyBottomBar.reservedHeight]) plus the unconsumed system inset on
/// mobile at depth 0, and the inset alone everywhere else — at `>= 600px` the
/// sidebar occupies its own column and takes nothing off the bottom, and a
/// sub-page has no bar over it to clear.
///
/// Not the grid: the grid carries the add-city FAB and uses
/// [bottomSafeForFab], which already includes this bar block.
///
/// ```dart
/// ListView.builder(
///   padding: EdgeInsets.only(
///     bottom: bottomSafeForBar(context, isSubPage: false),
///   ),
///   itemCount: rows.length,
///   itemBuilder: ...,
/// );
/// ```
double bottomSafeForBar(BuildContext context, {required bool isSubPage}) {
  final systemInset = MediaQuery.paddingOf(context).bottom;
  if (isSubPage || !ResponsiveLayout.isMobile(context)) return systemInset;
  return systemInset + TimeBuddyBottomBar.reservedHeight;
}

/// Diameter of a regular `FloatingActionButton`.
///
/// Material fixes it at 56 and Flutter does not export a constant for it, so
/// it is named once here rather than being retyped by every page that has to
/// clear one.
const double _regularFabDiameter = 56;

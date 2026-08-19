import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// The default page header: a large, left-aligned title in the iOS manner.
///
/// Left-aligned rather than centered because TimeBuddy's titles are city and
/// feature names of very different lengths, and a centered title truncates from
/// both ends the moment an action lands next to it.
///
/// ```dart
/// Scaffold(
///   appBar: TimeBuddyLargeAppBar(
///     title: t.settings.title,
///     actions: [TimeBuddyAppBarIconButton(icon: Icons.check, onTap: save)],
///   ),
///   body: body,
/// );
/// ```
class TimeBuddyLargeAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const TimeBuddyLargeAppBar({
    required this.title,
    this.actions,
    this.showBack = true,
    super.key,
  });

  /// Localized page title.
  final String title;

  /// Trailing actions, in the usual app-bar slot.
  final List<Widget>? actions;

  /// Whether this page *wants* a back affordance. Whether it *gets* one also
  /// depends on there being something to pop; see [build].
  final bool showBack;

  static const double _height = 64;
  static const double _chevronSize = 20;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A page reached with `go` replaces the stack instead of pushing onto it,
    // and on web any sub-page can be opened cold from its URL. In both cases
    // there is nothing beneath this route, so an unconditional chevron renders
    // dead: it is visible, it is tappable, and it does nothing
    // (design_system §7).
    final canGoBack = showBack && Navigator.canPop(context);
    return AppBar(
      toolbarHeight: _height,
      backgroundColor: colors.surface,
      surfaceTintColor: colors.surface,
      elevation: 0,
      centerTitle: false,
      automaticallyImplyLeading: false,
      titleSpacing: canGoBack ? 0 : AppSpacing.lg,
      leading: canGoBack
          ? IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                size: _chevronSize,
              ),
              color: colors.onBackground,
              // Popped through the Navigator rather than through GoRouter so
              // the bar also works inside a plain pushed route (dialogs, tests)
              // that has no router above it.
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.headlineLarge?.copyWith(
          color: colors.onBackground,
        ),
      ),
      actions: actions,
    );
  }
}

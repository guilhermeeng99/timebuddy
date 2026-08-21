import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/extensions/context_navigation_extensions.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

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
///     actions: [
///       TimeBuddyAppBarIconButton(
///         icon: FontAwesomeIcons.check,
///         onTap: save,
///       ),
///     ],
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
    this.fallbackRoute,
    super.key,
  });

  /// Localized page title.
  final String title;

  /// Trailing actions, in the usual app-bar slot.
  final List<Widget>? actions;

  /// Whether this page *wants* a back affordance. Whether it *gets* one also
  /// depends on there being something to pop, or on [fallbackRoute]; see
  /// [build].
  final bool showBack;

  /// Where the chevron goes when there is nothing to pop.
  ///
  /// **Pass this on any page that is reachable by URL but is not one of the
  /// nav destinations** — `/profile` is the case that made it necessary. Such
  /// a page opened cold (a bookmark, a pasted link, a page reload on web) has
  /// an empty navigator stack *and* no bottom bar or rail around it, so
  /// without a fallback the chevron correctly hides itself and leaves the user
  /// with no way out of the screen at all.
  ///
  /// `null` keeps the old behaviour, which is right for a pushed sheet that
  /// genuinely cannot be reached cold.
  final String? fallbackRoute;

  static const double _height = 64;
  static const double _chevronSize = 20;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A page reached with `go` replaces the stack instead of pushing onto it,
    // and on web any sub-page can be opened cold from its URL. In both cases
    // there is nothing beneath this route, so an unconditional chevron would
    // render dead: visible, tappable, and doing nothing (design_system §7).
    //
    // Hiding it is only the right answer when the page has other chrome around
    // it. A root-level route outside the shell has none, so a page that hands
    // over a [fallbackRoute] keeps its chevron and closes through `popOrGo`.
    final fallback = fallbackRoute;
    final canGoBack =
        showBack && (Navigator.canPop(context) || fallback != null);
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
              icon: const AppIcon(
                FontAwesomeIcons.chevronLeft,
                size: _chevronSize,
              ),
              // Without this the only control on the bar announces itself as
              // "button". A chevron is a shape, not a name.
              tooltip: t.common.back,
              color: colors.onBackground,
              // Without a fallback this stays a plain `Navigator.pop`, so the
              // bar still works inside a pushed route that has no router above
              // it (dialogs, widget tests). With one, it has to ask the router
              // instead, because that is the only thing that knows whether
              // there is a push to unwind or a URL to go to.
              onPressed: () => fallback == null
                  ? Navigator.of(context).pop()
                  : context.popOrGo(fallback),
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

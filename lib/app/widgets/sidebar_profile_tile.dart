import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The settings destination, pinned to the foot of the rail and wearing the
/// user's face (design_system §7).
///
/// **Why the same destination gets two shapes.** On a phone the bottom bar
/// lists settings as one more icon, because a floating pill has no bottom edge
/// to pin anything to. On the rail it becomes this: the thing a user reaches
/// for at the end of a nav is their account, and an avatar answers "am I
/// signed in, and as whom" without them opening anything.
///
/// [user] is `null` for a guest and for the frame before auth settles. It says
/// so rather than inventing a placeholder identity: guest mode is a supported
/// way to use this app, not a state to paper over
/// (docs/specs/guest_mode.md rule 1).
///
/// ```dart
/// TimeBuddySidebar(
///   profile: SidebarProfileTile(
///     user: signedInUser,
///     isSelected: destination == TimeBuddyNavDestination.settings,
///     onTap: () => context.go(AppRoutes.settings),
///   ),
/// );
/// ```
class SidebarProfileTile extends StatelessWidget {
  const SidebarProfileTile({
    required this.user,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final UserEntity? user;
  final bool isSelected;
  final VoidCallback onTap;

  /// Matches `_SidebarNavItem`'s selected tint, so the foot of the rail reads
  /// as part of the same nav rather than as a widget that happens to sit
  /// below it.
  static const double _selectedTintAlpha = 0.10;

  static const double _restingTintAlpha = 0.6;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.md);
    // Reads the rail's state itself rather than taking it as a parameter,
    // because it arrives at the rail through an opaque `Widget?` slot and a
    // slot cannot shrink what it is handed (`TimeBuddySidebar.profile`).
    final expanded = ResponsiveLayout.sidebarIsExpanded(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Material(
        color: isSelected
            ? colors.primary.withValues(alpha: _selectedTintAlpha)
            : colors.surfaceVariant.withValues(alpha: _restingTintAlpha),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: !expanded
                ? Tooltip(
                    message: user?.name ?? t.settings.notSignedIn,
                    child: Center(
                      child: _Avatar(user: user, colors: colors),
                    ),
                  )
                : Row(
                    children: [
                      _Avatar(user: user, colors: colors),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user?.name ?? t.settings.notSignedIn,
                              style: context.textTheme.labelLarge?.copyWith(
                                color: colors.onBackground,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              t.nav.settings,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: colors.onBackgroundLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      AppIcon(
                        FontAwesomeIcons.chevronRight,
                        size: _chevronSize,
                        color: colors.onBackgroundLight,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  static const double _chevronSize = 11;
}

/// The Google photo, or the first letter of the name over a tinted square.
///
/// The fallback is not decoration: `photoUrl` is nullable on `UserEntity`, a
/// guest has no name at all, and a perfectly valid URL can still fail to load
/// on a flaky network — so the initial has to cover three different absences
/// and `?` is the honest answer to the third.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.colors});

  final UserEntity? user;
  final AppColorsData colors;

  static const double _size = 36;
  static const double _initialFontSize = 14;
  static const double _glyphSize = 15;
  static const double _tintAlpha = 0.18;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user?.photoUrl;
    return SizedBox(
      width: _size,
      height: _size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // The fallback is the *background*, with the photo painted over it.
        // `Image.network` has no frame to show while a request is in flight,
        // and a Google photo URL is refused cross-origin often enough on web
        // to matter — so a fallback used only in `errorBuilder` leaves the
        // disc blank and then pops. The rail is on every screen, which makes
        // that the most-seen flicker in the app.
        child: Stack(
          fit: StackFit.expand,
          children: [
            _fallback(),
            if (photoUrl != null && photoUrl.isNotEmpty)
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() {
    final initial = _initialOf(user?.name);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: _tintAlpha),
            colors.primaryLight.withValues(alpha: _tintAlpha),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        // A guest gets a person, not a `?`. A question mark reads as an avatar
        // that failed to load; using the app without an account is a supported
        // choice, not an unknown (docs/specs/guest_mode.md rule 1).
        child: initial == null
            ? AppIcon(
                FontAwesomeIcons.solidUser,
                size: _glyphSize,
                color: colors.primary,
              )
            : Text(
                initial,
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: _initialFontSize,
                ),
              ),
      ),
    );
  }

  /// The first *character* of [name], or `null` when there is no name.
  ///
  /// Taken by rune and not by `substring(0, 1)`, which slices a name starting
  /// outside the BMP through its surrogate pair and renders half a codepoint.
  static String? _initialOf(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

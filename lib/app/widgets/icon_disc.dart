import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';

/// A glyph inside a circle of its own color at [AppAlpha.tint].
///
/// The mark every full-screen block in the app opens with: `ErrorView`'s
/// apology, `FeatureEmptyState`'s invitation, an onboarding slide, the splash's
/// brand mark (design_system §6). Those four each carried their own
/// `Container` + `BoxDecoration(shape: circle)` + `AppIcon`, and two of them
/// carried a comment saying the copy deliberately matched the others — which is
/// the argument for one widget rather than for a fourth copy of it.
///
/// [color] is the only thing a caller must choose: `colors.error` says
/// something broke, `colors.primary` says nothing did. Size is a parameter and
/// not a constant because the four are **not** the same disc — onboarding wants
/// a larger mark on a screen that holds nothing else, and the splash's glyph is
/// 34 against the standard 32. Both are preserved rather than flattened; that
/// drift is a design question, not a refactor's to settle.
///
/// ```dart
/// IconDisc(
///   icon: FontAwesomeIcons.earthAmericas,
///   color: context.appColors.primary,
/// );
/// ```
class IconDisc extends StatelessWidget {
  const IconDisc({
    required this.icon,
    required this.color,
    this.diameter = defaultDiameter,
    this.iconSize = defaultIconSize,
    super.key,
  });

  /// The glyph. Name the subject, not its absence: a crossed-out icon over an
  /// empty state reads as a failure, and nothing failed.
  final FaIconData icon;

  /// Drawn at full strength on the glyph and at [AppAlpha.tint] on the disc,
  /// so the two can never be picked from different tokens.
  final Color color;

  /// Outer diameter of the disc.
  final double diameter;

  /// Size of the glyph inside it.
  final double iconSize;

  /// The proportions `ErrorView` and `FeatureEmptyState` share, and the size
  /// any new block should start from.
  static const double defaultDiameter = 72;
  static const double defaultIconSize = 32;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppAlpha.tint),
        shape: BoxShape.circle,
      ),
      child: AppIcon(icon, size: iconSize, color: color),
    );
  }
}

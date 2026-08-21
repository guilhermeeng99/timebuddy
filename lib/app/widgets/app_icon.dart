import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Every icon in the app: a Font Awesome glyph, centred in a square of its own
/// nominal size (design_system §4b).
///
/// **Why this exists rather than a bare `FaIcon`.** `FaIcon` is a copy of
/// Flutter's `Icon` with the `SizedBox` and the `Center` deliberately removed,
/// so a glyph renders at its own intrinsic width instead of being boxed. That
/// is the right call for the package — Font Awesome glyphs are often wider
/// than they are tall, and a fixed square clips them — but it makes every
/// `FaIcon` inside a fixed-size parent sit wherever its advance width leaves
/// it. In this app that showed up as a brand mark pinned to the corner of its
/// disc and date-stepper chevrons drifting out of their tap targets.
///
/// This widget puts the box and the centring back *around* the glyph rather
/// than around the font: the glyph still lays out at its own width, and the
/// square that holds it is what the parent measures. One widget, so a fix to
/// the rule lands everywhere at once.
///
/// ```dart
/// AppIcon(FontAwesomeIcons.chevronRight, size: 12, color: colors.onBackground)
/// ```
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    this.size,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final FaIconData icon;

  /// Edge of the square, and the glyph's font size. Falls back to the ambient
  /// `IconTheme`, the way `Icon` does.
  final double? size;

  final Color? color;

  /// Without this a glyph is invisible to a screen reader. Pass one whenever
  /// the icon carries meaning the surrounding text does not.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = size ?? IconTheme.of(context).size ?? 24;
    return SizedBox(
      width: resolved,
      height: resolved,
      child: Center(
        // `Center` and not `FittedBox`: a glyph wider than the square is
        // allowed to overhang rather than be scaled down, because scaling one
        // icon in a row makes it visibly lighter than its neighbours.
        child: FaIcon(
          icon,
          size: resolved,
          color: color,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

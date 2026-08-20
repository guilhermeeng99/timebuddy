import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/offset_badge.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The identity block of a saved location: who this row is, and how far from
/// you.
///
/// One widget serves two callers on purpose. It is the grid's pinned first
/// column (time_grid.md, Anatomy) *and* the identity half of a row in the
/// saved-cities list, because they state the same four facts; two widgets
/// would be how the grid ends up saying `Sao Paulo · BRT` while the list says
/// `Sao Paulo (BR)`.
///
/// It renders and decides nothing about time. Every value it shows —
/// [abbreviation], [relativeToHome] — is resolved by the caller for **the
/// instant on screen**, because both move with the zone's DST transitions and
/// a value cached on the row would keep claiming `BRT` into November.
///
/// It also says nothing about an unresolved row beyond marking it. The two
/// screens that own that state print their own sentence for it
/// (`t.locations.unresolvedZone` beside the repair on the board,
/// `t.grid.unresolvedRow` across the empty track), and a note here would say
/// it twice on the same row.
///
/// ```dart
/// LocationRow(
///   location: row.location,
///   abbreviation: row.zoneState?.abbreviation,
///   relativeToHome: row.relativeToHome,
///   isHome: row.isHome,
///   isUnresolved: row.isUnresolved,
///   dense: ResponsiveLayout.isMobile(context),
/// );
/// ```
class LocationRow extends StatelessWidget {
  const LocationRow({
    required this.location,
    this.abbreviation,
    this.relativeToHome,
    this.isHome = false,
    this.isUnresolved = false,
    this.dense = false,
    super.key,
  });

  /// The board row being drawn. Its `label` and `countryCode` are the
  /// denormalised display copy; the raw IANA id is never shown, because
  /// `America/Sao_Paulo` is an identifier and "Sao Paulo" is a label
  /// (CLAUDE.md, UI & Formatting).
  final SavedLocationEntity location;

  /// Zone abbreviation for the instant shown (`BRT`, `IST`, `+07`), from
  /// `ZoneState.abbreviation`. `null` renders no abbreviation, which is the
  /// honest answer for a row whose zone did not resolve.
  final String? abbreviation;

  /// Difference from the home zone at that instant, from `GridRow`. `null`
  /// hides the badge entirely; [Duration.zero] is a real answer and renders
  /// "same time as home" (see [OffsetBadge]).
  final Duration? relativeToHome;

  /// Marks the board's reference row. Its difference from home is zero by
  /// definition, so the badge slot carries the home marker rather than a
  /// number that could only ever read "same time as home".
  final bool isHome;

  /// The stored zone id is not in the shipped tzdata (locations.md rule 11).
  /// The row is greyed and marked rather than dropped: it keeps its position
  /// so the board order stays stable while the user repairs it, and a row that
  /// vanished on a data upgrade would read as deleted data.
  final bool isUnresolved;

  /// Narrow form for the grid's 96px mobile label column, which drops the
  /// country line and keeps the label, the abbreviation and the offset
  /// (time_grid.md, Responsive). The type scale does **not** shrink with it: a
  /// label nobody can read costs the same width as one they can.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      // Horizontal only. In the grid this block is handed a tight 64px row, so
      // vertical padding here is what turns the third line into an overflow.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            location.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isUnresolved ? colors.onBackgroundLight : null,
            ),
          ),
          if (!dense)
            Text(
              location.countryCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // labelMedium rather than bodySmall: the body styles carry a 1.5
              // line height, and three of those do not fit a 64px row.
              style: context.textTheme.labelMedium?.copyWith(
                color: colors.onBackgroundLight,
              ),
            ),
          _StatusLine(
            abbreviation: abbreviation,
            relativeToHome: relativeToHome,
            isHome: isHome,
            isUnresolved: isUnresolved,
            dense: dense,
          ),
        ],
      ),
    );
  }
}

/// The bottom line: what this zone is called right now, and how far off it is.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.abbreviation,
    required this.relativeToHome,
    required this.isHome,
    required this.isUnresolved,
    required this.dense,
  });

  final String? abbreviation;
  final Duration? relativeToHome;
  final bool dense;
  final bool isHome;
  final bool isUnresolved;

  @override
  Widget build(BuildContext context) {
    final relative = relativeToHome;
    // Dropped on every dense row that already has something more useful in
    // this slot: the Home chip on the home row, the unresolved mark on a
    // broken one, the relative offset on all the rest.
    //
    // The 96px mobile column leaves about 80px inside its padding, the Home
    // chip eats roughly 46 of them, and a zone abbreviation is routinely four
    // characters (CEST, AEDT) or five for a numeric zone (Asia/Kathmandu
    // renders `+0545`). Showing both meant a RenderFlex overflow: in a test it
    // shouts, in release it silently painted the chip across the grid's first
    // hour column. Measured on the deployed build at 390px, keeping both
    // ellipsized `+8h30` down to `+...`, which is the badge being present in
    // name only. Between that and dropping the abbreviation, dropping reads
    // better — the chip or the offset already says what the row is.
    final crowded = isHome || isUnresolved || relative != null;
    final zoneAbbreviation = dense && crowded ? null : abbreviation;
    return Row(
      children: [
        if (zoneAbbreviation != null) ...[
          // Flexible even now that the home row drops it: a large text scale
          // factor overflows this line unconditionally otherwise, and the
          // ellipsis is only reachable if the Text is allowed to shrink.
          Flexible(
            child: Text(
              zoneAbbreviation,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(
                color: context.appColors.onBackgroundLight,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (isUnresolved)
          const _UnresolvedMark()
        else if (isHome)
          const _HomeChip()
        else if (relative != null)
          // Always the dense badge: this column is 132px at its widest and
          // 96px on mobile, and the full pair would ellipsize away the
          // relative offset, which is the one number the column exists to
          // show.
          Flexible(
            child: OffsetBadge(relativeToHome: relative, dense: true),
          ),
      ],
    );
  }
}

class _HomeChip extends StatelessWidget {
  const _HomeChip();

  static const double _tintAlpha = 0.12;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: _tintAlpha),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          t.grid.homeBadge,
          maxLines: 1,
          style: context.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}

/// The mark on a row whose zone the tzdata no longer knows.
///
/// A glyph and a tooltip rather than a sentence: the sentence belongs to the
/// screen that offers the repair, and printing it here would double it on the
/// board while overflowing the grid's label column.
class _UnresolvedMark extends StatelessWidget {
  const _UnresolvedMark();

  static const double _iconSize = 14;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: t.locations.unresolvedZone,
      child: Icon(
        Icons.public_off,
        size: _iconSize,
        color: context.appColors.onBackgroundLight,
        semanticLabel: t.locations.unresolvedZone,
      ),
    );
  }
}

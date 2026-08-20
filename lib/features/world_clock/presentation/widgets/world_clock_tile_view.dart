import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/clock_text.dart';
import 'package:timebuddy/app/widgets/day_night_dot.dart';
import 'package:timebuddy/app/widgets/dst_badge.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/world_clock/domain/entities/world_clock_view_model.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Band tint behind a tile (rule 7): 8%, so a sleeping city looks asleep
/// without the digits on top of it losing contrast in either palette.
const double _bandTintAlpha = 0.08;

/// Digit size on a tile. Smaller than the hero's on purpose: the page has one
/// clock the user reads first, and twenty of equal weight is a wall.
const double _clockFontSize = 22;

/// Width reserved for the digits and the line under them.
///
/// Fixed, and measured rather than guessed. The widest reading is `12:34:56`
/// with seconds on (about 103px at [_clockFontSize]), and the line below it
/// carries a DST badge, `Tue 24` and `Tomorrow`. Bounding the column is what
/// lets those three ellipsize instead of overflowing: laid out unflexed
/// against an unbounded `Row`, `Flexible` buys nothing and the overflow only
/// appears on a narrow phone, in release, where nobody sees the stripes.
const double _clockColumnWidth = 136;

/// One live clock in the board list (docs/specs/world_clock.md rules 5 to 9).
///
/// Every value it renders arrives already resolved for the instant on screen;
/// the tile computes nothing about time. The **digits are the exception**, and
/// deliberately so: they come from [ClockText], which subscribes to the app's
/// shared `TickerService` and repaints one `Text` per tick. A `Timer` in here
/// would be one timer and one subtree rebuild per second per tile, which on a
/// 20-city board is the whole page (rule 3).
///
/// ```dart
/// WorldClockTileView(
///   tile: model.tiles[index],
///   showSeconds: preferences.showSeconds,
///   onTap: () => openDetail(model.tiles[index]),
/// );
/// ```
class WorldClockTileView extends StatelessWidget {
  const WorldClockTileView({
    required this.tile,
    required this.onTap,
    this.showSeconds = false,
    super.key,
  });

  /// The clock to draw, from `BuildWorldClockUseCase`.
  final WorldClockTile tile;

  /// Opens the location detail sheet (rule 9). The tile reports the tap and
  /// never navigates itself, so the same tile works in the list and in a
  /// preview.
  final VoidCallback onTap;

  /// Renders `HH:mm:ss`. Follows the `showSeconds` preference, which also
  /// decides the shared ticker's rate (rule 4).
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    // A Material, not a DecoratedBox carrying the tint. InkWell paints its ink
    // on the nearest Material ancestor, so a plain coloured box between the
    // row and the scaffold swallows every ripple: the tile still fires onTap,
    // it just looks dead under the finger.
    return Material(
      color: hourBandColor(
        tile.band,
        context.appColors,
      ).withValues(alpha: _bandTintAlpha),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              DayNightDot(band: tile.band),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LocationRow(
                  location: tile.location,
                  // Resolved for the instant on screen, never cached on the
                  // row: both move with the zone's next transition.
                  abbreviation: tile.abbreviation,
                  relativeToHome: tile.offsetFromHome,
                  isHome: tile.isHome,
                  isUnresolved: tile.isUnresolved,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _TileClock(
                tile: tile,
                showSeconds: showSeconds,
                onDstTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The right-hand block: the ticking digits, and what day they belong to.
class _TileClock extends StatelessWidget {
  const _TileClock({
    required this.tile,
    required this.showSeconds,
    required this.onDstTap,
  });

  final WorldClockTile tile;
  final bool showSeconds;
  final VoidCallback onDstTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _clockColumnWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClockText(
            zoneId: tile.location.zoneId,
            showSeconds: showSeconds,
            fontSize: _clockFontSize,
          ),
          const SizedBox(height: AppSpacing.xs),
          _DateLine(tile: tile, onDstTap: onDstTap),
        ],
      ),
    );
  }
}

/// The date, the relative day word, and the DST marker when one applies.
class _DateLine extends StatelessWidget {
  const _DateLine({required this.tile, required this.onDstTap});

  final WorldClockTile tile;
  final VoidCallback onDstTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dayWord = worldClockDayWord(tile.dayDelta);
    // Per tile, never once per page: at a single instant two cities can be on
    // different calendar dates, which is the whole point of rule 6.
    final localeTag = LocaleSettings.currentLocale.languageTag;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (tile.isDst) DstBadge(onTap: onDstTap),
        // One span rather than two Texts side by side. Two `Flexible`s split
        // the free width evenly regardless of what they need, so `Tomorrow`
        // would ellipsize next to a `Tue 24` sitting in half a column it never
        // asked for; one line lays out once and clips at its own end.
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: formatDayMonth(tile.localTime, localeTag)),
                if (dayWord != null)
                  TextSpan(
                    text: ' · $dayWord',
                    // The accent, because this is the fact the user came for
                    // on a board that crosses the date line (rule 6).
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: context.textTheme.labelMedium?.copyWith(
              color: colors.onBackgroundLight,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Tomorrow" / "Yesterday" for a [WorldClockTile.dayDelta], or `null` when
/// there is nothing to say (rule 6).
///
/// `null` for `0` because the tile then shares the home zone's date, and also
/// for the `±2` a Kiritimati-to-Niue board really can produce: naming that
/// "Yesterday" would be wrong by a day, and the date beside it is already
/// exact.
///
/// ```dart
/// worldClockDayWord(1);   // 'Tomorrow'
/// worldClockDayWord(-2);  // null
/// ```
String? worldClockDayWord(int dayDelta) => switch (dayDelta) {
  1 => t.worldClock.tomorrow,
  -1 => t.worldClock.yesterday,
  _ => null,
};

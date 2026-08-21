import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_typography.dart';
import 'package:timebuddy/app/widgets/day_night_dot.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/time_converter/domain/entities/conversion_result.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Band tint behind a row: 8%, the same weight the world clock's tiles carry,
/// so a city that is asleep at the converted moment looks asleep without the
/// digits on top of it losing contrast in either palette.
const double _bandTintAlpha = 0.08;

/// Digit size of one line's reading.
const double _readingFontSize = 22;

/// Width reserved for the reading and the date line under it.
///
/// Fixed and measured, not guessed. The widest reading is `12:30 PM` (about
/// 95px at [_readingFontSize] in the tabular clock face) and the widest date
/// line is `Tue 24 · Tomorrow` (about 110px at `labelMedium`). Bounding the
/// column is what lets those ellipsize instead of overflowing: laid out
/// unflexed against an unbounded `Row` a `Flexible` buys nothing, and the
/// overflow then only appears on a narrow phone, in release, where nobody
/// sees the stripes.
const double _readingColumnWidth = 132;

/// The converted moment, read in every city on the board (rules 3, 6 and 7).
///
/// Every value it draws arrives already resolved by `ConvertTimeUseCase` for
/// the instant in question; this widget computes nothing about time. The
/// digits in particular are **static text and not `ClockText`**: the
/// converter answers a question about a chosen moment, and digits that ticked
/// would quietly turn that answer into "now" a minute later.
///
/// An empty [lines] is a valid answer, not an error: a board holding only the
/// source zone gets the muted note rather than an empty state (Edge cases).
///
/// ```dart
/// ConversionResultList(
///   lines: result.lines,
///   hourFormat: preferences.hourFormat,
/// );
/// ```
class ConversionResultList extends StatelessWidget {
  const ConversionResultList({
    required this.lines,
    required this.hourFormat,
    super.key,
  });

  /// The board's lines in board order, minus the source zone (rule 3).
  final List<ConversionLine> lines;

  /// The user's 12h/24h preference, applied to every reading.
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const _NeedMoreCitiesNote();
    // A Column and not a lazy builder, deliberately: the board is capped at
    // `BoardEntity.maxLocations` rows, and this block is one child of the
    // page's scroll view. A nested lazy list would have to be given a height
    // or become a sliver, and both cost more than eagerly laying out at most
    // twenty rows that are already fully computed.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ConversionRow(line: line, hourFormat: hourFormat),
          ),
      ],
    );
  }
}

/// One city's reading of the converted instant.
class _ConversionRow extends StatelessWidget {
  const _ConversionRow({required this.line, required this.hourFormat});

  final ConversionLine line;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    // A DecoratedBox rather than a Material: nothing inside this row is
    // tappable, so there is no ink to be swallowed, and the row is drawn once
    // per conversion for up to twenty cities.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hourBandColor(
          line.band,
          context.appColors,
        ).withValues(alpha: _bandTintAlpha),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            DayNightDot(band: line.band),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: LocationRow(
                location: line.location,
                // Resolved for the converted instant, never cached on the
                // row: both move with the zone's transitions, which on a date
                // months out is the whole reason this page exists.
                abbreviation: line.abbreviation,
                relativeToHome: _offsetFromSource,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _LineReading(line: line, hourFormat: hourFormat),
          ],
        ),
      ),
    );
  }

  /// The distance from the source zone, or `null` when there is none.
  ///
  /// `null` rather than [Duration.zero] on a match, and only here: the badge
  /// renders `t.grid.sameTime` for zero, which names *home* as the reference.
  /// That is right on the board and wrong here the moment the user converts
  /// from a city that is not their home, and the two readings being identical
  /// is already visible in the digits beside it.
  Duration? get _offsetFromSource =>
      line.offsetFromSource == Duration.zero ? null : line.offsetFromSource;
}

/// The right-hand block: the local reading, and what day it belongs to.
class _LineReading extends StatelessWidget {
  const _LineReading({required this.line, required this.hourFormat});

  final ConversionLine line;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _readingColumnWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatClock(line.localTime, hourFormat),
            maxLines: 1,
            style: AppTypography.clock(
              color: context.appColors.onBackground,
              fontSize: _readingFontSize,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _DateLine(line: line),
        ],
      ),
    );
  }
}

/// The local date of this line, and the relative day word when there is one.
class _DateLine extends StatelessWidget {
  const _DateLine({required this.line});

  final ConversionLine line;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dayWord = _dayWord(line.dayDelta);
    // Per line, never once per page: at a single instant two cities can be on
    // different calendar dates, which is exactly what rule 7 is about.
    final localeTag = LocaleSettings.currentLocale.languageTag;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: formatDayMonth(line.localTime, localeTag)),
          if (dayWord != null)
            TextSpan(
              text: ' · $dayWord',
              // The accent, because on a board that crosses the date line
              // this is the fact the user came for.
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
    );
  }
}

/// Rule 3's other valid answer: the board holds nothing but the source.
class _NeedMoreCitiesNote extends StatelessWidget {
  const _NeedMoreCitiesNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        t.converter.needMoreCities,
        textAlign: TextAlign.center,
        style: context.textTheme.bodyMedium?.copyWith(
          color: context.appColors.onBackgroundLight,
        ),
      ),
    );
  }
}

/// "Tomorrow" / "Yesterday" for a [ConversionLine.dayDelta], or `null` when
/// there is nothing to say (rule 7).
///
/// `null` for `0` because the line then shares the source's date, and also
/// for the `±2` a Kiritimati-to-Niue board really can produce: naming that
/// "Yesterday" would be wrong by a day, and the date beside it is exact.
///
/// The world clock's copy, deliberately its own four lines rather than an
/// import of that page's helper: the two features say the same thing about a
/// day delta and have no other reason to depend on each other, which is the
/// same trade `ConvertTimeUseCase` made with its own stand-in row.
String? _dayWord(int dayDelta) => switch (dayDelta) {
  1 => t.worldClock.tomorrow,
  -1 => t.worldClock.yesterday,
  _ => null,
};

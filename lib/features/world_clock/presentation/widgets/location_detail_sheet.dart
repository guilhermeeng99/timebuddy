import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/clock_text.dart';
import 'package:timebuddy/app/widgets/dst_badge.dart';
import 'package:timebuddy/app/widgets/local_date_line.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_row.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_sheet.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/world_clock/domain/entities/world_clock_view_model.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Digit size in the sheet's header block. Between the tile's and the hero's:
/// the sheet is about one city, so its clock leads, but it shares the surface
/// with six lines of detail.
const double _sheetClockFontSize = 32;

/// What the user picked from a location's detail sheet.
///
/// The sheet reports a choice instead of performing it, exactly as
/// `showLocationRowActionsSheet` does: the caller already holds the
/// `BoardCubit` every mutation has to go through, so a sheet that mutated
/// would be a second place that writes the board.
enum LocationDetailAction {
  /// Make this clock's zone the board's reference zone.
  setHome,

  /// Take the row off the board. The caller owns the undo window.
  remove,

  /// Leave for the comparison grid, where this zone is one row among many.
  openInGrid,
}

/// Opens the detail sheet for one clock (docs/specs/world_clock.md rule 9).
///
/// Shows the full date, the zone id, the offset from UTC, the offset from
/// home and the zone's next clock change, then the three actions. Resolves to
/// the chosen [LocationDetailAction], or to `null` when the sheet is dismissed
/// — and also when "set as home" is tapped on the row that already is home,
/// since that choice is a no-op rather than a mutation.
///
/// [nextTransitionLocalTime] is wall-clock time **in this tile's zone**, from
/// `WorldClockCubit.nextTransitionLocalTime`; `null` renders no line at all,
/// which is the honest answer for a zone with nothing scheduled.
///
/// [canRemove] is `false` for the hero of a board whose home zone has no row
/// of its own (`WorldClockViewModel.homeHasBoardRow`): home is a zone id, not
/// a row, so there is nothing to remove.
///
/// ```dart
/// final action = await showLocationDetailSheet(
///   context,
///   tile: model.home,
///   nextTransitionLocalTime: cubit.nextTransitionLocalTime(zoneId),
///   canRemove: model.homeHasBoardRow,
/// );
/// ```
Future<LocationDetailAction?> showLocationDetailSheet(
  BuildContext context, {
  required WorldClockTile tile,
  required DateTime? nextTransitionLocalTime,
  required bool canRemove,
  bool showSeconds = false,
}) {
  return showTimeBuddyPickerSheet<LocationDetailAction>(
    context,
    builder: (_) => _LocationDetailBody(
      tile: tile,
      nextTransitionLocalTime: nextTransitionLocalTime,
      canRemove: canRemove,
      showSeconds: showSeconds,
    ),
  );
}

class _LocationDetailBody extends StatelessWidget {
  const _LocationDetailBody({
    required this.tile,
    required this.nextTransitionLocalTime,
    required this.canRemove,
    required this.showSeconds,
  });

  final WorldClockTile tile;
  final DateTime? nextTransitionLocalTime;
  final bool canRemove;
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    // Fixed rather than draggable: the content is a header, five short lines
    // and three actions, and a sheet opening at 70% of the screen for that
    // would be mostly empty surface. Scrollable inside the cap all the same,
    // because "five short lines" is a phone in landscape away from not
    // fitting.
    return TimeBuddyPickerSheet.fixed(
      title: tile.location.label,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _Header(tile: tile, showSeconds: showSeconds),
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _Facts(
                tile: tile,
                nextTransitionLocalTime: nextTransitionLocalTime,
              ),
            ),
            // The rule is the break between "what is true here" and "what you
            // can do about it"; its height carries the gap under the facts.
            const Divider(height: AppSpacing.xl),
            _Actions(tile: tile, canRemove: canRemove),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// The live clock and the day it belongs to.
class _Header extends StatelessWidget {
  const _Header({required this.tile, required this.showSeconds});

  final WorldClockTile tile;
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    final dayWord = relativeDayWord(tile.dayDelta);
    final localeTag = LocaleSettings.currentLocale.languageTag;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Still live inside the sheet: it is the same shared ticker, so an
        // open sheet costs no timer of its own (rule 3).
        ClockText(
          zoneId: tile.location.zoneId,
          showSeconds: showSeconds,
          fontSize: _sheetClockFontSize,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          dayWord == null
              ? formatDayMonth(tile.localTime, localeTag)
              : '${formatDayMonth(tile.localTime, localeTag)} · $dayWord',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.appColors.onBackgroundLight,
          ),
        ),
      ],
    );
  }
}

/// The lines a user opens this sheet to read.
class _Facts extends StatelessWidget {
  const _Facts({required this.tile, required this.nextTransitionLocalTime});

  final WorldClockTile tile;
  final DateTime? nextTransitionLocalTime;

  @override
  Widget build(BuildContext context) {
    final transitionAt = nextTransitionLocalTime;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FactRow(
          label: t.worldClock.detailZoneId,
          // The one place in the app the raw IANA id is shown on purpose: this
          // sheet is where a user checks *which* zone a row really is.
          value: tile.location.zoneId,
        ),
        _FactRow(
          label: t.worldClock.detailOffsetUtc,
          value: offsetLabel(tile.offsetFromUtc),
        ),
        _FactRow(
          label: t.worldClock.detailOffsetHome,
          // `null` from the formatter means the two zones match, which is an
          // answer rather than an absence on a line that names the question.
          value:
              relativeOffsetLabel(tile.offsetFromHome) ?? t.worldClock.sameTime,
        ),
        if (tile.isDst) ...[
          const SizedBox(height: AppSpacing.sm),
          _DstNote(transitionAt: transitionAt),
        ] else if (transitionAt != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _NoteText(label: _nextTransitionLabel(transitionAt)),
        ],
      ],
    );
  }
}

/// The DST state, and when it ends (rule 8).
class _DstNote extends StatelessWidget {
  const _DstNote({required this.transitionAt});

  final DateTime? transitionAt;

  @override
  Widget build(BuildContext context) {
    final at = transitionAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // No tap: the sheet the badge would open is this one.
            const DstBadge(),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _NoteText(label: t.worldClock.dstActive)),
          ],
        ),
        if (at != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _NoteText(label: _nextTransitionLabel(at)),
        ],
      ],
    );
  }
}

/// One `label / value` line.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                color: colors.onBackgroundLight,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Flexible, not a bare Text: a zone id is up to about thirty
          // characters (`America/Argentina/Buenos_Aires`) and the label beside
          // it is a full sentence in Portuguese.
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteText extends StatelessWidget {
  const _NoteText({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.textTheme.bodySmall?.copyWith(
        color: context.appColors.onBackgroundLight,
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.tile, required this.canRemove});

  final WorldClockTile tile;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TimeBuddyPickerRow(
          leading: const AppIcon(FontAwesomeIcons.house),
          title: t.locations.setAsHome,
          // Already home reads as the selected option, which is what the check
          // mark means everywhere else in the app. Tapping it closes the sheet
          // without reporting an action.
          isSelected: tile.isHome,
          onTap: () => _close(
            context,
            tile.isHome ? null : LocationDetailAction.setHome,
          ),
        ),
        TimeBuddyPickerRow(
          leading: const AppIcon(FontAwesomeIcons.tableCells),
          title: t.worldClock.actionOpenInGrid,
          onTap: () => _close(context, LocationDetailAction.openInGrid),
        ),
        if (canRemove)
          TimeBuddyPickerRow(
            leading: const AppIcon(FontAwesomeIcons.trash),
            title: t.worldClock.actionRemove,
            onTap: () => _close(context, LocationDetailAction.remove),
          ),
      ],
    );
  }

  void _close(BuildContext context, LocationDetailAction? action) =>
      Navigator.of(context).pop(action);
}

/// "The clocks change here on Tue 24", for a transition already converted to
/// the zone's own wall clock.
String _nextTransitionLabel(DateTime transitionLocalTime) =>
    t.worldClock.nextTransition(
      date: formatDayMonth(
        transitionLocalTime,
        LocaleSettings.currentLocale.languageTag,
      ),
    );

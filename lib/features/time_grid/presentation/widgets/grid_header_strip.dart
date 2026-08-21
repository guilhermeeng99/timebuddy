import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';

/// The grid's hour ruler: the reference zone's clock, column by column.
///
/// **This is the only horizontally scrollable widget in the grid.** Its
/// [controller] is the one the rows and the "now" marker read their offset
/// from, so header and rows can never drift apart — a `ScrollController`
/// attached to several viewports gives each its own position and syncs
/// nothing, which is the bug this design removes rather than papers over
/// (time_grid.md, Performance; Interaction: dragging the header scrolls the
/// track, dragging the cells moves the cursor).
///
/// The labels come from [referenceZoneId] rather than from the home row's
/// cells, because home is a zone and not required to be a board row
/// (locations rule 3): a header fed by a row would go blank exactly when the
/// user has not added their own city.
///
/// ```dart
/// GridHeaderStrip(
///   slots: model.slots,
///   referenceZoneId: cubit.referenceZoneId,
///   columnWidth: layout.hourColumnWidth,
///   controller: hourScroll,
///   cursorInstant: model.cursorInstant,
/// );
/// ```
class GridHeaderStrip extends StatelessWidget {
  const GridHeaderStrip({
    required this.slots,
    required this.referenceZoneId,
    required this.columnWidth,
    required this.controller,
    this.cursorInstant,
    this.localeTag,
    this.engine,
    super.key,
  });

  /// The shared UTC instants, one per column, ascending.
  final List<DateTime> slots;

  /// The zone the columns are aligned to: the board's home zone, or `UTC`
  /// when it does not resolve.
  final String referenceZoneId;

  /// Width of one hour column, resolved from the surface by `GridLayout`.
  ///
  /// **This widget's `itemExtent` is the grid's authoritative content
  /// extent** — the rows and both painters compute their pixels to match it,
  /// never the other way round. It is the one number that must not be derived
  /// twice.
  final double columnWidth;

  /// The grid's single horizontal controller.
  final ScrollController controller;

  /// The slot the cursor sits on, highlighted here as well as in the rows.
  final DateTime? cursorInstant;

  /// Locale for the `Tue 24` labels. Defaults to the app's resolved locale.
  final String? localeTag;

  /// Injected for tests; resolved from `GetIt` otherwise.
  final TimeZoneEngine? engine;

  @override
  Widget build(BuildContext context) {
    final resolvedEngine = engine ?? GetIt.I<TimeZoneEngine>();
    final tag = localeTag ?? Localizations.localeOf(context).toLanguageTag();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.appColors.surfaceVariant),
        ),
      ),
      child: SizedBox(
        height: GridMetrics.headerHeight,
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          // Fixed extent so the viewport can jump straight to a column
          // instead of measuring its way there; the initial centre-on-now
          // scroll (rule 13) depends on it being exact.
          itemExtent: columnWidth,
          itemCount: slots.length,
          itemBuilder: (context, index) => _headerColumn(
            engine: resolvedEngine,
            index: index,
            localeTag: tag,
          ),
        ),
      ),
    );
  }

  /// One column, resolved from its own instant.
  ///
  /// The previous column is resolved too rather than inferred, for the same
  /// reason rule 4 gives for cells: on a fall-back day two neighbouring
  /// columns carry the same wall clock, and on a spring-forward day they skip
  /// one, so "the hour before" is not "this hour minus one".
  Widget _headerColumn({
    required TimeZoneEngine engine,
    required int index,
    required String localeTag,
  }) {
    final slot = slots[index];
    final localTime = engine.wallTimeAt(zoneId: referenceZoneId, instant: slot);
    final previous = index == 0
        ? null
        : engine.wallTimeAt(
            zoneId: referenceZoneId,
            instant: slots[index - 1],
          );
    final startsNewDate = previous != null && !_sameDate(localTime, previous);

    return _HeaderColumn(
      localTime: localTime,
      dateLabel: startsNewDate ? formatDayMonth(localTime, localeTag) : null,
      isCursor: cursorInstant == slot,
    );
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _HeaderColumn extends StatelessWidget {
  const _HeaderColumn({
    required this.localTime,
    required this.dateLabel,
    required this.isCursor,
  });

  /// Wall-clock time of this column in the reference zone.
  final DateTime localTime;

  /// The new date's short label, present only on a day boundary (rule 6).
  final String? dateLabel;

  final bool isCursor;

  static const double _dateFontSize = 10;

  /// The ruler's hour. Below the cells' 15pt on purpose — see [build].
  static const double _hourFontSize = 13;
  static const double _cursorFillAlpha = 0.12;

  /// `14`, or `14:30` after a 30-minute shift in the reference zone. Same
  /// contract as `HourCell`: the minutes are shown because hiding them would
  /// claim an alignment the column does not have (rule 5).
  String get _hourLabel {
    final hour = localTime.hour.toString().padLeft(2, '0');
    if (localTime.minute == 0) return hour;
    return '$hour:${localTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = dateLabel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isCursor
            ? colors.primary.withValues(alpha: _cursorFillAlpha)
            : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (label != null)
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: context.textTheme.labelSmall?.copyWith(
                fontSize: _dateFontSize,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          Text(
            _hourLabel,
            maxLines: 1,
            // 13pt against the cells' 15pt: the ruler names the column, the
            // cell carries the answer, and a ruler at the same weight as the
            // data competes with it.
            style: context.textTheme.labelSmall?.copyWith(
              fontSize: _hourFontSize,
              fontWeight: isCursor ? FontWeight.w600 : FontWeight.w500,
              color: isCursor ? colors.primary : colors.onBackgroundLight,
            ),
          ),
        ],
      ),
    );
  }
}

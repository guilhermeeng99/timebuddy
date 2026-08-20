import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_typography.dart';
import 'package:timebuddy/app/widgets/dst_badge.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_sheet.dart';
import 'package:timebuddy/app/widgets/timebuddy_pill_toggle.dart';
import 'package:timebuddy/app/widgets/timebuddy_section.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';
import 'package:timebuddy/features/meeting_planner/presentation/cubit/meeting_planner_state.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Resting, minimum and maximum extents of the mobile sheet.
///
/// Lower than `TimeBuddyPickerSheet`'s own defaults: those are for a modal
/// picker that owns the screen, while this sheet is not modal and sits over a
/// grid the user is still dragging on. Resting at 70% would cover the rows
/// the next selection has to be made on.
const double _sheetInitialSize = 0.45;
const double _sheetMinSize = 0.25;
const double _sheetMaxSize = 0.9;

/// Digit size of a range. Deliberately small: see `_SummaryLine` for the
/// width this has to survive in.
const double _rangeFontSize = 14;

/// The summary of the selected range: who it lands on, and how well
/// (docs/specs/meeting_planner.md, UI).
///
/// One widget for all three planner states and both breakpoints, so the grid
/// page hosts the planner with a single child rather than a switch of its
/// own: below `900px` a non-modal bottom sheet in `TimeBuddyPickerSheet`
/// chrome, draggable, with the hours still reachable above it; at `900px` and
/// up a right-hand panel of [sideWidth]. Nothing outside that surface is a
/// hit target, so the grid keeps its own gestures either way.
///
/// It renders and decides nothing about time: every value on screen — local
/// times, day deltas, verdicts, the real duration — was resolved by
/// `BuildMeetingSummaryUseCase` for the selection's own instants.
///
/// ```dart
/// MeetingSummaryPanel(
///   state: plannerState,
///   onTextStyleChanged: cubit.setTextStyle,
///   onCopy: cubit.copy,
///   onApplySuggestion: cubit.applySuggestion,
///   onClear: cubit.clear,
/// );
/// ```
class MeetingSummaryPanel extends StatelessWidget {
  const MeetingSummaryPanel({
    required this.state,
    required this.onTextStyleChanged,
    required this.onCopy,
    required this.onApplySuggestion,
    this.onClear,
    super.key,
  });

  /// Width of the `>= 900px` side panel. Wide enough for a city label beside
  /// a 12-hour range (`12:00 AM - 11:00 AM` is the longest this row holds),
  /// narrow enough to leave the grid its hours.
  static const double sideWidth = 340;

  /// The whole planner state: idle and mid-drag render the hint, a settled
  /// selection renders the summary.
  final MeetingPlannerState state;

  /// Which shape the copy action produces (rule 9).
  final ValueChanged<MeetingTextStyle> onTextStyleChanged;

  /// Writes the pasteable text and answers whether it landed.
  ///
  /// `false` is not an error: the cubit parks the text on
  /// `PlannerSelected.fallbackText` and this panel renders it as selectable
  /// text instead (rule 10's edge case).
  final Future<bool> Function() onCopy;

  /// Moves the selection onto the alternative of rule 7.
  final VoidCallback onApplySuggestion;

  /// Drops the selection. `null` renders no clear action, for a host that
  /// offers the way out somewhere else.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final selected = state;
    if (ResponsiveLayout.isDesktop(context)) {
      return _SidePanel(
        child: selected is PlannerSelected
            ? _body(selected)
            : const _HintText(),
      );
    }
    if (selected is! PlannerSelected) return const _HintBar();

    // Aligned here and not left to the host. `TimeBuddyPickerSheet` is a
    // `DraggableScrollableSheet`, which under the loose constraints a `Stack`
    // child gets sizes itself to its own 45% and is then placed by the
    // *Stack's* alignment — `topStart`, so the sheet would open across the
    // top of the grid.
    return Align(
      alignment: AlignmentDirectional.bottomCenter,
      child: TimeBuddyPickerSheet(
        title: t.planner.summaryTitle,
        initialSize: _sheetInitialSize,
        minSize: _sheetMinSize,
        maxSize: _sheetMaxSize,
        // The controller has to reach a scroll view or dragging the list
        // stops resizing the sheet; `_SummaryBody` hands it to its `ListView`.
        bodyBuilder: (context, controller) =>
            _body(selected, scrollController: controller),
      ),
    );
  }

  Widget _body(
    PlannerSelected selected, {
    ScrollController? scrollController,
  }) {
    return _SummaryBody(
      selected: selected,
      scrollController: scrollController,
      onTextStyleChanged: onTextStyleChanged,
      onCopy: onCopy,
      onApplySuggestion: onApplySuggestion,
      onClear: onClear,
    );
  }
}

/// The `>= 900px` form: a fixed-width column against the trailing edge.
///
/// Aligned rather than sized by its parent, so the same widget works whether
/// the grid page gives it a slot in a `Row` beside the grid or drops it into
/// the grid's `Stack`.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: MeetingSummaryPanel.sideWidth,
        child: Material(
          color: colors.surface,
          // The rule separates the panel from the grid it floats over; the
          // sheet gets the same job done with its rounded top edge.
          shape: Border(left: BorderSide(color: colors.surfaceVariant)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Text(
                  t.planner.summaryTitle,
                  style: context.textTheme.headlineSmall,
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mobile form of "planner mode is on, now pick some hours".
///
/// A bar rather than an empty sheet: there is nothing to scroll yet, and a
/// surface resting at 45% of the screen over the very rows the user has to
/// drag across would be the panel arguing with its own instructions.
class _HintBar extends StatelessWidget {
  const _HintBar();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.bottomCenter,
      // Full width, tall as its sentence. Without the width the bar would be
      // as wide as the text happens to be and would read as a floating
      // tooltip rather than as the panel that is about to open.
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: context.appColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
          child: const SafeArea(top: false, child: _HintText()),
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        t.planner.selectHint,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.appColors.onBackgroundLight,
        ),
      ),
    );
  }
}

/// The summary itself: a scrolling body and a copy bar pinned under it.
///
/// The bar is outside the scroll view on purpose. It is the primary action,
/// and a sheet resting at 45% of the screen would put it below the fold for
/// any board with more than three cities.
class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.selected,
    required this.onTextStyleChanged,
    required this.onCopy,
    required this.onApplySuggestion,
    required this.onClear,
    this.scrollController,
  });

  final PlannerSelected selected;
  final ValueChanged<MeetingTextStyle> onTextStyleChanged;
  final Future<bool> Function() onCopy;
  final VoidCallback onApplySuggestion;
  final VoidCallback? onClear;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final summary = selected.summary;
    final hourFormat = _hourFormatOf(context);
    final fallbackText = selected.fallbackText;
    final suggestionHome = selected.suggestionHome;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            // Children rather than a builder: the board caps at 20 rows, so
            // this list is at most 21 lines long, and every one of them lives
            // inside a single section card that has to be built whole anyway.
            children: [
              _LinesSection(
                summary: summary,
                hourFormat: hourFormat,
                onClear: onClear,
              ),
              if (summary.crossesDst) ...[
                const SizedBox(height: AppSpacing.md),
                const _DstNote(),
              ],
              if (suggestionHome != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _SuggestionCard(
                  home: suggestionHome,
                  hourFormat: hourFormat,
                  onApply: onApplySuggestion,
                ),
              ] else if (wantsBetterWindow(summary)) ...[
                // Rule 7's honest answer: an equally bad alternative is worse
                // than none, so the panel says there is none.
                const SizedBox(height: AppSpacing.lg),
                _MutedCard(
                  child: Text(
                    t.planner.noSuggestion,
                    style: context.textTheme.bodySmall,
                  ),
                ),
              ],
              if (fallbackText != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _MutedCard(
                  child: SelectableText(
                    fallbackText,
                    style: context.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
        _CopyBar(
          textStyle: selected.textStyle,
          onTextStyleChanged: onTextStyleChanged,
          onCopy: onCopy,
        ),
      ],
    );
  }
}

/// The lines, under a header that says how long the meeting really is.
///
/// The duration is the header rather than a line of its own because it is the
/// one fact about the range that no row can show: across a transition the
/// clocks lie about it (rule 8).
class _LinesSection extends StatelessWidget {
  const _LinesSection({
    required this.summary,
    required this.hourFormat,
    required this.onClear,
  });

  final MeetingSummary summary;
  final ClockFormat hourFormat;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final lines = summary.allLines;
    final clear = onClear;
    return TimeBuddySection(
      label: t.planner.durationLabel(
        duration: _durationText(summary.duration),
      ),
      count: lines.length,
      trailing: clear == null
          ? null
          : TextButton(onPressed: clear, child: Text(t.common.clear)),
      child: Column(
        // Tight cross-axis constraints, so every row measures its shares
        // against the card rather than against its own longest word.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < lines.length; index++)
            _SummaryLine(
              line: lines[index],
              // Rule 5: home is always first, and every other line's day
              // delta is measured against it.
              isHome: index == 0,
              hourFormat: hourFormat,
            ),
        ],
      ),
    );
  }
}

/// One location's answer to "when is this for you?".
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.line,
    required this.isHome,
    required this.hourFormat,
  });

  /// Measured, not guessed, because this row is the dense one. At
  /// [MeetingSummaryPanel.sideWidth] the section card leaves 276px and a
  /// 360px phone leaves 296px; the dot and the two gaps take 24. The widest
  /// range the row can hold is `12:00 AM - 11:00 AM`, about 124px at
  /// [_rangeFontSize], which four sevenths of the narrower case (144px)
  /// clears. The label takes the rest and ellipsizes — a truncated city name
  /// is still recognisable, a truncated hour is not.
  ///
  /// Both shares are tight [Expanded]s rather than a loose [Flexible], so the
  /// hours land on one right edge instead of floating on their own width.
  static const int _labelFlex = 3;
  static const int _timesFlex = 4;

  final MeetingLine line;
  final bool isHome;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          _VerdictDot(verdict: line.verdict),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: _labelFlex,
            // Dense: this row is the identity beside the hours, and the
            // country line would push a two-line block against a one-line
            // one. The zone abbreviation is deliberately absent too — the
            // times are already local, and naming `BRT` beside them says the
            // same thing twice.
            child: LocationRow(
              location: line.location,
              isHome: isHome,
              dense: true,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: _timesFlex,
            child: _RangeText(line: line, hourFormat: hourFormat),
          ),
        ],
      ),
    );
  }
}

/// The hours, and the date when this line is not on home's day (rule 5).
class _RangeText extends StatelessWidget {
  const _RangeText({required this.line, required this.hourFormat});

  final MeetingLine line;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dayLabel = _dayLabel(line);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _rangeText(line, hourFormat),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.clock(
            color: colors.onBackground,
            fontSize: _rangeFontSize,
          ),
        ),
        if (dayLabel != null)
          Text(
            dayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
          ),
      ],
    );
  }
}

/// Rule 6's verdict, as the row's left accent dot.
///
/// A dot rather than a word because the row already carries a label and a
/// range; the word is on the tooltip and on the semantics node, where a
/// screen reader and a hovering pointer can both reach it.
class _VerdictDot extends StatelessWidget {
  const _VerdictDot({required this.verdict});

  static const double _size = 8;

  final HourBand verdict;

  @override
  Widget build(BuildContext context) {
    final label = _verdictLabel(verdict);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: _size,
          height: _size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // The one band-to-token table, so a `fair` dot here is the same
              // amber as a `fair` hour in the grid above it.
              color: hourBandColor(verdict, context.appColors),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rule 8: the clocks move inside this range, so its length is not what the
/// columns suggest.
class _DstNote extends StatelessWidget {
  const _DstNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No `onTap`: the explanation is the sentence beside it, and a second
        // way in would open a sheet over a sheet.
        const DstBadge(),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            t.planner.crossesDst,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.appColors.onBackgroundLight,
            ),
          ),
        ),
      ],
    );
  }
}

/// The alternative of rule 7, with the one action that takes it.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.home,
    required this.hourFormat,
    required this.onApply,
  });

  /// The suggested range's **home** line: the selection is made in the
  /// reference zone's columns, so its hours are the ones the user recognises.
  final MeetingLine home;
  final ClockFormat hourFormat;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _MutedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.planner.suggestionTitle,
            style: context.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onBackgroundLight,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Stacked rather than beside the action: inside this card a 12-hour
          // range and a two-word button both want most of the width, and a
          // phone has none to spare.
          Text(
            _rangeText(home, hourFormat),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.clock(
              color: colors.onBackground,
              fontSize: _rangeFontSize,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onApply,
              child: Text(t.planner.suggestionApply),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet surface for something that is not the main line of the panel.
class _MutedCard extends StatelessWidget {
  const _MutedCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A Material, not a DecoratedBox: the suggestion card carries a
    // TextButton, and ink painted on a plain coloured box is swallowed — the
    // button still fires and just looks dead under the finger.
    return Material(
      color: context.appColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

/// The copy action and the shape it copies (rules 9 and 10).
///
/// Clipboard only: no share sheet, no link. A shareable link needs a backend
/// and public data, which is a v2 decision recorded in the roadmap.
class _CopyBar extends StatelessWidget {
  const _CopyBar({
    required this.textStyle,
    required this.onTextStyleChanged,
    required this.onCopy,
  });

  /// The toggle takes the larger share: two words against one.
  static const int _toggleFlex = 3;
  static const int _buttonFlex = 2;

  final MeetingTextStyle textStyle;
  final ValueChanged<MeetingTextStyle> onTextStyleChanged;
  final Future<bool> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            flex: _toggleFlex,
            child: TimeBuddyPillToggle<MeetingTextStyle>(
              options: [
                PillOption(
                  value: MeetingTextStyle.compact,
                  label: t.planner.copyCompact,
                ),
                PillOption(
                  value: MeetingTextStyle.verbose,
                  label: t.planner.copyVerbose,
                ),
              ],
              selected: textStyle,
              onChanged: onTextStyleChanged,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: _buttonFlex,
            child: FilledButton.icon(
              onPressed: () => unawaited(_copy(context)),
              icon: const Icon(Icons.content_copy_rounded),
              label: Text(
                t.converter.copy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    // Resolved before the await: a sync landing while the clipboard write is
    // in flight can rebuild this bar out from under the context it came from.
    final messenger = ScaffoldMessenger.of(context);
    final copied = await onCopy();
    // A refusal is reported by the panel itself, which now shows the text as
    // selectable, so a snackbar would be a second answer to one tap.
    if (!copied) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t.planner.copied)));
  }
}

/// Watched rather than read: a 12h/24h switch in settings must repaint every
/// time on screen, and it lands without the selection changing.
ClockFormat _hourFormatOf(BuildContext context) =>
    switch (context.watch<PreferencesCubit>().state) {
      PreferencesReady(:final preferences) => preferences.hourFormat,
      // Preferences resolve during startup, before any page mounts; this only
      // covers the frame where a test builds the panel first.
      PreferencesLoading() => ClockFormat.h24,
    };

/// Rule 6's verdict in words, for the dot's tooltip and semantics.
///
/// The planner copy names three verdicts because rule 6 names three;
/// [HourBand] carries a fourth, and the shared band vocabulary already has
/// the word for a row that is asleep rather than merely off duty.
String _verdictLabel(HourBand verdict) => switch (verdict) {
  HourBand.good => t.planner.verdictGood,
  HourBand.fair => t.planner.verdictFair,
  HourBand.poor => t.planner.verdictPoor,
  HourBand.night => t.bands.night,
};

/// `14:00 - 15:00` under the user's clock format.
String _rangeText(MeetingLine line, ClockFormat hourFormat) =>
    '${formatClock(line.localStart, hourFormat)} - '
    '${formatClock(line.localEnd, hourFormat)}';

/// Rule 5's mark: what to call this line's date when it is not home's.
///
/// `null` on the same day, because the absence is the information — a summary
/// where every line carries "Today" says nothing about the one line that does
/// not.
String? _dayLabel(MeetingLine line) => switch (line.dayDelta) {
  0 => null,
  1 => t.planner.dayTomorrow,
  -1 => t.planner.dayYesterday,
  // No word covers two days out, and a range that far from home is a real
  // date-line board rather than an error, so the date itself says it.
  _ => formatDayMonth(
    line.localStart,
    LocaleSettings.currentLocale.languageTag,
  ),
};

/// The real length, as `3h` or `1h30`.
///
/// Deliberately the same shape `FormatMeetingTextUseCase` puts on a verbose
/// line, and deliberately not shared with it: that one is wordless because a
/// pasted message has to survive a reader who is not running this app, while
/// this one is wrapped in `t.planner.durationLabel` and translated with the
/// rest of the panel.
String _durationText(Duration duration) {
  final minutes = duration.inMinutes.abs() % 60;
  if (minutes == 0) return '${duration.inHours}h';
  return '${duration.inHours}h${minutes.toString().padLeft(2, '0')}';
}

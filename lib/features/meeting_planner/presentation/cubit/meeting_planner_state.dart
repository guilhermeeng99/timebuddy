import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';

/// State of `MeetingPlannerCubit` (docs/specs/meeting_planner.md, State
/// Machine).
///
/// There is deliberately **no** `PlannerError` and no `PlannerLoading`. The
/// planner is a *mode* of the grid rather than a page of its own, so a board
/// that will not load is already `TimeGridError` on the screen behind it;
/// a second error surface would blank a page that is showing one, and a
/// second shimmer would flash under a grid that has already resolved.
sealed class MeetingPlannerState extends Equatable {
  const MeetingPlannerState();

  /// The range `PlannerSelectionOverlay` paints, or `null` when there is
  /// nothing to paint.
  ///
  /// On the base class so the overlay takes one nullable value and the grid
  /// page does not switch on three states to find out whether a band is on
  /// screen. A drag in progress and a finished selection paint identically:
  /// the columns under the finger are the meeting either way.
  MeetingSelection? get activeSelection => null;

  @override
  List<Object?> get props => const [];
}

/// Planner mode is on and nothing is selected yet: the grid renders normally
/// and the panel shows `t.planner.selectHint`.
final class PlannerIdle extends MeetingPlannerState {
  const PlannerIdle();
}

/// A drag is in progress.
///
/// Carries the range and **not** a summary: a summary per pointer move would
/// resolve every board row against every hour of the range sixty times a
/// second, and none of it would be read — the panel only opens once the
/// gesture ends.
final class PlannerSelecting extends MeetingPlannerState {
  const PlannerSelecting({required this.selection});

  /// Already clamped to `1..12` slots by `MeetingSelection.fromSlots`
  /// (rule 3).
  final MeetingSelection selection;

  @override
  MeetingSelection get activeSelection => selection;

  @override
  List<Object?> get props => [selection];
}

/// A range is settled and the summary panel is showing it.
final class PlannerSelected extends MeetingPlannerState {
  const PlannerSelected({
    required this.summary,
    required this.textStyle,
    this.suggestionHome,
    this.fallbackText,
  });

  /// Everything the panel renders and the copy action pastes.
  final MeetingSummary summary;

  /// Which shape the copy action produces (rule 9). Held in the state rather
  /// than read from a widget, because it is also what
  /// `FormatMeetingTextUseCase` is called with.
  final MeetingTextStyle textStyle;

  /// The **home line of [MeetingSummary.suggestion]**, or `null` when no
  /// alternative is being offered.
  ///
  /// The suggestion itself is a pair of instants, and a card reading only
  /// "a better window" asks the user to accept a range they cannot see. Its
  /// local times need the engine, which a widget may not touch, so the cubit
  /// resolves the one line the card shows and carries it here.
  final MeetingLine? suggestionHome;

  /// The pasteable text, present only after a clipboard write was refused.
  ///
  /// The panel renders it as selectable text so the user can copy it by hand
  /// (rule 10's edge case: a web build without a user gesture). `null` is the
  /// normal case, where the text lives on the clipboard and nowhere else.
  final String? fallbackText;

  /// Only the two fields that ever change without a new selection.
  ///
  /// [summary] and [suggestionHome] are deliberately **not** copyable one at
  /// a time: they are rebuilt together from one range, and a summary swapped
  /// under a stale suggestion line would offer a window the panel is no
  /// longer describing.
  ///
  /// Pass `clearFallbackText: true` to drop the fallback; passing
  /// `fallbackText: null` cannot say that, being indistinguishable from
  /// "leave it alone".
  PlannerSelected copyWith({
    MeetingTextStyle? textStyle,
    String? fallbackText,
    bool clearFallbackText = false,
  }) {
    return PlannerSelected(
      summary: summary,
      textStyle: textStyle ?? this.textStyle,
      suggestionHome: suggestionHome,
      fallbackText: clearFallbackText
          ? null
          : fallbackText ?? this.fallbackText,
    );
  }

  @override
  MeetingSelection get activeSelection => summary.selection;

  @override
  List<Object?> get props => [
    summary,
    textStyle,
    suggestionHome,
    fallbackText,
  ];
}

/// Rule 7's trigger: an alternative is only worth searching for when the
/// range costs somebody their evening or their night.
///
/// Top-level so the cubit that decides whether to search and the panel that
/// explains why nothing was found read the same predicate. Two spellings of
/// "is this bad enough" is how a panel ends up saying "no better window" for
/// a meeting that was never poor to begin with.
bool wantsBetterWindow(MeetingSummary summary) {
  final floor = meetingBandSeverity(HourBand.poor);
  return summary.allLines.any(
    (line) => meetingBandSeverity(line.verdict) >= floor,
  );
}

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/services.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/build_meeting_summary_usecase.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/find_best_slot_usecase.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/format_meeting_text_usecase.dart';
import 'package:timebuddy/features/meeting_planner/presentation/cubit/meeting_planner_state.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/meeting_planner/presentation/cubit/meeting_planner_state.dart';

/// The meeting planner (docs/specs/meeting_planner.md, State Machine).
///
/// Page-scoped, and narrower than that: `TimeGridPage` creates it when planner
/// mode is entered and disposes it when the mode is left, because the planner
/// **is** a mode of the grid rather than a route (rule: same rows, same
/// columns, same engine).
///
/// It reads three cubits and writes to none of them. The board is where the
/// rows come from, the preferences decide every verdict, and the grid owns the
/// two things a selection is expressed against: the column set and the
/// reference day. Subscribing to `TimeGridCubit` rather than being fed by the
/// page is what makes the last transition of the state machine automatic — a
/// reference date that moves takes the selection's instants off screen with
/// it, so the selection is cleared rather than left describing columns nobody
/// can see.
///
/// **The planner never mutates the board** (rule 11). It is a read-only
/// consumer of it, and there is no path from here to `BoardCubit`.
///
/// ```dart
/// BlocProvider<MeetingPlannerCubit>(
///   create: (context) => MeetingPlannerCubit(
///     boardCubit: context.read<BoardCubit>(),
///     preferencesCubit: context.read<PreferencesCubit>(),
///     gridCubit: context.read<TimeGridCubit>(),
///     buildSummary: sl<BuildMeetingSummaryUseCase>(),
///     findBestSlot: sl<FindBestSlotUseCase>(),
///     formatText: sl<FormatMeetingTextUseCase>(),
///     engine: sl<TimeZoneEngine>(),
///   )..start(),
///   child: const _PlannerLayer(),
/// );
/// ```
class MeetingPlannerCubit extends Cubit<MeetingPlannerState> {
  MeetingPlannerCubit({
    required BoardCubit boardCubit,
    required PreferencesCubit preferencesCubit,
    required TimeGridCubit gridCubit,
    required BuildMeetingSummaryUseCase buildSummary,
    required FindBestSlotUseCase findBestSlot,
    required FormatMeetingTextUseCase formatText,
    required TimeZoneEngine engine,
    Future<void> Function(String text)? writeToClipboard,
  }) : _boardCubit = boardCubit,
       _preferencesCubit = preferencesCubit,
       _gridCubit = gridCubit,
       _buildSummary = buildSummary,
       _findBestSlot = findBestSlot,
       _formatText = formatText,
       _engine = engine,
       _writeToClipboard = writeToClipboard ?? _setSystemClipboard,
       super(const PlannerIdle());

  final BoardCubit _boardCubit;
  final PreferencesCubit _preferencesCubit;
  final TimeGridCubit _gridCubit;
  final BuildMeetingSummaryUseCase _buildSummary;
  final FindBestSlotUseCase _findBestSlot;
  final FormatMeetingTextUseCase _formatText;

  /// Used for one question the grid model does not answer: which instants the
  /// reference day itself holds, which is the search space rule 7 bounds the
  /// alternative to. The grid's `slots` cannot stand in — it carries flanking
  /// columns from the days either side.
  final TimeZoneEngine _engine;

  /// The clipboard write, injectable so a test can assert what was copied and
  /// force the refusal rule 10's fallback exists for, neither of which a
  /// platform channel offers on demand.
  final Future<void> Function(String text) _writeToClipboard;

  StreamSubscription<BoardState>? _boardSubscription;
  StreamSubscription<PreferencesState>? _preferencesSubscription;
  StreamSubscription<TimeGridState>? _gridSubscription;

  BoardEntity? _board;

  /// The grid's column set, the list every selection index refers to.
  List<DateTime> _slots = const [];

  /// The reference day's own hours, from `ZoneDay.hours`. Rebuilt only when
  /// the day changes, because that walk is the one non-trivial cost here.
  List<DateTime> _daySlots = const [];

  DateTime? _referenceDate;

  /// Where the current drag started. The cap of rule 3 is measured from it,
  /// so the end the user is holding still stays where they put it.
  int? _anchorIndex;

  /// Survives a selection being replaced, which is why it is a field and not
  /// a value on the state: the choice is the user's, not this meeting's.
  ///
  /// Rule 9 wants it persisted in preferences. `PreferencesEntity` does not
  /// carry `meetingTextStyle` yet (preferences.md lists it as planned, to
  /// land with the feature that reads it), so today it lives for as long as
  /// planner mode does.
  MeetingTextStyle _textStyle = MeetingTextStyle.compact;

  /// Subscribes to the board, the preferences and the grid, and adopts what
  /// they are already holding.
  ///
  /// Separate from the constructor so a test can observe the very first
  /// emission: a cubit that emitted from its own constructor would have
  /// finished before anything could listen.
  void start() {
    _boardSubscription = _boardCubit.stream.listen(_onBoardState);
    // The working window decides every verdict (rule 6), so a change to it
    // rescores a selection that is already on screen.
    _preferencesSubscription = _preferencesCubit.stream.listen(
      (_) => _recompute(),
    );
    _gridSubscription = _gridCubit.stream.listen(_onGridState);
    _onBoardState(_boardCubit.state);
    _onGridState(_gridCubit.state);
  }

  /// Starts a selection on the slot holding [slotInstant].
  ///
  /// Takes an instant rather than a column index so the grid page can hand
  /// over exactly what it already hands `TimeGridCubit.setCursor`, and so a
  /// drag position landing mid-column resolves to the column it is inside.
  void startSelection(DateTime slotInstant) {
    final index = _indexHolding(slotInstant);
    if (index == null) return;
    _anchorIndex = index;
    emit(PlannerSelecting(selection: _selectionBetween(index, index)));
  }

  /// Extends the drag to the slot holding [slotInstant].
  ///
  /// Ignored unless a drag is in progress: a stray move after the gesture
  /// ended would silently regrow a range the user has already settled.
  void extendTo(DateTime slotInstant) {
    final anchor = _anchorIndex;
    if (anchor == null || state is! PlannerSelecting) return;
    final index = _indexHolding(slotInstant);
    if (index == null) return;
    emit(PlannerSelecting(selection: _selectionBetween(anchor, index)));
  }

  /// Settles the drag and builds the summary.
  void endSelection() {
    final selecting = state;
    if (selecting is! PlannerSelecting) return;
    _select(selecting.selection);
  }

  /// The one-slot selection a tap on a cell makes, start to finish.
  ///
  /// Rule 3's floor is one slot, so a tap is a valid meeting and not a
  /// degenerate drag the page has to special-case.
  void selectSlot(DateTime slotInstant) {
    startSelection(slotInstant);
    endSelection();
  }

  /// Moves the selection onto the alternative of rule 7.
  void applySuggestion() {
    final selected = state;
    if (selected is! PlannerSelected) return;
    final suggestion = selected.summary.suggestion;
    if (suggestion == null) return;
    _anchorIndex = _indexHolding(suggestion.startInstant);
    _select(suggestion);
  }

  /// Drops the selection; planner mode stays on.
  void clear() {
    _anchorIndex = null;
    emit(const PlannerIdle());
  }

  /// Switches which shape the copy action produces (rule 9).
  void setTextStyle(MeetingTextStyle value) {
    _textStyle = value;
    final selected = state;
    if (selected is! PlannerSelected) return;
    // A fallback block on screen is the text the user is about to copy by
    // hand, so it has to follow the style they just picked rather than keep
    // showing the shape they moved away from.
    final fallback = selected.fallbackText == null
        ? null
        : _pasteableText(summary: selected.summary, style: value);
    emit(
      selected.copyWith(
        textStyle: value,
        fallbackText: fallback,
        clearFallbackText: fallback == null,
      ),
    );
  }

  /// Puts the summary on the clipboard and answers whether it landed
  /// (rule 10: clipboard only, no share sheet and no link).
  ///
  /// A refusal is not an error state. The text is parked on
  /// [PlannerSelected.fallbackText] so the panel can render it as selectable
  /// text, which is a worse copy action and still a working one.
  Future<bool> copy() async {
    final selected = state;
    if (selected is! PlannerSelected) return false;
    final text = _pasteableText(
      summary: selected.summary,
      style: selected.textStyle,
    );
    try {
      await _writeToClipboard(text);
      return true;
    } on Exception catch (_) {
      // Every refusal reaching here is a PlatformException or a missing
      // plugin: a web build denying the write outside a user gesture, or a
      // platform with no clipboard channel at all.
      //
      // The state is re-read rather than reused: the write was awaited, and a
      // board or preference change landing inside that gap has already
      // replaced the summary this started from.
      final current = state;
      if (isClosed || current is! PlannerSelected) return false;
      emit(current.copyWith(fallbackText: text));
      return false;
    }
  }

  @override
  Future<void> close() {
    // Cancelled rather than awaited. `cancel()` takes effect the moment it is
    // called, and awaiting a broadcast subscription's future from a
    // `testWidgets` body strands the FakeAsync microtask queue: the symptom is
    // a bare "(did not complete)" with no stack.
    unawaited(_boardSubscription?.cancel());
    unawaited(_preferencesSubscription?.cancel());
    unawaited(_gridSubscription?.cancel());
    return super.close();
  }

  static Future<void> _setSystemClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  void _onBoardState(BoardState boardState) {
    // A board that failed to load is `TimeGridError` on the page behind this
    // one; holding the last board beats clearing a selection over a refresh
    // that will re-emit `BoardLoaded` a moment later.
    if (boardState is! BoardLoaded) return;
    _board = boardState.board;
    // A row removed while a selection is active drops out of the summary
    // (edge case); the range itself is untouched, because it never belonged
    // to a row.
    _recompute();
  }

  void _onGridState(TimeGridState gridState) {
    if (gridState is! TimeGridReady) return;
    _slots = gridState.model.slots;

    final referenceDate = gridState.model.referenceDate;
    // Deliberately no recompute on any other grid change. The grid re-emits
    // for a cursor move and for a tick, and nothing in a summary depends on
    // either; rebuilding here would run the rule 7 search — a whole day of
    // ranges scored against every row — once a minute for an answer that
    // cannot have changed.
    if (referenceDate == _referenceDate) return;
    _referenceDate = referenceDate;
    _daySlots = _engine
        .dayIn(zoneId: _gridCubit.referenceZoneId, localDate: referenceDate)
        .hours;
    // The selection's instants are no longer on screen, so it is cleared
    // rather than left pointing at columns the user cannot see.
    if (state is! PlannerIdle) clear();
  }

  /// Rebuilds the summary of the range already selected, if any.
  void _recompute() {
    final selected = state;
    if (selected is! PlannerSelected) return;
    _select(selected.summary.selection);
  }

  /// Resolves [selection] into the state the panel renders.
  void _select(MeetingSelection selection) {
    final board = _board;
    if (board == null) return;
    final workingHours = _workingHours;

    var summary = _buildSummary(
      board: board,
      selection: selection,
      workingHours: workingHours,
    );
    MeetingLine? suggestionHome;

    if (wantsBetterWindow(summary)) {
      final better = _findBestSlot(
        board: board,
        daySlots: _daySlots,
        slotCount: selection.slotCount,
        workingHours: workingHours,
      );
      // The use case is not told what is currently selected, so the range the
      // user is already on can come back as the best one. It is not an
      // alternative, and offering it would make "use this instead" a no-op.
      if (better != null && better != selection) {
        summary = summary.copyWith(suggestion: better);
        suggestionHome = _buildSummary(
          board: board,
          selection: better,
          workingHours: workingHours,
        ).home;
      }
    }

    emit(
      PlannerSelected(
        summary: summary,
        textStyle: _textStyle,
        suggestionHome: suggestionHome,
      ),
    );
  }

  String _pasteableText({
    required MeetingSummary summary,
    required MeetingTextStyle style,
  }) {
    return _formatText(
      summary: summary,
      style: style,
      hourFormat: _hourFormat,
      // The locale the app actually resolved, read from slang rather than
      // from a `BuildContext`: it is already what `Intl.defaultLocale` was
      // set from, and it is the same value the grid labels its dates with.
      localeTag: LocaleSettings.currentLocale.languageTag,
    );
  }

  MeetingSelection _selectionBetween(int anchorIndex, int cursorIndex) =>
      MeetingSelection.fromSlots(
        slots: _slots,
        anchorIndex: anchorIndex,
        cursorIndex: cursorIndex,
      );

  /// The column whose hour contains [instant], or `null` when it falls
  /// outside the window.
  int? _indexHolding(DateTime instant) {
    for (var index = 0; index < _slots.length; index++) {
      final slot = _slots[index];
      final slotEnd = slot.add(MeetingSelection.slotDuration);
      if (!instant.isBefore(slot) && instant.isBefore(slotEnd)) return index;
    }
    return null;
  }

  WorkingHours get _workingHours => switch (_preferencesCubit.state) {
    PreferencesReady(:final preferences) => preferences.workingHours,
    // Preferences resolve during startup, before any page mounts; this only
    // covers the frame where a test builds the planner first.
    PreferencesLoading() => WorkingHours.defaultHours,
  };

  ClockFormat get _hourFormat => switch (_preferencesCubit.state) {
    PreferencesReady(:final preferences) => preferences.hourFormat,
    PreferencesLoading() => ClockFormat.h24,
  };
}

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_state.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_state.dart';

/// View state of the comparison grid.
///
/// Page-scoped: created by `TimeGridPage` on each visit and disposed with it.
/// It **reads** `BoardCubit` and `PreferencesCubit` and never writes to either
/// (docs/specs/time_grid.md, State Machine); every board mutation the grid
/// offers goes straight to `BoardCubit`, so there is exactly one owner of the
/// list of places.
///
/// It holds three pieces of view state the board does not: the reference date,
/// the cursor, and the cursor's *time of day*. The third one is what makes
/// rule 10 work — see [_cursorTimeOfDay].
///
/// ```dart
/// BlocProvider<TimeGridCubit>(
///   create: (context) => TimeGridCubit(
///     boardCubit: context.read<BoardCubit>(),
///     preferencesCubit: context.read<PreferencesCubit>(),
///     buildGrid: sl<BuildGridUseCase>(),
///     engine: sl<TimeZoneEngine>(),
///     clock: sl<Clock>(),
///   )..start(),
///   child: const _TimeGridView(),
/// );
/// ```
class TimeGridCubit extends Cubit<TimeGridState> {
  TimeGridCubit({
    required BoardCubit boardCubit,
    required PreferencesCubit preferencesCubit,
    required BuildGridUseCase buildGrid,
    required TimeZoneEngine engine,
    required Clock clock,
  }) : _boardCubit = boardCubit,
       _preferencesCubit = preferencesCubit,
       _buildGrid = buildGrid,
       _engine = engine,
       _clock = clock,
       super(const TimeGridLoading());

  final BoardCubit _boardCubit;
  final PreferencesCubit _preferencesCubit;
  final BuildGridUseCase _buildGrid;

  /// Used for the two questions the model cannot answer: what day it is in the
  /// home zone, and which instant a kept time of day lands on after a date
  /// step (rule 10).
  final TimeZoneEngine _engine;
  final Clock _clock;

  StreamSubscription<BoardState>? _boardSubscription;
  StreamSubscription<PreferencesState>? _preferencesSubscription;

  BoardEntity? _board;
  DateTime? _referenceDate;
  DateTime? _cursorInstant;

  /// The cursor as the user thinks of it: "two in the afternoon", not an
  /// instant (rule 10). Stepping the date re-resolves this against the new
  /// day, so a cursor on 14:00 stays on 14:00 tomorrow instead of collapsing
  /// to the new day's first column.
  ({int hour, int minute})? _cursorTimeOfDay;

  /// Subscribes to the board and the preferences and builds the first model.
  ///
  /// Separate from the constructor so a test can observe the very first
  /// emission: a cubit that emitted from its own constructor would have
  /// finished before anything could listen.
  void start() {
    _boardSubscription = _boardCubit.stream.listen(_onBoardState);
    // Any preference change can repaint the grid: the working window decides
    // every band (rule 7) and the locale decides every date label (rule 6).
    _preferencesSubscription = _preferencesCubit.stream.listen(
      (_) => _rebuild(),
    );
    _onBoardState(_boardCubit.state);
  }

  /// The zone the columns are aligned to: the board's home zone, or `UTC` when
  /// that zone resolves against no tzdata entry (rule 1 and the home-zone
  /// edge case).
  ///
  /// Derived on every read rather than stored in the state, because it is a
  /// pure function of the board and the state contract is `{ model }` alone.
  String get referenceZoneId =>
      zoneOrNull(_board?.homeZoneId ?? utcZoneId)?.id ?? utcZoneId;

  /// Today's calendar date **in the home zone**, for the date pill's reset
  /// (rule 11).
  ///
  /// Not the device's date: a user in Sao Paulo whose home is Tokyo is already
  /// on tomorrow there, and a "Today" that jumps to the wrong day is worse
  /// than no reset at all.
  DateTime get todayInHomeZone => _localDateOf(_clock.nowUtc());

  /// Moves the reference date by whole calendar days, keeping the cursor's
  /// time of day (rule 10).
  void stepDate(int days) {
    final current = _referenceDate;
    if (current == null) return;
    setReferenceDate(
      DateTime.utc(current.year, current.month, current.day + days),
    );
  }

  /// Jumps back to today in the home zone (rule 11).
  void goToToday() => setReferenceDate(todayInHomeZone);

  /// Sets the reference day the columns cover.
  ///
  /// Named to match `TimeBuddyDatePill.onChanged`, which hands back a whole
  /// date rather than a delta: a swipe, a chevron and the Today reset are all
  /// the same operation to the pill.
  void setReferenceDate(DateTime date) {
    final normalized = DateTime.utc(date.year, date.month, date.day);
    if (normalized == _referenceDate) return;
    _referenceDate = normalized;
    _cursorInstant = _cursorInstantOn(normalized);
    _rebuild();
  }

  /// Puts the cursor on the slot holding [instant] (rule 8).
  ///
  /// Snapped to a slot rather than stored raw, so a drag across the cells area
  /// and a tap on one cell produce the same value and every row highlights the
  /// same column.
  void setCursor(DateTime instant) {
    final ready = state;
    if (ready is! TimeGridReady) return;
    final slot = _slotHolding(ready.model.slots, instant);
    if (slot == null || slot == _cursorInstant) return;
    _cursorInstant = slot;
    final wall = _engine.wallTimeAt(zoneId: referenceZoneId, instant: slot);
    _cursorTimeOfDay = (hour: wall.hour, minute: wall.minute);
    emit(TimeGridReady(model: ready.model.copyWith(cursorInstant: slot)));
  }

  /// Drops the cursor, and with it the time of day a later date step would
  /// have restored.
  void clearCursor() {
    final ready = state;
    if (ready is! TimeGridReady) return;
    _cursorInstant = null;
    _cursorTimeOfDay = null;
    emit(TimeGridReady(model: ready.model.copyWith(clearCursor: true)));
  }

  /// Advances the "now" marker and nothing else.
  ///
  /// Deliberately not a `TickerService` subscription inside this cubit: a
  /// minute tick that re-emitted the whole model would rebuild every row once
  /// a minute, which is exactly what the `CustomPainter` marker exists to
  /// avoid (time_grid.md, Performance). The page calls this when the model's
  /// idea of now has to catch up — on resume, or when the day rolls over.
  void tick(DateTime nowUtc) {
    final ready = state;
    if (ready is! TimeGridReady) return;
    if (ready.model.nowInstant == nowUtc) return;
    emit(TimeGridReady(model: ready.model.copyWith(nowInstant: nowUtc)));
  }

  @override
  Future<void> close() async {
    await _boardSubscription?.cancel();
    await _preferencesSubscription?.cancel();
    return super.close();
  }

  void _onBoardState(BoardState boardState) {
    switch (boardState) {
      case BoardLoaded(:final board):
        _board = board;
        _rebuild();
      case BoardError(:final failure):
        emit(TimeGridError(failure: failure));
      case _:
        // A refresh re-emits BoardLoaded, so the only way to land here with a
        // board already in hand is a transient one. Holding the last grid
        // beats blanking a screen the user is reading.
        if (_board == null) emit(const TimeGridLoading());
    }
  }

  void _rebuild() {
    final board = _board;
    if (board == null) return;
    if (board.locations.isEmpty) {
      emit(const TimeGridEmpty());
      return;
    }

    final referenceDate = _referenceDate ??= todayInHomeZone;
    final model = _buildGrid(
      board: board,
      workingHours: _workingHours,
      referenceDate: referenceDate,
      nowInstant: _clock.nowUtc(),
      cursorInstant: _cursorInstant,
      // Read from slang rather than from a `BuildContext`: this is the locale
      // the app actually resolved (preferences or device), and it is already
      // what `Intl.defaultLocale` was set from in `app_widget`.
      localeTag: LocaleSettings.currentLocale.languageTag,
    );

    // The window moved, so a cursor resolved against the old one may no longer
    // land on a column. Snapping here keeps `cursorInstant` a member of
    // `slots`, which is the invariant every widget relies on.
    final snapped = _slotHolding(model.slots, _cursorInstant);
    _cursorInstant = snapped;
    emit(
      TimeGridReady(
        model: model.copyWith(
          cursorInstant: snapped,
          clearCursor: snapped == null,
        ),
      ),
    );
  }

  WorkingHours get _workingHours => switch (_preferencesCubit.state) {
    PreferencesReady(:final preferences) => preferences.workingHours,
    // Preferences resolve during startup, before any page mounts; this only
    // covers the frame where a test builds the grid first.
    PreferencesLoading() => WorkingHours.defaultHours,
  };

  /// The cursor's time of day, resolved against [date] in the home zone.
  ///
  /// Through `instantFor` rather than by adding 24 hours to the old instant:
  /// a day is 23 or 25 hours long twice a year, and the engine is also what
  /// answers what 02:30 means on a day that skips it (CLAUDE.md, Time rule 3).
  DateTime? _cursorInstantOn(DateTime date) {
    final timeOfDay = _cursorTimeOfDay;
    if (timeOfDay == null) return null;
    return _engine
        .instantFor(
          zoneId: referenceZoneId,
          year: date.year,
          month: date.month,
          day: date.day,
          hour: timeOfDay.hour,
          minute: timeOfDay.minute,
        )
        .utcInstant;
  }

  /// The slot whose hour contains [instant], or `null` when it falls outside
  /// the window.
  DateTime? _slotHolding(List<DateTime> slots, DateTime? instant) {
    if (instant == null) return null;
    for (final slot in slots) {
      final slotEnd = slot.add(BuildGridUseCase.slotDuration);
      if (!instant.isBefore(slot) && instant.isBefore(slotEnd)) return slot;
    }
    return null;
  }

  /// [instant] as a calendar date in the home zone, date fields only.
  ///
  /// UTC-flagged like every date the engine hands back: it is a field carrier
  /// for `dayIn`, not a moment (timezone_engine.md).
  DateTime _localDateOf(DateTime instant) {
    final wall = _engine.wallTimeAt(zoneId: referenceZoneId, instant: instant);
    return DateTime.utc(wall.year, wall.month, wall.day);
  }
}

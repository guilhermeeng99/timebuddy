import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state_defaults.dart';
import 'package:timebuddy/features/time_converter/domain/entities/conversion_result.dart';
import 'package:timebuddy/features/time_converter/domain/usecases/convert_time_usecase.dart';
import 'package:timebuddy/features/time_converter/presentation/cubit/time_converter_state.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/time_converter/presentation/cubit/time_converter_state.dart';

/// View state of the time converter (docs/specs/time_converter.md).
///
/// Page-scoped: created by `TimeConverterPage` on each visit and disposed with
/// it. It **reads** `BoardCubit` and `PreferencesCubit` and never writes to
/// either (State Machine); the converter adds no city and moves no row, so
/// there is still exactly one owner of the list of places.
///
/// It holds one piece of view state the board does not: the
/// [ConversionInput], which dies with the page (rule 10). Every setter below
/// rewrites it and recomputes synchronously — the use case is pure arithmetic
/// over data already in memory, so there is nothing to await and nothing to
/// show a spinner for.
///
/// ```dart
/// BlocProvider<TimeConverterCubit>(
///   create: (context) => TimeConverterCubit(
///     boardCubit: context.read<BoardCubit>(),
///     preferencesCubit: context.read<PreferencesCubit>(),
///     convertTime: sl<ConvertTimeUseCase>(),
///     engine: sl<TimeZoneEngine>(),
///     clock: sl<Clock>(),
///   )..start(),
///   child: const _ConverterView(),
/// );
/// ```
class TimeConverterCubit extends Cubit<TimeConverterState> {
  TimeConverterCubit({
    required BoardCubit boardCubit,
    required PreferencesCubit preferencesCubit,
    required ConvertTimeUseCase convertTime,
    required TimeZoneEngine engine,
    required Clock clock,
  }) : _boardCubit = boardCubit,
       _preferencesCubit = preferencesCubit,
       _convertTime = convertTime,
       _engine = engine,
       _clock = clock,
       super(const ConverterPreparing());

  final BoardCubit _boardCubit;
  final PreferencesCubit _preferencesCubit;
  final ConvertTimeUseCase _convertTime;

  /// Used for the one question the use case does not answer: what the wall
  /// clock reads in the source zone right now, which is where the default
  /// date and time come from (rule 2).
  final TimeZoneEngine _engine;
  final Clock _clock;

  StreamSubscription<BoardState>? _boardSubscription;
  StreamSubscription<PreferencesState>? _preferencesSubscription;

  BoardEntity? _board;
  ConversionInput? _input;

  /// The catalog name of a source zone that has no board row.
  ///
  /// The use case builds a stand-in row whose label is the last segment of the
  /// IANA id, because the domain cannot reach the city catalog; the picker
  /// that chose the zone can, so the name it showed is carried here and put
  /// back on the result (see [_named]). `null` once the source is a board row,
  /// which already carries its own label.
  String? _sourceLabel;

  /// Subscribes to the board and the preferences and builds the first answer.
  ///
  /// Separate from the constructor so a test can observe the very first
  /// emission: a cubit that emitted from its own constructor would have
  /// finished before anything could listen.
  void start() {
    _boardSubscription = _boardCubit.stream.listen(_onBoardState);
    // The working window decides every line's band, so a change to it
    // repaints the answer without changing the question.
    _preferencesSubscription = _preferencesCubit.stream.listen(
      (_) => _recompute(),
    );
    _onBoardState(_boardCubit.state);
  }

  /// The earliest date rule 8 allows, for the date picker's lower bound.
  DateTime get earliestDate => ConversionInput.earliestDate(_clock.nowUtc());

  /// The latest date rule 8 allows, for the date picker's upper bound.
  DateTime get latestDate => ConversionInput.latestDate(_clock.nowUtc());

  /// Reads the local fields in [zoneId] instead (rule 1).
  ///
  /// [label] is the catalog name of the city that was picked. Pass it
  /// whenever one is in hand: a zone the user has never saved has no board
  /// row to take a display name from, and `America/Argentina/Buenos_Aires`
  /// split on its last segment is not the name anybody chose.
  void setSourceZone(String zoneId, {String? label}) {
    final input = _input;
    // Canonically, so picking Oslo while the source is Berlin is understood
    // as the same clock rather than as a second one (locations rule 2).
    final resolved = zoneOrNull(zoneId)?.id;
    if (input == null || resolved == null) return;
    if (resolved == input.sourceZoneId && label == _sourceLabel) return;
    _sourceLabel = label;
    _apply(input.copyWith(sourceZoneId: resolved));
  }

  /// Moves the question to another calendar date.
  ///
  /// [localDate] is read for its date fields only; it is a date in the source
  /// zone, not an instant. Returns `false` when the date sits outside rule
  /// 8's window, leaving the answer on screen untouched — the page owns the
  /// sentence that explains the refusal.
  bool setDate(DateTime localDate) {
    final input = _input;
    if (input == null) return false;
    return _apply(
      input.copyWith(
        year: localDate.year,
        month: localDate.month,
        day: localDate.day,
      ),
    );
  }

  /// Moves the question to another time of day, `0..23` and `0..59`.
  ///
  /// Always inside the window: the date did not move, so a legal input stays
  /// legal.
  void setTime({required int hour, required int minute}) {
    final input = _input;
    if (input == null) return;
    _apply(input.copyWith(hour: hour, minute: minute));
  }

  /// Answers with the other occurrence of an ambiguous local time (rule 5).
  ///
  /// Kept even when the current input is not ambiguous, because the use case
  /// ignores it there; what it must never do is silently move an unambiguous
  /// answer, which is why every other setter resets it (see [_apply]).
  void setAmbiguousPick(AmbiguousPick pick) {
    final input = _input;
    if (input == null || input.ambiguousPick == pick) return;
    _emitFor(input.copyWith(ambiguousPick: pick));
  }

  /// Steps the date by whole calendar days, for the chevrons beside the date
  /// field. Returns `false` when the step would leave rule 8's window.
  ///
  /// Through UTC field carriers rather than by adding 24 hours to a local
  /// time: a day is 23 or 25 hours long twice a year, and month lengths and
  /// leap years are the calendar's arithmetic, not a duration's (CLAUDE.md,
  /// Time rule 3). Stepping off 31 January lands on 1 February for the same
  /// reason.
  bool stepDay(int days) {
    final input = _input;
    if (input == null) return false;
    return setDate(DateTime.utc(input.year, input.month, input.day + days));
  }

  /// Puts the question back on the next round half hour from now (rule 2).
  ///
  /// The *moment* only. The source zone is a separate choice the user made,
  /// and a button labelled "back to now" that also threw away the city they
  /// just picked would be answering a question they did not ask.
  void resetToNow() {
    final input = _input;
    if (input == null) return;
    _emitFor(_defaultInput(input.sourceZoneId));
  }

  @override
  Future<void> close() {
    // Cancelled rather than awaited. `cancel()` takes effect the moment it is
    // called, and awaiting a broadcast subscription's future from a
    // `testWidgets` body strands the FakeAsync microtask queue: the symptom is
    // a bare "(did not complete)" with no stack.
    unawaited(_boardSubscription?.cancel());
    unawaited(_preferencesSubscription?.cancel());
    return super.close();
  }

  void _onBoardState(BoardState boardState) {
    switch (boardState) {
      case BoardLoaded(:final board):
        _board = board;
        // Resolved once, on the first board that arrives. A later home change
        // must not move a source the user has since chosen, and the cubit
        // dies with the page anyway, so the next visit reads the new home.
        _input ??= _defaultInput(_homeZoneIdOf(board));
        _recompute();
      case BoardError(:final failure):
        emit(ConverterError(failure: failure));
      case _:
        // A refresh re-emits BoardLoaded, so the only way to land here with a
        // board already in hand is a transient state. Holding the last answer
        // beats blanking a page the user is reading.
        if (_board == null) emit(const ConverterPreparing());
    }
  }

  /// Takes [next] as the new question, unless rule 8 refuses its date.
  ///
  /// Every field change funnels through here so the ambiguity toggle is reset
  /// in exactly one place: it answers "which of *these* two occurrences", and
  /// a `second` left over from a previous date would otherwise ride along to
  /// a fall-back date the user never looked at.
  bool _apply(ConversionInput next) {
    if (!next.isWithinRange(_clock.nowUtc())) return false;
    _emitFor(next.copyWith(ambiguousPick: AmbiguousPick.first));
    return true;
  }

  void _emitFor(ConversionInput next) {
    if (next == _input) return;
    _input = next;
    _recompute();
  }

  void _recompute() {
    final board = _board;
    final input = _input;
    if (board == null || input == null) return;
    emit(
      ConverterReady(
        result: _named(
          _convertTime(
            board: board,
            input: input,
            workingHours: _preferencesCubit.state.workingHoursOrDefault,
          ),
        ),
      ),
    );
  }

  /// [result] with the picked city's name on a source line that has no board
  /// row (see [_sourceLabel]).
  ///
  /// An empty `SavedLocationEntity.id` is the domain's mark for a stand-in
  /// row; a row with an id came from the board and already carries the label
  /// the rest of the app shows for it.
  ConversionResult _named(ConversionResult result) {
    final label = _sourceLabel;
    if (label == null || result.source.location.id.isNotEmpty) return result;
    return result.copyWith(
      source: result.source.copyWith(
        location: result.source.location.copyWith(label: label),
      ),
    );
  }

  /// Rule 2's defaults: [sourceZoneId], on the next round half hour there.
  ///
  /// "There", not here: a user in Sao Paulo asking about Tokyo starts from
  /// Tokyo's clock, which may already be on tomorrow. The rounded value is
  /// built as a UTC field carrier so an hour of 24 rolls the date the way the
  /// calendar does; it is a set of local fields either way, and the engine is
  /// what turns it into an instant. On a spring-forward morning the rounded
  /// half hour can be one that does not exist, which resolves forward and is
  /// disclosed (rule 4) rather than special-cased here.
  ConversionInput _defaultInput(String sourceZoneId) {
    final wall = _engine.wallTimeAt(
      zoneId: sourceZoneId,
      instant: _clock.nowUtc(),
    );
    final rounded = wall.minute < 30
        ? DateTime.utc(wall.year, wall.month, wall.day, wall.hour, 30)
        : DateTime.utc(wall.year, wall.month, wall.day, wall.hour + 1);
    return ConversionInput(
      sourceZoneId: sourceZoneId,
      year: rounded.year,
      month: rounded.month,
      day: rounded.day,
      hour: rounded.hour,
      minute: rounded.minute,
    );
  }

  /// The board's home zone as the tzdata names it, or `UTC` when it resolves
  /// against no entry at all (locations rule 11).
  String _homeZoneIdOf(BoardEntity board) =>
      zoneOrNull(board.homeZoneId)?.id ?? utcZoneId;
}

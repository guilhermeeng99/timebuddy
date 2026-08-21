import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state_defaults.dart';
import 'package:timebuddy/features/world_clock/domain/usecases/build_world_clock_usecase.dart';
import 'package:timebuddy/features/world_clock/presentation/cubit/world_clock_state.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// Re-exported so a widget that imports the cubit also gets its states, the way
// a `part`-based bloc would, without giving up the standalone state file.
export 'package:timebuddy/features/world_clock/presentation/cubit/world_clock_state.dart';

/// View state of the world clock page.
///
/// Page-scoped: created by `WorldClockPage` on each visit and disposed with it.
/// It **reads** `BoardCubit` and `PreferencesCubit` and never writes to either
/// (docs/specs/world_clock.md, State Machine); every board mutation the page
/// offers goes straight to `BoardCubit`, so there is exactly one owner of the
/// list of places.
///
/// **One ticker, and one rebuild a minute.** The cubit subscribes to the app's
/// shared [TickerService] (rule 3) and filters its stream down to the ticks
/// that begin a new minute. Nothing in the model moves inside a minute — the
/// digits are `ClockText`'s job, and it subscribes to the same ticker itself —
/// so re-emitting a whole board 60 times a minute with `showSeconds` on would
/// be exactly the per-second rebuild storm the shared ticker exists to prevent.
///
/// The tick **rate** is not this cubit's business: `app_widget` applies the
/// `showSeconds` preference once through [TickerService.setNeedsSeconds]
/// (rule 4), because the preference is global and two owners of one rate is
/// one bad merge away from a clock stuck at 1 Hz.
///
/// ```dart
/// BlocProvider<WorldClockCubit>(
///   create: (context) => WorldClockCubit(
///     boardCubit: context.read<BoardCubit>(),
///     preferencesCubit: context.read<PreferencesCubit>(),
///     buildWorldClock: sl<BuildWorldClockUseCase>(),
///     engine: sl<TimeZoneEngine>(),
///     clock: sl<Clock>(),
///     ticker: sl<TickerService>(),
///   )..start(),
///   child: const WorldClockView(),
/// );
/// ```
class WorldClockCubit extends Cubit<WorldClockState> {
  WorldClockCubit({
    required BoardCubit boardCubit,
    required PreferencesCubit preferencesCubit,
    required BuildWorldClockUseCase buildWorldClock,
    required TimeZoneEngine engine,
    required Clock clock,
    required TickerService ticker,
  }) : _boardCubit = boardCubit,
       _preferencesCubit = preferencesCubit,
       _buildWorldClock = buildWorldClock,
       _engine = engine,
       _clock = clock,
       _ticker = ticker,
       super(const WorldClockLoading());

  final BoardCubit _boardCubit;
  final PreferencesCubit _preferencesCubit;
  final BuildWorldClockUseCase _buildWorldClock;

  /// Used for the one question the model does not answer: when a zone's clocks
  /// next change, for the DST badge and the detail sheet (rule 8).
  final TimeZoneEngine _engine;
  final Clock _clock;
  final TickerService _ticker;

  StreamSubscription<BoardState>? _boardSubscription;
  StreamSubscription<PreferencesState>? _preferencesSubscription;
  StreamSubscription<DateTime>? _tickerSubscription;

  BoardEntity? _board;

  /// Subscribes to the board, the preferences and the ticker, and builds the
  /// first model.
  ///
  /// Separate from the constructor so a test can observe the very first
  /// emission: a cubit that emitted from its own constructor would have
  /// finished before anything could listen.
  void start() {
    _boardSubscription = _boardCubit.stream.listen(_onBoardState);
    // Any preference change can repaint the page: the working window decides
    // every band (rule 7) and the locale decides every date label (rule 6).
    _preferencesSubscription = _preferencesCubit.stream.listen(
      (_) => _rebuild(),
    );
    _tickerSubscription = _ticker.stream.listen(_onTick);
    _onBoardState(_boardCubit.state);
  }

  /// Recomputes every clock for [nowUtc] and emits the result.
  ///
  /// The ticker subscription filters ticks down to one a minute before calling
  /// this; the method itself does not, so a caller with a reason to refresh
  /// mid-minute — a resume (rule 10) — gets an immediate answer.
  void tick(DateTime nowUtc) => _rebuildAt(nowUtc);

  /// Rule 10: the clock never drifts across a resume.
  ///
  /// [TickerService.resume] emits the current instant straight away, so every
  /// `ClockText` on screen catches up in the same frame instead of holding the
  /// minute the phone was locked at until the next tick lands; the [tick] that
  /// follows brings the dates, offsets and bands with them.
  void onAppResumed() {
    _ticker.resume();
    tick(_clock.nowUtc());
  }

  /// A backgrounded app must not wake the CPU once a second
  /// (world_clock.md, Performance).
  ///
  /// Safe to pair with [onAppResumed] from a page: the app cannot be navigated
  /// away from while it is in the background, so a pause this page owns is
  /// always followed by its own resume.
  void onAppPaused() => _ticker.pause();

  /// The wall-clock time in [zoneId] at which its clocks next change, or `null`
  /// when nothing is scheduled inside the engine's horizon (rule 8).
  ///
  /// Answered here rather than in the sheet so the `TimeZoneEngine` stays on
  /// one side of the presentation layer, and resolved for the current instant
  /// rather than for the model's, which may be a minute old.
  DateTime? nextTransitionLocalTime(String zoneId) {
    final next = _engine.nextTransition(
      zoneId: zoneId,
      instant: _clock.nowUtc(),
    );
    if (next == null) return null;
    return _engine.wallTimeAt(zoneId: zoneId, instant: next.atUtc);
  }

  @override
  Future<void> close() {
    // Cancelled rather than awaited. `cancel()` takes effect the moment it is
    // called, and awaiting a broadcast subscription's future from a
    // `testWidgets` body strands the FakeAsync microtask queue: the symptom is
    // a bare "(did not complete)" with no stack.
    unawaited(_boardSubscription?.cancel());
    unawaited(_preferencesSubscription?.cancel());
    unawaited(_tickerSubscription?.cancel());
    return super.close();
  }

  void _onBoardState(BoardState boardState) {
    switch (boardState) {
      case BoardLoaded(:final board):
        _board = board;
        _rebuild();
      case BoardError(:final failure):
        emit(WorldClockError(failure: failure));
      case _:
        // A refresh re-emits BoardLoaded, so the only way to land here with a
        // board already in hand is a transient state. Holding the last clocks
        // beats blanking a page the user is reading.
        if (_board == null) emit(const WorldClockLoading());
    }
  }

  /// Drops a tick that lands inside the minute already on screen.
  ///
  /// With `showSeconds` on the ticker runs at 1 Hz, and every field this model
  /// carries — the date, the day delta, the offset, the band, the DST flag —
  /// is constant across a minute.
  void _onTick(DateTime nowUtc) {
    final ready = state;
    if (ready is! WorldClockReady) return;
    if (_startOfMinute(nowUtc) == _startOfMinute(ready.model.nowInstant)) {
      return;
    }
    tick(nowUtc);
  }

  void _rebuild() => _rebuildAt(_clock.nowUtc());

  void _rebuildAt(DateTime nowInstant) {
    final board = _board;
    if (board == null) return;
    emit(
      WorldClockReady(
        model: _buildWorldClock(
          board: board,
          workingHours: _preferencesCubit.state.workingHoursOrDefault,
          nowInstant: nowInstant,
          // Read from slang rather than from a `BuildContext`: this cubit has
          // none, and rule 11 needs the hero named even on a board whose home
          // zone the user never saved as a city.
          homeFallbackLabel: t.locations.homeLabel,
        ),
      ),
    );
  }

  /// [instant] with its seconds and sub-seconds dropped, for comparing two
  /// instants by the minute they belong to.
  DateTime _startOfMinute(DateTime instant) => DateTime.utc(
    instant.year,
    instant.month,
    instant.day,
    instant.hour,
    instant.minute,
  );
}

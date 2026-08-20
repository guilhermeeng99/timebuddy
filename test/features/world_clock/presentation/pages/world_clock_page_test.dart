import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/clock_text.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/world_clock/domain/usecases/build_world_clock_usecase.dart';
import 'package:timebuddy/features/world_clock/presentation/pages/world_clock_page.dart';
import 'package:timebuddy/features/world_clock/presentation/widgets/world_clock_tile_view.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/fake_clock.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

// This file covers the half of docs/specs/world_clock.md no unit test can
// reach: what is actually on screen, and how much it costs to keep it ticking.
// `build_world_clock_usecase_test.dart` already proves the model, so nothing
// here re-derives a local hour — every assertion reads a rendered string or a
// laid-out rectangle.
//
// Every zone is picked so a wrong answer cannot look plausible at the one
// instant this file pins, 2024-06-15 10:00 UTC (a Saturday):
//
//   Europe/London is the home zone and reads 11:00 on Sat 15, because it is
//     on BST (+01:00) in June. A page that rendered UTC would read 10:00.
//   Pacific/Kiritimati is +14:00 and reads 00:00 on Sun 16: the one tile that
//     is already on tomorrow.
//   Asia/Kolkata is +05:30 and Asia/Kathmandu +05:45, so their digits carry
//     minutes that a renderer assuming whole-hour offsets silently drops.
//   Pacific/Pago_Pago is -11:00 and reads 23:00 on Fri 14: the one tile still
//     on yesterday.
const String _london = 'Europe/London';
const String _kiritimati = 'Pacific/Kiritimati';
const String _kolkata = 'Asia/Kolkata';
const String _kathmandu = 'Asia/Kathmandu';
const String _pagoPago = 'Pacific/Pago_Pago';

/// The board this file renders, in the order it was saved in (rule 2).
const List<String> _boardZones = <String>[
  _london,
  _kiritimati,
  _kolkata,
  _kathmandu,
  _pagoPago,
];

/// 2024-06-15 10:00 UTC. On the hour, deliberately: a half-hour zone then
/// reads `:30` while home reads `:00`, so a dropped minute field is visible
/// rather than merely wrong.
final DateTime _saturdayMorningUtc = utcDate(2024, 6, 15, 10);

/// Tall enough that every tile of [_boardZones] is built.
///
/// The list is lazy, and an unbuilt tile is a clock that never subscribed to
/// anything, which would quietly make the subscriber count below pass.
const Size _tallSurface = Size(800, 1200);

/// The board state a loaded `BoardCubit` publishes.
BoardState _loaded(BoardEntity board) => BoardLoaded(board: board);

SavedLocationEntity _location(String zoneId, int sortIndex) =>
    SavedLocationEntity(
      id: 'row-$sortIndex-$zoneId',
      zoneId: zoneId,
      label: zoneId.split('/').last.replaceAll('_', ' '),
      countryCode: 'ZZ',
      sortIndex: sortIndex,
      addedAt: utcDate(2024),
    );

BoardEntity _board(String homeZoneId, List<String> zoneIds) => BoardEntity(
  homeZoneId: homeZoneId,
  locations: [
    for (var i = 0; i < zoneIds.length; i++) _location(zoneIds[i], i),
  ],
  revision: 3,
  updatedAt: utcDate(2024),
);

/// One tile of the list, found by the zone it draws rather than by index: the
/// assertions below compare named rows, and an index would quietly test the
/// wrong one the day the board order changes.
Finder _tileOf(String zoneId) => find.byWidgetPredicate(
  (widget) =>
      widget is WorldClockTileView && widget.tile.location.zoneId == zoneId,
  description: 'world clock tile of $zoneId',
);

Finder _tileClockOf(String zoneId) =>
    find.descendant(of: _tileOf(zoneId), matching: find.byType(ClockText));

/// The session's `BoardCubit`. The world clock reads it and never writes to
/// it, so a mock holding one state is the whole of what the page needs.
class _MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

/// A [TickerService] the test drives, which counts what is subscribed to it.
///
/// The real service exposes no subscriber count, and world_clock rule 3 is a
/// claim about *how many* subscriptions a screen full of clocks costs: one per
/// set of digits plus the cubit's, and nothing per tile above them. Only a
/// count can state that — `hasListener` cannot tell one subscriber from
/// twenty, and a tile that owned a `Timer` would not show up in it at all.
///
/// The stream is the test's own, so a tick lands exactly when a test asks for
/// one instead of whenever a timer happened to fire.
class _CountingTickerService extends TickerService {
  _CountingTickerService({required super.clock}) {
    // The inherited constructor starts a Timer, and flutter_test fails any
    // test whose body returns with one pending — that check runs before
    // tear-downs, so disposing later would be too late. Pausing cancels it
    // without closing anything, exactly as `pumpApp` does for the real one.
    pause();
    _counted = Stream<DateTime>.multi(_onListen, isBroadcast: true);
  }

  final StreamController<DateTime> _ticks =
      StreamController<DateTime>.broadcast();

  /// Built once and handed out unchanged: `StreamBuilder` re-subscribes
  /// whenever the stream *instance* changes, so a getter minting a new one per
  /// build would inflate [listeners] on every rebuild.
  late final Stream<DateTime> _counted;

  /// How many live subscriptions [stream] currently has.
  int listeners = 0;

  @override
  Stream<DateTime> get stream => _counted;

  /// Publishes one tick, standing in for the timer this service is not
  /// running.
  void emit(DateTime instantUtc) => _ticks.add(instantUtc);

  // dispose() is deliberately not overridden: closing [_ticks] would push an
  // `onDone` through every mounted StreamBuilder during tear-down, and an
  // unclosed broadcast controller holds no timer and no other resource.

  void _onListen(MultiStreamController<DateTime> controller) {
    listeners++;
    final published = _ticks.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    // The inherited stream too, so a test that lets the *real* timer run —
    // `resume`, and the one-Timer assertion that needs it — reaches the same
    // clocks a hand-published tick does. Its `onDone` is deliberately not
    // forwarded: only `dispose` closes it, and this service is never disposed.
    final ticked = super.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = () async {
      listeners--;
      await published.cancel();
      await ticked.cancel();
    };
  }
}

/// What a pumped page hands back to its test.
typedef _PumpedClocks = ({FakeClock clock, _CountingTickerService ticker});

void main() {
  setUpAll(() async {
    initTestTimeZones();
    registerCommonFallbacks();
    // formatDayMonth reads intl's date symbols, which the app gets from
    // flutter_localizations and a test process has to load itself.
    await initializeDateFormatting();
  });

  final fullBoard = _board(_london, _boardZones);

  /// Mounts [WorldClockPage] the way `AppShell` mounts it.
  ///
  /// `pumpApp` owns the locator, the locale, the fonts and the paused ticker,
  /// so it installs first against a throwaway home. `BuildWorldClockUseCase`
  /// needs the engine it has just made, and the ticker is swapped for the
  /// counting one — hence a second `pumpWidget` here rather than a private
  /// copy of the harness.
  Future<_PumpedClocks> pumpWorldClock(
    WidgetTester tester, {
    required BoardState boardState,
  }) async {
    final app = await pumpApp(
      tester,
      const SizedBox.shrink(),
      nowUtc: _saturdayMorningUtc,
      surfaceSize: _tallSurface,
    );

    final ticker = _CountingTickerService(clock: app.clock);
    // The harness registered the app's real ticker; this page needs the one
    // the test can count and drive in its place.
    await GetIt.I.unregister<TickerService>();
    GetIt.I
      ..registerSingleton<TickerService>(ticker)
      ..registerSingleton<BuildWorldClockUseCase>(
        BuildWorldClockUseCase(engine: app.engine),
      );

    final boardCubit = _MockBoardCubit();
    whenListen(
      boardCubit,
      const Stream<BoardState>.empty(),
      initialState: boardState,
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PreferencesCubit>.value(value: app.cubit),
            BlocProvider<BoardCubit>.value(value: boardCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const WorldClockPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    return (clock: app.clock, ticker: ticker);
  }

  /// The hero's digits: the one [ClockText] on the page that is not inside a
  /// tile, because rule 1 draws it in the list's header, above the board.
  ClockText heroClock() {
    final inTiles = find
        .descendant(
          of: find.byType(WorldClockTileView),
          matching: find.byType(ClockText),
        )
        .evaluate()
        .toSet();
    final hero = find.byType(ClockText).evaluate().toSet().difference(inTiles);
    expect(hero, hasLength(1), reason: 'exactly one clock leads the page');
    return hero.single.widget as ClockText;
  }

  /// The digits one [ClockText] is currently rendering.
  String digitsOf(WidgetTester tester, Finder clock) {
    final digits = find.descendant(of: clock, matching: find.byType(Text));
    expect(digits, findsOneWidget, reason: 'one Text of digits per clock');
    return tester.widget<Text>(digits).data ?? '';
  }

  testWidgets('the home clock leads the board, larger and above it', (
    tester,
  ) async {
    await pumpWorldClock(tester, boardState: _loaded(fullBoard));

    final hero = heroClock();
    // Rule 1: the hero is the *home* zone, whichever row happens to be first.
    expect(hero.zoneId, _london);
    expect(digitsOf(tester, find.byWidget(hero)), '11:00');

    final heroRect = tester.getRect(find.byWidget(hero));
    final firstTileRect = tester.getRect(
      find.byType(WorldClockTileView).first,
    );
    expect(
      heroRect.top,
      lessThan(firstTileRect.top),
      reason: 'everyone reads their own time first',
    );
    // "Visually distinct from the list", stated as the one thing a test can
    // measure: a hero drawn at tile size is a row, not a hero.
    final tileFontSizes = tester
        .widgetList<ClockText>(find.byType(ClockText))
        .where((clock) => clock != hero)
        .map((clock) => clock.fontSize);
    expect(tileFontSizes, isNotEmpty);
    expect(tileFontSizes.every((size) => size < hero.fontSize), isTrue);

    // Rule 2: the list *is* the board, in board order. A page that sorted by
    // offset would still show five tiles and the wrong five rows.
    final drawn = tester
        .widgetList<WorldClockTileView>(find.byType(WorldClockTileView))
        .map((view) => view.tile.location.zoneId)
        .toList();
    expect(drawn, _boardZones);
  });

  testWidgets('an empty board still shows the home clock, with the CTA', (
    tester,
  ) async {
    await pumpWorldClock(
      tester,
      boardState: _loaded(_board(_london, const [])),
    );

    // Rule 11: there is no empty state in front of the hero. The user's own
    // clock is the one thing this page can always answer.
    expect(find.byType(WorldClockTileView), findsNothing);
    final hero = heroClock();
    expect(hero.zoneId, _london);
    expect(digitsOf(tester, find.byWidget(hero)), '11:00');

    // Home is a zone id, not a row (locations rule 3), so a board with no
    // rows still names the hero rather than leaving it blank.
    expect(find.text(t.locations.homeLabel), findsOneWidget);

    expect(find.text(t.worldClock.emptyTitle), findsOneWidget);
    expect(find.text(t.worldClock.emptyMessage), findsOneWidget);
    expect(find.text(t.worldClock.emptyCta), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('a half-hour zone renders its minutes and home does not', (
    tester,
  ) async {
    await pumpWorldClock(tester, boardState: _loaded(fullBoard));

    // The digits, not the model: a tile that printed only the hour would be
    // claiming an alignment with home that Kolkata and Kathmandu do not have
    // (CLAUDE.md, Time & Timezone rule 6).
    expect(digitsOf(tester, _tileClockOf(_kolkata)), '15:30');
    expect(digitsOf(tester, _tileClockOf(_kathmandu)), '15:45');
    // The other half of the pair: a renderer that always printed `:30` would
    // pass the two above on its own.
    expect(digitsOf(tester, _tileClockOf(_london)), '11:00');
    expect(digitsOf(tester, _tileClockOf(_kiritimati)), '00:00');
    expect(digitsOf(tester, _tileClockOf(_pagoPago)), '23:00');
  });

  testWidgets('Tomorrow and Yesterday land on the rows that earned them', (
    tester,
  ) async {
    await pumpWorldClock(tester, boardState: _loaded(fullBoard));

    // Rule 6, and the reason it exists: at 10:00 UTC these three cities are
    // on three different calendar dates, and the word is the fact the user
    // came for.
    expect(
      find.descendant(
        of: _tileOf(_kiritimati),
        matching: find.text('Sun 16 · ${t.worldClock.tomorrow}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _tileOf(_pagoPago),
        matching: find.text('Fri 14 · ${t.worldClock.yesterday}'),
      ),
      findsOneWidget,
    );

    // A row on home's own date says nothing, because there is nothing to say;
    // a page that labelled every row would be noise on twenty of them.
    expect(
      find.descendant(of: _tileOf(_kolkata), matching: find.text('Sat 15')),
      findsOneWidget,
    );
    // And the words are on exactly one row each, nowhere else on the page.
    expect(find.textContaining(t.worldClock.tomorrow), findsOneWidget);
    expect(find.textContaining(t.worldClock.yesterday), findsOneWidget);
  });

  testWidgets('every clock runs off the one shared ticker', (tester) async {
    final pumped = await pumpWorldClock(
      tester,
      boardState: _loaded(fullBoard),
    );

    final clocks = find.byType(ClockText).evaluate().length;
    expect(clocks, _boardZones.length + 1, reason: 'the hero and five tiles');

    // Rule 3 is a claim about **timers**, not about subscriptions, and the
    // difference decides what this test may assert. `ClockText` subscribes
    // once per set of digits *by design* (spec, Performance: the StreamBuilder
    // wraps the digits and nothing else, so a tick repaints one `Text` instead
    // of a row), so a hero over five tiles is six subscriptions plus the
    // cubit's seventh. A test demanding a subscriber count of 1 would be
    // demanding the opposite of the design and would go red on a page that is
    // behaving perfectly.
    //
    // What must be true — and what "one ticker for every clock" is worth
    // pinning as — is the cost: the whole app runs **one** `Timer` and
    // `TickerService` owns it. Both halves are asserted below.
    expect(pumped.ticker.listeners, clocks + 1);

    // One tick on that one stream moves every clock on the page at once.
    //
    // Two pumps, and the second is not ceremony: the tick reaches every
    // `StreamBuilder` in a microtask, while `WidgetTester.pump` decides
    // whether to draw a frame *before* it flushes microtasks. The first pump
    // therefore delivers the tick and draws nothing.
    pumped.clock.advance(const Duration(hours: 1));
    pumped.ticker.emit(pumped.clock.nowUtc());
    await tester.pump();
    await tester.pump();

    expect(digitsOf(tester, _tileClockOf(_london)), '12:00');
    expect(digitsOf(tester, _tileClockOf(_kiritimati)), '01:00');
    expect(digitsOf(tester, _tileClockOf(_kolkata)), '16:30');
    expect(digitsOf(tester, _tileClockOf(_kathmandu)), '16:45');
    expect(digitsOf(tester, _tileClockOf(_pagoPago)), '00:00');
    expect(digitsOf(tester, find.byWidget(heroClock())), '12:00');

    // The rebuild the tick caused must not have bought a second subscription
    // per clock, which is the classic way a "shared ticker" leaks back into a
    // subscription per tick.
    expect(pumped.ticker.listeners, clocks + 1);

    // Now the timer half, with the service's own timer actually running: this
    // is the only test in the file that lets it, because a paused ticker costs
    // nothing by construction and would prove nothing.
    //
    // Nobody publishes a tick from here on. A minute of elapsed time has to
    // move every clock on the page by itself, which it can only do if a real
    // `Timer` inside `TickerService` is driving them.
    pumped.ticker.resume();
    pumped.clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(digitsOf(tester, _tileClockOf(_london)), '12:01');
    expect(digitsOf(tester, _tileClockOf(_kolkata)), '16:31');
    expect(digitsOf(tester, find.byWidget(heroClock())), '12:01');

    // And that timer is the *only* one in the app. `pause` cancels
    // `TickerService`'s and nothing else, so the body now returns with none
    // pending — a state `flutter_test` verifies for us before any tear-down
    // runs. A tile that started a `Timer.periodic` of its own, which rule 3
    // calls a review blocker, fails right here and names its own creation site
    // in the pending-timer dump.
    pumped.ticker.pause();
  });
}

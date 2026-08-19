import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/clock_text.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../harness/factories/preferences_factory.dart';
import '../../harness/fake_clock.dart';
import '../../harness/helpers.dart';
import '../../harness/mocks.dart';

// Three clocks are in play here, and keeping them apart is what makes this
// file deterministic:
//
//  * `FakeClock` decides *what instant* a tick carries. Only `advance()` moves
//    it, so nothing below depends on the wall clock or on how long a test ran.
//  * The fake async that `testWidgets` runs its body in decides *when* the
//    ticker's timer fires. `tester.pump(duration)` moves it for free.
//  * The zone id decides what the digits read for that instant.
//
// Every case disposes its ticker before returning: the binding fails a test
// that leaves a pending timer behind, which doubles as a free assertion that
// nothing here leaks a heartbeat into the next case.

/// The instant every expectation below is pinned to.
///
/// 1 June sits far from any transition in the three zones used here, so an
/// hour that comes out wrong is a real bug rather than a DST edge this file
/// was never meant to cover.
final DateTime _instantUtc = utcDate(2024, 6, 1, 12);

const _kolkata = 'Asia/Kolkata'; // +05:30, a half-hour zone on purpose
const _saoPaulo = 'America/Sao_Paulo'; // -03:00, no DST since 2019
const _newYork = 'America/New_York'; // -04:00 (EDT) in June

// The wall clock each zone reads at _instantUtc, written out by hand rather
// than derived from the engine: an expectation computed by the code under test
// can only prove that the code agrees with itself.
const _kolkataDigits = '17:30';
const _saoPauloDigits = '09:00';
const _newYorkDigits = '08:00';
const _utcDigits = '12:00';

void main() {
  setUpAll(() {
    initTestTimeZones();
    registerCommonFallbacks();
    // Pinned so the tree below never resolves strings against whatever locale
    // the machine running the suite happens to report.
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  late FakeClock clock;
  late TzTimeZoneEngine engine;
  late MockPreferencesRepository repository;

  setUp(() async {
    // get_it is process-wide: a registration surviving into the next test
    // would quietly feed a disposed ticker to a widget that resolves its own
    // collaborators.
    await GetIt.I.reset();
    clock = FakeClock(_instantUtc);
    engine = TzTimeZoneEngine();
    repository = MockPreferencesRepository();
    when(() => repository.save(any())).thenAnswer(
      (_) async => Right<Failure, PreferencesEntity>(aPreferences()),
    );
  });

  /// A cubit already in `PreferencesReady`.
  ///
  /// The widget falls back to 24h while preferences are loading, so a 12h
  /// case mounted against a loading cubit would pass for the wrong reason.
  Future<PreferencesCubit> readyCubit({
    ClockFormat hourFormat = ClockFormat.h24,
  }) async {
    when(
      () => repository.load(deviceLocale: any(named: 'deviceLocale')),
    ).thenAnswer(
      (_) async => Right<Failure, PreferencesEntity>(
        aPreferences(hourFormat: hourFormat),
      ),
    );
    final cubit = PreferencesCubit(repository: repository, clock: clock);
    await cubit.load(deviceLocale: const Locale('en'));
    addTearDown(cubit.close);
    return cubit;
  }

  ClockText clockFor(
    String zoneId,
    TickerService ticker, {
    bool withSeconds = false,
  }) {
    return ClockText(
      zoneId: zoneId,
      showSeconds: withSeconds,
      ticker: ticker,
      engine: engine,
      clock: clock,
    );
  }

  group('what the digits say', () {
    testWidgets('renders the wall clock of each zone, not the instant', (
      tester,
    ) async {
      final cubit = await readyCubit();
      final ticker = TickerService(clock: clock);

      await tester.pumpWidget(
        _host(
          cubit: cubit,
          subject: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              clockFor(_kolkata, ticker),
              clockFor(_saoPaulo, ticker),
            ],
          ),
        ),
      );

      expect(find.text(_kolkataDigits), findsOneWidget);
      expect(find.text(_saoPauloDigits), findsOneWidget);
      // The instant itself must never reach the screen: rendering it would
      // look plausible and be wrong for every zone except UTC.
      expect(find.text(_utcDigits), findsNothing);

      await ticker.dispose();
    });

    testWidgets('shows seconds only when asked for them', (tester) async {
      final cubit = await readyCubit();
      final ticker = TickerService(clock: clock);

      await tester.pumpWidget(
        _host(
          cubit: cubit,
          subject: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              clockFor(_kolkata, ticker),
              clockFor(_kolkata, ticker, withSeconds: true),
            ],
          ),
        ),
      );

      expect(find.text(_kolkataDigits), findsOneWidget);
      expect(find.text('$_kolkataDigits:00'), findsOneWidget);

      await ticker.dispose();
    });

    testWidgets('repaints when the hour format preference changes', (
      tester,
    ) async {
      final cubit = await readyCubit();
      final ticker = TickerService(clock: clock);

      await tester.pumpWidget(
        _host(cubit: cubit, subject: clockFor(_kolkata, ticker)),
      );
      expect(_digitsOf(tester), _kolkataDigits);

      // Watched, not read: the switch lands between ticks and must not wait
      // for the next one to show up on screen.
      await cubit.setClockFormat(ClockFormat.h12);
      await tester.pump();

      final twelveHour = _digitsOf(tester);
      expect(twelveHour, isNot(_kolkataDigits));
      expect(twelveHour, startsWith('5:30'));
      expect(twelveHour, contains('PM'));

      await ticker.dispose();
    });

    testWidgets('digits carry tabular figures, the size and the token', (
      tester,
    ) async {
      final cubit = await readyCubit();
      final ticker = TickerService(clock: clock);

      await tester.pumpWidget(
        _host(
          cubit: cubit,
          subject: ClockText(
            zoneId: _kolkata,
            fontSize: 42,
            ticker: ticker,
            engine: engine,
            clock: clock,
          ),
        ),
      );

      final style = tester.widget<Text>(find.text(_kolkataDigits)).style!;
      // Non-jittering digits are a hard requirement: with proportional
      // figures every glyph has its own advance width, so a board of clocks
      // twitches sideways once a second.
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.fontSize, 42);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, AppColors.light.onBackground);

      await ticker.dispose();
    });
  });

  group('following the ticker', () {
    testWidgets('advances the digits on a minute tick', (tester) async {
      final cubit = await readyCubit();
      final ticker = TickerService(clock: clock);

      await tester.pumpWidget(
        _host(cubit: cubit, subject: clockFor(_kolkata, ticker)),
      );
      expect(_digitsOf(tester), _kolkataDigits);

      // The clock moves first, then the timer that reads it fires: the digits
      // change because the instant changed, not because a frame was drawn.
      clock.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(_digitsOf(tester), '17:31');
      expect(find.text(_kolkataDigits), findsNothing);

      await ticker.dispose();
    });

    testWidgets('advances every second at the seconds rate', (tester) async {
      final cubit = await readyCubit();
      final ticker = TickerService(clock: clock)..setNeedsSeconds(value: true);

      await tester.pumpWidget(
        _host(
          cubit: cubit,
          subject: clockFor(_kolkata, ticker, withSeconds: true),
        ),
      );
      expect(_digitsOf(tester), '$_kolkataDigits:00');

      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(_digitsOf(tester), '$_kolkataDigits:01');

      await ticker.dispose();
    });
  });

  group('one ticker for the whole app', () {
    testWidgets('resolves its collaborators from get_it when not given', (
      tester,
    ) async {
      final cubit = await readyCubit();
      final ticker = TickerService(clock: clock);
      GetIt.I
        ..registerSingleton<Clock>(clock)
        ..registerSingleton<TimeZoneEngine>(engine)
        ..registerSingleton<TickerService>(ticker);

      await tester.pumpWidget(
        _host(cubit: cubit, subject: const ClockText(zoneId: _kolkata)),
      );

      expect(find.text(_kolkataDigits), findsOneWidget);

      await ticker.dispose();
    });

    testWidgets('every clock on screen is fed by the one app ticker', (
      tester,
    ) async {
      final cubit = await readyCubit();
      final ticker = _CountingTickerService(clock: clock);
      GetIt.I
        ..registerSingleton<Clock>(clock)
        ..registerSingleton<TimeZoneEngine>(engine)
        ..registerSingleton<TickerService>(ticker);

      var rowBuilds = 0;
      await tester.pumpWidget(
        _host(
          cubit: cubit,
          subject: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final zoneId in const [_kolkata, _saoPaulo, _newYork])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RowProbe(() {
                      rowBuilds++;
                    }),
                    ClockText(zoneId: zoneId),
                  ],
                ),
            ],
          ),
        ),
      );

      // One subscription per digit leaf and not one more: a widget that grew
      // its own Timer would leave the shared ticker with fewer, and a
      // StreamBuilder wrapped around the row instead of around the digits
      // would show up as a rebuilt probe.
      expect(ticker.liveSubscriptions, 3);
      expect(rowBuilds, 3);
      expect(find.text(_kolkataDigits), findsOneWidget);
      expect(find.text(_saoPauloDigits), findsOneWidget);
      expect(find.text(_newYorkDigits), findsOneWidget);

      clock.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      // One emission, three repainted leaves, no rebuilt rows.
      expect(find.text('17:31'), findsOneWidget);
      expect(find.text('09:01'), findsOneWidget);
      expect(find.text('08:01'), findsOneWidget);
      expect(rowBuilds, 3);
      expect(ticker.liveSubscriptions, 3);

      // Unmounting has to release every one of them, or a page the user left
      // keeps repainting for the rest of the session.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(ticker.liveSubscriptions, 0);

      await ticker.dispose();
    });
  });
}

/// Everything a `ClockText` needs above it: the localized tree the app runs
/// in, the preferences it watches and the palette it colours itself from.
Widget _host({required PreferencesCubit cubit, required Widget subject}) {
  return TranslationProvider(
    child: BlocProvider<PreferencesCubit>.value(
      value: cubit,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: subject)),
      ),
    ),
  );
}

/// The digits of the single `ClockText` on screen.
String _digitsOf(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(of: find.byType(ClockText), matching: find.byType(Text)),
  );
  return text.data!;
}

/// A `TickerService` that reports how many live subscriptions its stream has.
///
/// The count is the whole point: one ticker for the whole app means every
/// clock on screen hangs off this single broadcast stream, so the number of
/// live subscriptions must equal the number of rendered clocks and must drop
/// back to zero when they leave.
class _CountingTickerService extends TickerService {
  _CountingTickerService({required super.clock});

  int liveSubscriptions = 0;

  /// Built once and cached, so its identity is stable across rebuilds: a
  /// fresh stream object per build would make `StreamBuilder` resubscribe and
  /// the counter would then be measuring rebuilds instead of subscriptions.
  late final Stream<DateTime> _observed = Stream<DateTime>.multi(
    _onListen,
    isBroadcast: true,
  );

  @override
  Stream<DateTime> get stream => _observed;

  void _onListen(MultiStreamController<DateTime> controller) {
    liveSubscriptions++;
    final source = super.stream.listen(controller.add);
    controller.onCancel = () {
      liveSubscriptions--;
      return source.cancel();
    };
  }
}

/// A leaf standing in for the row around the digits: a tick must not rebuild
/// it, which is the difference between repainting one `Text` and repainting
/// thirty rows a second.
class _RowProbe extends StatelessWidget {
  const _RowProbe(this.onBuild);

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.shrink();
  }
}

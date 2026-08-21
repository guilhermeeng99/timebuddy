import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_field.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_converter/domain/entities/conversion_result.dart';
import 'package:timebuddy/features/time_converter/domain/usecases/convert_time_usecase.dart';
import 'package:timebuddy/features/time_converter/presentation/cubit/time_converter_cubit.dart';
import 'package:timebuddy/features/time_converter/presentation/pages/time_converter_page.dart';
import 'package:timebuddy/features/time_converter/presentation/widgets/conversion_result_list.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

// `convert_time_usecase_test.dart` already pins the arithmetic. What no unit
// test can reach is whether the page *says* which question it answered, so
// every case below drives an input and then reads the sentence and the digits
// that came back.
//
// Every date is pinned to its year, because the converter exists precisely
// because a zone's rules are a function of the instant:
//
//   America/New_York 2024 springs forward 10 March, 02:00 EST -> 03:00 EDT at
//     07:00 UTC, so 02:30 never happens and resolves to 03:30; it falls back
//     3 November, 02:00 EDT -> 01:00 EST at 06:00 UTC, so 01:30 happens at
//     05:30 UTC and again at 06:30 UTC.
//   Europe/London is on GMT on both of those dates (BST runs 31 March to 27
//     October in 2024), so its readings move only when the source instant
//     does — which is exactly what the ambiguity toggle has to change.
//   America/Sao_Paulo abolished DST in 2019 and sits at -03:00 all year, so
//     it is the fixed source against which New York's own January/July
//     difference shows up.
const String _saoPaulo = 'America/Sao_Paulo';
const String _newYork = 'America/New_York';
const String _london = 'Europe/London';
const String _tokyo = 'Asia/Tokyo';

/// 2024-06-15 12:00 UTC, which is 09:00 in Sao Paulo: far from any transition,
/// and on the hour so the rounded default below is unambiguous.
final DateTime _middayUtc = utcDate(2024, 6, 15, 12);

/// Tall enough that the source block, the disclosure banner and the results
/// are all laid out at once; the page is one lazy `ListView`.
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

/// One of the three source fields, found by the label it carries.
Finder _fieldLabelled(String label) => find.byWidgetPredicate(
  (widget) => widget is TimeBuddyPickerField && widget.label == label,
  description: 'picker field labelled "$label"',
);

/// Something rendered inside the answer, rather than inside the question: the
/// requested time appears in both, and only one of them is the result.
Finder _inResults(Finder matching) =>
    find.descendant(of: find.byType(ConversionResultList), matching: matching);

/// The identity block of one target line.
Finder _resultRowOf(String zoneId) => _inResults(
  find.byWidgetPredicate(
    (widget) => widget is LocationRow && widget.location.zoneId == zoneId,
    description: 'result row of $zoneId',
  ),
);

/// The session's `BoardCubit`. The converter reads it and never writes to it
/// (rule 3), so a mock holding one state is all the page needs from it.
class _MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

void main() {
  setUpAll(() async {
    initTestTimeZones();
    registerCommonFallbacks();
    // formatDayMonth reads intl's date symbols, which the app gets from
    // flutter_localizations and a test process has to load itself.
    await initializeDateFormatting();
  });

  /// Mounts [TimeConverterPage] the way `AppShell` mounts it.
  ///
  /// `pumpApp` owns the locator, the locale, the fonts and the paused ticker,
  /// so it installs first against a throwaway home. `ConvertTimeUseCase` is
  /// the one dependency this page resolves that the shared harness has no
  /// reason to register, and building it needs the engine `pumpApp` has just
  /// made — hence a second `pumpWidget` here.
  Future<void> pumpConverter(
    WidgetTester tester, {
    required BoardState boardState,
  }) async {
    final app = await pumpApp(
      tester,
      const SizedBox.shrink(),
      nowUtc: _middayUtc,
      surfaceSize: _tallSurface,
    );
    GetIt.I.registerSingleton<ConvertTimeUseCase>(
      ConvertTimeUseCase(engine: app.engine),
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
            home: const TimeConverterPage(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The page's own cubit, read from inside its provider.
  ///
  /// The date and time pickers are platform dialogs whose dials a test can
  /// only drive by tapping numbers on a clock face; the question they set is
  /// this one call, and every assertion below is still about what the page
  /// rendered for it.
  TimeConverterCubit converterCubit(WidgetTester tester) =>
      tester.element(find.byType(Scaffold)).read<TimeConverterCubit>();

  /// The value one source field is showing.
  String valueOf(WidgetTester tester, String label) =>
      tester.widget<TimeBuddyPickerField>(_fieldLabelled(label)).value ?? '';

  /// Points the question at [year]-[month]-[day], [hour]:[minute] and lets the
  /// page rebuild.
  ///
  /// `pumpAndSettle` and not a single `pump`, and the difference is not
  /// cosmetic: a cubit hands its new state to `BlocBuilder` through a
  /// broadcast stream, so the rebuild is marked in a *microtask*, while
  /// `WidgetTester.pump` decides whether to draw a frame **before** it flushes
  /// those. One pump after a setter therefore delivers the state and draws
  /// nothing, and every assertion below would read the previous answer.
  Future<void> ask(
    WidgetTester tester, {
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
  }) async {
    final cubit = converterCubit(tester);
    expect(
      cubit.setDate(utcDate(year, month, day)),
      isTrue,
      reason: 'the date has to be inside rule 8 for the case to mean anything',
    );
    cubit.setTime(hour: hour, minute: minute);
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the next round half hour in the source zone', (
    tester,
  ) async {
    await pumpConverter(
      tester,
      boardState: _loaded(_board(_saoPaulo, [_saoPaulo, _tokyo])),
    );

    // Rule 2. "There", not here: it is 09:00 in Sao Paulo at the pinned
    // instant, so a default read off the UTC clock would open on 12:30.
    expect(valueOf(tester, t.converter.timeLabel), '09:30');
    expect(valueOf(tester, t.converter.sourceLabel), 'Sao Paulo');
    // Nothing was disclosed, because nothing needed to be.
    expect(find.text(t.converter.ambiguousFirst), findsNothing);
  });

  testWidgets('a nonexistent local time is disclosed with what is shown', (
    tester,
  ) async {
    await pumpConverter(
      tester,
      boardState: _loaded(_board(_newYork, [_newYork, _london])),
    );

    await ask(tester, year: 2024, month: 3, day: 10, hour: 2, minute: 30);

    // Rule 4: it never silently answers a different question. The banner
    // names both the time that does not exist and the one on screen instead.
    expect(
      find.text(
        t.converter.shiftedForwardNotice(requested: '02:30', shown: '03:30'),
      ),
      findsOneWidget,
    );
    // A gap is not an ambiguity, so there is nothing to toggle between.
    expect(find.text(t.converter.ambiguousFirst), findsNothing);
    expect(find.text(t.converter.ambiguousSecond), findsNothing);

    // And the answer is the one for 03:30 EDT, which is 07:30 UTC and
    // therefore 07:30 in a London still on GMT in early March.
    expect(_resultRowOf(_london), findsOneWidget);
    expect(_inResults(find.text('07:30')), findsOneWidget);
  });

  testWidgets('the ambiguity toggle moves the answer to the other hour', (
    tester,
  ) async {
    await pumpConverter(
      tester,
      boardState: _loaded(_board(_newYork, [_newYork, _london])),
    );

    await ask(tester, year: 2024, month: 11, day: 3, hour: 1, minute: 30);

    // Rule 5: on a fall-back date both readings are legitimate and only the
    // user knows which they meant, so the page discloses and offers.
    expect(
      find.text(t.converter.ambiguousNotice(zone: 'New York')),
      findsOneWidget,
    );
    expect(find.text(t.converter.ambiguousFirst), findsOneWidget);
    expect(find.text(t.converter.ambiguousSecond), findsOneWidget);

    // The earlier occurrence: 01:30 EDT is 05:30 UTC, and London is on GMT.
    expect(_resultRowOf(_london), findsOneWidget);
    expect(_inResults(find.text('05:30')), findsOneWidget);
    expect(_inResults(find.text('+4h')), findsOneWidget);

    await tester.tap(find.text(t.converter.ambiguousSecond));
    await tester.pumpAndSettle();

    // The same wall clock in New York, an hour later in real time — which is
    // the whole reason the toggle exists, and it moves every line with it.
    expect(_inResults(find.text('06:30')), findsOneWidget);
    expect(_inResults(find.text('05:30')), findsNothing);
    // 01:30 EST rather than EDT, so the distance from the source changed too.
    expect(_inResults(find.text('+5h')), findsOneWidget);
    // The question is untouched: only which of its two answers is shown.
    expect(valueOf(tester, t.converter.timeLabel), '01:30');
  });

  testWidgets('a target is read under the DST rules of the chosen date', (
    tester,
  ) async {
    await pumpConverter(
      tester,
      boardState: _loaded(_board(_saoPaulo, [_saoPaulo, _newYork])),
    );

    await ask(tester, year: 2024, month: 1, day: 15, hour: 12, minute: 0);

    // Rule 6, and the converter's whole reason to exist. Sao Paulo is -03:00
    // in both months, so every difference below belongs to New York.
    expect(_resultRowOf(_newYork), findsOneWidget);
    expect(_inResults(find.text('10:00')), findsOneWidget);
    expect(_inResults(find.text('EST')), findsOneWidget);
    expect(_inResults(find.text('-2h')), findsOneWidget);

    await ask(tester, year: 2024, month: 7, day: 15, hour: 12, minute: 0);

    // Same source wall clock, six months later: New York is on EDT, so the
    // answer is an hour later there and one hour closer to Sao Paulo. A page
    // reading an offset cached off the board would still say 10:00 and EST.
    expect(_inResults(find.text('11:00')), findsOneWidget);
    expect(_inResults(find.text('EDT')), findsOneWidget);
    expect(_inResults(find.text('-1h')), findsOneWidget);
    expect(_inResults(find.text('10:00')), findsNothing);
  });

  testWidgets('the ten-year bound refuses the step and says why', (
    tester,
  ) async {
    await pumpConverter(
      tester,
      boardState: _loaded(_board(_saoPaulo, [_saoPaulo, _tokyo])),
    );
    final cubit = converterCubit(tester);

    // Rule 8's window, which is also what the date picker is handed as its
    // bounds, so a picker that could reach past it would be a wider bug.
    expect(cubit.earliestDate, utcDate(2014, 6, 15));
    expect(cubit.latestDate, utcDate(2034, 6, 15));
    expect(cubit.setDate(utcDate(2034, 6, 16)), isFalse);
    expect(cubit.setDate(utcDate(2014, 6, 14)), isFalse);

    expect(cubit.setDate(utcDate(2034, 6, 15)), isTrue);
    // Settled, not pumped once, for the reason `ask` spells out: a single
    // pump delivers the emission and draws no frame for it, and the field
    // read on the next line would still be showing today's date.
    await tester.pumpAndSettle();
    final atTheEdge = valueOf(tester, t.converter.dateLabel);

    await tester.tap(
      find.widgetWithIcon(IconButton, FontAwesomeIcons.chevronRight.data),
    );
    await tester.pump();

    // A chevron that silently did nothing is worse than one that explains
    // itself: the day did not move, and the page said so.
    expect(
      find.text(t.converter.outOfRange(years: ConversionInput.rangeYears)),
      findsOneWidget,
    );
    expect(valueOf(tester, t.converter.dateLabel), atTheEdge);

    // The other chevron still works, so the bound is a wall and not a freeze.
    await tester.tap(
      find.widgetWithIcon(IconButton, FontAwesomeIcons.chevronLeft.data),
    );
    await tester.pump();
    expect(valueOf(tester, t.converter.dateLabel), isNot(atTheEdge));

    // Settle the offer in, time it out, then settle it back off screen: a
    // snackbar still counting down when the body returns is a pending Timer,
    // which flutter_test fails the test for.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a board holding only the source asks for another city', (
    tester,
  ) async {
    await pumpConverter(
      tester,
      boardState: _loaded(_board(_saoPaulo, [_saoPaulo])),
    );

    // Rule 3's other valid answer. An empty result set is not an error, and
    // an `ErrorView` here would tell the user something broke when nothing
    // did (Edge cases).
    expect(find.text(t.converter.needMoreCities), findsOneWidget);
    expect(_inResults(find.byType(LocationRow)), findsNothing);
    expect(valueOf(tester, t.converter.sourceLabel), 'Sao Paulo');
  });
}

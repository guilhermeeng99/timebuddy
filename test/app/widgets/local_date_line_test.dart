import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/local_date_line.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// The world clock's tile and the converter's row drew this line themselves,
// from the same span and the same accent. The assertions below are the two
// facts that made them worth merging: the day word is *appended* to the date
// rather than replacing it, and it is accented because on a board crossing the
// date line it is the fact the user came for.
//
// A `DateTime` here is a carrier for calendar fields, never an instant: the
// widget renders what it is handed and computes nothing about time.

/// A Tuesday, so the weekday in the expectation is not an accident.
final DateTime _localTime = DateTime(2026, 8, 25, 14, 30);

void main() {
  // `formatDayMonth` goes through `DateFormat`, which throws until the locale
  // data is loaded — the same setup every page test that renders a date does.
  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting();
  });

  testWidgets('shows the date alone when the row shares the reference day', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(LocalDateLine(localTime: _localTime, dayDelta: 0)),
    );

    expect(find.text(_dayMonth), findsOneWidget);
  });

  testWidgets('appends the day word for the two deltas that have one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(LocalDateLine(localTime: _localTime, dayDelta: 1)),
    );
    expect(_rendered(tester), '$_dayMonth · ${t.worldClock.tomorrow}');

    await tester.pumpWidget(
      _host(LocalDateLine(localTime: _localTime, dayDelta: -1)),
    );
    expect(_rendered(tester), '$_dayMonth · ${t.worldClock.yesterday}');
  });

  testWidgets('says nothing about a two-day gap, which really happens', (
    tester,
  ) async {
    // Kiritimati to Niue is +2 at some hours of the day. Calling that
    // "Tomorrow" would be wrong by a day, and the date beside it is exact.
    for (final delta in [2, -2]) {
      await tester.pumpWidget(
        _host(LocalDateLine(localTime: _localTime, dayDelta: delta)),
      );
      expect(_rendered(tester), _dayMonth);
      expect(relativeDayWord(delta), isNull);
    }
  });

  testWidgets('accents the day word and leaves the date muted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(LocalDateLine(localTime: _localTime, dayDelta: 1)),
    );

    final line = tester.widget<Text>(find.byType(Text));
    final spans = (line.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.style, isNull, reason: 'the date takes the line style');
    expect(spans.last.style!.color, AppColors.light.primary);
    expect(spans.last.style!.fontWeight, FontWeight.w600);
    expect(line.style!.color, AppColors.light.onBackgroundLight);

    // One span and not two Texts: two Flexibles split the free width evenly
    // regardless of what they need, so the day word would ellipsize beside a
    // date sitting in half a column it never asked for.
    expect(line.maxLines, 1);
    expect(line.overflow, TextOverflow.ellipsis);
    expect(line.textAlign, TextAlign.end);
  });
}

/// The date half, through the same formatter the widget uses: a copy typed as
/// an English literal here would pass while the app rendered something else.
String get _dayMonth =>
    formatDayMonth(_localTime, LocaleSettings.currentLocale.languageTag);

String _rendered(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text)).textSpan!.toPlainText();

/// The tree a [LocalDateLine] needs above it: a palette to read tokens from
/// and the localized scope every page of the app renders inside.
Widget _host(Widget subject) {
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: subject)),
    ),
  );
}

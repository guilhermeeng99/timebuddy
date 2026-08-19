import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// The cell decides nothing about time: the band arrives already computed by
// `hourBandFor`, so everything asserted here is presentation. What makes these
// assertions worth writing is that the presentation *is* the specification:
// the alpha, the border width and the minute suffix are the only things
// telling a user that 09:00 is reachable and that a row does not line up with
// the column above it.

/// The band token's opacity on the cell fill (design_system, hour bands).
const double _fillAlpha = 0.12;

/// The selection wash over that fill.
const double _selectedAlpha = 0.18;

/// Border width of the shared hour cursor.
const double _cursorBorderWidth = 2;

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('band colours', () {
    testWidgets('each band paints its own token at 12 percent', (
      tester,
    ) async {
      // Written against the palette tokens rather than against
      // `hourBandColor`, so a mapping that sent two bands to the same token
      // cannot pass by agreeing with itself.
      final tokens = <HourBand, Color>{
        HourBand.good: AppColors.light.hourGood,
        HourBand.fair: AppColors.light.hourFair,
        HourBand.poor: AppColors.light.hourPoor,
        HourBand.night: AppColors.light.hourNight,
      };
      expect(tokens.values.toSet(), hasLength(HourBand.values.length));

      for (final band in HourBand.values) {
        await tester.pumpWidget(_host(HourCell(hour: 9, band: band)));

        expect(
          _decorationsOf(tester).first.color,
          tokens[band]!.withValues(alpha: _fillAlpha),
          reason: 'fill for HourBand.${band.name}',
        );
      }
    });

    testWidgets('reads the palette in force, not the light one', (
      tester,
    ) async {
      // `fair` is the band whose two palettes actually differ, so a hardcoded
      // light token would survive any other choice here.
      await tester.pumpWidget(
        _host(
          const HourCell(hour: 8, band: HourBand.fair),
          theme: AppTheme.dark(),
        ),
      );

      final fill = _decorationsOf(tester).first.color;
      expect(fill, AppColors.dark.hourFair.withValues(alpha: _fillAlpha));
      expect(
        fill,
        isNot(AppColors.light.hourFair.withValues(alpha: _fillAlpha)),
      );
    });
  });

  group('the label', () {
    testWidgets('renders a zero-padded hour and no suffix on the hour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 7, band: HourBand.good)),
      );
      expect(find.text('07'), findsOneWidget);

      // A zero minute is a whole-hour row too: showing `07:00` would imply the
      // row is offset from the column when it is not.
      await tester.pumpWidget(
        _host(const HourCell(hour: 7, band: HourBand.good, minute: 0)),
      );
      expect(find.text('07'), findsOneWidget);
    });

    testWidgets('renders the minute suffix for a half-hour zone', (
      tester,
    ) async {
      // Kolkata is +05:30 and Kathmandu +05:45: hiding those minutes would
      // claim the row lines up with the column when it does not.
      await tester.pumpWidget(
        _host(const HourCell(hour: 14, band: HourBand.good, minute: 30)),
      );
      expect(find.text('14:30'), findsOneWidget);
      final withMinutes = _labelStyle(tester, '14:30').fontSize!;

      await tester.pumpWidget(
        _host(const HourCell(hour: 5, band: HourBand.night, minute: 45)),
      );
      expect(find.text('05:45'), findsOneWidget);

      await tester.pumpWidget(
        _host(const HourCell(hour: 14, band: HourBand.good)),
      );
      // Two extra glyphs have to fit the same 44px column.
      expect(withMinutes, lessThan(_labelStyle(tester, '14').fontSize!));
    });
  });

  group('cursor and selection', () {
    testWidgets('a plain cell has neither border nor wash', (tester) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good)),
      );

      final decorations = _decorationsOf(tester);
      expect(decorations, hasLength(2));
      expect(decorations.first.border, isNull);
      expect(decorations.last.color, isNull);
      expect(_labelStyle(tester, '09').color, AppColors.light.onBackground);
      expect(_labelStyle(tester, '09').fontWeight, FontWeight.w500);
    });

    testWidgets('the cursor draws a primary border and emphasises', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good, isCursor: true)),
      );

      final border = _decorationsOf(tester).first.border! as Border;
      expect(border.top.color, AppColors.light.primary);
      expect(border.top.width, _cursorBorderWidth);
      expect(_labelStyle(tester, '09').color, AppColors.light.primary);
      expect(_labelStyle(tester, '09').fontWeight, FontWeight.w600);
    });

    testWidgets('selection washes primary over the band it keeps', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.poor, isSelected: true)),
      );

      final decorations = _decorationsOf(tester);
      // The wash sits *over* the band rather than replacing it, so a picked
      // slot still says whether it is a good hour to meet.
      expect(
        decorations.first.color,
        AppColors.light.hourPoor.withValues(alpha: _fillAlpha),
      );
      expect(
        decorations.last.color,
        AppColors.light.primary.withValues(alpha: _selectedAlpha),
      );
      expect(decorations.first.border, isNull);
      expect(_labelStyle(tester, '09').color, AppColors.light.primary);
    });
  });

  group('interaction and geometry', () {
    testWidgets('reports taps, and stays inert without a handler', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          HourCell(
            hour: 9,
            band: HourBand.good,
            onTap: () {
              taps++;
            },
          ),
        ),
      );

      await tester.tap(find.byType(HourCell));
      expect(taps, 1);

      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good)),
      );
      final inkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byType(HourCell),
          matching: find.byType(InkWell),
        ),
      );
      // A null callback also removes the ink response, so a non-interactive
      // cell does not splash on touch.
      expect(inkWell.onTap, isNull);
    });

    testWidgets('fills exactly one grid column', (tester) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good)),
      );

      // The grid's scroll offsets and cursor position are computed from these
      // two numbers, so a cell that sizes itself freely desynchronises them.
      final size = tester.getSize(find.byType(HourCell));
      expect(size.width, GridMetrics.hourColumnWidth);
      expect(size.height, GridMetrics.rowHeight);
    });
  });
}

/// The tree an `HourCell` needs above it: a palette to read tokens from and
/// the localized scope every page of the app renders inside.
Widget _host(Widget subject, {ThemeData? theme}) {
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.light(),
      home: Scaffold(body: Center(child: subject)),
    ),
  );
}

/// The cell's two stacked box decorations: the band fill, then the selection
/// wash drawn over it.
List<BoxDecoration> _decorationsOf(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(HourCell),
      matching: find.byType(DecoratedBox),
    ),
  );
  return boxes
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .toList();
}

TextStyle _labelStyle(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;

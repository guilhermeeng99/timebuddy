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
// the alpha, the digit size and the minute suffix are the only things telling
// a user that 09:00 is reachable and that a row does not line up with the
// column above it.

// The four weights below are read off `HourCell` rather than copied. They
// used to be local literals, and one of them (`_cursorInkBlend`) went stale
// the moment the accessibility pass retuned it — a test asserting a number
// nobody paints any more is worse than no test, because it passes.
const double _fillAlpha = HourCell.fillAlpha;
const double _selectedAlpha = HourCell.selectedAlpha;
const double _inkBlend = HourCell.inkBlend;
const double _cursorInkBlend = HourCell.cursorInkBlend;

/// The comfortable cell's digits, and the compact chip's. Still literals: they
/// are private to the widget and a size is what this file is here to assert.
const double _comfortableFontSize = 15;
const double _compactFontSize = 11;

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('band colours', () {
    testWidgets('each band paints its own token at 16 percent', (
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
      // **The same size, and that inversion is the point.** The column used to
      // be 44pt and a minute suffix was squeezed to 9pt to fit it, so the rows
      // that most need explaining — Kolkata, Kathmandu, Chatham — were the
      // hardest ones on the screen to read. A 60pt column holds `05:45` at the
      // size every other cell uses.
      expect(withMinutes, _comfortableFontSize);
      expect(_labelStyle(tester, '14').fontSize, _comfortableFontSize);
    });

    testWidgets('the compact chip keeps the small digits and the rounding', (
      tester,
    ) async {
      // The settings preview shares this widget so its 24 cells are a legend
      // for the grid's colours, but it can afford as little as 26pt each.
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good, compact: true)),
      );

      expect(_labelStyle(tester, '09').fontSize, _compactFontSize);
      expect(_decorationsOf(tester).first.borderRadius, isNotNull);
      expect(_labelStyle(tester, '09').color, AppColors.light.onBackground);
    });
  });

  group('cursor and selection', () {
    testWidgets('a plain cell has no wash, and tints its digits', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good)),
      );

      final decorations = _decorationsOf(tester);
      expect(decorations, hasLength(2));
      expect(decorations.first.border, isNull);
      expect(decorations.last.color, isNull);
      // The digits carry the band too, so a row read out of the corner of the
      // eye still says which band it is in. Lerped toward the foreground
      // rather than hardcoded, which is what keeps it legible on the light
      // palettes as well as the dark ones.
      expect(
        _labelStyle(tester, '09').color,
        Color.lerp(
          AppColors.light.hourGood,
          AppColors.light.onBackground,
          _inkBlend,
        ),
      );
      expect(_labelStyle(tester, '09').fontWeight, FontWeight.w500);
    });

    testWidgets('the cursor is a wash, not a ring', (tester) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good, isCursor: true)),
      );

      final decorations = _decorationsOf(tester);
      // It used to draw a 2pt border around the cell. A ring is a fifth box on
      // a screen that already has eighty; a filled column reads as "here" from
      // across the row and costs no extra edge.
      expect(decorations.first.border, isNull);
      expect(
        decorations.first.color,
        AppColors.light.primary.withValues(alpha: _selectedAlpha),
      );
      expect(
        _labelStyle(tester, '09').color,
        Color.lerp(
          AppColors.light.primary,
          AppColors.light.onBackground,
          _cursorInkBlend,
        ),
      );
      expect(_labelStyle(tester, '09').fontWeight, FontWeight.w700);
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
      expect(
        _labelStyle(tester, '09').color,
        Color.lerp(
          AppColors.light.primary,
          AppColors.light.onBackground,
          _cursorInkBlend,
        ),
      );
    });
  });

  group('interaction and geometry', () {
    testWidgets('is a read surface, with no tap target of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const HourCell(hour: 9, band: HourBand.good)),
      );

      // The cursor is set from the ruler (docs/specs/time_grid.md rule 8), so
      // the cell answers no gesture at all — which is what leaves every pixel
      // of the track free for the pan in rule 16. Asserted as the absence of
      // an `InkWell` rather than as a null callback: a splash that leads
      // nowhere is the defect, and a disabled `InkWell` still renders one on
      // some platforms.
      expect(
        find.descendant(
          of: find.byType(HourCell),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
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

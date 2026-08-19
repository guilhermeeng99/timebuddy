import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/timebuddy_pill_toggle.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// A segmented control earns its place by keeping both alternatives visible,
// which only works if the selected one is unmistakable and the other one is
// still tappable. Those two facts, plus "a disabled control changes nothing",
// are the whole contract, and all three are silent when they break: a toggle
// that renders identically for both states still looks like a toggle.
//
// The labels come from the generated translations, because the toggle takes
// finished copy and never formats anything itself.

/// How far a disabled toggle is dimmed.
const double _disabledOpacity = 0.5;

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('fills the selected option and leaves the other plain', (
    tester,
  ) async {
    final selectedLabel = t.settings.hourFormat24;
    final otherLabel = t.settings.hourFormat12;

    await tester.pumpWidget(
      _host(_toggle(selected: ClockFormat.h24, onChanged: (_) {})),
    );

    expect(find.text(selectedLabel), findsOneWidget);
    expect(find.text(otherLabel), findsOneWidget);
    expect(_opacityOf(tester), 1);

    final selectedFill = _segmentDecoration(tester, selectedLabel).color;
    final otherFill = _segmentDecoration(tester, otherLabel).color;
    expect(selectedFill, AppColors.light.primary);
    expect(otherFill, isNull);

    // The fill alone is not enough: the label has to flip to the foreground
    // computed for that fill, or a light palette renders it unreadable.
    final selectedStyle = _labelStyle(tester, selectedLabel);
    expect(selectedStyle.color, AppColors.light.onPrimary);
    expect(selectedStyle.fontWeight, FontWeight.w600);

    final otherStyle = _labelStyle(tester, otherLabel);
    expect(otherStyle.color, AppColors.light.onBackgroundLight);
    expect(otherStyle.fontWeight, FontWeight.w500);
  });

  testWidgets('reports the value of the option that was tapped', (
    tester,
  ) async {
    final changes = <ClockFormat>[];

    await tester.pumpWidget(
      _host(_toggle(selected: ClockFormat.h24, onChanged: changes.add)),
    );
    await tester.tap(find.text(t.settings.hourFormat12));
    await tester.pump();

    expect(changes, [ClockFormat.h12]);
  });

  testWidgets('stays silent when the selected option is tapped again', (
    tester,
  ) async {
    final changes = <ClockFormat>[];

    await tester.pumpWidget(
      _host(_toggle(selected: ClockFormat.h24, onChanged: changes.add)),
    );
    await tester.tap(find.text(t.settings.hourFormat24));
    await tester.pump();

    expect(changes, isEmpty);
    // No callback also means no ink response, so the active segment does not
    // splash as though something had happened.
    expect(_segmentInkWell(tester, t.settings.hourFormat24).onTap, isNull);
  });

  testWidgets('a disabled toggle dims itself and ignores taps', (
    tester,
  ) async {
    final changes = <ClockFormat>[];

    await tester.pumpWidget(
      _host(
        _toggle(
          selected: ClockFormat.h24,
          onChanged: changes.add,
          disabled: true,
        ),
      ),
    );
    await tester.tap(find.text(t.settings.hourFormat12));
    await tester.pump();

    expect(changes, isEmpty);
    expect(_opacityOf(tester), _disabledOpacity);
    expect(_segmentInkWell(tester, t.settings.hourFormat12).onTap, isNull);
  });
}

/// The 12h / 24h choice, the toggle's first real use.
List<PillOption<ClockFormat>> _options() => [
  PillOption(value: ClockFormat.h24, label: t.settings.hourFormat24),
  PillOption(value: ClockFormat.h12, label: t.settings.hourFormat12),
];

TimeBuddyPillToggle<ClockFormat> _toggle({
  required ClockFormat selected,
  required ValueChanged<ClockFormat> onChanged,
  bool disabled = false,
}) {
  return TimeBuddyPillToggle<ClockFormat>(
    options: _options(),
    selected: selected,
    onChanged: onChanged,
    disabled: disabled,
  );
}

/// The tree a `TimeBuddyPillToggle` needs above it, plus the bounded width it
/// would otherwise not get from a `Center`.
Widget _host(Widget subject) {
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, child: subject)),
      ),
    ),
  );
}

/// The decoration of the segment carrying [label].
BoxDecoration _segmentDecoration(WidgetTester tester, String label) {
  final segment = find
      .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
      .first;
  return tester.widget<DecoratedBox>(segment).decoration as BoxDecoration;
}

InkWell _segmentInkWell(WidgetTester tester, String label) {
  final segment = find
      .ancestor(of: find.text(label), matching: find.byType(InkWell))
      .first;
  return tester.widget<InkWell>(segment);
}

TextStyle _labelStyle(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;

double _opacityOf(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(TimeBuddyPillToggle<ClockFormat>),
    matching: find.byType(Opacity),
  );
  return tester.widget<Opacity>(finder.first).opacity;
}

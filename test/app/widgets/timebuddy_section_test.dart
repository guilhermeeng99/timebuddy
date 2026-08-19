import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/timebuddy_section.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// The section is one widget with three configurations precisely so that the
// three do not drift apart, which means the interesting assertions are about
// what each configuration *omits*: a dot, a pill or a surface that shows up
// when it was not asked for is the drift this widget exists to prevent.
//
// The labels are pulled from the generated translations rather than typed as
// English literals, so a copy change moves the expectation with it and the
// uppercasing is asserted against the real string the app renders.

/// The count pill's tint over the accent.
const double _pillTintAlpha = 0.12;

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('renders the label uppercased and the body under it', (
    tester,
  ) async {
    final label = t.settings.groupAppearance;
    final body = t.settings.showSeconds;

    await tester.pumpWidget(
      _host(TimeBuddySection(label: label, child: Text(body))),
    );

    // Passed in sentence case, rendered in caps: the caller must not have to
    // shout at the section to get a header that matches every other one.
    expect(find.text(label.toUpperCase()), findsOneWidget);
    expect(find.text(label), findsNothing);
    expect(find.text(body), findsOneWidget);

    final style = tester.widget<Text>(find.text(label.toUpperCase())).style!;
    expect(style.color, AppColors.light.onBackgroundLight);
    expect(style.fontWeight, FontWeight.w600);
  });

  testWidgets('draws the accent dot only when one is asked for', (
    tester,
  ) async {
    final label = t.settings.groupTime;

    await tester.pumpWidget(
      _host(TimeBuddySection(label: label, child: const SizedBox.shrink())),
    );
    expect(_inSection(_isAccentDot), findsNothing);

    await tester.pumpWidget(
      _host(
        TimeBuddySection(
          label: label,
          dot: true,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(_inSection(_isAccentDot), findsOneWidget);
  });

  testWidgets('shows the count pill only when a count is given', (
    tester,
  ) async {
    final label = t.settings.groupTime;

    await tester.pumpWidget(
      _host(TimeBuddySection(label: label, child: const SizedBox.shrink())),
    );
    expect(find.text('3'), findsNothing);

    await tester.pumpWidget(
      _host(
        TimeBuddySection(
          label: label,
          count: 3,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);

    // Tinted rather than filled, so the pill reads as a quantity instead of a
    // second call to action next to the header.
    final pillSurface = find
        .ancestor(of: find.text('3'), matching: find.byType(DecoratedBox))
        .first;
    final pill = tester.widget<DecoratedBox>(pillSurface);
    expect(
      (pill.decoration as BoxDecoration).color,
      AppColors.light.primary.withValues(alpha: _pillTintAlpha),
    );
  });

  testWidgets('places a trailing widget only when given one', (tester) async {
    final label = t.settings.groupAccount;
    final action = t.common.save;

    await tester.pumpWidget(
      _host(TimeBuddySection(label: label, child: const SizedBox.shrink())),
    );
    expect(find.byType(TextButton), findsNothing);

    await tester.pumpWidget(
      _host(
        TimeBuddySection(
          label: label,
          trailing: TextButton(onPressed: () {}, child: Text(action)),
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.text(action), findsOneWidget);
  });

  testWidgets('card false drops the surface and keeps the header', (
    tester,
  ) async {
    final label = t.settings.groupWorkingHours;
    final body = t.settings.workingHoursPreview;

    await tester.pumpWidget(
      _host(TimeBuddySection(label: label, child: Text(body))),
    );
    expect(_inSection(_isSurfaceCard), findsOneWidget);

    await tester.pumpWidget(
      _host(
        TimeBuddySection(label: label, card: false, child: Text(body)),
      ),
    );

    // A body that is already a list of cards must not sit on a second
    // surface, but it still needs its header.
    expect(_inSection(_isSurfaceCard), findsNothing);
    expect(find.text(label.toUpperCase()), findsOneWidget);
    expect(find.text(body), findsOneWidget);
  });
}

/// The tree a `TimeBuddySection` needs above it: a palette to read tokens
/// from and the localized scope every page of the app renders inside.
Widget _host(Widget subject) {
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: subject)),
    ),
  );
}

Finder _inSection(WidgetPredicate predicate) => find.descendant(
  of: find.byType(TimeBuddySection),
  matching: find.byWidgetPredicate(predicate),
);

bool _isAccentDot(Widget widget) {
  if (widget is! Container) return false;
  final decoration = widget.decoration;
  if (decoration is! BoxDecoration) return false;
  return decoration.shape == BoxShape.circle &&
      decoration.color == AppColors.light.primary;
}

/// The section card, matched as a [Material] on purpose.
///
/// A plain coloured box would look identical and still be wrong: ListTile and
/// InkWell paint their ink on the nearest Material ancestor, so a card that is
/// not one swallows every ripple inside it. Flutter asserts on that, and this
/// predicate is what keeps the card from regressing back to a DecoratedBox.
bool _isSurfaceCard(Widget widget) {
  return widget is Material && widget.color == AppColors.light.surface;
}

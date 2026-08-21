import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/timebuddy_date_pill.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// Milestone 5's accessibility pass, for everything a contrast ratio cannot
// measure: whether a control has a name, and whether a colour is the only
// thing carrying a fact.
//
// Every case below is a defect this pass found, not a property someone thought
// worth asserting afterwards. Two of them — the date pill's chevrons and the
// app bar's back button — shipped for four milestones as buttons a screen
// reader announced as "button", and one of those had the parameters for a
// label already declared with **no caller passing them**, which is exactly the
// failure a test catches and a review does not.

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  /// A minimal host: the theme, and nothing that would pull in the router or
  /// the service locator. Every widget under test here is a leaf of the design
  /// system.
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );

  /// Everything the semantics tree actually publishes, flattened.
  ///
  /// Walked rather than inferred from the widgets' arguments, because the two
  /// are different things: a `Tooltip` publishes its message as
  /// `SemanticsData.tooltip` and not as a label, which is exactly the
  /// distinction that made `find.bySemanticsLabel` miss two named buttons
  /// while a screen reader would have read both.
  List<SemanticsData> semanticsIn(WidgetTester tester) {
    final collected = <SemanticsData>[];
    void visit(SemanticsNode node) {
      collected.add(node.getSemanticsData());
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    // The root pipeline owner owns no semantics itself — the one attached
    // to the view does — so the tree is reached through its children
    // rather than through the deprecated `binding.pipelineOwner`.
    tester.binding.rootPipelineOwner.visitChildren((child) {
      final root = child.semanticsOwner?.rootSemanticsNode;
      if (root != null) visit(root);
    });
    expect(collected, isNotEmpty, reason: 'no semantics tree was built');
    return collected;
  }

  /// Whether anything on screen announces itself as [name], by label or by
  /// tooltip — the two fields a screen reader reads as a control's name.
  bool isAnnounced(WidgetTester tester, String name) => semanticsIn(
    tester,
  ).any((data) => data.label == name || data.tooltip == name);

  group('an hour cell says which band it is in', () {
    // The band is drawn as a 16% wash and a tinted digit — colour, and nothing
    // else. A user reading the grid by voice heard twenty bare numbers and no
    // answer to the one question the screen exists to answer.
    for (final band in HourBand.values) {
      testWidgets('${band.name} is named, not just coloured', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(host(HourCell(hour: 9, band: band)));

        expect(
          find.bySemanticsLabel(
            t.common.hourInBand(hour: '09', band: HourCell.bandLabel(band)),
          ),
          findsOneWidget,
        );
        handle.dispose();
      });
    }

    testWidgets('the four bands are four different words', (tester) async {
      final named = HourBand.values.map(HourCell.bandLabel).toSet();
      expect(
        named,
        hasLength(HourBand.values.length),
        reason: 'two bands announce identically, so the label carries nothing',
      );
    });

    testWidgets('a half-hour zone announces its minutes', (tester) async {
      // The same rule the digits follow (time_grid.md rule 5): a row that does
      // not line up with the column must not claim it does, by voice either.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(const HourCell(hour: 18, band: HourBand.poor, minute: 30)),
      );

      expect(
        find.bySemanticsLabel(
          t.common.hourInBand(
            hour: '18:30',
            band: HourCell.bandLabel(HourBand.poor),
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a caller can replace the label wholesale', (tester) async {
      // `GridRowView` does, because the day boundary and the DST dot are drawn
      // over the cell and only the caller can see them.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const HourCell(
            hour: 0,
            band: HourBand.night,
            semanticLabel: '00, Night, Sat 22',
          ),
        ),
      );

      expect(find.bySemanticsLabel('00, Night, Sat 22'), findsOneWidget);
      // And it replaces rather than adds: the digits underneath must not
      // announce a second time.
      final announcing = semanticsIn(
        tester,
      ).where((data) => data.label.contains('Night'));
      expect(announcing, hasLength(1));
      handle.dispose();
    });
  });

  group('every icon-only control has a name', () {
    testWidgets('the date pill names both of its chevrons', (tester) async {
      // These took their tooltips as optional parameters and no caller ever
      // passed one, so both shipped unnamed — in a mirrored pair, where an
      // unnamed control is worse than usual: the user cannot tell which way
      // either one goes.
      final handle = tester.ensureSemantics();
      final today = DateTime(2026, 8, 21);
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 400,
            child: TimeBuddyDatePill(
              value: today,
              today: today,
              todayLabel: t.grid.today,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(isAnnounced(tester, t.common.previousDay), isTrue);
      expect(isAnnounced(tester, t.common.nextDay), isTrue);
      expect(
        t.common.previousDay,
        isNot(t.common.nextDay),
        reason: 'a mirrored pair needs two names, not one',
      );
      handle.dispose();
    });

    testWidgets('the app bar names its back chevron', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Navigator(
            onGenerateInitialRoutes: (navigator, _) => [
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('under')),
              ),
              // Pushed, so the bar has something to pop and draws the chevron.
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  appBar: TimeBuddyLargeAppBar(title: 'Profile'),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(isAnnounced(tester, t.common.back), isTrue);
      handle.dispose();
    });
  });

  testWidgets('a loading placeholder announces itself', (tester) async {
    // A shimmer is a purely visual placeholder: before this it published no
    // semantics at all, so a page that was still loading and a page that was
    // empty sounded exactly alike.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const LoadingShimmer(rowCount: 2)));

    expect(find.bySemanticsLabel(t.common.loading), findsOneWidget);
    handle.dispose();
    // The shimmer animates forever; let the controller wind down so the test
    // does not fail on a pending timer.
    await tester.pumpWidget(host(const SizedBox.shrink()));
  });
}

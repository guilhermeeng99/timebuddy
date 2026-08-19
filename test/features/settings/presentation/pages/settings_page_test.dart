import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/app/widgets/timebuddy_pill_toggle.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/settings/presentation/pages/settings_page.dart';
import 'package:timebuddy/features/settings/presentation/widgets/working_hours_preview.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

import '../../../../harness/factories/preferences_factory.dart';
import '../../../../harness/helpers.dart';
import '../../../../harness/pump_app.dart';

/// A viewport tall enough to build the whole page.
///
/// The settings body is a `ListView`, so at the default 800x600 the later
/// groups are never created at all, and an assertion about the About group
/// would fail on a widget that does not exist yet rather than on one that is
/// wrong. Every group has to be on screen for "renders every group" to mean
/// anything.
const Size _tallSurface = Size(900, 2400);

/// The catalog label of `LightPalette.forestSage`.
///
/// Written out rather than read back from `LightPalettes.all`: the assertion
/// is that the row shows the product name the catalog holds, and comparing
/// the catalog against itself would pass on any name at all.
const String _seededLightLabel = 'Forest Sage';

/// The catalog label of `DarkPalette.roseNoir`.
const String _seededDarkLabel = 'Rose Noir';

/// The catalog label of `LightPalette.amberWarm`, the palette picked in the
/// sheet, which is neither the seeded one nor the catalog's first entry.
const String _pickedLightLabel = 'Amber Warm';

/// How many palettes each brightness catalog offers (CLAUDE.md, Theme).
const int _palettesPerBrightness = 10;

void main() {
  setUpAll(() {
    initTestTimeZones();
    registerCommonFallbacks();
  });

  // Non-default palettes, so a row that rendered the catalog's first entry by
  // accident cannot pass for a row that read the document.
  final seeded = aPreferences(
    lightPalette: LightPalette.forestSage,
    darkPalette: DarkPalette.roseNoir,
  );

  Future<PumpedApp> pumpSettings(WidgetTester tester) => pumpApp(
    tester,
    const SettingsPage(),
    preferences: seeded,
    surfaceSize: _tallSurface,
  );

  // The bands the preview strip is currently painting, in hour order.
  List<HourBand> bandsOf(WidgetTester tester) => tester
      .widgetList<HourCell>(
        find.descendant(
          of: find.byType(WorkingHoursPreview),
          matching: find.byType(HourCell),
        ),
      )
      .map((cell) => cell.band)
      .toList();

  testWidgets('renders every group the spec lists, with its controls', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text(t.settings.title), findsOneWidget);

    // TimeBuddySection uppercases whatever header it is handed.
    for (final group in <String>[
      t.settings.groupAppearance,
      t.settings.groupTime,
      t.settings.groupWorkingHours,
      t.settings.groupLanguage,
      t.settings.groupAbout,
    ]) {
      expect(find.text(group.toUpperCase()), findsOneWidget, reason: group);
    }

    // One control per group, so a header sitting above an empty card fails.
    expect(find.byType(TimeBuddyPillToggle<ThemeMode>), findsOneWidget);
    expect(find.byType(TimeBuddyPillToggle<ClockFormat>), findsOneWidget);
    expect(find.byType(TimeBuddyPillToggle<WeekStart>), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(find.byType(WorkingHoursPreview), findsOneWidget);
    expect(find.text(t.settings.languageSystem), findsOneWidget);
    expect(find.text(t.settings.languagePortuguese), findsOneWidget);
    expect(find.text(t.settings.languageEnglish), findsOneWidget);
    expect(find.text(t.settings.licenses), findsOneWidget);
  });

  testWidgets('omits the Account group while there is no auth', (
    tester,
  ) async {
    await pumpSettings(tester);

    // preferences.md, Settings page: the copy keys exist, the group does not.
    // A "not signed in" row with a dead sign-out button would promise a
    // feature this build cannot deliver.
    expect(find.text(t.settings.groupAccount.toUpperCase()), findsNothing);
    expect(find.text(t.settings.notSignedIn), findsNothing);
    expect(find.text(t.settings.signOut), findsNothing);
    expect(find.text(t.settings.deleteAccount), findsNothing);
  });

  testWidgets('the theme toggle writes through to PreferencesCubit', (
    tester,
  ) async {
    final app = await pumpSettings(tester);

    await tester.tap(find.text(t.settings.themeLight));
    await tester.pumpAndSettle();

    // There is no save button (preferences.md rule 6): the tap itself is the
    // write, and it lands in the cubit, in the repository and on the pill.
    final state = app.cubit.state as PreferencesReady;
    expect(state.preferences.themeMode, ThemeMode.light);
    expect(state.preferences.revision, seeded.revision + 1);

    final captured = verify(() => app.repository.save(captureAny())).captured;
    expect(captured, hasLength(1));
    final saved = captured.single as PreferencesEntity;
    expect(saved.themeMode, ThemeMode.light);
    expect(saved.revision, seeded.revision + 1);

    final toggle = tester.widget<TimeBuddyPillToggle<ThemeMode>>(
      find.byType(TimeBuddyPillToggle<ThemeMode>),
    );
    expect(toggle.selected, ThemeMode.light);
  });

  testWidgets('switching to 12h relabels what the page shows', (tester) async {
    await pumpSettings(tester);

    final summary24 = t.settings.workingHoursSummary(
      start: '09:00',
      end: '17:00',
    );
    final summary12 = t.settings.workingHoursSummary(
      start: '9:00 AM',
      end: '5:00 PM',
    );

    expect(find.text(summary24), findsOneWidget);
    expect(find.text(summary12), findsNothing);

    await tester.tap(find.text(t.settings.hourFormat12));
    await tester.pumpAndSettle();

    // The same window, spelled the way the user just asked for it.
    expect(find.text(summary12), findsOneWidget);
    expect(find.text(summary24), findsNothing);
  });

  testWidgets('the preview renders 24 cells and repaints on a new window', (
    tester,
  ) async {
    final app = await pumpSettings(tester);

    // 24 hour-of-day values, always: the strip has no zone and no date, so
    // this is not the "a day can be 23 or 25 hours" case CLAUDE.md rule 7
    // forbids hardcoding.
    var bands = bandsOf(tester);
    expect(bands, hasLength(24));

    // 09:00-17:00 covers 9 through 16 (half-open), its two neighbours are
    // fair, and the hours nothing claims between 23:00 and 06:59 are night.
    expect(bands[12], HourBand.good);
    expect(bands[8], HourBand.fair);
    expect(bands[17], HourBand.fair);
    expect(bands[23], HourBand.night);
    expect(bands.where((band) => band == HourBand.good), hasLength(8));
    expect(bands.where((band) => band == HourBand.night), hasLength(8));

    await app.cubit.setWorkingHours(
      const WorkingHours(startHour: 22, endHour: 6),
    );
    await tester.pumpAndSettle();

    // A night shift wraps past midnight (preferences.md rule 4): the small
    // hours turn good, the middle of the day turns off-hours, and no hour is
    // left for the night band at all.
    bands = bandsOf(tester);
    expect(bands, hasLength(24));
    expect(bands[23], HourBand.good);
    expect(bands[0], HourBand.good);
    expect(bands[12], HourBand.poor);
    expect(bands[21], HourBand.fair);
    expect(bands.where((band) => band == HourBand.good), hasLength(8));
    expect(bands.where((band) => band == HourBand.night), isEmpty);
  });

  testWidgets('the palette rows show the catalog label of each palette', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text(t.settings.lightPalette), findsOneWidget);
    expect(find.text(t.settings.darkPalette), findsOneWidget);
    // Product names from the catalog, never through slang: a palette name is
    // the same in every language (preferences.md, Settings page).
    expect(find.text(_seededLightLabel), findsOneWidget);
    expect(find.text(_seededDarkLabel), findsOneWidget);
  });

  testWidgets('the light palette picker lists the ten light palettes', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text(t.settings.lightPalette));
    await tester.pumpAndSettle();

    // Scoped to the sheet: it is modal but not opaque, so the page behind it
    // is still in the tree and still showing the selected palette's label.
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(LightPalettes.all, hasLength(_palettesPerBrightness));

    for (final option in LightPalettes.all) {
      final row = await _revealInSheet(tester, option.label);
      expect(row, findsOneWidget, reason: option.label);
      // Stronger than counting InkWells: every row must itself be tappable,
      // so a palette rendered as dead decoration fails here.
      expect(
        find.ancestor(of: row, matching: find.byType(InkWell)),
        findsOneWidget,
        reason: '${option.label} must be tappable',
      );
    }
    // The relevant brightness only: no dark palette leaks into this sheet.
    for (final option in DarkPalettes.all) {
      expect(
        find.descendant(of: sheet, matching: find.text(option.label)),
        findsNothing,
        reason: option.label,
      );
    }

    // A check mark on the current palette, and only there. Revealed first
    // because the seeded palette can sit below the fold after the sweep above.
    await _revealInSheet(tester, _seededLightLabel);
    expect(
      find.descendant(of: sheet, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
  });

  testWidgets('the dark palette picker lists the ten dark palettes', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text(t.settings.darkPalette));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(DarkPalettes.all, hasLength(_palettesPerBrightness));

    for (final option in DarkPalettes.all) {
      final row = await _revealInSheet(tester, option.label);
      expect(row, findsOneWidget, reason: option.label);
      expect(
        find.ancestor(of: row, matching: find.byType(InkWell)),
        findsOneWidget,
        reason: '${option.label} must be tappable',
      );
    }
    for (final option in LightPalettes.all) {
      expect(
        find.descendant(of: sheet, matching: find.text(option.label)),
        findsNothing,
        reason: option.label,
      );
    }
  });

  testWidgets('picking a palette writes it through and relabels the row', (
    tester,
  ) async {
    final app = await pumpSettings(tester);

    await tester.tap(find.text(t.settings.lightPalette));
    await tester.pumpAndSettle();

    // Tap the row, not the label: scrollUntilVisible can leave the text
    // flush against the sheet edge, where the tap point gets clamped onto a
    // neighbour. The InkWell spans the full row, so its centre is safe.
    final picked = await _revealInSheet(tester, _pickedLightLabel);
    await tester.ensureVisible(picked);
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: picked, matching: find.byType(InkWell)));
    await tester.pumpAndSettle();

    final state = app.cubit.state as PreferencesReady;
    expect(state.preferences.lightPalette, LightPalette.amberWarm);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text(_pickedLightLabel), findsOneWidget);
    expect(find.text(_seededLightLabel), findsNothing);
  });
}

/// Brings one picker row into view and returns a finder for its label.
///
/// The sheet's list is lazy, so the tenth palette is not built until something
/// scrolls to it. Scrolling is also exactly what a user does to reach it, so
/// asserting after a scroll stays honest instead of relaxing the expectation
/// to "some rows exist".
Future<Finder> _revealInSheet(WidgetTester tester, String label) async {
  final sheet = find.byType(BottomSheet);
  final target = find.descendant(of: sheet, matching: find.text(label));
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
  );
  return target;
}

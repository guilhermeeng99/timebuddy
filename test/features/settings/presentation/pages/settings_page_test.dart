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

/// A phone, below `ResponsiveLayout.mobileBreakpoint`.
const Size _phoneSurface = Size(400, 900);

/// `TimeBuddySettingsRow._controlMaxWidth`, written out because it is private.
/// The number is the assertion: a control that grew past it would be the
/// defect this layout exists to avoid.
const double _controlMaxWidth = 420;

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

    // TimeBuddySection uppercases whatever header it is handed. Account is
    // no longer among them: the identity card at the top of the page took its
    // place, and a hero block plus a row two thirds down were two places
    // answering one question.
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
    // Language is a fourth pill now, not three checked rows. `String?`
    // because "follow the device" is the null tag, a value like any other
    // (preferences.md rule 3).
    expect(find.byType(TimeBuddyPillToggle<String?>), findsOneWidget);
    // A bare `Switch` in a row's trailing slot, not a `SwitchListTile`: the
    // row already owns the icon disc and the title, so the tile's own layout
    // would be a second one nested inside it. It carries no hint line —
    // what the switch does to the ticker rate is preferences.md rule 10's to
    // record, not the row's.
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(find.byType(WorkingHoursPreview), findsOneWidget);
    // Appearance is one row now: the theme toggle, with no palette pickers
    // under it.
    expect(find.text(t.settings.lightPalette), findsNothing);
    expect(find.text(t.settings.darkPalette), findsNothing);
    // About states two facts and offers nothing to tap; the licenses link is
    // gone with them.
    expect(find.text(t.settings.licenses), findsNothing);
    expect(find.text(t.settings.appVersion), findsOneWidget);
    // Scoped to the language pill: `languageSystem` and `themeSystem` are
    // both "System" in English, and an unscoped finder would count the theme
    // toggle's segment as this one.
    final languagePill = find.byType(TimeBuddyPillToggle<String?>);
    for (final label in <String>[
      t.settings.languageSystem,
      t.settings.languagePortuguese,
      t.settings.languageEnglish,
    ]) {
      expect(
        find.descendant(of: languagePill, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets('leads with an identity card, which reads as an offer while '
      'signed out', (tester) async {
    await pumpSettings(tester);

    // guest_mode.md rule 10, now as the page's hero rather than as a row two
    // thirds down. This assertion has been inverted twice: it began as "the
    // Account group is absent", became "the Account row is present", and is
    // now the card that replaced the row. What survived every rewrite is the
    // real requirement — a guest can see they are a guest, and can get from
    // here to the offer.
    expect(find.text(t.settings.notSignedIn), findsOneWidget);
    expect(find.text(t.auth.guestBody), findsOneWidget);

    // Still not here, and deliberately: signing in and out lives on the
    // profile page, and a second copy of either would be a second owner of
    // the session.
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

  testWidgets('the language pill writes through to PreferencesCubit', (
    tester,
  ) async {
    final app = await pumpSettings(tester);

    // Scoped for the same reason the presence check is: two pills on this
    // page can carry the word "System".
    await tester.tap(
      find.descendant(
        of: find.byType(TimeBuddyPillToggle<String?>),
        matching: find.text(t.settings.languageEnglish),
      ),
    );
    await tester.pumpAndSettle();

    final state = app.cubit.state as PreferencesReady;
    expect(state.preferences.localeTag, 'en');
    expect(state.preferences.revision, seeded.revision + 1);

    final captured = verify(() => app.repository.save(captureAny())).captured;
    expect(captured, hasLength(1));
    expect((captured.single as PreferencesEntity).localeTag, 'en');

    final pill = tester.widget<TimeBuddyPillToggle<String?>>(
      find.byType(TimeBuddyPillToggle<String?>),
    );
    expect(pill.selected, 'en');
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

  // The four palette tests that used to sit here are gone with the rows
  // they covered: Appearance is one theme toggle now, and the light/dark
  // palette pickers were removed from the page. `AppColors` still carries
  // both catalogs and `palette_picker_sheet.dart` still exists — nothing
  // on this screen opens them.

  testWidgets('a control sits beside its title on a wide window and under it '
      'on a phone', (tester) async {
    await pumpSettings(tester);

    // Above the breakpoint the toggle is capped and right-aligned: the eye is
    // already tracking values down that edge, and an uncapped one would be a
    // row of enormous buttons across a 1300pt window.
    final wideToggle = tester.getRect(
      find.byType(TimeBuddyPillToggle<ThemeMode>),
    );
    final wideTitle = tester.getRect(find.text(t.settings.themeMode));
    expect(wideToggle.left, greaterThan(wideTitle.right));
    expect(wideToggle.width, lessThanOrEqualTo(_controlMaxWidth));

    await tester.binding.setSurfaceSize(_phoneSurface);
    tester.view.physicalSize = _phoneSurface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();

    // Below it there is no room for two columns, so the control stacks and
    // fills the row instead.
    final phoneToggle = tester.getRect(
      find.byType(TimeBuddyPillToggle<ThemeMode>),
    );
    final phoneTitle = tester.getRect(find.text(t.settings.themeMode));
    expect(phoneToggle.top, greaterThan(phoneTitle.bottom));
  });
}

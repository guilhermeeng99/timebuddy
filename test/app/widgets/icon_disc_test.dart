import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/feature_empty_state.dart';
import 'package:timebuddy/app/widgets/icon_disc.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// This widget replaced four hand-kept copies of the same disc, two of which
// carried a comment promising they matched the others. The assertions below
// are therefore about the promise rather than about the pixels: one colour
// token drives both the wash and the glyph, and the two blocks that used to
// copy the proportions now read them from the same defaults.

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('washes the disc with the same token it inks the glyph with', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        IconDisc(
          icon: FontAwesomeIcons.earthAmericas,
          color: AppColors.light.primary,
        ),
      ),
    );

    final disc = tester.widget<Container>(
      find.descendant(
        of: find.byType(IconDisc),
        matching: find.byType(Container),
      ),
    );
    final decoration = disc.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(
      decoration.color,
      AppColors.light.primary.withValues(alpha: AppAlpha.tint),
    );

    // Full strength on the glyph: one parameter, so a caller cannot pick the
    // disc from one token and the icon from another.
    final glyph = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(glyph.color, AppColors.light.primary);
    expect(glyph.icon, FontAwesomeIcons.earthAmericas);
  });

  testWidgets('defaults to the 72/32 block mark and takes an override', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        IconDisc(
          icon: FontAwesomeIcons.earthAmericas,
          color: AppColors.light.error,
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(IconDisc)),
      const Size(IconDisc.defaultDiameter, IconDisc.defaultDiameter),
    );
    expect(
      tester.widget<AppIcon>(find.byType(AppIcon)).size,
      IconDisc.defaultIconSize,
    );

    // Onboarding's larger mark and the splash's 34pt glyph both survive the
    // consolidation as arguments; flattening them would have repainted two
    // screens this refactor promised not to touch.
    await tester.pumpWidget(
      _host(
        IconDisc(
          icon: FontAwesomeIcons.earthAmericas,
          color: AppColors.light.primary,
          diameter: 96,
          iconSize: 44,
        ),
      ),
    );
    expect(tester.getSize(find.byType(IconDisc)), const Size(96, 96));
    expect(tester.widget<AppIcon>(find.byType(AppIcon)).size, 44);
  });

  testWidgets('is the disc ErrorView and FeatureEmptyState draw', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ErrorView(failure: const ServerFailure('offline'), onRetry: () {}),
      ),
    );
    // Red, because something did break.
    expect(_discColorOf(tester), AppColors.light.error);

    await tester.pumpWidget(
      _host(
        FeatureEmptyState(
          icon: FontAwesomeIcons.earthAmericas,
          title: t.grid.emptyTitle,
          message: t.grid.emptyMessage,
        ),
      ),
    );
    // The accent, because nothing did: an empty board is an invitation, and
    // error red on a first run says the app is broken.
    expect(_discColorOf(tester), AppColors.light.primary);
  });
}

Color _discColorOf(WidgetTester tester) =>
    tester.widget<IconDisc>(find.byType(IconDisc)).color;

/// The tree an [IconDisc] needs above it: a palette to read tokens from and
/// the localized scope every page of the app renders inside.
Widget _host(Widget subject) {
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: subject)),
    ),
  );
}

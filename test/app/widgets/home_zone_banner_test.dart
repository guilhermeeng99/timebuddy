import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/widgets/home_zone_banner.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

// The grid and the world clock each carried their own copy of this banner,
// identical down to the comment, and the padding was the whole of what
// differed. So the assertions are about exactly that: one set of words, one
// warning tint, and the one thing a caller is still allowed to choose.

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('renders the warning in the words both pages shared', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const HomeZoneBanner()));

    expect(find.text(t.grid.homeZoneBrokenBanner), findsOneWidget);
  });

  testWidgets('washes itself in the warning token, not the error one', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const HomeZoneBanner()));

    // A Material rather than a coloured box, and a wash rather than a fill:
    // nothing is broken, a home city is simply unset.
    final surface = tester.widget<Material>(_surface);
    expect(
      surface.color,
      AppColors.light.warning.withValues(alpha: AppAlpha.tint),
    );
  });

  testWidgets('takes its padding from the caller and nothing else', (
    tester,
  ) async {
    // Nothing by default: a caller that says nothing gets a banner flush with
    // whatever it was dropped into.
    await tester.pumpWidget(_host(const HomeZoneBanner()));
    expect(tester.getRect(_surface), tester.getRect(_banner));

    // The grid gutters the banner into a page that has none; the world clock
    // only needs a gap under it inside an already-padded list. Both are the
    // same widget, so the difference has to be visible here and nowhere else.
    await tester.pumpWidget(
      _host(
        const HomeZoneBanner(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
        ),
      ),
    );
    final outer = tester.getRect(_banner);
    final inner = tester.getRect(_surface);

    expect(inner.left - outer.left, AppSpacing.lg);
    expect(outer.right - inner.right, AppSpacing.lg);
    expect(inner.top - outer.top, AppSpacing.sm);
    expect(outer.bottom - inner.bottom, 0);
  });
}

final Finder _banner = find.byType(HomeZoneBanner);

/// The tinted surface itself, which is what [HomeZoneBanner.padding] moves.
final Finder _surface = find.descendant(
  of: _banner,
  matching: find.byType(Material),
);

/// The tree a [HomeZoneBanner] needs above it: a palette to read tokens from,
/// the localized scope, and a bounded width, because the banner's text is
/// `Expanded` and has nothing to measure against inside a `Center`.
Widget _host(Widget subject) {
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, child: subject)),
      ),
    ),
  );
}

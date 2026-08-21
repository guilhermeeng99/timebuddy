import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/app/widgets/hour_cell.dart';
import 'package:timebuddy/core/time/hour_band.dart';

// Milestone 5's "light and dark checked against all 20 palettes", written as a
// test rather than performed as a review.
//
// A palette is not reviewable by looking at it: twenty of them times a dozen
// token pairs is 240 judgements, and the failures are the ones a designer with
// good eyesight does not notice. Every pair below is a composite the app
// actually paints, reproduced here from the widget that paints it, and
// measured against the WCAG 2.1 ratio its role owes. A palette added to either
// catalog is checked the moment it is added; a token retuned is checked the
// moment it is retuned.
//
// What this file cannot check is what colour *means*: that two adjacent bands
// are distinguishable to someone with deuteranopia is a different question,
// answered in the app by never letting colour be the only carrier — every hour
// cell prints its hour, and the grid's rows carry semantic labels.

/// One catalog entry, flattened so the two catalogs walk the same loop.
typedef _Palette = ({String label, AppColorsData colors});

List<_Palette> get _allPalettes => [
  for (final option in LightPalettes.all)
    (label: 'light/${option.label}', colors: option.colors),
  for (final option in DarkPalettes.all)
    (label: 'dark/${option.label}', colors: option.colors),
];

/// Composites [fill] at [alpha] over the opaque [page], the way the framework
/// does when it paints a translucent box.
///
/// Contrast has nowhere to put an alpha, so a translucent colour must be
/// flattened before it is measured; measuring the raw token instead reports a
/// ratio for a colour nobody sees.
Color _over(Color fill, double alpha, Color page) =>
    Color.alphaBlend(fill.withValues(alpha: alpha), page);

/// Fails with the palette's name and the measured ratio, because "expected
/// true" tells whoever added the palette nothing about which one broke.
void _expectRatio(
  Color foreground,
  Color background, {
  required double atLeast,
  required String what,
  required String palette,
}) {
  final ratio = contrastRatio(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(atLeast),
    reason:
        '$palette: $what measures ${ratio.toStringAsFixed(2)}:1, '
        'below the ${atLeast.toStringAsFixed(1)}:1 it owes.',
  );
}

void main() {
  test('both catalogs ship ten palettes', () {
    // The count is load-bearing for everything below: a catalog that lost an
    // entry would make this file pass by checking less.
    expect(LightPalettes.all, hasLength(10));
    expect(DarkPalettes.all, hasLength(10));
    expect(_allPalettes, hasLength(20));
  });

  test('the shipped defaults are the catalogs first entries', () {
    // `AppColors.defaultLight` / `defaultDark` are hand-copied duplicates of
    // Indigo Cloud and Midnight Indigo — `app_colors.dart` cannot import the
    // catalogs, because the catalogs import `AppColorsData` from it. That
    // makes them the one pair of values in the theme layer with no compiler
    // holding them together, and this accessibility pass found them already
    // drifting: `onBackgroundLight` was repaired in the catalog and the
    // default kept the old value, so the fallback palette would have failed a
    // check the palette it names had passed.
    for (final pair in [
      (
        name: 'defaultLight',
        shipped: AppColors.defaultLight,
        catalog: LightPalettes.colorsFor(LightPalette.indigoCloud),
      ),
      (
        name: 'defaultDark',
        shipped: AppColors.defaultDark,
        catalog: DarkPalettes.colorsFor(DarkPalette.midnightIndigo),
      ),
    ]) {
      for (final field in <(String, Color, Color)>[
        ('primary', pair.shipped.primary, pair.catalog.primary),
        ('primaryLight', pair.shipped.primaryLight, pair.catalog.primaryLight),
        ('primaryDark', pair.shipped.primaryDark, pair.catalog.primaryDark),
        ('secondary', pair.shipped.secondary, pair.catalog.secondary),
        ('background', pair.shipped.background, pair.catalog.background),
        ('surface', pair.shipped.surface, pair.catalog.surface),
        (
          'surfaceVariant',
          pair.shipped.surfaceVariant,
          pair.catalog.surfaceVariant,
        ),
        ('onBackground', pair.shipped.onBackground, pair.catalog.onBackground),
        (
          'onBackgroundLight',
          pair.shipped.onBackgroundLight,
          pair.catalog.onBackgroundLight,
        ),
        ('hourGood', pair.shipped.hourGood, pair.catalog.hourGood),
        ('hourFair', pair.shipped.hourFair, pair.catalog.hourFair),
        ('hourPoor', pair.shipped.hourPoor, pair.catalog.hourPoor),
        ('warning', pair.shipped.warning, pair.catalog.warning),
        ('success', pair.shipped.success, pair.catalog.success),
        ('error', pair.shipped.error, pair.catalog.error),
      ]) {
        expect(
          field.$2,
          field.$3,
          reason: '${pair.name}.${field.$1} drifted from its catalog entry',
        );
      }
    }
  });

  group('body copy clears WCAG AA', () {
    for (final palette in _allPalettes) {
      test(palette.label, () {
        final colors = palette.colors;
        for (final surface in [
          (name: 'background', color: colors.background),
          (name: 'surface', color: colors.surface),
          (name: 'surfaceVariant', color: colors.surfaceVariant),
        ]) {
          _expectRatio(
            colors.onBackground,
            surface.color,
            atLeast: AppColorsData.minTextRatio,
            what: 'onBackground on ${surface.name}',
            palette: palette.label,
          );
          // Muted text is still text: captions, placeholders and the inactive
          // nav label all take this token, and a caption nobody can read is a
          // caption that is not there.
          _expectRatio(
            colors.onBackgroundLight,
            surface.color,
            atLeast: AppColorsData.minTextRatio,
            what: 'onBackgroundLight on ${surface.name}',
            palette: palette.label,
          );
        }
      });
    }
  });

  group('a filled brand control labels itself legibly', () {
    // The regression that produced this group: `foregroundOn` used to pick by
    // a luminance threshold of 0.55 and put white on fourteen of the twenty
    // primaries, as low as 1.81:1. `onPrimary` is what labels every filled
    // button, the selected bottom-bar destination and the selected rail item,
    // so those were the app's least readable pixels on most palettes.
    for (final palette in _allPalettes) {
      test(palette.label, () {
        final colors = palette.colors;
        _expectRatio(
          colors.onPrimary,
          colors.primary,
          atLeast: AppColorsData.minTextRatio,
          what: 'onPrimary on primary',
          palette: palette.label,
        );
      });
    }

    test('foregroundOn never returns the worse of its two candidates', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      for (final palette in _allPalettes) {
        for (final token in [
          palette.colors.primary,
          palette.colors.secondary,
          palette.colors.hourGood,
          palette.colors.hourFair,
          palette.colors.hourPoor,
        ]) {
          final chosen = contrastRatio(foregroundOn(token), token);
          final best = [
            contrastRatio(white, token),
            contrastRatio(black, token),
          ].reduce((a, b) => a > b ? a : b);
          expect(
            chosen,
            closeTo(best, 0.001),
            reason: '${palette.label}: foregroundOn left contrast on the table',
          );
        }
      }
    });
  });

  group('the accent is legible where it is drawn as content', () {
    for (final palette in _allPalettes) {
      test(palette.label, () {
        final colors = palette.colors;
        // `primaryInk`: the Today pill, the Tomorrow word, a count badge.
        // Measured on `background` and on `surface` because the three of them
        // sit on both, and on the accent's own 12% wash because two of them
        // sit inside one.
        for (final page in [
          (name: 'background', color: colors.background),
          (name: 'surface', color: colors.surface),
        ]) {
          _expectRatio(
            colors.primaryInk,
            page.color,
            atLeast: AppColorsData.minTextRatio,
            what: 'primaryInk on ${page.name}',
            palette: palette.label,
          );
        }
        // `primaryGlyph`: the now line, a selected row's check, the splash's
        // progress track. Nobody reads a line, so the non-text bar applies.
        _expectRatio(
          colors.primaryGlyph,
          colors.background,
          atLeast: AppColorsData.minGlyphRatio,
          what: 'primaryGlyph on background',
          palette: palette.label,
        );
        // The three status glyphs, each the only thing distinguishing one
        // banner or sync state from another.
        for (final status in [
          (name: 'warningInk', color: colors.warningInk),
          (name: 'successInk', color: colors.successInk),
          (name: 'errorInk', color: colors.errorInk),
        ]) {
          for (final page in [
            (name: 'background', color: colors.background),
            (name: 'surface', color: colors.surface),
          ]) {
            _expectRatio(
              status.color,
              page.color,
              atLeast: AppColorsData.minGlyphRatio,
              what: '${status.name} on ${page.name}',
              palette: palette.label,
            );
          }
        }
      });
    }

    test('inkFor leaves an accent that already passes alone', () {
      // The repair must be surgical. A blend applied unconditionally would
      // mute the accent on the thirteen palettes that never needed it, which
      // is a design change wearing an accessibility argument.
      var untouched = 0;
      for (final palette in _allPalettes) {
        final colors = palette.colors;
        if (contrastRatio(colors.primary, colors.background) >=
            AppColorsData.minTextRatio) {
          expect(
            colors.primaryInk,
            colors.primary,
            reason: '${palette.label}: primary was repaired without needing it',
          );
          untouched++;
        }
      }
      expect(untouched, greaterThan(10), reason: 'the repair should be rare');
    });
  });

  group('the grid says which band an hour is in', () {
    // The hour cell is the hardest surface in the app: a 15pt digit on a 16%
    // wash of its own band colour, over the page. Both halves move with the
    // palette, so this is the pair most likely to fail on a catalog nobody
    // re-measured.
    for (final palette in _allPalettes) {
      test(palette.label, () {
        final colors = palette.colors;
        for (final band in HourBand.values) {
          final token = hourBandColor(band, colors);
          final fill = _over(token, HourCell.fillAlpha, colors.background);
          final ink = Color.lerp(
            token,
            colors.onBackground,
            HourCell.inkBlend,
          )!;
          _expectRatio(
            ink,
            fill,
            atLeast: AppColorsData.minTextRatio,
            what: '${band.name} digits on the ${band.name} fill',
            palette: palette.label,
          );
        }

        final cursorFill = _over(
          colors.primary,
          HourCell.selectedAlpha,
          colors.background,
        );
        final cursorInk = Color.lerp(
          colors.primary,
          colors.onBackground,
          HourCell.cursorInkBlend,
        )!;
        _expectRatio(
          cursorInk,
          cursorFill,
          atLeast: AppColorsData.minTextRatio,
          what: 'cursor digits on the cursor wash',
          palette: palette.label,
        );
      });
    }

    test('the four bands are four distinguishable digit colours', () {
      // Colour is not the only carrier — every cell prints its hour — but a
      // band tint that collapsed onto its neighbour would make the tinting
      // pure decoration while still costing the reader a decision.
      for (final palette in _allPalettes) {
        final colors = palette.colors;
        final inks = [
          for (final band in HourBand.values)
            Color.lerp(
              hourBandColor(band, colors),
              colors.onBackground,
              HourCell.inkBlend,
            )!,
        ];
        expect(
          inks.toSet(),
          hasLength(HourBand.values.length),
          reason: '${palette.label}: two bands render the same digit colour',
        );
      }
    });
  });

  group('a banner is separable from the page it sits on', () {
    // A status wash at `AppAlpha.tint` is what tells a warning banner from the
    // card under it. It is deliberately faint, so the bar here is only that it
    // is not *invisible*; the icon and the copy carry the meaning.
    for (final palette in _allPalettes) {
      test(palette.label, () {
        final colors = palette.colors;
        for (final token in [colors.warning, colors.error, colors.primary]) {
          final wash = _over(token, AppAlpha.tint, colors.surface);
          expect(
            wash,
            isNot(colors.surface),
            reason: '${palette.label}: a tinted banner paints nothing at all',
          );
        }
      });
    }
  });
}

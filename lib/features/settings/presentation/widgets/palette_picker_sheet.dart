import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

// TODO(m2): migrate this onto the shared `TimeBuddyPickerSheet` /
// `TimeBuddyPickerRow` chrome (docs/specs/design_system.md §6) once the
// component library lands. The chrome below is deliberately local and
// deliberately small: shipping a half-designed shared sheet now, before the
// city picker exists to be its second caller, would fix the wrong shape.

/// How much of the screen the sheet may take before its list scrolls.
const double _maxSheetHeightFraction = 0.7;

/// One colour chip in a row's preview cluster.
const double _swatchSize = 18;

/// The sheet's drag handle, sized to the Material 3 default.
const double _handleWidth = 32;
const double _handleHeight = 4;

/// One selectable palette, brightness-agnostic.
///
/// A record rather than a class because the two catalogs already model this
/// (`LightPaletteOption` / `DarkPaletteOption`); the sheet only needs their
/// intersection, and a third class would exist purely to be converted into.
typedef _PaletteEntry<T> = ({T id, String label, AppColorsData colors});

/// Opens the light-palette picker, resolving to the chosen palette or `null`
/// when the sheet is dismissed.
///
/// The caller writes the result through `PreferencesCubit` and supplies the
/// [title]; the sheet itself touches neither state nor copy, so it can be
/// opened from anywhere and tested by pumping it alone.
///
/// Row labels come from the catalog, not from slang: a palette name is a
/// product name ('Indigo Cloud'), which is why `LightPaletteOption.label`
/// holds it as a literal in the first place.
///
/// ```dart
/// final picked = await showLightPaletteSheet(
///   context,
///   selected: preferences.lightPalette,
///   title: t.settings.lightPalette,
/// );
/// if (picked != null) await cubit.setLightPalette(picked);
/// ```
Future<LightPalette?> showLightPaletteSheet(
  BuildContext context, {
  required LightPalette selected,
  required String title,
}) {
  return _showPaletteSheet<LightPalette>(
    context,
    title: title,
    selected: selected,
    entries: [
      for (final option in LightPalettes.all)
        (id: option.id, label: option.label, colors: option.colors),
    ],
  );
}

/// Dark-mode twin of [showLightPaletteSheet].
Future<DarkPalette?> showDarkPaletteSheet(
  BuildContext context, {
  required DarkPalette selected,
  required String title,
}) {
  return _showPaletteSheet<DarkPalette>(
    context,
    title: title,
    selected: selected,
    entries: [
      for (final option in DarkPalettes.all)
        (id: option.id, label: option.label, colors: option.colors),
    ],
  );
}

Future<T?> _showPaletteSheet<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<_PaletteEntry<T>> entries,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _PaletteSheetBody<T>(
      title: title,
      selected: selected,
      entries: entries,
    ),
  );
}

class _PaletteSheetBody<T> extends StatelessWidget {
  const _PaletteSheetBody({
    required this.title,
    required this.selected,
    required this.entries,
  });

  final String title;
  final T selected;
  final List<_PaletteEntry<T>> entries;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: context.screenSize.height * _maxSheetHeightFraction,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(title, style: context.textTheme.headlineSmall),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _PaletteRow(
                    label: entry.label,
                    colors: entry.colors,
                    isSelected: entry.id == selected,
                    onTap: () => Navigator.of(context).pop(entry.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Center(
        child: Container(
          width: _handleWidth,
          height: _handleHeight,
          decoration: BoxDecoration(
            color: context.appColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
      ),
    );
  }
}

/// One palette, previewed by the four tokens a user actually notices: the
/// brand accent, the two surfaces it sits on, and the good-hour green that
/// will fill most of their grid.
///
/// The swatches are drawn from the *previewed* palette, not from
/// `context.appColors`, which is the whole point of the row: the active theme
/// is what you are choosing to leave.
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.label,
    required this.colors,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final AppColorsData colors;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColors = context.appColors;
    return Material(
      color: isSelected
          ? activeColors.primary.withValues(alpha: 0.08)
          : activeColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              _SwatchCluster(colors: colors),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, color: activeColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwatchCluster extends StatelessWidget {
  const _SwatchCluster({required this.colors});

  final AppColorsData colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Swatch(color: colors.primary),
        _Swatch(color: colors.background),
        _Swatch(color: colors.surface),
        _Swatch(color: colors.hourGood),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _swatchSize,
      height: _swatchSize,
      margin: const EdgeInsets.only(right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        // Without the hairline a white `surface` swatch disappears into a
        // white sheet, which is exactly the palette detail worth showing.
        border: Border.all(color: context.appColors.surfaceVariant),
      ),
    );
  }
}

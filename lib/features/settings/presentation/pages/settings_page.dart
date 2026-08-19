import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_pill_toggle.dart';
import 'package:timebuddy/app/widgets/timebuddy_section.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/settings/presentation/widgets/palette_picker_sheet.dart';
import 'package:timebuddy/features/settings/presentation/widgets/working_hours_preview.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Locale tags the app ships, matching the slang bundles.
const String _portugueseTag = 'pt-BR';
const String _englishTag = 'en';

// TODO(m5): read from package_info_plus. Hardcoding the pubspec version keeps
// M1 free of another plugin for a string nobody reads until a bug report.
const String _appVersion = '0.1.0';

// TODO(m2): surface the real tzdata release through `TimeZoneEngine`
// (docs/specs/timezone_engine.md rule 12). The `timezone` package does not
// expose its version, and features may not import it directly (CLAUDE.md), so
// an honest dash beats a hardcoded '2026a' that silently goes stale.
const String _tzDataVersion = '—';

/// Size of the palette accent chip in [_PaletteTile].
const double _paletteChipSize = 20;

// The two hour menus enumerate hour-of-day values, which is always 24 of them.
// This is not the "a day can be 23 or 25 hours" case CLAUDE.md rule 7 forbids
// hardcoding: no zone and no date are involved, only the legal ends of a
// working window.

/// Inclusive start hours, `0..23`.
final List<int> _startHourOptions = List<int>.generate(24, (index) => index);

/// Exclusive end hours, `1..24`, where 24 means midnight.
final List<int> _endHourOptions = List<int>.generate(24, (index) => index + 1);

/// Every user preference, in one page.
///
/// There is no save button anywhere on it: each control writes straight
/// through `PreferencesCubit`, which is a singleton, so a change is immediate
/// and global (docs/specs/preferences.md rule 6).
///
/// The Account group listed in the spec is deliberately absent: there is no
/// authentication until M3 (docs/specs/auth.md), and a stubbed "not signed in"
/// row promises a feature the build cannot deliver.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(title: t.settings.title),
      body: BlocBuilder<PreferencesCubit, PreferencesState>(
        builder: (context, state) => switch (state) {
          // Only reachable by deep-linking to /settings before the startup
          // load resolves; the page has nothing to render until it does.
          PreferencesLoading() => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: LoadingShimmer(rowCount: 5),
          ),
          PreferencesReady(:final preferences) => _SettingsBody(
            preferences: preferences,
          ),
        },
      ),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.preferences});

  final PreferencesEntity preferences;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.maxContentWidth,
        ),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _AppearanceSection(preferences: preferences),
            const SizedBox(height: AppSpacing.xl),
            _TimeSection(preferences: preferences),
            const SizedBox(height: AppSpacing.xl),
            _WorkingHoursSection(preferences: preferences),
            const SizedBox(height: AppSpacing.xl),
            _LanguageSection(localeTag: preferences.localeTag),
            const SizedBox(height: AppSpacing.xl),
            const _AboutSection(),
          ],
        ),
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.preferences});

  final PreferencesEntity preferences;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PreferencesCubit>();
    final lightOption = _lightOption(preferences.lightPalette);
    final darkOption = _darkOption(preferences.darkPalette);

    return TimeBuddySection(
      label: t.settings.groupAppearance,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(t.settings.themeMode),
          TimeBuddyPillToggle<ThemeMode>(
            options: [
              PillOption(
                value: ThemeMode.system,
                label: t.settings.themeSystem,
              ),
              PillOption(
                value: ThemeMode.light,
                label: t.settings.themeLight,
              ),
              PillOption(
                value: ThemeMode.dark,
                label: t.settings.themeDark,
              ),
            ],
            selected: preferences.themeMode,
            onChanged: (value) => unawaited(cubit.setThemeMode(value)),
          ),
          const SizedBox(height: AppSpacing.md),
          _PaletteTile(
            label: t.settings.lightPalette,
            value: lightOption.label,
            swatch: lightOption.colors.primary,
            onTap: () => unawaited(_pickLightPalette(context)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PaletteTile(
            label: t.settings.darkPalette,
            value: darkOption.label,
            swatch: darkOption.colors.primary,
            onTap: () => unawaited(_pickDarkPalette(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLightPalette(BuildContext context) async {
    // Read before the await: the cubit reference must not be looked up on a
    // context that the sheet may have unmounted.
    final cubit = context.read<PreferencesCubit>();
    final picked = await showLightPaletteSheet(
      context,
      selected: preferences.lightPalette,
      title: t.settings.lightPalette,
    );
    if (picked == null) return;
    await cubit.setLightPalette(picked);
  }

  Future<void> _pickDarkPalette(BuildContext context) async {
    final cubit = context.read<PreferencesCubit>();
    final picked = await showDarkPaletteSheet(
      context,
      selected: preferences.darkPalette,
      title: t.settings.darkPalette,
    );
    if (picked == null) return;
    await cubit.setDarkPalette(picked);
  }
}

class _TimeSection extends StatelessWidget {
  const _TimeSection({required this.preferences});

  final PreferencesEntity preferences;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PreferencesCubit>();
    return TimeBuddySection(
      label: t.settings.groupTime,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(t.settings.hourFormat),
          TimeBuddyPillToggle<ClockFormat>(
            options: [
              PillOption(
                value: ClockFormat.h12,
                label: t.settings.hourFormat12,
              ),
              PillOption(
                value: ClockFormat.h24,
                label: t.settings.hourFormat24,
              ),
            ],
            selected: preferences.hourFormat,
            onChanged: (value) => unawaited(cubit.setClockFormat(value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: preferences.showSeconds,
            title: Text(
              t.settings.showSeconds,
              style: context.textTheme.titleSmall,
            ),
            // The hint is not decoration: this switch changes the app-wide
            // ticker rate, not just the digits (preferences.md rule 10).
            subtitle: Text(
              t.settings.showSecondsHint,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.appColors.onBackgroundLight,
              ),
            ),
            onChanged: (value) =>
                unawaited(cubit.setShowSeconds(value: value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _FieldLabel(t.settings.weekStartsOn),
          TimeBuddyPillToggle<WeekStart>(
            options: [
              PillOption(
                value: WeekStart.monday,
                label: t.settings.weekStartsMonday,
              ),
              PillOption(
                value: WeekStart.sunday,
                label: t.settings.weekStartsSunday,
              ),
            ],
            selected: preferences.weekStartsOn,
            onChanged: (value) => unawaited(cubit.setWeekStart(value)),
          ),
        ],
      ),
    );
  }
}

class _WorkingHoursSection extends StatelessWidget {
  const _WorkingHoursSection({required this.preferences});

  final PreferencesEntity preferences;

  @override
  Widget build(BuildContext context) {
    final workingHours = preferences.workingHours;
    return TimeBuddySection(
      label: t.settings.groupWorkingHours,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _HourField(
                  label: t.settings.workingHoursStart,
                  value: workingHours.startHour,
                  hours: _startHourOptions,
                  hourFormat: preferences.hourFormat,
                  onChanged: (hour) => _apply(
                    context,
                    workingHours.copyWith(startHour: hour),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _HourField(
                  label: t.settings.workingHoursEnd,
                  value: workingHours.endHour,
                  hours: _endHourOptions,
                  hourFormat: preferences.hourFormat,
                  onChanged: (hour) => _apply(
                    context,
                    workingHours.copyWith(endHour: hour),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          WorkingHoursPreview(
            workingHours: workingHours,
            hourFormat: preferences.hourFormat,
          ),
        ],
      ),
    );
  }

  /// Writes [candidate] through the cubit, or refuses it.
  ///
  /// Refusing rather than clamping is deliberate. `WorkingHours.clamped()`
  /// repairs a bad *persisted* pair by replacing it with 09:00-17:00, which is
  /// right for a parser and wrong for a form: a user who picks a 20-hour
  /// window would watch their window silently become someone else's
  /// (preferences.md rule 5, "enforced in the form and in the parser").
  void _apply(BuildContext context, WorkingHours candidate) {
    if (!candidate.isValid) {
      context.showSnack(
        t.settings.workingHoursInvalid(
          min: WorkingHours.minLength,
          max: WorkingHours.maxLength,
        ),
      );
      return;
    }
    unawaited(context.read<PreferencesCubit>().setWorkingHours(candidate));
  }
}

/// One hour-of-day selector, wearing the app's input decoration.
class _HourField extends StatelessWidget {
  const _HourField({
    required this.label,
    required this.value,
    required this.hours,
    required this.hourFormat,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> hours;
  final ClockFormat hourFormat;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final hour in hours)
              DropdownMenuItem<int>(
                value: hour,
                child: Text(workingHourLabel(hour, hourFormat)),
              ),
          ],
          onChanged: (picked) {
            if (picked == null) return;
            onChanged(picked);
          },
        ),
      ),
    );
  }
}

class _LanguageSection extends StatelessWidget {
  const _LanguageSection({required this.localeTag});

  /// `null` means "follow the device", a real value rather than a missing one
  /// (docs/specs/preferences.md rule 3).
  final String? localeTag;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PreferencesCubit>();
    return TimeBuddySection(
      label: t.settings.groupLanguage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChoiceRow(
            label: t.settings.languageSystem,
            isSelected: localeTag == null,
            onTap: () => unawaited(cubit.setLocaleTag(null)),
          ),
          _ChoiceRow(
            label: t.settings.languagePortuguese,
            isSelected: localeTag == _portugueseTag,
            onTap: () => unawaited(cubit.setLocaleTag(_portugueseTag)),
          ),
          _ChoiceRow(
            label: t.settings.languageEnglish,
            isSelected: localeTag == _englishTag,
            onTap: () => unawaited(cubit.setLocaleTag(_englishTag)),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return TimeBuddySection(
      label: t.settings.groupAbout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(label: t.settings.appVersion, value: _appVersion),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(label: t.settings.tzDataVersion, value: _tzDataVersion),
          const SizedBox(height: AppSpacing.sm),
          _LinkRow(
            label: t.settings.licenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: t.app.name,
              applicationVersion: _appVersion,
            ),
          ),
        ],
      ),
    );
  }
}

/// The muted caption that names the control under it.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: context.textTheme.labelMedium?.copyWith(
          color: context.appColors.onBackgroundLight,
        ),
      ),
    );
  }
}

/// One row of a settings group.
///
/// Four configurations of one shape rather than four widgets that drift apart
/// on vertical padding: a read-only pair, a link, a one-of-N choice and a
/// picker tile. It is the same argument `TimeBuddySection` makes one level up
/// (design_system §10, Financo backlog item 2).
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    this.leading,
    this.trailing,
    this.onTap,
    this.isSelected = false,
  });

  final String label;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Weights the label and is how a choice row marks the current value.
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Text(
              label,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : null,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    // Its own transparent Material: a TimeBuddySection card is a DecoratedBox,
    // so an InkWell here would splash on the Scaffold's Material *behind* the
    // card and never be seen.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: row,
      ),
    );
  }
}

/// The row that opens a palette sheet, previewing the current choice with its
/// own accent rather than with the active theme's.
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.label,
    required this.value,
    required this.swatch,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: label,
      onTap: onTap,
      leading: Container(
        width: _paletteChipSize,
        height: _paletteChipSize,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MutedText(value),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_rounded,
            color: context.appColors.onBackgroundLight,
          ),
        ],
      ),
    );
  }
}

/// A one-of-N row: tap to pick, a check marks the current value.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: label,
      isSelected: isSelected,
      onTap: onTap,
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: context.appColors.primary)
          : null,
    );
  }
}

/// A read-only `label: value` row.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      _SettingsRow(label: label, trailing: _MutedText(value));
}

/// A row that opens something outside the settings page.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: label,
      onTap: onTap,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: context.appColors.onBackgroundLight,
      ),
    );
  }
}

/// Secondary text on a row: a value, a version, a current selection.
class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.textTheme.bodyMedium?.copyWith(
        color: context.appColors.onBackgroundLight,
      ),
    );
  }
}

/// The catalog entry for [id], falling back to the first palette.
///
/// The fallback mirrors `LightPalettes.colorsFor`: the enum and the catalog
/// are maintained by hand, and a palette with no entry must not take down the
/// settings page.
LightPaletteOption _lightOption(LightPalette id) =>
    LightPalettes.all.firstWhere(
      (option) => option.id == id,
      orElse: () => LightPalettes.all.first,
    );

/// Dark-mode twin of [_lightOption].
DarkPaletteOption _darkOption(DarkPalette id) => DarkPalettes.all.firstWhere(
  (option) => option.id == id,
  orElse: () => DarkPalettes.all.first,
);

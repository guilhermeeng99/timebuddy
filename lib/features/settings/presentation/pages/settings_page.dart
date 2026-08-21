import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_pill_toggle.dart';
import 'package:timebuddy/app/widgets/timebuddy_row_group.dart';
import 'package:timebuddy/app/widgets/timebuddy_section.dart';
import 'package:timebuddy/app/widgets/timebuddy_settings_row.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
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
/// The Account group is one row and one destination: it says who is signed in
/// and opens `/profile`, where the session actually lives. Since guest mode
/// (docs/specs/guest_mode.md rule 10) it is also where a visitor without an
/// account finds the offer to make one — and the only in-app path to a route
/// that had none.
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
    // **Deliberately not clamped to `ResponsiveLayout.maxContentWidth`.**
    // A 600pt column of settings floating in the middle of a 1600pt window is
    // the layout this page used to have, and it read as a phone screen someone
    // forgot to finish. The cap earns its keep on prose — onboarding still
    // uses it — but these are rows: an icon on the left, a label, a value on
    // the right, and the eye tracks the two ends. Widening them puts the value
    // where it is easiest to find rather than making a sentence too long to
    // follow (design_system section 7).
    return ListView(
      // Settings is a primary destination, so on mobile the floating bottom
      // bar hovers over the end of this list. A flat inset leaves the licenses
      // row visible but untappable, which design_system section 9 lists among
      // the things a screen must never do.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        bottomSafeForBar(context, isSubPage: false),
      ),
      children: [
        const _IdentityCard(),
        const SizedBox(height: AppSpacing.xxl),
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
    );
  }
}

/// Who is signed in, as the page's first and largest element.
///
/// The hero of a settings screen is the account it belongs to: the same thing
/// the rail's foot shows, at a size that anchors the page rather than labels a
/// nav row. It replaces the Account *row* that used to sit between Language
/// and About, because an identity block at the top and a row two thirds down
/// were two places answering one question.
///
/// Tapping it opens `/profile`, which owns everything that ends a session.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard();

  static const double _avatarSize = 64;
  static const double _initialFontSize = 26;
  static const double _chevronSize = 12;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final user = state is Authenticated ? state.user : null;
        final colors = context.appColors;
        return Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(AppRoutes.profile),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  _IdentityAvatar(user: user),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user?.name ?? t.settings.notSignedIn,
                          style: context.textTheme.titleLarge?.copyWith(
                            color: colors.onBackground,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // A guest is told where their data lives, which is
                          // the one thing signing in would change
                          // (docs/specs/guest_mode.md rule 10).
                          user?.email ?? t.auth.guestBody,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: colors.onBackgroundLight,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppIcon(
                    FontAwesomeIcons.chevronRight,
                    size: _chevronSize,
                    color: colors.onBackgroundLight,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IdentityAvatar extends StatelessWidget {
  const _IdentityAvatar({required this.user});

  final UserEntity? user;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final photoUrl = user?.photoUrl;
    // The gradient is the avatar, not a backdrop for it: a photo covers it
    // entirely, and its absence is then a deliberate shape rather than a hole.
    return Container(
      width: _IdentityCard._avatarSize,
      height: _IdentityCard._avatarSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, colors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl == null || photoUrl.isEmpty
          ? _initial(context)
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initial(context),
            ),
    );
  }

  Widget _initial(BuildContext context) {
    final name = user?.name.trim() ?? '';
    return Center(
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: context.appColors.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: _IdentityCard._initialFontSize,
          height: 1,
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

    return TimeBuddySection(
      label: t.settings.groupAppearance,
      // The section's own card is off because the group below *is* the card:
      // rows have to reach both its edges for a pressed row to look like a row
      // rather than a rectangle floating inside one.
      card: false,
      // One row. The two palette pickers used to sit under it — twenty options
      // behind two sheets the user had to open, decide in and close — and they
      // are gone. The theme is the choice worth offering here; the palettes
      // are still the app's own (`AppColors`), just not a question.
      child: TimeBuddyRowGroup(
        children: [
          TimeBuddySettingsRow(
            icon: _themeIcon(preferences.themeMode),
            title: t.settings.themeMode,
            control: TimeBuddyPillToggle<ThemeMode>(
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
          ),
        ],
      ),
    );
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
      card: false,
      child: TimeBuddyRowGroup(
        children: [
          TimeBuddySettingsRow(
            icon: FontAwesomeIcons.clock,
            title: t.settings.hourFormat,
            control: TimeBuddyPillToggle<ClockFormat>(
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
          ),
          TimeBuddySettingsRow(
            icon: FontAwesomeIcons.stopwatch,
            title: t.settings.showSeconds,
            // The hint is not decoration: this switch changes the app-wide
            // ticker rate, not just the digits (preferences.md rule 10).
            subtitle: t.settings.showSecondsHint,
            trailing: Switch(
              value: preferences.showSeconds,
              onChanged: (value) =>
                  unawaited(cubit.setShowSeconds(value: value)),
            ),
          ),
          TimeBuddySettingsRow(
            icon: FontAwesomeIcons.calendar,
            title: t.settings.weekStartsOn,
            control: TimeBuddyPillToggle<WeekStart>(
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
      card: false,
      child: TimeBuddyRowGroup(
        children: [
          _LanguageRow(
            label: t.settings.languageSystem,
            isSelected: localeTag == null,
            onTap: () => unawaited(cubit.setLocaleTag(null)),
          ),
          _LanguageRow(
            label: t.settings.languagePortuguese,
            isSelected: localeTag == _portugueseTag,
            onTap: () => unawaited(cubit.setLocaleTag(_portugueseTag)),
          ),
          _LanguageRow(
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
        ],
      ),
    );
  }
}

/// A plain label-and-value line, for the About group.
///
/// Everything interactive on this page is a `TimeBuddySettingsRow` inside a
/// `TimeBuddyRowGroup`; what is left here states a fact and offers nothing to
/// tap, so it carries no icon disc and no chevron.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textTheme.titleSmall)),
          ?trailing,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      _SettingsRow(label: label, trailing: _MutedText(value));
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

/// Which glyph stands for the theme mode currently in force.
///
/// The row's icon reports the setting instead of naming the category twice:
/// the title already says "Theme", so a fixed paint-roller would be decoration
/// while a sun, a moon or a half-lit circle is the answer at a glance.
FaIconData _themeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => FontAwesomeIcons.circleHalfStroke,
  ThemeMode.light => FontAwesomeIcons.solidSun,
  ThemeMode.dark => FontAwesomeIcons.solidMoon,
};

/// One locale choice, marked with a check rather than a chevron.
///
/// A radio group and not a list of doors: every row here sets the same field,
/// so the trailing slot has to say *which one is on* rather than promising a
/// screen behind each.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  static const double _markSize = 14;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TimeBuddySettingsRow(
      icon: FontAwesomeIcons.language,
      title: label,
      accent: isSelected ? colors.primary : colors.onBackgroundLight,
      trailing: isSelected
          ? AppIcon(
              FontAwesomeIcons.check,
              size: _markSize,
              color: colors.primary,
            )
          : const SizedBox(width: _markSize),
      onTap: onTap,
    );
  }
}

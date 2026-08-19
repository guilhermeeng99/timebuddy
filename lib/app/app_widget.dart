import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/routes/app_router.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_theme.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The root widget: theme, locale, router and the app-wide lifecycle hook.
///
/// `PreferencesCubit` is the single source of truth for theme mode and both
/// palettes — there is deliberately no `ThemeCubit` / `LightPaletteCubit` /
/// `DarkPaletteCubit`, because two cubits persisting the same field are two
/// sources of truth for it. This widget reads the preferences state, reassigns
/// `AppColors.light` / `AppColors.dark`, and only then builds `MaterialApp`.
///
/// ```dart
/// runApp(TranslationProvider(child: const TimeBuddyApp()));
/// ```
class TimeBuddyApp extends StatefulWidget {
  const TimeBuddyApp({super.key});

  @override
  State<TimeBuddyApp> createState() => _TimeBuddyAppState();
}

class _TimeBuddyAppState extends State<TimeBuddyApp>
    with WidgetsBindingObserver {
  // Applying a locale rebuilds the whole TranslationProvider subtree, so it is
  // only worth doing when the tag actually changed. The flag distinguishes
  // "never applied" from "applied null", which both read as null otherwise.
  String? _appliedLocaleTag;
  bool _hasAppliedLocale = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // There is no StartupCubit until M3 (docs/specs/startup.md), so the app
    // widget owns the one-shot preferences load that every page depends on.
    // The device locale only seeds the first launch (preferences.md rule 2).
    unawaited(
      sl<PreferencesCubit>().load(
        deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Stops the app-wide ticker while the app is backgrounded and restarts it
  /// on the way back (CLAUDE.md, Performance).
  ///
  /// A backgrounded app that keeps ticking burns a wakeup per second to
  /// repaint pixels nobody can see; `resume` re-emits immediately so a phone
  /// unlocked an hour later does not show the minute it was locked at.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ticker = sl<TickerService>();
    switch (state) {
      case AppLifecycleState.paused:
        ticker.pause();
      case AppLifecycleState.resumed:
        ticker.resume();
      // inactive / hidden / detached are transient states on the way to one of
      // the two above; reacting to them would thrash the timer.
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PreferencesCubit>.value(
      value: sl<PreferencesCubit>(),
      child: BlocListener<PreferencesCubit, PreferencesState>(
        listener: (_, state) => _applySideEffects(state),
        child: BlocBuilder<PreferencesCubit, PreferencesState>(
          builder: (context, state) => switch (state) {
            PreferencesLoading() => const _BootstrapApp(),
            PreferencesReady(:final preferences) => _buildApp(
              context,
              preferences,
            ),
          },
        ),
      ),
    );
  }

  /// The parts of a preference change that are not a rebuild: the ticker rate
  /// and the active locale.
  ///
  /// Both live in a listener rather than in `build` because both are global
  /// mutations, and running them mid-build would mean a `MaterialApp` whose
  /// theme is one frame ahead of the strings inside it.
  void _applySideEffects(PreferencesState state) {
    if (state is! PreferencesReady) return;
    final preferences = state.preferences;

    // Turning seconds on is the only thing that puts the ticker at 1 Hz
    // (docs/specs/preferences.md rule 10). The setter no-ops on an unchanged
    // value, so calling it on every preference change is free.
    sl<TickerService>().setNeedsSeconds(value: preferences.showSeconds);

    if (_hasAppliedLocale && _appliedLocaleTag == preferences.localeTag) return;
    _hasAppliedLocale = true;
    _appliedLocaleTag = preferences.localeTag;
    unawaited(_applyLocale(preferences.localeTag));
  }

  /// Switches the app locale, where `null` means "follow the device"
  /// (docs/specs/preferences.md rule 3).
  ///
  /// `Intl.defaultLocale` is set from whatever slang resolved, because
  /// `formatClock` renders its am/pm marker through it and would otherwise
  /// print an English marker under a Portuguese UI.
  Future<void> _applyLocale(String? localeTag) async {
    if (localeTag == null) {
      await LocaleSettings.useDeviceLocale();
    } else {
      // A tag the app does not ship falls back to the base locale, while the
      // stored value is kept, so shipping that locale later just works.
      await LocaleSettings.setLocaleRaw(localeTag);
    }
    Intl.defaultLocale = LocaleSettings.currentLocale.languageTag;
  }

  Widget _buildApp(BuildContext context, PreferencesEntity preferences) {
    // Assigned before AppTheme reads them. The theme builders snapshot the
    // active palette at call time, so these two lines plus the rebuild below
    // are the entire runtime palette switch (design_system §2).
    AppColors.light = LightPalettes.colorsFor(preferences.lightPalette);
    AppColors.dark = DarkPalettes.colorsFor(preferences.darkPalette);

    return MaterialApp.router(
      title: t.app.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // `system` follows the OS at sunset without a restart, because
      // MaterialApp watches the platform brightness itself.
      themeMode: preferences.themeMode,
      routerConfig: AppRouter.router,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

/// What the user sees between `runApp` and the first resolved preferences
/// document: one frame or two on a warm start, longer on a cold web load.
///
/// Deliberately bare. It cannot use the selected palette (that is what it is
/// waiting for) and a branded splash belongs to the startup flow in M3
/// (docs/specs/startup.md).
class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      ),
    );
  }
}

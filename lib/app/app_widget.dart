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
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The root widget: theme, locale, router and the app-wide lifecycle hook.
///
/// `PreferencesCubit` is the single source of truth for theme mode and both
/// palettes — there is deliberately no `ThemeCubit` / `LightPaletteCubit` /
/// `DarkPaletteCubit`, because two cubits persisting the same field are two
/// sources of truth for it. This widget reads the preferences state, reassigns
/// `AppColors.light` / `AppColors.dark`, and only then builds `MaterialApp`.
///
/// It owns three things and no more: the preferences load, the app-wide bloc
/// providers, and the lifecycle hook.
///
/// **Why preferences load here and not in `StartupCubit`.** The splash is a
/// *route*, so it lives inside `MaterialApp.router` — which cannot be built
/// until the theme, the palettes and the locale are known. Loading them here
/// is what lets the splash itself be drawn in the user's own colors. Every
/// other startup concern (tzdata, the catalog, the session, the first sync)
/// belongs to `StartupCubit`, where a failure has a screen to be reported on.
///
/// The board is loaded one level further down, by `AppShell`
/// (see `app_shell.dart`), which the router only builds once startup has left
/// `/startup` — so that load reads the document the first sync reconciled.
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
    // The one-shot preferences load every page depends on, including the
    // splash. The device locale only seeds the first launch
    // (docs/specs/preferences.md rule 2).
    unawaited(
      sl<PreferencesCubit>().load(
        deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
      ),
    );
    // Asked here rather than by `StartupCubit`, which is deliberately a
    // read-only observer of `AuthBloc` (docs/specs/startup.md, Collaborators).
    // This is the one place that runs exactly once per process and sits above
    // the router, so the session check cannot be started twice by a route
    // being rebuilt, and it is already in flight by the time the splash
    // starts waiting on it.
    sl<AuthBloc>().add(const AuthCheckRequested());
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
        _flushPendingWrites();
      // inactive / hidden / detached are transient states on the way to one of
      // the two above; reacting to them would thrash the timer.
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Retries whatever a failed remote write left behind (docs/specs/sync.md,
  /// Sync flow).
  ///
  /// Cheap enough to run on every resume: `flushDirty` costs zero reads and
  /// publishes no status when nothing is dirty. Fire and forget on purpose — a
  /// flush that fails again leaves the flag set for the next attempt and says
  /// nothing to the user (sync.md rule 4).
  void _flushPendingWrites() {
    final session = sl<AuthBloc>().state;
    if (session is! Authenticated) return;
    unawaited(sl<SyncService>().flushDirty(userId: session.user.id));
  }

  @override
  Widget build(BuildContext context) {
    // `.value` for all three: they are `GetIt` singletons, so the provider
    // must not adopt them and close them with this widget.
    return MultiBlocProvider(
      providers: [
        BlocProvider<PreferencesCubit>.value(value: sl<PreferencesCubit>()),
        // Above the router, because the redirect reads both to decide what
        // may render (`app_router.dart`), and the profile and onboarding
        // pages read the session out of the same instance.
        BlocProvider<AuthBloc>.value(value: sl<AuthBloc>()),
        BlocProvider<StartupCubit>.value(value: sl<StartupCubit>()),
      ],
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
/// Deliberately bare, and not to be confused with the splash. It cannot use
/// the selected palette — that is exactly what it is waiting for — while
/// `StartupPage` runs *inside* the router, in the user's own colors, and owns
/// everything the app actually has to load (docs/specs/startup.md).
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/clock_text.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The splash: the only screen allowed to be on top of an uninitialized app
/// (docs/specs/startup.md).
///
/// It owns three things and nothing else — starting `StartupCubit`, turning
/// its terminal states into a route, and rendering the progress the cubit
/// reports. Every string here is localized, because the cubit deliberately
/// carries none: `StartupError` has no field at all, and `StartupLoading`
/// carries a number the page maps to a step label.
///
/// ```dart
/// GoRoute(
///   path: AppRoutes.startup,
///   builder: (context, state) => const StartupPage(),
/// );
/// ```
class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    // Fire and forget: the cubit owns the future and publishes every outcome
    // as a state, so awaiting it here would only duplicate the listener below.
    unawaited(context.read<StartupCubit>().initialize());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      body: BlocListener<StartupCubit, StartupState>(
        listener: _route,
        child: const SafeArea(child: Center(child: _StartupBody())),
      ),
    );
  }

  /// Startup's whole output: which screen the app opens on.
  ///
  /// `go`, not `push`: the splash must not stay under the app as a back
  /// destination. `StartupError` is deliberately absent — recovery is the
  /// in-page retry, not a route out (responsibility 6).
  void _route(BuildContext context, StartupState state) {
    switch (state) {
      case StartupAuthenticated():
        context.go(AppRoutes.grid);
      // One state, two destinations (docs/specs/guest_mode.md rule 4).
      // "Auth resolved to nobody" is still the whole of what startup found;
      // whether that nobody has already chosen to go without an account is a
      // device fact, and asking it here is what keeps `StartupState` from
      // growing a variant that `AppRouter._startupResolved` would have to
      // learn about.
      case StartupUnauthenticated():
        context.go(
          sl<GuestSession>().isGuest ? AppRoutes.grid : AppRoutes.onboarding,
        );
      case StartupInitial():
      case StartupLoading():
      case StartupError():
        break;
    }
  }
}

/// Reserved height of the clock, so the layout does not step when the device
/// zone resolves.
const double _clockHeight = 44;

/// Size of the ticking digits. Large enough to read as the app's point.
const double _clockFontSize = 34;

/// The brand disc and the glyph inside it, matching `ErrorView`'s proportions.
const double _brandDiscSize = 72;
const double _brandGlyphSize = 34;
const double _brandDiscAlpha = 0.12;

/// Width of the progress track and of the error copy.
const double _contentWidth = 320;

/// Thickness of the progress track.
const double _progressHeight = 4;

/// What the user looks at while startup runs.
class _StartupBody extends StatelessWidget {
  const _StartupBody();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _contentWidth),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: BlocBuilder<StartupCubit, StartupState>(
          builder: (context, state) => switch (state) {
            StartupError() => const _StartupErrorBlock(),
            _ => _StartupProgress(progress: _progressOf(state)),
          },
        ),
      ),
    );
  }

  /// The bar's value for [state].
  ///
  /// The terminal states carry no progress of their own: they *are* the end,
  /// so they read as 1 and the bar is full for the frame before the route
  /// changes (spec, Page Behavior).
  static double _progressOf(StartupState state) => switch (state) {
    StartupLoading(:final progress) => progress,
    StartupInitial() => StartupLoading.startedProgress,
    StartupAuthenticated() || StartupUnauthenticated() || StartupError() => 1,
  };
}

/// The brand mark, the device's own clock, and how far along startup is.
class _StartupProgress extends StatelessWidget {
  const _StartupProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BrandMark(),
        const SizedBox(height: AppSpacing.xxl),
        // Only once tzdata is loaded: every engine call before that is a lie,
        // and `deviceZone()` asserts against exactly this (rule 2).
        if (progress >= StartupLoading.preparedProgress)
          const _DeviceClock()
        else
          const SizedBox(height: _clockHeight),
        const SizedBox(height: AppSpacing.xxl),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: _progressHeight,
            backgroundColor: colors.surfaceVariant,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _stepLabel(progress),
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall?.copyWith(
            color: colors.onBackgroundLight,
          ),
        ),
      ],
    );
  }

  /// The localized step, derived from rule 9's sentinels rather than from a
  /// second state field: the cubit carries no strings, and two enumerations of
  /// the same four steps would be one edit away from disagreeing.
  String _stepLabel(double progress) {
    if (progress >= 1) return t.startup.stepReady;
    if (progress >= StartupLoading.syncingProgress) {
      return t.startup.stepSyncing;
    }
    if (progress >= StartupLoading.preparedProgress) {
      return t.startup.stepCheckingAuth;
    }
    return t.startup.stepLoadingData;
  }
}

/// The app's name and what it is for, above everything else on the splash.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _brandDiscSize,
          height: _brandDiscSize,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: _brandDiscAlpha),
            shape: BoxShape.circle,
          ),
          child: AppIcon(
            FontAwesomeIcons.earthAmericas,
            size: _brandGlyphSize,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(t.app.name, style: context.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          t.startup.tagline,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(
            color: colors.onBackgroundLight,
          ),
        ),
      ],
    );
  }
}

/// A live clock for the zone this device is in.
///
/// It costs nothing — the engine is loaded by the time this mounts — and it
/// says what kind of app this is before the user has signed in (spec, Page
/// Behavior).
class _DeviceClock extends StatefulWidget {
  const _DeviceClock();

  @override
  State<_DeviceClock> createState() => _DeviceClockState();
}

class _DeviceClockState extends State<_DeviceClock> {
  /// Resolved once and held, because the widget rebuilds on every progress
  /// change and `deviceZone()` crosses a platform channel.
  late final Future<DeviceZone> _deviceZone = sl<TimeZoneEngine>().deviceZone();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _clockHeight,
      child: FutureBuilder<DeviceZone>(
        future: _deviceZone,
        builder: (context, snapshot) {
          final zone = snapshot.data;
          // No spinner while the channel answers: a second progress indicator
          // next to the real one would read as two things loading.
          if (zone == null) return const SizedBox.shrink();
          return ClockText(zoneId: zone.zoneId, fontSize: _clockFontSize);
        },
      ),
    );
  }
}

/// The one hard error in the app: tzdata or the city catalog did not load.
///
/// The copy is localized and generic on purpose (rule 10). A user cannot act
/// on the exception, which is why it went to `dart:developer` instead; what
/// they can act on is the retry.
class _StartupErrorBlock extends StatelessWidget {
  const _StartupErrorBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BrandMark(),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          t.startup.errorTitle,
          textAlign: TextAlign.center,
          style: context.textTheme.titleMedium?.copyWith(color: colors.error),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          t.startup.errorBody,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(
            color: colors.onBackgroundLight,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton(
          // The same entry point `initState` uses: a retry is a second attempt
          // at the whole sequence, not a resume of the half that failed.
          onPressed: () => unawaited(context.read<StartupCubit>().initialize()),
          child: Text(t.startup.errorRetry),
        ),
      ],
    );
  }
}

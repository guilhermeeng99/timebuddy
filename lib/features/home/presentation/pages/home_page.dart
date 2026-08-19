import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/clock_text.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Font size of the hero clock. Larger than `displayLarge` on purpose: this
/// page has exactly one thing to show, and it doubles as the proof that the
/// engine, the ticker and the preferences are all wired.
const double _heroClockFontSize = 56;
const double _noticeTintAlpha = 0.12;
const double _noticeIconSize = 20;

/// The milestone-1 landing page.
///
/// It shows the device's own zone and nothing else, because the board it will
/// eventually host does not exist yet (docs/specs/time_grid.md). What it does
/// prove, on screen and without a test, is the whole M1 foundation: tzdata
/// resolved the device zone, the ticker drives the digits, the theme paints
/// them and the preferences decide their format.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Resolved once and held: `deviceZone()` crosses a platform channel, so
  // re-reading it from `build` would put an async round-trip in the paint
  // path of a page that rebuilds on every tick.
  late final Future<DeviceZone> _deviceZone = sl<TimeZoneEngine>().deviceZone();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(
        title: t.home.title,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.home.settingsAction,
            // `push`, not `go`: settings is a sub-page, and a replaced stack
            // leaves its back chevron with nothing to pop (design_system §7).
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: FutureBuilder<DeviceZone>(
        future: _deviceZone,
        builder: (context, snapshot) {
          final zone = snapshot.data;
          if (zone == null) {
            // Shaped like the block it replaces, so the clock lands without
            // shifting the page (design_system §8, State screens).
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: LoadingShimmer(rowCount: 1),
            );
          }
          return _DeviceClock(
            zoneId: zone.zoneId,
            isFallback: zone.isFallback,
          );
        },
      ),
    );
  }
}

class _DeviceClock extends StatelessWidget {
  const _DeviceClock({required this.zoneId, required this.isFallback});

  final String zoneId;

  /// Whether [zoneId] is the UTC fallback rather than a detected zone.
  ///
  /// Rendered, never swallowed. A detection failure that shows a plausible
  /// UTC clock under the label "your device" is the silent-wrong-hour failure
  /// CLAUDE.md Time rule 8 calls the most dangerous one in the codebase: the
  /// user has no way to tell a correct clock from an hour-wrong one.
  final bool isFallback;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = context.watch<PreferencesCubit>().state;
    final showSeconds =
        state is PreferencesReady && state.preferences.showSeconds;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ResponsiveLayout.maxContentWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.home.deviceClockLabel.toUpperCase(),
                style: context.textTheme.labelSmall?.copyWith(
                  color: colors.onBackgroundLight,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ClockText(
                zoneId: zoneId,
                fontSize: _heroClockFontSize,
                showSeconds: showSeconds,
              ),
              const SizedBox(height: AppSpacing.sm),
              // The raw IANA id, not a city label: the location catalog that
              // turns `America/Sao_Paulo` into "Sao Paulo" arrives in M2
              // (docs/specs/locations.md).
              Text(zoneId, style: context.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _OffsetPill(zoneId: zoneId),
              if (isFallback) ...[
                const SizedBox(height: AppSpacing.xl),
                const _FallbackNotice(),
              ],
              const SizedBox(height: AppSpacing.xxl),
              Text(
                t.home.milestoneNotice,
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  color: colors.onBackgroundLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The zone's current UTC offset, e.g. `-03:00`.
class _OffsetPill extends StatelessWidget {
  const _OffsetPill({required this.zoneId});

  final String zoneId;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final engine = sl<TimeZoneEngine>();

    // Recomputed per tick rather than once: an offset is a function of
    // (zone, instant), never of a zone alone (CLAUDE.md, Time rule 2), so this
    // label has to change by itself when the zone crosses a DST transition
    // while the page is open. It is a leaf, so the rebuild is cheap.
    return StreamBuilder<DateTime>(
      stream: sl<TickerService>().stream,
      initialData: sl<Clock>().nowUtc(),
      builder: (context, snapshot) {
        final instant = snapshot.data ?? sl<Clock>().nowUtc();
        final offset = engine.stateAt(zoneId: zoneId, instant: instant).offset;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              offsetLabel(offset),
              style: context.textTheme.labelMedium?.copyWith(
                color: colors.onBackgroundLight,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Says out loud that the zone under the clock was not detected.
///
/// Deliberately not a dismissible snackbar: the condition lasts as long as the
/// session does, and a message the user can lose is not a warning. The home
/// city picker that would let them fix it arrives with the board in M2
/// (docs/specs/locations.md rule 3), so the copy states the fact without
/// promising a control that does not exist yet.
class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: _noticeTintAlpha),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: _noticeIconSize,
              color: colors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.home.deviceZoneUnknownTitle,
                    style: context.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    t.home.deviceZoneUnknownBody,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: colors.onBackgroundLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

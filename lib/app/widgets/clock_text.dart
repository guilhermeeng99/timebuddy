import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/theme/app_typography.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state_defaults.dart';

/// Live wall-clock digits for one zone.
///
/// The only sanctioned way to render a ticking time. A page that starts its own
/// `Timer` gets one timer per row and rebuilds the whole row every second; a
/// board of 20 cities makes that 20 timers and 20 subtree rebuilds a second
/// (CLAUDE.md, Performance). This widget instead subscribes to the app's single
/// [TickerService] and repaints exactly one [Text].
///
/// The instant comes from the ticker in UTC and is converted through
/// [TimeZoneEngine] per tick, never by adding a stored offset: an offset is a
/// function of `(zone, instant)` and changes under the widget on a DST
/// boundary while it is on screen.
///
/// The dependencies are constructor parameters with an `sl` fallback so a
/// widget test can drive the digits from a fake ticker and a pinned clock
/// without standing up the service locator.
///
/// ```dart
/// ClockText(zoneId: location.zoneId, fontSize: 28);
/// ```
class ClockText extends StatelessWidget {
  const ClockText({
    required this.zoneId,
    this.showSeconds = false,
    this.fontSize = 18,
    this.color,
    this.ticker,
    this.engine,
    this.clock,
    super.key,
  });

  /// IANA id of the zone to display.
  final String zoneId;

  /// Renders `HH:mm:ss` instead of `HH:mm`.
  ///
  /// This does **not** speed the ticker up. The rate follows the global
  /// `showSeconds` preference, which the app applies once via
  /// [TickerService.setNeedsSeconds]; a per-widget claim would need reference
  /// counting and one widget forgetting to release it would pin the whole app
  /// at 1 Hz (see that method's contract).
  final bool showSeconds;

  /// Digit size. The style is always [AppTypography.clock].
  final double fontSize;

  /// Digit color. Defaults to the current palette's primary text token.
  final Color? color;

  /// Injected for tests; resolved from `GetIt` otherwise.
  final TickerService? ticker;

  /// Injected for tests; resolved from `GetIt` otherwise.
  final TimeZoneEngine? engine;

  /// Injected for tests; resolved from `GetIt` otherwise. Used only to seed the
  /// first frame, so the digits are correct before the first tick lands — at
  /// the minute rate that would otherwise be a blank clock for up to 59s.
  final Clock? clock;

  @override
  Widget build(BuildContext context) {
    final resolvedTicker = ticker ?? sl<TickerService>();
    final resolvedEngine = engine ?? sl<TimeZoneEngine>();
    final resolvedClock = clock ?? sl<Clock>();
    // Watched rather than read: a 12h/24h switch in settings must
    // repaint every clock on screen, and it lands between ticks.
    final hourFormat =
        context.watch<PreferencesCubit>().state.hourFormatOrDefault;
    final style = AppTypography.clock(
      color: color ?? context.appColors.onBackground,
      fontSize: fontSize,
    );

    // The StreamBuilder wraps the digits and nothing else. Anything above it —
    // the city label, the offset badge, the row itself — is static between
    // ticks and must not be rebuilt by one.
    return StreamBuilder<DateTime>(
      stream: resolvedTicker.stream,
      initialData: resolvedClock.nowUtc(),
      builder: (context, snapshot) {
        final utcInstant = snapshot.data;
        if (utcInstant == null) return const SizedBox.shrink();
        return Text(
          formatClock(
            resolvedEngine.wallTimeAt(zoneId: zoneId, instant: utcInstant),
            hourFormat,
            showSeconds: showSeconds,
          ),
          style: style,
        );
      },
    );
  }
}

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
import 'package:timebuddy/app/widgets/day_night_dot.dart';
import 'package:timebuddy/app/widgets/dst_badge.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/home_zone_banner.dart';
import 'package:timebuddy/app/widgets/lifted_fab.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/offset_badge.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/locations/presentation/board_actions.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_state_defaults.dart';
import 'package:timebuddy/features/world_clock/domain/entities/world_clock_view_model.dart';
import 'package:timebuddy/features/world_clock/domain/usecases/build_world_clock_usecase.dart';
import 'package:timebuddy/features/world_clock/presentation/cubit/world_clock_cubit.dart';
import 'package:timebuddy/features/world_clock/presentation/widgets/location_detail_sheet.dart';
import 'package:timebuddy/features/world_clock/presentation/widgets/world_clock_tile_view.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Placeholder rows while the board resolves. Five is roughly a phone screen,
/// so the real clocks land without the page jumping (design_system §8).
const int _loadingRowCount = 5;

/// Digit size of the hero clock (design_system: `displayLarge`, the hero clock
/// on the world-clock header).
const double _heroClockFontSize = 40;

/// The world clock: the user's own time, then every saved city ticking under
/// it (docs/specs/world_clock.md).
///
/// The "glance" view to the grid's "compare" view — same board, same engine,
/// different question. It creates its own [WorldClockCubit] per visit, because
/// it owns no persisted state (CLAUDE.md, Lifecycle).
class WorldClockPage extends StatelessWidget {
  const WorldClockPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<WorldClockCubit>(
      create: (context) => WorldClockCubit(
        boardCubit: context.read<BoardCubit>(),
        preferencesCubit: context.read<PreferencesCubit>(),
        buildWorldClock: sl<BuildWorldClockUseCase>(),
        engine: sl<TimeZoneEngine>(),
        clock: sl<Clock>(),
        ticker: sl<TickerService>(),
      )..start(),
      child: const _WorldClockView(),
    );
  }
}

/// The page itself, split from [WorldClockPage] so the lifecycle observer
/// lives below the provider and can reach the cubit.
class _WorldClockView extends StatefulWidget {
  const _WorldClockView();

  @override
  State<_WorldClockView> createState() => _WorldClockViewState();
}

class _WorldClockViewState extends State<_WorldClockView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Rule 10: a phone unlocked an hour after it was locked must not show the
  /// minute it was locked at.
  ///
  /// `inactive` is deliberately not a pause: iOS reports it for the app
  /// switcher and for a notification shade, and a clock that stopped every
  /// time a banner slid down would be wrong far more often than a backgrounded
  /// one.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cubit = context.read<WorldClockCubit>();
    if (state == AppLifecycleState.resumed) {
      cubit.onAppResumed();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      cubit.onAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched rather than read: turning seconds on in settings must repaint
    // every clock on screen, and it lands between ticks.
    final showSeconds =
        context.watch<PreferencesCubit>().state.showSecondsOrDefault;
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(title: t.worldClock.title, showBack: false),
      floatingActionButton: LiftedFab(
        child: FloatingActionButton(
          onPressed: () => context.push(AppRoutes.addLocation),
          tooltip: t.locations.addTitle,
          child: const AppIcon(FontAwesomeIcons.plus),
        ),
      ),
      body: BlocBuilder<WorldClockCubit, WorldClockState>(
        builder: (context, state) => _body(context, state, showSeconds),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WorldClockState state,
    bool showSeconds,
  ) => switch (state) {
    WorldClockLoading() => const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: LoadingShimmer(rowCount: _loadingRowCount),
    ),
    WorldClockError(:final failure) => ErrorView(
      failure: failure,
      onRetry: () => unawaited(context.read<BoardCubit>().load()),
    ),
    // No empty branch: an empty board is a valid Ready whose hero is the
    // user's own clock (rule 11).
    WorldClockReady(:final model) => _ready(context, model, showSeconds),
  };

  Widget _ready(
    BuildContext context,
    WorldClockViewModel model,
    bool showSeconds,
  ) {
    return ReorderableListView.builder(
      // Rule 2: the list *is* the board, so dragging here writes through
      // `BoardCubit.reorder` and this page holds no order of its own.
      //
      // No default handles: the platform's are an overlay pinned to the
      // trailing edge, which is exactly where the digits are. A delayed
      // listener gives press-and-hold to drag on every platform without
      // taking a pixel from the clock, and the tile's own `onTap` still
      // fires for a tap, since an InkWell without `onLongPress` never
      // claims the long press.
      buildDefaultDragHandles: false,
      header: _Header(
        model: model,
        showSeconds: showSeconds,
        onOpenHome: () => unawaited(
          _openDetail(
            context,
            tile: model.home,
            // Home is a zone id, not a row: there is nothing to remove
            // when the user never saved their own city (rule 11).
            canRemove: model.homeHasBoardRow,
            showSeconds: showSeconds,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        // The bar and the FAB float over this list, so the last clock
        // needs room to clear them (design_system §7).
        bottomSafeForFab(context, isSubPage: false),
      ),
      itemCount: model.tiles.length,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(context, oldIndex, newIndex),
      itemBuilder: (context, index) =>
          _tile(context, model.tiles[index], index, showSeconds),
    );
  }

  Widget _tile(
    BuildContext context,
    WorldClockTile tile,
    int index,
    bool showSeconds,
  ) {
    return ReorderableDelayedDragStartListener(
      // Keyed by the row's own id, not by its position: a reorder moves the
      // element, and a positional key would animate the wrong tile.
      key: ValueKey<String>(tile.location.id),
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: WorldClockTileView(
          tile: tile,
          showSeconds: showSeconds,
          onTap: () => unawaited(
            _openDetail(
              context,
              tile: tile,
              canRemove: true,
              showSeconds: showSeconds,
            ),
          ),
        ),
      ),
    );
  }

  void _reorder(BuildContext context, int oldIndex, int newIndex) {
    // `onReorderItem`, not the deprecated `onReorder`: it reports both indices
    // as final positions, so the board takes them as they are and there is no
    // off-by-one correction here to hide a bug in.
    if (newIndex == oldIndex) return;
    unawaited(
      reorderBoardRow(context, oldIndex: oldIndex, newIndex: newIndex),
    );
  }

  /// Rule 9: the sheet reports a choice and this page performs it, so every
  /// board mutation still goes through the one `BoardCubit`.
  Future<void> _openDetail(
    BuildContext context, {
    required WorldClockTile tile,
    required bool canRemove,
    required bool showSeconds,
  }) async {
    final action = await showLocationDetailSheet(
      context,
      tile: tile,
      // Resolved now rather than carried on the tile: the model may be up to a
      // minute old, and this answer is a binary search over tzdata, not
      // something worth recomputing for twenty rows every minute (rule 8).
      nextTransitionLocalTime: context
          .read<WorldClockCubit>()
          .nextTransitionLocalTime(tile.location.zoneId),
      canRemove: canRemove,
      showSeconds: showSeconds,
    );
    if (action == null) return;
    // The sheet was open across an await; a sync landing underneath may have
    // rebuilt the tile it was opened from.
    if (!context.mounted) return;
    switch (action) {
      case LocationDetailAction.setHome:
        // Home is a zone id, not a row (locations rule 3), so this leaves the
        // list untouched and only moves what every offset is measured from.
        unawaited(setBoardHome(context, tile.location.zoneId));
      case LocationDetailAction.remove:
        unawaited(removeLocationWithUndo(context, tile.location));
      case LocationDetailAction.openInGrid:
        context.go(AppRoutes.grid);
    }
  }
}

/// Everything above the list: the UTC warning when there is one, the hero, and
/// the invitation when the board is still empty.
class _Header extends StatelessWidget {
  const _Header({
    required this.model,
    required this.showSeconds,
    required this.onOpenHome,
  });

  final WorldClockViewModel model;
  final bool showSeconds;

  /// Opens the hero's detail sheet. Handed down rather than looked up, so this
  /// widget stays a pure function of the model.
  final VoidCallback onOpenHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.homeZoneUnresolved)
          const HomeZoneBanner(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
          ),
        _HomeHero(
          tile: model.home,
          showSeconds: showSeconds,
          onTap: onOpenHome,
        ),
        if (model.tiles.isEmpty) const _EmptyBoardInvitation(),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// Rule 1: the home clock leads, as a hero block distinct from the list.
///
/// Everyone reads their own time first, and every offset on the page is
/// measured from this one.
class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.tile,
    required this.showSeconds,
    required this.onTap,
  });

  final WorldClockTile tile;
  final bool showSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xl);
    // A Material for the same reason every card in this app is one: an InkWell
    // paints its ink on the nearest Material ancestor, and a plain coloured
    // box would swallow the ripple and leave the hero dead under the finger.
    return Material(
      color: context.appColors.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroIdentity(tile: tile, onDstTap: onTap),
              const SizedBox(height: AppSpacing.sm),
              ClockText(
                zoneId: tile.location.zoneId,
                showSeconds: showSeconds,
                fontSize: _heroClockFontSize,
              ),
              const SizedBox(height: AppSpacing.sm),
              _HeroFacts(tile: tile),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity({required this.tile, required this.onDstTap});

  final WorldClockTile tile;
  final VoidCallback onDstTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DayNightDot(band: tile.band),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            tile.location.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleMedium,
          ),
        ),
        if (tile.isDst) DstBadge(onTap: onDstTap),
      ],
    );
  }
}

/// The full date, the zone abbreviation and the distance from UTC (rule 1).
class _HeroFacts extends StatelessWidget {
  const _HeroFacts({required this.tile});

  final WorldClockTile tile;

  @override
  Widget build(BuildContext context) {
    final style = context.textTheme.bodyMedium?.copyWith(
      color: context.appColors.onBackgroundLight,
    );
    // A Wrap rather than a Row: three items of unpredictable width — a
    // localized date, an abbreviation that is four or five characters, and a
    // pill — cannot be made to fit a 320px phone by ellipsizing one of them.
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          formatDayMonth(
            tile.localTime,
            LocaleSettings.currentLocale.languageTag,
          ),
          style: style,
        ),
        Text(tile.abbreviation, style: style),
        OffsetBadge(offset: tile.offsetFromUtc),
      ],
    );
  }
}

/// Rule 11: an empty board still shows the home clock, with the invitation
/// under it rather than in place of it.
class _EmptyBoardInvitation extends StatelessWidget {
  const _EmptyBoardInvitation();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        children: [
          Text(
            t.worldClock.emptyTitle,
            textAlign: TextAlign.center,
            style: context.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            t.worldClock.emptyMessage,
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.appColors.onBackgroundLight,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton(
            onPressed: () => context.push(AppRoutes.addLocation),
            child: Text(t.worldClock.emptyCta),
          ),
        ],
      ),
    );
  }
}

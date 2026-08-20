import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/routes/app_shell.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/feature_empty_state.dart';
import 'package:timebuddy/app/widgets/lifted_fab.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_date_pill.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/domain/entities/grid_view_model.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_cubit.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_header_strip.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_now_marker.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_row_view.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Width of the pinned column below `600px` (time_grid.md, Responsive).
///
/// Narrower than `GridMetrics.labelColumnWidth` because on a phone every pixel
/// spent on the label is an hour column the user cannot see; `LocationRow`
/// drops its country line at this width rather than shrinking its type.
const double _denseLabelColumnWidth = 96;

/// Placeholder rows while the board resolves. Five is roughly a phone screen,
/// so the real rows land without the page jumping (design_system §8).
const int _loadingRowCount = 5;

/// Long enough to read as a move, short enough not to lag a held arrow key.
const Duration _revealDuration = Duration(milliseconds: 180);

/// The comparison grid: one row per saved location, one column per hour
/// (docs/specs/time_grid.md).
///
/// Creates its own [TimeGridCubit] per visit — the grid owns view state
/// (reference date, cursor) and nothing persisted, so there is no reason for
/// it to outlive the page (CLAUDE.md, Lifecycle).
class TimeGridPage extends StatelessWidget {
  const TimeGridPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TimeGridCubit>(
      create: (context) => TimeGridCubit(
        boardCubit: context.read<BoardCubit>(),
        preferencesCubit: context.read<PreferencesCubit>(),
        buildGrid: sl<BuildGridUseCase>(),
        engine: sl<TimeZoneEngine>(),
        clock: sl<Clock>(),
      )..start(),
      child: const _TimeGridView(),
    );
  }
}

/// The grid itself, split from [TimeGridPage] so the scroll controller lives
/// below the provider and can be read by everything that needs it.
class _TimeGridView extends StatefulWidget {
  const _TimeGridView();

  @override
  State<_TimeGridView> createState() => _TimeGridViewState();
}

class _TimeGridViewState extends State<_TimeGridView> {
  /// The track's scroll position, republished as a value every row and the
  /// "now" marker can listen to without touching the controller.
  final ValueNotifier<double> _hourOffset = ValueNotifier<double>(0);

  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'TimeGrid');

  /// The grid's one horizontal controller, owned by the header strip.
  ///
  /// Created on the first build that knows both the model and the viewport
  /// width, because rule 13 centres the initial offset on "now" and neither
  /// half of that sum is available before layout. Created *once*: a second
  /// controller would reset the user's scroll on every rebuild.
  ScrollController? _hourScroll;

  @override
  void dispose() {
    _hourScroll?.dispose();
    _hourOffset.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(title: t.grid.title, showBack: false),
      floatingActionButton: LiftedFab(
        child: FloatingActionButton(
          onPressed: () => context.push(AppRoutes.addLocation),
          tooltip: t.locations.addTitle,
          child: const Icon(Icons.add),
        ),
      ),
      body: BlocBuilder<TimeGridCubit, TimeGridState>(builder: _body),
    );
  }

  Widget _body(BuildContext context, TimeGridState state) => switch (state) {
    TimeGridLoading() => const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: LoadingShimmer(rowCount: _loadingRowCount),
    ),
    // An empty board is a valid state, not an error (locations rule 6), and it
    // renders the invitation rather than a header strip over nothing.
    TimeGridEmpty() => const _EmptyBoard(),
    TimeGridError(:final failure) => ErrorView(
      failure: failure,
      onRetry: context.read<BoardCubit>().load,
    ),
    TimeGridReady(:final model) => _ready(context, model),
  };

  Widget _ready(BuildContext context, GridViewModel model) {
    final dense = ResponsiveLayout.isMobile(context);
    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: (_, event) => _onKeyEvent(context, event, model),
      child: Column(
        children: [
          if (model.homeZoneUnresolved) const _HomeZoneBanner(),
          // Rendered unconditionally: `ShellDatePill` is what decides whether
          // the stepper stays here or goes to the sidebar, so the page cannot
          // get half of design_system §7 right and show two of them.
          _DateBar(referenceDate: model.referenceDate),
          Expanded(child: _grid(context, model, dense: dense)),
        ],
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    GridViewModel model, {
    required bool dense,
  }) {
    final labelWidth = dense
        ? _denseLabelColumnWidth
        : GridMetrics.labelColumnWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = math.max<double>(
          0,
          constraints.maxWidth - labelWidth,
        );
        final controller = _trackController(model, trackWidth);
        return Stack(
          children: [
            Column(
              children: [
                Row(
                  children: [
                    // The pinned column has no header of its own: the ruler
                    // above it belongs to the hour track.
                    SizedBox(width: labelWidth),
                    Expanded(
                      child: GridHeaderStrip(
                        slots: model.slots,
                        referenceZoneId: context
                            .read<TimeGridCubit>()
                            .referenceZoneId,
                        controller: controller,
                        cursorInstant: model.cursorInstant,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: _rows(
                    context,
                    model,
                    labelWidth: labelWidth,
                    dense: dense,
                  ),
                ),
              ],
            ),
            if (model.slots.isNotEmpty)
              Positioned(
                left: labelWidth,
                top: 0,
                right: 0,
                bottom: 0,
                child: GridNowMarker(
                  firstSlot: model.slots.first,
                  slotCount: model.slots.length,
                  horizontalOffset: _hourOffset,
                  color: context.appColors.primary,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _rows(
    BuildContext context,
    GridViewModel model, {
    required double labelWidth,
    required bool dense,
  }) {
    return GestureDetector(
      // Interaction: a horizontal drag over the cells moves the cursor. It
      // cannot fight the track's scrolling, because the only thing that
      // scrolls horizontally is the header strip.
      onHorizontalDragStart: (details) =>
          _cursorAt(context, details.localPosition.dx, labelWidth, model),
      onHorizontalDragUpdate: (details) =>
          _cursorAt(context, details.localPosition.dx, labelWidth, model),
      child: ListView.builder(
        // The floating bar and the FAB both paint over this list, so the last
        // row has to clear them (design_system §7).
        padding: EdgeInsets.only(
          bottom: bottomSafeForFab(context, isSubPage: false),
        ),
        // Constant across breakpoints (time_grid.md, Responsive), which also
        // lets the viewport skip straight to a row instead of measuring.
        itemExtent: GridMetrics.rowHeight,
        itemCount: model.rows.length,
        itemBuilder: (context, index) => _row(
          context,
          model.rows[index],
          cursorInstant: model.cursorInstant,
          labelWidth: labelWidth,
          dense: dense,
        ),
      ),
    );
  }

  /// One row: its identity block, then its hours.
  ///
  /// Both halves live in the same list item, which is what pins the label
  /// column. It scrolls vertically with its own row and cannot scroll
  /// horizontally at all, because nothing inside the item is a horizontal
  /// `Scrollable`.
  Widget _row(
    BuildContext context,
    GridRow row, {
    required DateTime? cursorInstant,
    required double labelWidth,
    required bool dense,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: labelWidth,
          child: LocationRow(
            location: row.location,
            isHome: row.isHome,
            isUnresolved: row.isUnresolved,
            // Resolved for the day being shown, not for "now": stepping the
            // reference date onto the far side of a transition has to move
            // the badge with it (timezone_engine rule 2).
            abbreviation: row.zoneState?.abbreviation,
            relativeToHome: row.relativeToHome,
            dense: dense,
          ),
        ),
        Expanded(
          child: GridRowView(
            row: row,
            horizontalOffset: _hourOffset,
            cursorInstant: cursorInstant,
            onCellTap: context.read<TimeGridCubit>().setCursor,
          ),
        ),
      ],
    );
  }

  /// The grid's single horizontal controller, created on first use.
  ///
  /// Seeding [_hourOffset] here is safe despite running inside `build`: it
  /// happens on the one build where no row is listening yet, since the rows
  /// below subscribe from their own `initState` later in the same frame.
  ScrollController _trackController(
    GridViewModel model,
    double viewportWidth,
  ) {
    final existing = _hourScroll;
    if (existing != null) return existing;
    final initialOffset = _centreOnNowOffset(model, viewportWidth);
    _hourOffset.value = initialOffset;
    return _hourScroll = ScrollController(initialScrollOffset: initialOffset)
      ..addListener(_publishOffset);
  }

  void _publishOffset() {
    final controller = _hourScroll;
    if (controller == null || !controller.hasClients) return;
    _hourOffset.value = controller.offset;
  }

  /// Rule 13: opening the grid puts the current instant in the middle of the
  /// viewport, not at column 0.
  ///
  /// Measured in fractional columns from the window's first slot, so it lands
  /// on the same position the "now" marker paints rather than on the start of
  /// the current hour.
  double _centreOnNowOffset(GridViewModel model, double viewportWidth) {
    if (model.slots.isEmpty || viewportWidth <= 0) return 0;
    final elapsed = model.nowInstant.difference(model.slots.first);
    final columns =
        elapsed.inMicroseconds / BuildGridUseCase.slotDuration.inMicroseconds;
    final nowCentre = columns * GridMetrics.hourColumnWidth;
    final contentWidth = model.slots.length * GridMetrics.hourColumnWidth;
    final maxOffset = math.max<double>(0, contentWidth - viewportWidth);
    return math.min<double>(
      math.max<double>(nowCentre - viewportWidth / 2, 0),
      maxOffset,
    );
  }

  void _cursorAt(
    BuildContext context,
    double localDx,
    double labelWidth,
    GridViewModel model,
  ) {
    final trackDx = localDx - labelWidth;
    if (trackDx < 0) return;
    final index =
        ((_hourOffset.value + trackDx) / GridMetrics.hourColumnWidth).floor();
    if (index < 0 || index >= model.slots.length) return;
    context.read<TimeGridCubit>().setCursor(model.slots[index]);
  }

  KeyEventResult _onKeyEvent(
    BuildContext context,
    KeyEvent event,
    GridViewModel model,
  ) {
    // Repeats are honoured so a held arrow key walks the cursor.
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveCursor(context, model, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveCursor(context, model, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _cursorToNow(context, model);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveCursor(BuildContext context, GridViewModel model, int delta) {
    final cursor = model.cursorInstant;
    // With no cursor yet the arrows start at now: that is where the user is
    // looking, and column 0 is three hours into yesterday (rule 3). On a
    // reference day that is not today there is no now column, so the middle
    // of the window stands in rather than the key doing nothing.
    if (cursor == null) {
      final nowIndex = _indexOf(model, sl<Clock>().nowUtc());
      final start = nowIndex >= 0 ? nowIndex : model.slots.length ~/ 2;
      _cursorToIndex(context, model, start);
      return;
    }
    final current = _indexOf(model, cursor);
    if (current < 0) return;
    _cursorToIndex(context, model, current + delta);
  }

  /// `Home`: the cursor goes back to the current instant (rule 8).
  ///
  /// Read from the [Clock] rather than from `model.nowInstant`, and pushed
  /// back into the model with `tick`: the marker keeps its own time so the
  /// grid does not rebuild once a minute, which leaves the model's copy as old
  /// as the last real rebuild.
  void _cursorToNow(BuildContext context, GridViewModel model) {
    final cubit = context.read<TimeGridCubit>();
    final nowUtc = sl<Clock>().nowUtc();
    cubit.tick(nowUtc);
    final index = _indexOf(model, nowUtc);
    if (index >= 0) {
      _cursorToIndex(context, model, index);
      return;
    }
    // Now is outside the window entirely, which is what stepping the date
    // does. "Back to now" then means today as well as this hour.
    cubit
      ..goToToday()
      ..setCursor(nowUtc);
  }

  void _cursorToIndex(BuildContext context, GridViewModel model, int index) {
    if (index < 0 || index >= model.slots.length) return;
    context.read<TimeGridCubit>().setCursor(model.slots[index]);
    _revealColumn(index);
  }

  /// Scrolls the track just far enough to bring column [index] into view.
  void _revealColumn(int index) {
    final controller = _hourScroll;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final left = index * GridMetrics.hourColumnWidth;
    final right = left + GridMetrics.hourColumnWidth;
    var target = position.pixels;
    if (left < position.pixels) target = left;
    if (right > position.pixels + position.viewportDimension) {
      target = right - position.viewportDimension;
    }
    if (target == position.pixels) return;

    controller.animateTo(
      math.min<double>(
        math.max<double>(target, position.minScrollExtent),
        position.maxScrollExtent,
      ),
      duration: _revealDuration,
      curve: Curves.easeOut,
    );
  }

  /// Index of the column whose hour holds [instant], or `-1` when it falls
  /// outside the window.
  int _indexOf(GridViewModel model, DateTime instant) {
    for (var index = 0; index < model.slots.length; index++) {
      final slot = model.slots[index];
      final slotEnd = slot.add(BuildGridUseCase.slotDuration);
      if (!instant.isBefore(slot) && instant.isBefore(slotEnd)) return index;
    }
    return -1;
  }
}

/// The first-run invitation, shown instead of an empty grid.
class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return FeatureEmptyState(
      icon: Icons.public_outlined,
      title: t.grid.emptyTitle,
      message: t.grid.emptyMessage,
      ctaLabel: t.grid.emptyCta,
      onCta: () => context.push(AppRoutes.addLocation),
    );
  }
}

/// Says out loud that the columns are lined up to UTC rather than to the
/// user's own zone (time_grid.md, home-zone edge case).
///
/// Not a snackbar: the condition lasts until the user picks a home city, and a
/// warning they can lose by scrolling is not a warning. Tapping it goes to the
/// board, because that is where the home zone is set.
class _HomeZoneBanner extends StatelessWidget {
  const _HomeZoneBanner();

  static const double _tintAlpha = 0.12;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.md);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Material(
        color: colors.warning.withValues(alpha: _tintAlpha),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => context.go(AppRoutes.locations),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: _iconSize,
                  color: colors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    t.grid.homeZoneBrokenBanner,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: colors.onBackground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The reference-day stepper, placed by the breakpoint.
///
/// `ShellDatePill` renders it here below `600px` and publishes it into the
/// sidebar above that (design_system §7). It still takes a row of layout on
/// mobile only, which is why the padding lives inside the pill branch.
class _DateBar extends StatelessWidget {
  const _DateBar({required this.referenceDate});

  final DateTime referenceDate;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TimeGridCubit>();
    return ShellDatePill(
      pill: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TimeBuddyDatePill(
            value: referenceDate,
            // "Today" is a question about the home zone, never about the
            // device (rule 11): a user whose home is Tokyo is already on
            // tomorrow.
            today: cubit.todayInHomeZone,
            todayLabel: t.grid.today,
            onChanged: cubit.setReferenceDate,
          ),
        ),
      ),
    );
  }
}

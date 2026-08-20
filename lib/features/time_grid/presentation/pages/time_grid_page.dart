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
import 'package:timebuddy/app/widgets/timebuddy_pill_toggle.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/build_meeting_summary_usecase.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/find_best_slot_usecase.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/format_meeting_text_usecase.dart';
import 'package:timebuddy/features/meeting_planner/presentation/cubit/meeting_planner_cubit.dart';
import 'package:timebuddy/features/meeting_planner/presentation/widgets/meeting_summary_panel.dart';
import 'package:timebuddy/features/meeting_planner/presentation/widgets/planner_selection_overlay.dart';
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

/// Width of the Compare / Plan toggle in the app bar.
///
/// A fixed width because `TimeBuddyPillToggle` lays its options out in equal
/// `Expanded` shares and an `AppBar` action is measured with an unbounded
/// width, which those shares cannot divide. Sized for the widest pair of
/// labels either locale ships — pt-BR `Comparar` / `Planejar` at `labelLarge`
/// — so neither segment ellipses; the app-bar title takes the difference and
/// already ellipses by design.
const double _modeToggleWidth = 144;

/// What the grid's columns are for right now
/// (docs/specs/meeting_planner.md).
///
/// Page state and not a route, because the planner **is** the grid: same
/// rows, same columns, same engine, with the cursor turned into a range. The
/// mode owns the `MeetingPlannerCubit`'s lifetime — entering builds it,
/// leaving disposes it — so there is no way to be in plan mode without a
/// planner, or to leave one behind holding a selection nothing is drawing.
enum _GridMode {
  /// One cursor, one hour: the M2 grid (docs/specs/time_grid.md).
  compare,

  /// A drag selects a range and the summary panel opens on it.
  plan,
}

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

  /// Keeps the grid's *elements* when the planner provider appears above
  /// them.
  ///
  /// Entering plan mode changes `Scaffold.body` from the grid to a
  /// `BlocProvider` wrapping the same grid, and a different widget type in
  /// that slot means Flutter rebuilds everything under it: the header strip
  /// would get a fresh `ScrollPosition` seeded from `initialScrollOffset`, so
  /// the hour track would jump back to the column it was first centred on and
  /// the row list back to its first row. A `GlobalKey` reparents the subtree
  /// instead of re-inflating it, which is the one thing it is for.
  final GlobalKey _gridKey = GlobalKey(debugLabel: 'TimeGridBody');

  /// Compare or plan. Held here rather than in a cubit because it decides
  /// which cubits exist: the planner is created and disposed by the mode.
  _GridMode _mode = _GridMode.compare;

  bool get _planning => _mode == _GridMode.plan;

  @override
  void dispose() {
    _hourScroll?.dispose();
    _hourOffset.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = BlocBuilder<TimeGridCubit, TimeGridState>(
      key: _gridKey,
      builder: _body,
    );
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(
        title: t.grid.title,
        showBack: false,
        actions: [_ModeToggle(mode: _mode, onChanged: _setMode)],
      ),
      // No "add a city" while planning: the planner is a read-only consumer
      // of the board (meeting_planner.md rule 11), and the summary panel
      // occupies exactly the corner the FAB floats in.
      floatingActionButton: _planning
          ? null
          : LiftedFab(
              child: FloatingActionButton(
                onPressed: () => context.push(AppRoutes.addLocation),
                tooltip: t.locations.addTitle,
                child: const Icon(Icons.add),
              ),
            ),
      // The planner is provided *around* the grid rather than inside it so
      // every context below — the drag handlers, the band overlay, the panel
      // — reads the same cubit. It takes `TimeGridCubit` as a collaborator,
      // so it has to be built under `TimeGridPage`'s provider, which is where
      // this widget already sits.
      body: _planning
          ? BlocProvider<MeetingPlannerCubit>(
              create: _createPlanner,
              child: grid,
            )
          : grid,
    );
  }

  /// Builds the planner for the mode it is entered in, and disposes it with
  /// the mode (docs/specs/meeting_planner.md, State Machine).
  MeetingPlannerCubit _createPlanner(BuildContext context) {
    return MeetingPlannerCubit(
      boardCubit: context.read<BoardCubit>(),
      preferencesCubit: context.read<PreferencesCubit>(),
      gridCubit: context.read<TimeGridCubit>(),
      buildSummary: sl<BuildMeetingSummaryUseCase>(),
      findBestSlot: sl<FindBestSlotUseCase>(),
      formatText: sl<FormatMeetingTextUseCase>(),
      engine: sl<TimeZoneEngine>(),
    )..start();
  }

  void _setMode(_GridMode mode) {
    if (mode == _mode) return;
    // Leaving plan mode disposes the planner and with it the selection; the
    // grid's own cursor is untouched by either mode, so switching back and
    // forth lands the user where they were looking.
    setState(() => _mode = mode);
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
      child: Stack(
        children: [
          Column(
            children: [
              if (model.homeZoneUnresolved) const _HomeZoneBanner(),
              // Rendered unconditionally: `ShellDatePill` is what decides
              // whether the stepper stays here or goes to the sidebar, so the
              // page cannot get half of design_system §7 right and show two
              // of them.
              _DateBar(referenceDate: model.referenceDate),
              Expanded(child: _grid(context, model, dense: dense)),
            ],
          ),
          // One child for both breakpoints and all three planner states:
          // `MeetingSummaryPanel` is a bottom sheet below `900px` and a
          // trailing-edge panel above it, and it aligns itself either way, so
          // the page drops it in the stack rather than repeating the
          // breakpoint. It only hit-tests its own surface, which is what
          // leaves the rows underneath still draggable.
          //
          // `Positioned.fill` and not a bare child: the sheet is a
          // `DraggableScrollableSheet(expand: false)`, which bottom-aligns
          // itself *inside the box it is given*. A loose stack child sizes to
          // that sheet's 45%, and the summary would open across the top of
          // the grid instead of the bottom — the modal route it normally
          // lives in is what usually supplies these constraints.
          if (_planning) const Positioned.fill(child: _PlannerPanel()),
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
            // Last in the stack, so the wash covers the cells and the "now"
            // line alike: at 16% alpha the hairline still reads through it,
            // and a selection that stopped at the marker would look like two
            // ranges with a gap.
            if (_planning && model.slots.isNotEmpty)
              Positioned(
                left: labelWidth,
                top: 0,
                right: 0,
                bottom: 0,
                child: BlocBuilder<MeetingPlannerCubit, MeetingPlannerState>(
                  builder: (context, planner) => PlannerSelectionOverlay(
                    slots: model.slots,
                    selection: planner.activeSelection,
                    horizontalOffset: _hourOffset,
                    color: context.appColors.primary,
                  ),
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
      // Interaction: a horizontal drag over the cells moves the cursor in
      // compare mode and grows the meeting range in plan mode. It cannot
      // fight the track's scrolling, because the only thing that scrolls
      // horizontally is the header strip.
      onHorizontalDragStart: (details) =>
          _dragStart(context, details.localPosition.dx, labelWidth, model),
      onHorizontalDragUpdate: (details) =>
          _dragUpdate(context, details.localPosition.dx, labelWidth, model),
      // Only the planner cares where a drag ended: that is what turns a range
      // into a summary (meeting_planner.md, State Machine). Left null in
      // compare mode so the cursor keeps costing one gesture arena entry
      // fewer.
      onHorizontalDragEnd: _planning
          ? (_) => context.read<MeetingPlannerCubit>().endSelection()
          : null,
      child: ListView.builder(
        // The floating bar and the FAB both paint over this list, so the last
        // row has to clear them (design_system §7). Planner mode retires the
        // FAB, so it clears the bar alone and the summary sheet gets the 72pt
        // back — it is draggable, and the rows behind it are what the next
        // selection is made on.
        padding: EdgeInsets.only(
          bottom: _planning
              ? bottomSafeForBar(context, isSubPage: false)
              : bottomSafeForFab(context, isSubPage: false),
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
            // A tap is a one-slot meeting while planning, which rule 3's
            // floor makes a valid one rather than a degenerate drag.
            onCellTap: _planning
                ? context.read<MeetingPlannerCubit>().selectSlot
                : context.read<TimeGridCubit>().setCursor,
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

  /// The column instant under [localDx], or `null` when the pointer is over
  /// the pinned label column or past the last hour of the window.
  DateTime? _slotAt(double localDx, double labelWidth, GridViewModel model) {
    final trackDx = localDx - labelWidth;
    if (trackDx < 0) return null;
    final index =
        ((_hourOffset.value + trackDx) / GridMetrics.hourColumnWidth).floor();
    if (index < 0 || index >= model.slots.length) return null;
    return model.slots[index];
  }

  /// A drag beginning: the cursor jumps to that hour, or the meeting anchors
  /// on it.
  ///
  /// Start and continuation are separate handlers because the planner needs
  /// the difference — the anchor is what rule 3's twelve-slot cap is measured
  /// from, so an `extendTo` that had silently re-anchored would let a long
  /// drag walk the range across the whole day a slot at a time.
  void _dragStart(
    BuildContext context,
    double localDx,
    double labelWidth,
    GridViewModel model,
  ) {
    final slot = _slotAt(localDx, labelWidth, model);
    if (slot == null) return;
    if (_planning) {
      context.read<MeetingPlannerCubit>().startSelection(slot);
      return;
    }
    context.read<TimeGridCubit>().setCursor(slot);
  }

  /// The same drag continuing: the cursor follows the finger, or the range
  /// grows to it.
  void _dragUpdate(
    BuildContext context,
    double localDx,
    double labelWidth,
    GridViewModel model,
  ) {
    final slot = _slotAt(localDx, labelWidth, model);
    if (slot == null) return;
    if (_planning) {
      context.read<MeetingPlannerCubit>().extendTo(slot);
      return;
    }
    context.read<TimeGridCubit>().setCursor(slot);
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

/// Compare / Plan, in the app bar's action slot
/// (docs/specs/meeting_planner.md, UI).
///
/// Width-pinned because an app-bar action is measured unbounded and
/// `TimeBuddyPillToggle` divides its width into equal segments; see
/// [_modeToggleWidth].
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _GridMode mode;
  final ValueChanged<_GridMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.lg),
      child: Center(
        child: SizedBox(
          width: _modeToggleWidth,
          child: TimeBuddyPillToggle<_GridMode>(
            options: [
              PillOption(
                value: _GridMode.compare,
                label: t.planner.modeCompare,
              ),
              PillOption(value: _GridMode.plan, label: t.planner.modePlan),
            ],
            selected: mode,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// The summary panel, wired to the planner that owns the selection.
///
/// A widget rather than a closure in `_ready` so the `BlocBuilder` rebuilds
/// the panel alone: a selection settling would otherwise rebuild the grid's
/// rows, which is the one thing the overlay's painter exists to avoid.
class _PlannerPanel extends StatelessWidget {
  const _PlannerPanel();

  @override
  Widget build(BuildContext context) {
    final planner = context.read<MeetingPlannerCubit>();
    return BlocBuilder<MeetingPlannerCubit, MeetingPlannerState>(
      builder: (context, state) => MeetingSummaryPanel(
        state: state,
        onTextStyleChanged: planner.setTextStyle,
        onCopy: planner.copy,
        onApplySuggestion: planner.applySuggestion,
        onClear: planner.clear,
      ),
    );
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

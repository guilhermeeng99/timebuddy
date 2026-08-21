import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/home_zone_banner.dart';
import 'package:timebuddy/app/widgets/lifted_fab.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/location_row.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/presentation/board_actions.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_grid/domain/entities/grid_view_model.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_cubit.dart';
import 'package:timebuddy/features/time_grid/presentation/grid_layout.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_date_bar.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_empty_board.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_header_strip.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_now_marker.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_row_label_handle.dart';
import 'package:timebuddy/features/time_grid/presentation/widgets/grid_row_view.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Placeholder rows while the board resolves. Five is roughly a phone screen,
/// so the real rows land without the page jumping (design_system §8).
const int _loadingRowCount = 5;

/// Long enough to read as a move, short enough not to lag a held arrow key.
const Duration _revealDuration = Duration(milliseconds: 180);

/// How far the track may sit from its rescaled position before a resize
/// bothers to correct it. Half a pixel is below anything a user can see and
/// above the rounding a `track / columns` division leaves behind.
const double _offsetEpsilon = 0.5;

/// The comparison grid: one row per saved location, one column per hour
/// (docs/specs/time_grid.md).
///
/// **It compares, and that is all it does.** It carried a Compare / Plan
/// toggle that turned the same rows and columns into a meeting planner. The
/// toggle went first, then the mode, and finally the feature itself: a folder
/// with 47 green tests and no entry point is not an asset, it is a second
/// answer to "what does this screen do" that every future reader has to rule
/// out.
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

  /// The geometry the last layout resolved, kept so the handlers that have
  /// no `BoxConstraints` in scope — the arrow keys, the cursor drag — can turn
  /// pixels into hours the same way the painters do.
  ///
  /// One frame stale after a resize, which is harmless: the value it is stale
  /// against is corrected in the same post-frame callback that rescales the
  /// scroll offset.
  GridLayout? _layout;

  /// The grid's one horizontal controller, owned by the header strip.
  ///
  /// Created on the first build that knows both the model and the viewport
  /// width, because rule 13 centres the initial offset on "now" and neither
  /// half of that sum is available before layout. Created *once*: a second
  /// controller would reset the user's scroll on every rebuild.
  ScrollController? _hourScroll;

  /// The pan in flight over the cells, or `null` between drags.
  ///
  /// A [Drag] handed out by the track's own `ScrollPosition` rather than a
  /// `jumpTo` loop of our own: it is the same object a `Scrollable` would
  /// hold, so the cells inherit the platform's physics — the fling after the
  /// finger lifts, the clamp at both ends, the overscroll indicator — instead
  /// of a linear scrub that stops dead on release.
  Drag? _trackDrag;

  @override
  void dispose() {
    // The position outlives nothing here, but a `Drag` left open would keep a
    // dragging activity on a controller about to be torn down.
    _trackDrag?.cancel();
    _hourScroll?.dispose();
    _hourOffset.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = BlocBuilder<TimeGridCubit, TimeGridState>(builder: _body);
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(title: t.grid.title, showBack: false),
      floatingActionButton: LiftedFab(
        child: FloatingActionButton(
          onPressed: () => context.push(AppRoutes.addLocation),
          tooltip: t.locations.addTitle,
          child: const AppIcon(FontAwesomeIcons.plus),
        ),
      ),
      body: grid,
    );
  }

  Widget _body(BuildContext context, TimeGridState state) => switch (state) {
    TimeGridLoading() => const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: LoadingShimmer(rowCount: _loadingRowCount),
    ),
    // An empty board is a valid state, not an error (locations rule 6), and it
    // renders the invitation rather than a header strip over nothing.
    TimeGridEmpty() => const GridEmptyBoard(),
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
          if (model.homeZoneUnresolved)
            const HomeZoneBanner(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
            ),
          // Rendered unconditionally: `ShellDatePill` is what decides whether
          // the stepper stays here or goes to the sidebar, so the page cannot
          // get half of design_system §7 right and show two of them.
          GridDateBar(referenceDate: model.referenceDate),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Resolved from the box the grid actually got, never from the window:
        // behind the rail those differ by up to 240pt, and the whole point of
        // the fluid column is that it answers to the space it has.
        final layout = GridLayout.resolve(
          availableWidth: constraints.maxWidth,
          slotCount: model.slots.length,
          dense: dense,
        );
        final previous = _layout;
        _layout = layout;
        final controller = _trackController(model, layout);
        if (previous != null && previous != layout) {
          _syncTrackAfterResize(previous, layout, model.slots.length);
        }
        return Stack(
          children: [
            Column(
              children: [
                Row(
                  children: [
                    // The pinned column has no header of its own: the ruler
                    // above it belongs to the hour track.
                    SizedBox(width: layout.labelColumnWidth),
                    Expanded(
                      child: GridHeaderStrip(
                        slots: model.slots,
                        referenceZoneId: context
                            .read<TimeGridCubit>()
                            .referenceZoneId,
                        columnWidth: layout.hourColumnWidth,
                        controller: controller,
                        onColumnTap: context.read<TimeGridCubit>().setCursor,
                        cursorInstant: model.cursorInstant,
                      ),
                    ),
                  ],
                ),
                Expanded(child: _rows(context, model, layout, dense: dense)),
              ],
            ),
            if (model.slots.isNotEmpty)
              Positioned(
                left: layout.labelColumnWidth,
                top: 0,
                right: 0,
                bottom: 0,
                child: GridNowMarker(
                  firstSlot: model.slots.first,
                  slotCount: model.slots.length,
                  columnWidth: layout.hourColumnWidth,
                  horizontalOffset: _hourOffset,
                  color: context.appColors.primary,
                ),
              ),
            // Last in the stack, so the wash covers the cells and the "now"
            // line alike: at 16% alpha the hairline still reads through it,
            // and a selection that stopped at the marker would look like two
            // ranges with a gap.
          ],
        );
      },
    );
  }

  Widget _rows(
    BuildContext context,
    GridViewModel model,
    GridLayout layout, {
    required bool dense,
  }) {
    return GestureDetector(
      // Interaction: a horizontal drag over the cells pans the hour track.
      // The rows are not `Scrollable`s and cannot become them without giving
      // each its own position, so the drag is forwarded to the one position
      // that exists — the header's (docs/specs/time_grid.md rule 16).
      onHorizontalDragStart: _trackDragStart,
      onHorizontalDragUpdate: (details) => _trackDrag?.update(details),
      onHorizontalDragEnd: _trackDragEnd,
      onHorizontalDragCancel: _trackDragCancel,
      // Reorderable since the board lost the page that used to own its order
      // (docs/specs/time_grid.md, Interaction). The lift lives on the pinned
      // label column, which is the one part of a row that owns no horizontal
      // gesture: the pan below refuses a drag that starts left of
      // `labelColumnWidth`, so the two never enter the same arena.
      child: ReorderableListView.builder(
        // The label column is the handle. The default one is an overlay
        // pinned to the trailing edge, which here would land on top of the
        // hour cells and fight the cursor for the same pixels.
        buildDefaultDragHandles: false,
        // The floating bar and the FAB both paint over this list, so the last
        // row has to clear them (design_system §7).
        padding: EdgeInsets.only(
          bottom: bottomSafeForFab(context, isSubPage: false),
        ),
        // Constant across breakpoints (time_grid.md, Responsive), which also
        // lets the viewport skip straight to a row instead of measuring.
        itemExtent: GridMetrics.rowHeight,
        itemCount: model.rows.length,
        onReorderItem: (oldIndex, newIndex) => unawaited(
          reorderBoardRow(context, oldIndex: oldIndex, newIndex: newIndex),
        ),
        itemBuilder: (context, index) => _row(
          context,
          model.rows[index],
          layout,
          index: index,
          cursorInstant: model.cursorInstant,
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
    GridRow row,
    GridLayout layout, {
    required int index,
    required DateTime? cursorInstant,
    required bool dense,
  }) {
    // A hairline under every row, and it is load-bearing now rather than
    // decoration: the comfortable cell fills its column edge to edge, so
    // without a rule four rows of contiguous fills read as one block of colour
    // instead of four cities.
    return DecoratedBox(
      key: ValueKey<String>(row.location.id),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.appColors.surfaceVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: layout.labelColumnWidth,
            // Both of the row's own gestures, and the only two it has: drag to
            // move it, tap to open its actions. The hours to the right keep the
            // cursor drag they always had.
            child: GridRowLabelHandle(
              index: index,
              onTap: () => unawaited(
                openLocationRowActions(
                  context,
                  location: row.location,
                  isHome: row.isHome,
                ),
              ),
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
          ),
          Expanded(
            child: GridRowView(
              row: row,
              columnWidth: layout.hourColumnWidth,
              horizontalOffset: _hourOffset,
              cursorInstant: cursorInstant,
            ),
          ),
        ],
      ),
    );
  }

  /// The grid's single horizontal controller, created on first use.
  ///
  /// Seeding [_hourOffset] here is safe despite running inside `build`: it
  /// happens on the one build where no row is listening yet, since the rows
  /// below subscribe from their own `initState` later in the same frame.
  ScrollController _trackController(GridViewModel model, GridLayout layout) {
    final existing = _hourScroll;
    if (existing != null) return existing;
    final initialOffset = _centreOnNowOffset(model, layout);
    _hourOffset.value = initialOffset;
    return _hourScroll = ScrollController(initialScrollOffset: initialOffset)
      ..addListener(_publishOffset);
  }

  void _publishOffset() {
    final controller = _hourScroll;
    if (controller == null || !controller.hasClients) return;
    _hourOffset.value = controller.offset;
  }

  /// Keeps the track on the hour the user was reading when the window changed
  /// size, and re-publishes the offset the rows draw from.
  ///
  /// **Two separate repairs, and both are needed.**
  ///
  /// The first is the resize itself: a `ScrollPosition` stores pixels, and a
  /// pixel stopped meaning a fixed hour the moment the column width became a
  /// function of the viewport. Offset 600 is column 10 at 60pt and column 12.5
  /// at 48pt, so without converting through [GridLayout.columnOf] a user
  /// dragging their window edge would watch the grid scrub through time.
  ///
  /// The second is a guard, and it is worth being precise about how much work
  /// it does. When a relayout shrinks `maxScrollExtent` the framework clamps
  /// the position through `correctPixels`, which assigns the field directly
  /// and notifies nobody; [_publishOffset] is a controller *listener*, so it
  /// would never run and `_hourOffset` would keep the pre-resize value while
  /// the header painted at the corrected one. In practice the `jumpTo` above
  /// almost always fires first and notifies for it — a track that changed
  /// width changed the column width with it, so the rescaled target is rarely
  /// within [_offsetEpsilon] of where the clamp left the position. Publishing
  /// unconditionally afterwards costs one assignment and removes the need to
  /// reason about which of the two got there first; a mutation test confirms
  /// the `jumpTo` is what the suite actually catches.
  void _syncTrackAfterResize(
    GridLayout previous,
    GridLayout next,
    int slotCount,
  ) {
    final column = previous.columnOf(_hourOffset.value);
    // Post-frame rather than here: by this point every row's
    // `ValueListenableBuilder` is subscribed, so writing `_hourOffset` during
    // build would mark them dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _hourScroll;
      if (!mounted || controller == null || !controller.hasClients) return;
      final target = next.offsetOfColumn(column, slotCount);
      if ((controller.offset - target).abs() > _offsetEpsilon) {
        controller.jumpTo(target);
      }
      _publishOffset();
    });
  }

  /// Rule 13: opening the grid puts the current instant in the middle of the
  /// viewport, not at column 0.
  ///
  /// Measured in fractional columns from the window's first slot, so it lands
  /// on the same position the "now" marker paints rather than on the start of
  /// the current hour.
  /// A no-op on a screen wide enough to hold the whole window, and that is
  /// the rule working rather than failing: there is no scrolling to do when
  /// every hour is already on screen.
  double _centreOnNowOffset(GridViewModel model, GridLayout layout) {
    if (model.slots.isEmpty || layout.trackWidth <= 0) return 0;
    final elapsed = model.nowInstant.difference(model.slots.first);
    final columns =
        elapsed.inMicroseconds / BuildGridUseCase.slotDuration.inMicroseconds;
    final halfViewport = layout.trackWidth / 2 / layout.hourColumnWidth;
    return layout.offsetOfColumn(columns - halfViewport, model.slots.length);
  }

  /// A pan beginning over the cells: the track's position takes the drag.
  ///
  /// Refused left of the pinned column, which owns the row lift. Everything
  /// else about the gesture — direction, slop, who wins the arena against the
  /// vertical list — is the recognizer's job, not this method's.
  void _trackDragStart(DragStartDetails details) {
    final layout = _layout;
    final controller = _hourScroll;
    if (layout == null || controller == null || !controller.hasClients) return;
    if (details.localPosition.dx < layout.labelColumnWidth) return;
    _trackDrag = controller.position.drag(details, _forgetTrackDrag);
  }

  /// The finger lifted: the position keeps going under its own physics.
  void _trackDragEnd(DragEndDetails details) => _trackDrag?.end(details);

  /// The arena took the gesture back before it ended.
  void _trackDragCancel() => _trackDrag?.cancel();

  /// The position finished with the drag and is about to dispose it.
  ///
  /// Drops the reference and **does nothing else**: this runs from inside
  /// `ScrollDragController.dispose`, so ending it again here would re-enter
  /// the disposal it was called from and recurse until the stack gave out.
  /// `end` and `cancel` above are what finish a drag; this only forgets it.
  void _forgetTrackDrag() => _trackDrag = null;

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
    final layout = _layout;
    if (controller == null || layout == null || !controller.hasClients) return;
    final position = controller.position;
    final left = layout.columnLeft(index);
    final right = left + layout.hourColumnWidth;
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

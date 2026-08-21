import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/sidebar_profile_tile.dart';
import 'package:timebuddy/app/widgets/timebuddy_bottom_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_sidebar.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:uuid/uuid.dart';

/// The chrome every primary destination renders inside, and the one place the
/// board is loaded.
///
/// **Layout** follows design_system §7 and nothing else decides it: at
/// `>= 600px` a [TimeBuddySidebar] sits beside the content and owns the date
/// stepper; below that a floating [TimeBuddyBottomBar] hangs over the content
/// and the page surfaces its own stepper. Both widgets render nothing on the
/// wrong side of the breakpoint, so the shell places them unconditionally and
/// the breakpoint is decided once, in each widget, rather than twice here.
///
/// **Why the board is loaded here.** `BoardCubit` is session-scoped
/// (CLAUDE.md, Lifecycle): it is created by this route through `BlocProvider`
/// and disposed with it, so it is not a `GetIt` singleton and `main` has
/// nowhere to hold it. The shell is the only widget that is an ancestor of
/// every page that reads the board *and* is built exactly once per session, so
/// it is the earliest honest point for the load. Doing it in the grid page
/// instead would re-run on every visit and would leave the locations page
/// loading the same document a second time, which is two answers to "is the
/// board ready". `StartupCubit` reconciles the *documents* before the router
/// leaves `/startup` (docs/specs/startup.md), so the load below reads an
/// already-synced board; it deliberately does not own the cubit, because the
/// board's lifetime is the shell's and the startup flow outlives no session.
///
/// From M4 the shell hosts five branches, and one `BoardCubit` above all of
/// them is the whole point: the grid, the world clock and the converter read
/// the same list of places, and an `IndexedStack` keeps all three mounted, so
/// a per-page load would be three answers to the same question.
///
/// ```dart
/// StatefulShellRoute.indexedStack(
///   builder: (context, state, shell) => AppShell(navigationShell: shell),
///   branches: branches,
/// );
/// ```
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  /// go_router's branch container. Owns one `Navigator` per destination, so a
  /// trip to settings and back leaves the grid's scroll position alone.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    assert(
      navigationShell.route.branches.length ==
          TimeBuddyNavDestination.values.length,
      'Branch order is pinned to TimeBuddyNavDestination.values: goBranch is '
      'indexed by destination.index.',
    );
    // Read off the shell's own branch index rather than off the router's
    // current path. The index is a property of this widget, so it cannot go
    // stale (`GoRouter.of(context).state` explicitly does not rebuild its
    // reader), and it is the answer the highlight actually wants: a sub-page
    // pushed onto a branch leaves that branch's destination lit, which is the
    // §7 rule and one fewer path-matching special case for the root route.
    final index = navigationShell.currentIndex;
    final destination = TimeBuddyNavDestination.values[index];
    final currentRoute = destination.route;
    return BlocProvider<BoardCubit>(
      // Eager: the load is the app's first real work, and deferring it to the
      // first `context.read` would start it a frame after the grid asked.
      lazy: false,
      create: (_) => _createBoardCubit(),
      child: Scaffold(
        backgroundColor: context.appColors.background,
        body: Row(
          children: [
            TimeBuddySidebar(
              currentRoute: currentRoute,
              onSelect: _select,
              // Only the grid has a reference day. The converter has a
              // date too, but it is a field
              // inside its own form with its own chevrons
              // (docs/specs/time_converter.md), not the shell's stepper.
              // Every branch stays mounted in the indexed stack, so without
              // this gate a stepper published by the grid would keep showing
              // while the user is reading settings.
              datePill: destination == TimeBuddyNavDestination.grid
                  ? const _SidebarDatePill()
                  : null,
              // The settings destination, wearing the session. Built here
              // rather than by the rail so `TimeBuddySidebar` stays free of
              // auth: the shell is already a reader of it, and a second one
              // is a second answer to "who is signed in".
              profile: _SidebarProfile(
                isSelected: destination == TimeBuddyNavDestination.settings,
                onTap: () => _select(TimeBuddyNavDestination.settings),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  navigationShell,
                  // Floating, not a `bottomNavigationBar` slot: the grid
                  // scrolls a row underneath it and keeps the full window
                  // height for hour columns (design_system §7).
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: TimeBuddyBottomBar(
                      currentRoute: currentRoute,
                      onSelect: _select,
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

  /// Switches branches, preserving each one's stack.
  ///
  /// Selecting the destination you are already on pops that branch back to its
  /// root instead, which is the standard escape hatch from anything a branch
  /// has pushed on itself.
  void _select(TimeBuddyNavDestination destination) {
    navigationShell.goBranch(
      destination.index,
      initialLocation: destination.index == navigationShell.currentIndex,
    );
  }

  /// Builds the session's `BoardCubit` and starts its load.
  ///
  /// Every collaborator comes from `GetIt` and none of them is this cubit, so
  /// a test drives `BoardCubit` directly with fakes and never mounts a shell
  /// to get one.
  BoardCubit _createBoardCubit() {
    final cubit = BoardCubit(
      repository: sl<BoardRepository>(),
      engine: sl<TimeZoneEngine>(),
      clock: sl<Clock>(),
      uuid: sl<Uuid>(),
    );
    unawaited(cubit.load());
    return cubit;
  }
}

/// The stepper the sidebar renders, whatever the current page published.
class _SidebarDatePill extends StatelessWidget {
  const _SidebarDatePill();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Widget?>(
      valueListenable: shellDatePill,
      builder: (context, pill, _) => pill ?? const SizedBox.shrink(),
    );
  }
}

/// The date stepper the sidebar shows at `>= 600px`, published by whichever
/// page owns a reference day.
///
/// **Why a global listenable and not a parameter.** The sidebar is built by
/// the shell, which is an *ancestor* of every page: the page that owns the
/// reference day (the grid) cannot hand a widget
/// upwards, and an `InheritedWidget` flows the wrong direction for exactly the
/// reason `subPageDepth` documents. The alternative — hoisting the reference
/// day into the shell — would put grid state above the grid's own cubit and
/// give every other screen a day it has no use for. One app-scoped slot keeps
/// the day where docs/specs/time_grid.md puts it and still lets §7 place the
/// control.
///
/// Written only through [ShellDatePill]; [DatePillSlot.reset] exists for test
/// teardown, because the slot outlives a pumped widget tree.
final DatePillSlot shellDatePill = DatePillSlot();

/// A single-widget slot, observable without a `BuildContext`.
class DatePillSlot implements ValueListenable<Widget?> {
  /// Prefer the app-wide [shellDatePill]; this constructor exists so a test
  /// can drive an isolated instance.
  DatePillSlot();

  final ValueNotifier<Widget?> _published = ValueNotifier<Widget?>(null);

  // Kept apart from the published value for the reason [_flush] explains:
  // publication is deferred out of the build phase, and a later clear that
  // applied immediately would land before the publish it is meant to undo.
  Widget? _pending;
  bool _publishScheduled = false;

  @override
  Widget? get value => _published.value;

  @override
  void addListener(VoidCallback listener) => _published.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _published.removeListener(listener);

  /// Hands [pill] to the sidebar; `null` empties the slot.
  void publish(Widget? pill) {
    _pending = pill;
    _flush();
  }

  /// Empties the slot immediately.
  ///
  /// For `tearDown`: this notifier is app-scoped, so it would otherwise carry
  /// one test's pill into the next.
  void reset() {
    _pending = null;
    _published.value = null;
  }

  /// Publishes [_pending], deferring past the build phase when necessary.
  ///
  /// A page publishes from its own `build`, and the shell listening here was
  /// built earlier in the same frame; marking it dirty from there is the
  /// "setState() called during build" assertion. The visible cost is one
  /// frame of stale chrome.
  void _flush() {
    if (identical(_published.value, _pending) || _publishScheduled) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _published.value = _pending;
      return;
    }
    _publishScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      // Read at fire time, so a publish and a clear inside one frame collapse
      // to the net result instead of fighting.
      _published.value = _pending;
    });
  }
}

/// Puts a page's date stepper where the breakpoint says it belongs.
///
/// Below `600px` it renders [pill] in place; at and above it the sidebar owns
/// the stepper (design_system §7), so this publishes [pill] into
/// [shellDatePill] and takes no space on the page. One widget rather than an
/// `if (isMobile)` at the call site, for the same reason `TimeBuddyBottomBar`
/// hides itself: a page that gets half the rule right shows two steppers, and
/// only on a tablet.
///
/// ```dart
/// ShellDatePill(
///   pill: TimeBuddyDatePill(
///     value: state.model.referenceDate,
///     today: state.todayInHomeZone,
///     todayLabel: t.grid.today,
///     onChanged: context.read<TimeGridCubit>().setReferenceDate,
///   ),
/// );
/// ```
class ShellDatePill extends StatefulWidget {
  const ShellDatePill({required this.pill, super.key});

  /// The stepper itself, normally a `TimeBuddyDatePill`.
  final Widget pill;

  @override
  State<ShellDatePill> createState() => _ShellDatePillState();
}

class _ShellDatePillState extends State<ShellDatePill> {
  @override
  void dispose() {
    // The page is going away; a rail that kept its stepper would step a day
    // nothing on screen is showing.
    shellDatePill.publish(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The rail owns the stepper only while it is wide enough to hold one.
    // Collapsed to 80pt it hands the control back and the page draws it, the
    // same as on a phone — so the §7 rule stays "exactly one stepper on
    // screen" across all three widths.
    if (!ResponsiveLayout.sidebarIsExpanded(context)) {
      // Clears rather than skips: a window dragged narrower keeps the same
      // State, and a stale publication would leave the rail's copy behind.
      shellDatePill.publish(null);
      return widget.pill;
    }
    shellDatePill.publish(widget.pill);
    return const SizedBox.shrink();
  }
}

/// The rail's foot: the settings destination with whoever is signed in on it.
///
/// A `BlocBuilder` of its own rather than a value read in `AppShell.build`, so
/// a sign-in repaints thirty-six pixels of avatar instead of the whole shell —
/// which owns the board and every branch navigator under it.
class _SidebarProfile extends StatelessWidget {
  const _SidebarProfile({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) => SidebarProfileTile(
        // Everything that is not a session reads as a guest here, and that is
        // the honest rendering: `AuthLoading` is a frame long, and a guest is
        // a supported visitor rather than a state to paper over.
        user: state is Authenticated ? state.user : null,
        isSelected: isSelected,
        onTap: onTap,
      ),
    );
  }
}

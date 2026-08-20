import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The app-wide count of pushed sub-pages currently on screen.
///
/// The shell watches it to hide its bottom bar and date pill while a sub-page
/// (add location, settings, converter detail) is open, and `LiftedFab` watches
/// it to stop lifting a FAB over a bar that is no longer there
/// (design_system §7).
///
/// **Why a global listenable and not an `InheritedWidget`.** Inheritance flows
/// down, and every consumer of this flag sits *above* the pushed route: the
/// shell built the bottom bar before the sub-page existed, so a value the
/// sub-page publishes into its own subtree is invisible to it. The sharper
/// version of the same problem is [PreferredSizeWidget.preferredSize]: it is a
/// plain getter with no `BuildContext`, so a chrome widget that has to reserve
/// height cannot look anything up, inherited or otherwise. One app-scoped
/// `ValueListenable` is readable from both directions and from a getter. The
/// cost is global mutable state, which is why [SubPageScope] is the only
/// writer and [SubPageDepth.reset] exists for test teardown.
///
/// ```dart
/// ValueListenableBuilder<int>(
///   valueListenable: subPageDepth,
///   builder: (context, depth, _) =>
///       depth == 0 ? const TimeBuddyBottomBar(...) : const SizedBox.shrink(),
/// );
/// ```
final SubPageDepth subPageDepth = SubPageDepth();

/// A counter of mounted [SubPageScope]s, observable without a `BuildContext`.
///
/// A counter rather than a bool because sub-pages stack: pushing the city
/// picker from the add-location page keeps both mounted, and a bool would be
/// cleared by the first of the two to pop while the other is still open.
class SubPageDepth implements ValueListenable<int> {
  /// Prefer the app-wide [subPageDepth]; this constructor exists so a test can
  /// drive an isolated instance.
  SubPageDepth();

  final ValueNotifier<int> _published = ValueNotifier<int>(0);

  // Kept apart from the published value because publication is deferred out of
  // the build phase (see [_publish]): if `enter` deferred and a later `exit`
  // applied immediately, the two would land out of order and leave the depth
  // stuck at 1. Every mutation lands here synchronously and in order; the
  // notifier only ever catches up to it.
  int _pending = 0;
  bool _publishScheduled = false;

  @override
  int get value => _published.value;

  /// Whether any sub-page is open. The question every consumer actually asks.
  bool get isSubPage => value > 0;

  @override
  void addListener(VoidCallback listener) => _published.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _published.removeListener(listener);

  /// Registers one more open sub-page. Called by `SubPageScope`.
  void enter() {
    _pending += 1;
    _publish();
  }

  /// Retires one open sub-page. Called by `SubPageScope`.
  ///
  /// Floors at zero so a stray `exit` — a hot reload that dropped a scope, a
  /// test that disposed a tree twice — cannot drive the counter negative and
  /// leave the shell permanently convinced it is on a sub-page.
  void exit() {
    _pending = _pending > 0 ? _pending - 1 : 0;
    _publish();
  }

  /// Clears the counter immediately.
  ///
  /// For `tearDown`: the notifier is app-scoped, so it outlives a pumped
  /// widget tree and would carry one test's depth into the next.
  void reset() {
    _pending = 0;
    _published.value = 0;
  }

  /// Publishes [_pending], deferring past the build phase when necessary.
  ///
  /// `initState` and `dispose` both run inside the build phase, and the shell
  /// listening to this notifier was already built earlier in the same frame.
  /// Marking it dirty from there is the classic "setState() called during
  /// build" assertion, so the change rides a post-frame callback instead. The
  /// visible cost is one frame of stale chrome, which lands underneath a route
  /// transition that is still animating in.
  void _publish() {
    if (_published.value == _pending || _publishScheduled) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _published.value = _pending;
      return;
    }
    _publishScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      // Read at fire time, not at schedule time, so a push and a pop inside
      // the same frame collapse to the net depth instead of fighting.
      _published.value = _pending;
    });
  }
}

/// Marks its subtree as a pushed sub-page.
///
/// Wrap the body of every page that is pushed on top of the shell — add
/// location, settings, a converter detail. While it is mounted the shell hides
/// its bottom bar and date pill and `LiftedFab` stops lifting
/// (design_system §7).
///
/// It renders [child] unchanged; the only thing it contributes is its
/// lifetime, which is exactly the window the chrome needs to know about.
///
/// ```dart
/// @override
/// Widget build(BuildContext context) => SubPageScope(
///   child: Scaffold(
///     appBar: TimeBuddyLargeAppBar(title: t.settings.title),
///     body: body,
///   ),
/// );
/// ```
class SubPageScope extends StatefulWidget {
  const SubPageScope({required this.child, super.key});

  /// The sub-page itself, usually a `Scaffold`.
  final Widget child;

  @override
  State<SubPageScope> createState() => _SubPageScopeState();
}

class _SubPageScopeState extends State<SubPageScope> {
  @override
  void initState() {
    super.initState();
    subPageDepth.enter();
  }

  @override
  void dispose() {
    subPageDepth.exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The unauthenticated landing: three slides, the last one holding the Google
/// button (docs/specs/auth.md).
///
/// **There is no `SignInPage`.** The app is Google-only, so a screen whose
/// whole content is one button would be a second stop on the way to the same
/// tap. Sign-in lives on the last slide instead, which is also the slide that
/// explains why an account exists at all: the board following you from the
/// phone to the browser (rule 1).
///
/// The tour is skippable, and the skip goes *to the sign-in slide* rather than
/// past it: skipping the tour and declining an account are two different
/// intentions, and they get two different controls.
///
/// The second of them, "continue without an account", is on **every** slide
/// and starts a guest session (docs/specs/guest_mode.md rule 3). Sign-in is an
/// offer here, not a gate — this page is the only place that offer is made
/// before the app opens, so it is also the only place the offer can be
/// declined.
///
/// ```dart
/// GoRoute(
///   path: AppRoutes.onboarding,
///   builder: (context, state) => const OnboardingPage(),
/// );
/// ```
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  /// Long enough to read as a page turning, short enough that a double tap on
  /// Next does not queue two visible animations.
  static const Duration _slideDuration = Duration(milliseconds: 280);
  static const Curve _slideCurve = Curves.easeOutCubic;

  /// Height the action block always occupies, whichever slide is showing.
  ///
  /// Fixed because that block swaps between three controls, two and a spinner:
  /// without it the dots and the copy above them would step up and down as the
  /// user pages through the tour.
  ///
  /// Raised from 112 when "continue without an account" was added to every
  /// slide (docs/specs/guest_mode.md rule 3): the tallest arrangement is now
  /// Next plus Skip plus that, and a constant left at the two-control height
  /// clips the third.
  static const double _actionsHeight = 152;

  /// How many slides [_buildSlides] returns.
  ///
  /// A constant because the opening slide has to be chosen in [initState],
  /// before the localized list exists. The assertion in [build] is what stops
  /// the two from drifting apart.
  static const int _slideCount = 3;

  late final PageController _controller;

  late int _index;

  @override
  void initState() {
    super.initState();
    // A user coming back from a sign-in this browser blocked is being told to
    // press one button, and that button lives on the last slide. Opening on
    // slide 1 would put the advice three swipes from the thing it is advice
    // about — and they have already been through the tour on the way out.
    _index = _blockOf(context.read<AuthBloc>().state) == null
        ? 0
        : _slideCount - 1;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The animation is deliberately not awaited: nothing follows the page turn,
  /// and awaiting it would hold a `State` reference across an animation the
  /// user can interrupt by swiping.
  ///
  /// No `unawaited` wrapper either: `animateToPage` is annotated
  /// `@awaitNotRequired` in this SDK, so the wrapper is what the analyzer
  /// objects to, not the dropped future.
  void _goToSlide(int index) {
    _controller.animateToPage(
      index,
      duration: _slideDuration,
      curve: _slideCurve,
    );
  }

  /// Starts a guest session and opens the app (docs/specs/guest_mode.md
  /// rule 3).
  ///
  /// **It has to navigate, unlike the sign-in path below.** The redirect is a
  /// *guard*: it says which routes a visitor may not be on, and a guest may be
  /// on this one — the tour stays readable for someone still deciding. So
  /// writing the marker alone leaves them exactly where they were, looking at
  /// the button they just pressed. This is the same division `StartupPage`
  /// works under: the page that knows a decision was made is the page that
  /// acts on it.
  ///
  /// `go`, not `push`: onboarding must not stay under the app as a back
  /// destination.
  Future<void> _continueAsGuest() async {
    await sl<GuestSession>().enter();
    if (!mounted) return;
    context.go(AppRoutes.grid);
  }

  /// Says the one thing about a sign-in that the router cannot.
  ///
  /// It deliberately does not navigate. `AppRouter` already sends a session
  /// that lands here back through the splash, so the new account's documents
  /// are reconciled before a clock is drawn, and a `context.go` from this page
  /// would be a second owner of that rule.
  ///
  /// [Unauthenticated] is silent: it is where a *cancelled* dialog lands (rule
  /// 5), and it is also the state this page opens in, so anything said about
  /// it would be said to a user who did nothing.
  ///
  /// It stays silent *here* even when it carries a [SignInBlock], because a
  /// listener only fires on a change. The boot-leg diagnosis is settled while
  /// the splash is still up, so by the time this page mounts there is no
  /// change left to hear and a snackbar raised from here would be shown to
  /// nobody — on precisely the failure the whole mechanism exists for. The
  /// advice is built instead ([_SignInBlockedNotice]), which also keeps it on
  /// screen beside the button it is about instead of for four seconds.
  void _onAuthState(BuildContext context, AuthState state) {
    if (state is! AuthError) return;
    context.showSnack(t.auth.signInFailed);
  }

  /// The obstacle [state] is carrying, if it is carrying one.
  ///
  /// Only a signed-out state can: a sign-in the browser blocked ends with
  /// nobody signed in, so `AuthBloc` hangs the diagnosis on [Unauthenticated]
  /// rather than inventing a state that would mean the same thing.
  static SignInBlock? _blockOf(AuthState state) =>
      state is Unauthenticated ? state.blockedBy : null;

  @override
  Widget build(BuildContext context) {
    final slides = _buildSlides();
    assert(
      slides.length == _slideCount,
      'initState picks the opening slide from _slideCount.',
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ResponsiveLayout.maxContentWidth,
            ),
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: _onAuthState,
              builder: (context, state) => Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: slides.length,
                      onPageChanged: (index) => setState(() => _index = index),
                      itemBuilder: (context, index) =>
                          _OnboardingSlide(slide: slides[index]),
                    ),
                  ),
                  _SlideDots(count: slides.length, index: _index),
                  const SizedBox(height: AppSpacing.lg),
                  // Above the button rather than over it: this is something to
                  // read before pressing it again, not a dialog to dismiss.
                  if (_blockOf(state) case final block?)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.lg,
                      ),
                      child: _SignInBlockedNotice(block: block),
                    ),
                  SizedBox(
                    height: _actionsHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: _Actions(
                        isSignInSlide: _index == slides.length - 1,
                        isSigningIn: state is AuthLoading,
                        onNext: () => _goToSlide(_index + 1),
                        onSkip: () => _goToSlide(slides.length - 1),
                        onContinueAsGuest: () => unawaited(_continueAsGuest()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The tour, in order. Built per rebuild rather than held as a constant,
  /// because `t` resolves against the locale in effect and the user can change
  /// that from settings while the app is running.
  List<_Slide> _buildSlides() => [
    _Slide(
      icon: FontAwesomeIcons.tableCells,
      title: t.auth.onboardingTitle1,
      body: t.auth.onboardingBody1,
    ),
    _Slide(
      icon: FontAwesomeIcons.clock,
      title: t.auth.onboardingTitle2,
      body: t.auth.onboardingBody2,
    ),
    _Slide(
      icon: FontAwesomeIcons.laptop,
      title: t.auth.onboardingTitle3,
      body: t.auth.onboardingBody3,
    ),
  ];
}

/// One slide's finished, localized copy.
class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});

  final FaIconData icon;
  final String title;
  final String body;
}

/// The tinted disc, headline and body of one slide.
///
/// The same shape as `FeatureEmptyState`, deliberately: this is the first
/// screen of the app, and it should already look like the screens behind it
/// (docs/specs/design_system.md §6).
class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.slide});

  final _Slide slide;

  static const double _discSize = 96;
  static const double _iconSize = 44;
  static const double _discAlpha = 0.12;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      // Scrollable so the slide survives a short landscape phone: it is the
      // whole screen's content, so there is nothing else to give up height.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _discSize,
              height: _discSize,
              decoration: BoxDecoration(
                // The brand accent at low alpha, the same invitation an empty
                // state makes. Error red on a first screen says it is broken.
                color: colors.primary.withValues(alpha: _discAlpha),
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                slide.icon,
                size: _iconSize,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: context.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              slide.body,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: colors.onBackgroundLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the user is in the tour.
class _SlideDots extends StatelessWidget {
  const _SlideDots({required this.count, required this.index});

  final int count;
  final int index;

  static const double _dotSize = 8;
  static const double _activeWidth = 22;
  static const double _inactiveAlpha = 0.3;
  static const Duration _morphDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Decorative: the slide's own heading already tells a screen reader where
    // it is, and three unlabelled dots in the middle of that are only
    // something to swipe past.
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var dot = 0; dot < count; dot++)
            AnimatedContainer(
              duration: _morphDuration,
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              width: dot == index ? _activeWidth : _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(
                color: dot == index
                    ? colors.primary
                    : colors.onBackgroundLight.withValues(
                        alpha: _inactiveAlpha,
                      ),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
        ],
      ),
    );
  }
}

/// Next and Skip on the first two slides, the Google button on the last, the
/// way past both on every slide, and a spinner in place of all of it while the
/// sign-in is away.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.isSignInSlide,
    required this.isSigningIn,
    required this.onNext,
    required this.onSkip,
    required this.onContinueAsGuest,
  });

  final bool isSignInSlide;

  /// Whether `AuthBloc` is in [AuthLoading]. The Google flow leaves the app —
  /// a plugin dialog on Android, a full redirect on web — so without this the
  /// page would sit on a live button through a round trip the user cannot see,
  /// and a second tap would start a second flow.
  final bool isSigningIn;

  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// Enters guest mode (docs/specs/guest_mode.md rule 3).
  final VoidCallback onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    if (isSigningIn) return const Center(child: CircularProgressIndicator());
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isSignInSlide)
          ElevatedButton.icon(
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthGoogleSignInRequested()),
            // A glyph rather than the Google mark: the brand asset carries
            // usage rules of its own and this app bundles no images, so the
            // provider is named by the label instead of drawn badly.
            icon: const AppIcon(FontAwesomeIcons.rightToBracket),
            label: Text(t.auth.signInWithGoogle),
          )
        else ...[
          ElevatedButton(onPressed: onNext, child: Text(t.auth.onboardingNext)),
          const SizedBox(height: AppSpacing.xs),
          Tooltip(
            message: t.auth.onboardingSkipHint,
            child: TextButton(
              onPressed: onSkip,
              child: Text(t.auth.onboardingSkip),
            ),
          ),
        ],
        // On **every** slide, including the last (guest_mode.md rule 3). A
        // visitor whose browser blocked the Google popup opens straight on
        // that slide, and they are precisely the person who most needs a way
        // past it — a control that only appeared on slides 1 and 2 would be
        // three swipes behind the notice explaining why they are stuck.
        if (isSignInSlide) const SizedBox(height: AppSpacing.xs),
        Tooltip(
          message: t.auth.continueAsGuestHint,
          child: TextButton(
            onPressed: onContinueAsGuest,
            child: Text(t.auth.continueAsGuest),
          ),
        ),
      ],
    );
  }
}

/// What this browser did to the sign-in, and what the user can do about it.
///
/// Drawn, never announced. Both legs of rule 2 end up here, and the boot leg —
/// the redirect that came back empty — settles before this page exists, so a
/// snackbar would be shown to nobody on exactly the failure the mechanism was
/// built for (see `_OnboardingPageState._onAuthState`).
///
/// Warning-toned, not error-toned: nothing is broken, a browser setting is in
/// the way, and the app's first screen painting itself red would say the app
/// is the problem (docs/specs/design_system.md §6).
class _SignInBlockedNotice extends StatelessWidget {
  const _SignInBlockedNotice({required this.block});

  final SignInBlock block;

  static const double _tintAlpha = 0.12;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      // It arrives without the user moving focus — already on screen when the
      // page mounts after a redirect, or in place of the spinner when a
      // sign-in comes back blocked — so a screen reader has to be told rather
      // than left to be walked into it.
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: _tintAlpha),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                FontAwesomeIcons.triangleExclamation,
                size: _iconSize,
                color: colors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              // Expanded, not a bare Text: this is two sentences of advice
              // sharing a row with a fixed-width icon, and an unflexed child
              // takes its full intrinsic width and overflows the phone it is
              // meant to be read on.
              Expanded(
                child: Text(
                  _advice,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onBackground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The copy says what to *do*, which is the whole point of telling them:
  /// one of these is a pop-up blocker the user can turn off, the other is a
  /// browser that will not carry the sign-in at all and wants a different
  /// browser (docs/specs/auth.md rule 2).
  ///
  /// No default branch, so a third obstacle has to be given words here before
  /// it compiles, rather than reaching the user as an empty box.
  String get _advice => switch (block) {
    SignInBlock.storage => t.auth.signInStorageBlocked,
    SignInBlock.popup => t.auth.signInPopupBlocked,
  };
}

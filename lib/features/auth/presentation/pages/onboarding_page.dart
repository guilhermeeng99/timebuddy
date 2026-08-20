
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
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
/// past it. Sign-in is required, so there is nothing behind this page to skip
/// to.
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
  /// Fixed because that block swaps between two buttons, one button and a
  /// spinner: without it the dots and the copy above them would step up and
  /// down as the user pages through the tour.
  static const double _actionsHeight = 112;

  final PageController _controller = PageController();

  int _index = 0;

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
  void _onAuthState(BuildContext context, AuthState state) {
    if (state is! AuthError) return;
    context.showSnack(t.auth.signInFailed);
  }

  @override
  Widget build(BuildContext context) {
    final slides = _buildSlides();
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
      icon: Icons.grid_view_rounded,
      title: t.auth.onboardingTitle1,
      body: t.auth.onboardingBody1,
    ),
    _Slide(
      icon: Icons.schedule_rounded,
      title: t.auth.onboardingTitle2,
      body: t.auth.onboardingBody2,
    ),
    _Slide(
      icon: Icons.devices_rounded,
      title: t.auth.onboardingTitle3,
      body: t.auth.onboardingBody3,
    ),
  ];
}

/// One slide's finished, localized copy.
class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});

  final IconData icon;
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
              child: Icon(slide.icon, size: _iconSize, color: colors.primary),
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

/// Next and Skip on the first two slides, the Google button on the last, and
/// a spinner in place of either while the sign-in is away.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.isSignInSlide,
    required this.isSigningIn,
    required this.onNext,
    required this.onSkip,
  });

  final bool isSignInSlide;

  /// Whether `AuthBloc` is in [AuthLoading]. The Google flow leaves the app —
  /// a plugin dialog on Android, a full redirect on web — so without this the
  /// page would sit on a live button through a round trip the user cannot see,
  /// and a second tap would start a second flow.
  final bool isSigningIn;

  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    if (isSigningIn) return const Center(child: CircularProgressIndicator());
    if (isSignInSlide) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthGoogleSignInRequested()),
            // A glyph rather than the Google mark: the brand asset carries
            // usage rules of its own and this app bundles no images, so the
            // provider is named by the label instead of drawn badly.
            icon: const Icon(Icons.login_rounded),
            label: Text(t.auth.signInWithGoogle),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
    );
  }
}

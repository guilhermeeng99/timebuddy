import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_section.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/profile/presentation/widgets/sync_status_row.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Runs the account deletion for the signed-in user id it is handed.
///
/// Answers `null` when the account is gone and the [Failure] when it is not,
/// which is the one-shot channel `BoardCubit`'s mutations already use: the
/// page that asked for the deletion is the only one that should hear about it.
typedef DeleteAccountAction = Future<Failure?> Function(String userId);

/// Who is signed in, whether their data is synced, and the two ways out.
///
/// **There is no signed-out variant of this page.** Sign-in is required
/// (docs/specs/auth.md rule 1), so an unauthenticated visitor is a routing
/// mistake rather than a state to design for; the page shows a placeholder for
/// the frame it takes the router to send them to onboarding.
///
/// The sync indicator here is passive and stays passive (docs/specs/sync.md
/// rule 4): it is the only place a failed background write is ever mentioned,
/// and it never asks the user to do anything about it.
///
/// ```dart
/// GoRoute(
///   path: AppRoutes.profile,
///   builder: (context, state) => const ProfilePage(),
/// );
/// ```
class ProfilePage extends StatelessWidget {
  const ProfilePage({this.deleteAccount, super.key});

  /// What "delete my account" actually runs, once the user has confirmed it.
  ///
  /// A parameter rather than a repository read, because `ProfileRepository`
  /// (auth.md, Repository Contract) has no implementation in the tree yet:
  /// inventing one here would be guessing at an API, and hiding the row would
  /// hide a promise the spec makes. Wired at the route, the page needs no
  /// change; unwired, the confirmation ends in
  /// `t.auth.deleteAccountFailed` rather than in a lie about what happened.
  final DeleteAccountAction? deleteAccount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TimeBuddyLargeAppBar(title: t.profile.title),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: _onAuthState,
        builder: (context, state) => switch (state) {
          Authenticated(:final user) => _ProfileBody(
            user: user,
            deleteAccount: deleteAccount,
          ),
          // Sign-out and deletion both end here for the frame between the
          // session ending and the router's redirect landing, and a deep link
          // to /profile before the startup check resolves lands here too. A
          // shimmer says "a moment" without promising a signed-out page that
          // does not exist. The states are spelled out rather than left to a
          // `_`, so a state added later has to be looked at instead of
          // silently rendering as a placeholder.
          AuthInitial() ||
          AuthLoading() ||
          Unauthenticated() ||
          AuthError() => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: LoadingShimmer(),
          ),
        },
      ),
    );
  }

  /// Sign-out is the only auth operation this page starts, so an [AuthError]
  /// here is that one failing. It matters that the user hears it: a failed
  /// sign-out deliberately leaves the local board in place (auth.md, Edge
  /// Cases), so they are still signed in and would not otherwise know.
  ///
  /// A *successful* sign-out says nothing and navigates nowhere. `AppRouter`
  /// watches the session and moves an unauthenticated user to onboarding
  /// (auth.md rule 1); a `context.go` here would be a second owner of that.
  void _onAuthState(BuildContext context, AuthState state) {
    if (state is! AuthError) return;
    context.showSnack(t.auth.signOutFailed);
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.user, required this.deleteAccount});

  final UserEntity user;
  final DeleteAccountAction? deleteAccount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.maxContentWidth,
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            // A pushed page, not one of the three primary destinations: it is
            // opened from the sidebar's profile slot, so no floating bar hangs
            // over its last row.
            bottomSafeForBar(context, isSubPage: true),
          ),
          children: [
            TimeBuddySection(
              label: t.profile.signedInAs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Identity(user: user),
                  const Divider(height: AppSpacing.xxl),
                  // Resolved from the locator rather than passed down: the row
                  // is a leaf that subscribes to a stream, and threading a
                  // service through every page that shows one is how two of
                  // them end up watching different services.
                  SyncStatusRow(syncService: sl<SyncService>()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: () => unawaited(_confirmSignOut(context)),
              icon: const Icon(Icons.logout_rounded),
              label: Text(t.auth.signOut),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.appColors.error,
                ),
                onPressed: () => unawaited(_confirmDeleteAccount(context)),
                child: Text(t.auth.deleteAccount),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Asks before ending the session, because signing out clears the local copy
  /// of the board (auth.md rule 7) and an accidental tap would read as data
  /// loss even though the cities are safe in the account.
  Future<void> _confirmSignOut(BuildContext context) async {
    // Resolved before the await: a `context.read` after one is exactly what
    // `use_build_context_synchronously` is about, and the bloc reference is
    // valid whether or not this page survives the dialog.
    final bloc = context.read<AuthBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: Text(t.auth.signOutConfirm),
        content: Text(t.auth.signOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.auth.signOut),
          ),
        ],
      ),
    );
    if (confirmed ?? false) bloc.add(const AuthSignOutRequested());
  }

  /// The stronger confirmation, and deliberately harder to answer by reflex
  /// than the sign-out one: the barrier does not dismiss it, the warning is
  /// spelled out, and the destructive action is a filled button in the error
  /// token rather than one more text button beside Cancel. Signing out is
  /// undone by signing back in; this is not undone at all.
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: colors.error),
        title: Text(t.auth.deleteAccountConfirm),
        content: Text(t.auth.deleteAccountWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              // The palette has no `onError` token, and this is the case
              // `foregroundOn` exists for: the readable foreground is a
              // function of the fill, not a 16th colour to hand-pick per
              // palette (app_colors.dart).
              foregroundColor: foregroundOn(colors.error),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.auth.deleteAccount),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    final deleter = deleteAccount;
    if (deleter != null) {
      final failure = await deleter(user.id);
      // Nothing to announce on success: the deletion ends the session, so
      // `authStateChanges` emits null, `AuthBloc` lands on `Unauthenticated`
      // and the router moves the user to onboarding on its own.
      if (failure == null) return;
    }
    if (!context.mounted) return;
    context.showSnack(t.auth.deleteAccountFailed);
  }
}

/// Photo, name and address of the signed-in account.
class _Identity extends StatelessWidget {
  const _Identity({required this.user});

  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Avatar(user: user),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                user.email,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.appColors.onBackgroundLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The Google profile picture, or the account's initial when there is none.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final UserEntity user;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoUrl;
    final fallback = _InitialAvatar(name: user.name);
    return ClipOval(
      child: SizedBox.square(
        dimension: _size,
        // An empty string is not a URL. The entity keeps `photoUrl` nullable,
        // but a profile document written from an account with no picture can
        // still hold `''`, and `Image.network('')` fails on every rebuild.
        child: photoUrl == null || photoUrl.isEmpty
            ? fallback
            : Image.network(
                photoUrl,
                fit: BoxFit.cover,
                // A Google photo URL stops resolving on its own schedule — the
                // token in it rotates, and on web the host may refuse the
                // cross-origin read outright. An image that throws paints a
                // debug error box across the profile page, so the initial
                // stands in for it instead.
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

/// The tinted disc standing in for a missing photo.
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});

  final String name;

  static const double _tintAlpha = 0.12;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final trimmed = name.trim();
    return ColoredBox(
      color: colors.primary.withValues(alpha: _tintAlpha),
      child: Center(
        child: trimmed.isEmpty
            // A nameless account gets a glyph rather than a hardcoded letter:
            // any letter chosen here would be one the user never typed, in a
            // language nobody localized.
            ? Icon(Icons.person_outline, color: colors.primary)
            : Text(
                _initialOf(trimmed),
                style: context.textTheme.titleLarge?.copyWith(
                  color: colors.primary,
                ),
              ),
      ),
    );
  }

  /// First code point of [value], upper-cased.
  ///
  /// A code point rather than `substring(0, 1)`, which cuts a name starting
  /// outside the BMP through its surrogate pair and renders a replacement box.
  String _initialOf(String value) =>
      String.fromCharCode(value.runes.first).toUpperCase();
}

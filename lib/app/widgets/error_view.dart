import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/icon_disc.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The app's error state: what went wrong, and one way out of it.
///
/// The copy is deliberately generic and localized. [Failure.message] is a
/// developer string for logs and test output — rendering it would put
/// "PERMISSION_DENIED" in front of a user (see `failures.dart`). The failure
/// still earns its place in the signature: its *type* picks the icon, so a
/// sign-in problem does not look like a lost network connection.
///
/// ```dart
/// BlocBuilder<BoardCubit, BoardState>(
///   builder: (context, state) => switch (state) {
///     BoardError(:final failure) => ErrorView(
///       failure: failure,
///       onRetry: context.read<BoardCubit>().load,
///     ),
///     _ => BoardList(board: state.board),
///   },
/// );
/// ```
class ErrorView extends StatelessWidget {
  const ErrorView({required this.failure, required this.onRetry, super.key});

  /// What failed. Used for the icon, never rendered as text.
  final Failure failure;

  /// Runs the same operation again. Always offered: every failure this app
  /// raises is transient or fixable by the user.
  final VoidCallback onRetry;

  static const double _maxCopyWidth = 320;

  FaIconData get _icon => switch (failure) {
    AuthFailure() => FontAwesomeIcons.lock,
    ServerFailure() => FontAwesomeIcons.linkSlash,
    StorageFailure() => FontAwesomeIcons.plugCircleXmark,
    NotFoundFailure() => FontAwesomeIcons.magnifyingGlass,
    ValidationFailure() => FontAwesomeIcons.circleExclamation,
    DuplicateZoneFailure() => FontAwesomeIcons.copy,
    BoardFullFailure() => FontAwesomeIcons.layerGroup,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxCopyWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconDisc(icon: _icon, color: colors.error),
              const SizedBox(height: AppSpacing.lg),
              Text(
                t.common.errorTitle,
                textAlign: TextAlign.center,
                style: context.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                t.common.errorBody,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: colors.onBackgroundLight,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(t.common.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

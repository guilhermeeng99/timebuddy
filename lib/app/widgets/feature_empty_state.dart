import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// The first impression of a feature that has nothing to show yet.
///
/// An empty board is a valid state, not an error (locations.md rule 6), so it
/// gets the product's voice and a way forward rather than `ErrorView`'s
/// apology. The shape is fixed by design_system §6 — tinted icon disc,
/// headline, message, optional example chip, primary CTA, optional footer —
/// so every feature's first run reads as the same app.
///
/// All copy arrives finished and localized; this widget owns the layout, never
/// the words.
///
/// ```dart
/// FeatureEmptyState(
///   icon: Icons.public_outlined,
///   title: t.grid.emptyTitle,
///   message: t.grid.emptyMessage,
///   ctaLabel: t.grid.emptyCta,
///   onCta: () => context.push(AppRoutes.addLocation),
/// );
/// ```
class FeatureEmptyState extends StatelessWidget {
  const FeatureEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.example,
    this.ctaLabel,
    this.onCta,
    this.footer,
    super.key,
  }) : assert(
         (ctaLabel == null) == (onCta == null),
         'A CTA needs both its label and its callback, or neither.',
       );

  /// The glyph inside the tinted disc. Name the feature's subject, not its
  /// absence: a crossed-out icon reads as a failure, and nothing failed.
  final IconData icon;

  /// One short line naming what is missing.
  final String title;

  /// A sentence saying what the user gets by filling it.
  final String message;

  /// Optional muted chip showing what a filled-in entry looks like — a sample
  /// city, a sample time. It teaches the shape of the input faster than
  /// another sentence of [message] does.
  final String? example;

  /// Label of the primary action. Pass it with [onCta] or leave both out.
  final String? ctaLabel;

  /// The primary action. The empty state is the one screen where the CTA is
  /// the content, so it is a full-width filled button, not a text link.
  final VoidCallback? onCta;

  /// Optional secondary line under the CTA: a "restore from backup" link, a
  /// hint about where the data comes from.
  final Widget? footer;

  static const double _discSize = 72;
  static const double _iconSize = 32;
  static const double _discAlpha = 0.12;
  static const double _maxCopyWidth = 320;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = ctaLabel;
    final exampleLabel = example;
    final footerWidget = footer;
    return Center(
      // Scrollable so the block survives a short landscape phone. It is the
      // whole screen's content, so there is nothing else to give up height.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxCopyWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _discSize,
                  height: _discSize,
                  decoration: BoxDecoration(
                    // The brand accent at low alpha: this is an invitation,
                    // and error red on a first run says the app is broken.
                    color: colors.primary.withValues(alpha: _discAlpha),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: _iconSize, color: colors.primary),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: colors.onBackgroundLight,
                  ),
                ),
                if (exampleLabel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ExampleChip(label: exampleLabel),
                ],
                if (label != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(onPressed: onCta, child: Text(label)),
                ],
                if (footerWidget != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  footerWidget,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: context.textTheme.labelMedium?.copyWith(
            color: colors.onBackgroundLight,
          ),
        ),
      ),
    );
  }
}

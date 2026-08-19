import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// One choice inside a [TimeBuddyPillToggle].
///
/// [label] is already localized: the toggle takes finished copy so it never has
/// to know whether a value is an enum, a bool or a zone id.
///
/// ```dart
/// const PillOption(value: ClockFormat.h24, label: '24h');
/// ```
class PillOption<T> extends Equatable {
  const PillOption({required this.value, required this.label});

  /// The value reported to `onChanged` when this option is picked.
  final T value;

  /// Display text.
  final String label;

  @override
  List<Object?> get props => [value, label];
}

/// A segmented control: two or three mutually exclusive options in one pill.
///
/// Used wherever the choice is a mode rather than a setting the user hunts for
/// — Grid / Clocks, 12h / 24h. Both alternatives stay visible, which a switch
/// or a dropdown cannot do, and the cost is that it only works for short
/// labels and a handful of options.
///
/// ```dart
/// TimeBuddyPillToggle<ClockFormat>(
///   options: const [
///     PillOption(value: ClockFormat.h24, label: '24h'),
///     PillOption(value: ClockFormat.h12, label: '12h'),
///   ],
///   selected: preferences.hourFormat,
///   onChanged: context.read<PreferencesCubit>().setClockFormat,
/// );
/// ```
class TimeBuddyPillToggle<T> extends StatelessWidget {
  const TimeBuddyPillToggle({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.disabled = false,
    super.key,
  });

  /// The choices, laid out left to right in equal shares of the width.
  final List<PillOption<T>> options;

  /// The value currently active. An option matching it renders as filled.
  final T selected;

  /// Called with the picked value. Not called for the already-selected option.
  final ValueChanged<T> onChanged;

  /// Dims the control and ignores taps, for a choice that is unavailable in the
  /// current state rather than absent from it.
  final bool disabled;

  static const double _disabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? _disabledOpacity : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            children: [
              for (final option in options)
                Expanded(
                  child: _PillSegment(
                    label: option.label,
                    isSelected: option.value == selected,
                    // A null callback also removes the ink response, so a
                    // disabled segment does not splash on touch.
                    onTap: disabled || option.value == selected
                        ? null
                        : () => onChanged(option.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillSegment extends StatelessWidget {
  const _PillSegment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.xl);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? colors.primary : null,
        borderRadius: radius,
      ),
      child: Material(
        // Transparent so the ink ripple paints over the fill above instead of
        // covering it with a second opaque surface.
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelLarge?.copyWith(
                color: isSelected ? colors.onPrimary : colors.onBackgroundLight,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

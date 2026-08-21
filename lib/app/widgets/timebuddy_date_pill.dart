import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The compact stepper for the grid's reference day: chevron, date, chevron,
/// and a Today reset (design_system §7, time_grid.md rule 11).
///
/// **It does not own the date.** [value] comes in and [onChanged] goes out;
/// the reference day lives in the grid's cubit, which is the only thing that
/// can rebuild the columns for it. That is also why [today] is a parameter and
/// not something this widget works out for itself: "today" is a question about
/// the *home zone*, not about the device, and `DateTime.now()` is banned in
/// `lib/` for exactly the reason it would be wrong here (CLAUDE.md, Time &
/// Timezone rule 4).
///
/// Placement follows the breakpoint: the sidebar hosts it at `>= 600px`, and
/// below that the page renders it itself. Never both — a page that draws one
/// unconditionally shows two steppers on a tablet.
///
/// ```dart
/// TimeBuddyDatePill(
///   value: state.grid.referenceDate,
///   today: state.todayInHomeZone,
///   todayLabel: t.grid.today,
///   onChanged: context.read<TimeGridCubit>().setReferenceDate,
/// );
/// ```
class TimeBuddyDatePill extends StatelessWidget {
  const TimeBuddyDatePill({
    required this.value,
    required this.today,
    required this.todayLabel,
    required this.onChanged,
    this.localeTag,
    super.key,
  });

  /// The reference day, as a local calendar date in the home zone.
  final DateTime value;

  /// The current day in the home zone. Decides whether the reset shows, and is
  /// the value the reset hands back.
  final DateTime today;

  /// Localized copy for the reset, e.g. `t.grid.today`.
  ///
  /// Finished copy rather than a key, the same contract `PillOption` uses: the
  /// widget never has to know which section of the translations it came from.
  final String todayLabel;

  /// Called with the new reference day. Never called with the current one.
  final ValueChanged<DateTime> onChanged;

  // The two chevrons used to take their tooltips as optional parameters, and
  // **no caller ever passed one**, so both shipped as buttons a screen reader
  // announced as "button" — twice, in a mirrored pair, which is worse than one
  // unnamed control because the user cannot tell which way either goes. There
  // is no caller that would want different words for "the day before this
  // one", so the copy is resolved here, the way `TimeBuddyNavDestination.label`
  // resolves its own: at read time, so switching language relabels it.

  /// Locale for the `Tue 24` label. Defaults to the app's resolved locale.
  final String? localeTag;

  /// Below this a horizontal drag reads as a scroll, not as a day step.
  static const double _swipeVelocityThreshold = 200;

  bool get _isToday =>
      value.year == today.year &&
      value.month == today.month &&
      value.day == today.day;

  /// The reference day [days] away, rebuilt from calendar fields.
  ///
  /// Never `value.add(const Duration(days: 1))`: a local day is 23 or 25 hours
  /// long twice a year, so adding 24 hours to a date in a DST zone lands on
  /// the wrong calendar day (CLAUDE.md, Time & Timezone rule 3). The
  /// constructor also rolls month and year boundaries over for free.
  ///
  /// The UTC carrier flag is preserved so the caller gets back a value shaped
  /// like the one it passed in, rather than one that compares unequal to it.
  DateTime _stepped(int days) => value.isUtc
      ? DateTime.utc(value.year, value.month, value.day + days)
      : DateTime(value.year, value.month, value.day + days);

  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || velocity.abs() < _swipeVelocityThreshold) return;
    // Swiping left pulls the next day in from the right, matching the
    // direction of the forward chevron on that side of the pill.
    onChanged(_stepped(velocity < 0 ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tag = localeTag ?? Localizations.localeOf(context).toLanguageTag();
    return GestureDetector(
      // time_grid.md, Interaction: swiping the pill steps the reference date.
      onHorizontalDragEnd: _onSwipe,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepButton(
                icon: FontAwesomeIcons.chevronLeft,
                tooltip: t.common.previousDay,
                onTap: () => onChanged(_stepped(-1)),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    formatDayMonth(value, tag),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.labelLarge?.copyWith(
                      color: colors.onBackground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: FontAwesomeIcons.chevronRight,
                tooltip: t.common.nextDay,
                onTap: () => onChanged(_stepped(1)),
              ),
              // Absent on today, because a reset to where you already are is a
              // control that does nothing (time_grid.md rule 11).
              if (!_isToday)
                Flexible(
                  child: _TodayReset(
                    label: todayLabel,
                    onTap: () => onChanged(today),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final FaIconData icon;
  final VoidCallback onTap;

  /// Required, not optional: a chevron has no accessible name of its own,
  /// and the version of this class that let a caller omit one had two call
  /// sites, both omitting it.
  final String tooltip;

  /// 36, against Material's 48 guidance and WCAG 2.2's 24 minimum.
  /// Deliberate: the pill is chrome that has to fit a 375pt phone beside a
  /// date and a Today reset, and 48 would cost 24pt of that width. It
  /// clears the accessibility floor with half again to spare; it does not
  /// clear the comfort guidance, and that is the trade.
  static const double _size = 36;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final button = Material(
      // Transparent so the ripple paints over the pill fill instead of
      // covering it with a second opaque surface.
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: _size,
          height: _size,
          child: AppIcon(icon, size: _iconSize, color: colors.onBackground),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: button);
  }
}

class _TodayReset extends StatelessWidget {
  const _TodayReset({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.xl);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelMedium?.copyWith(
              color: colors.primaryInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

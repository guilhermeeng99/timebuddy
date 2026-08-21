import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/routes/app_shell.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/timebuddy_date_pill.dart';
import 'package:timebuddy/features/time_grid/presentation/cubit/time_grid_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The reference-day stepper, placed by the breakpoint.
///
/// `ShellDatePill` renders it here on a phone and publishes it into the
/// sidebar once the rail is wide enough to hold it (design_system §7). It
/// still takes a row of layout in the first case only, which is why the
/// padding lives inside the pill branch.
///
/// [referenceDate] is the day the grid is currently showing; the widget reads
/// [TimeGridCubit] from the tree for the two things only the cubit can answer
/// — what "today" is, and where a change goes.
///
/// ```dart
/// GridDateBar(referenceDate: model.referenceDate),
/// ```
class GridDateBar extends StatelessWidget {
  const GridDateBar({required this.referenceDate, super.key});

  final DateTime referenceDate;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TimeGridCubit>();
    return ShellDatePill(
      pill: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TimeBuddyDatePill(
            value: referenceDate,
            // "Today" is a question about the home zone, never about the
            // device (rule 11): a user whose home is Tokyo is already on
            // tomorrow.
            today: cubit.todayInHomeZone,
            todayLabel: t.grid.today,
            onChanged: cubit.setReferenceDate,
          ),
        ),
      ),
    );
  }
}

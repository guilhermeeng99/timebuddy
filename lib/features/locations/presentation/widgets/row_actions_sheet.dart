import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_row.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_sheet.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// What the user picked from a saved row's action sheet.
///
/// The sheet reports a choice instead of performing it. Two callers open it —
/// the locations list and a long-press on a grid row label
/// (docs/specs/time_grid.md, Interaction) — and both already hold the
/// `BoardCubit` the mutation has to go through, so a sheet that mutated would
/// be a second place that writes the board.
enum LocationRowAction {
  /// Make this row's zone the board's reference zone.
  setHome,

  /// Take the row off the board. The caller owns the undo window.
  remove,

  /// Point this row at a different zone, keeping its id and position. The one
  /// repair for a row whose zone the tzdata no longer knows
  /// (docs/specs/locations.md rule 11).
  replaceZone,
}

/// Opens the action sheet for one saved location.
///
/// Resolves to the chosen [LocationRowAction], or to `null` when the sheet is
/// dismissed — and also when the user taps "set as home" on the row that
/// already is home, since that choice is a no-op rather than a mutation.
///
/// [label] titles the sheet, so the user can see which of twenty rows they
/// long-pressed. [isHome] only decides how the first row is marked; it never
/// removes the row, because an action list whose entries move between openings
/// is one a thumb cannot learn.
///
/// The copy is the board's (`t.locations.*`), whichever screen opened the
/// sheet. One sheet that renamed its own actions depending on the caller would
/// teach the user two vocabularies for one gesture.
///
/// ```dart
/// final action = await showLocationRowActionsSheet(
///   context,
///   label: location.label,
///   isHome: location.zoneId == board.homeZoneId,
/// );
/// if (action == LocationRowAction.remove) removeWithUndo(location);
/// ```
Future<LocationRowAction?> showLocationRowActionsSheet(
  BuildContext context, {
  required String label,
  required bool isHome,
}) {
  return showTimeBuddyPickerSheet<LocationRowAction>(
    context,
    builder: (_) => _RowActionsBody(label: label, isHome: isHome),
  );
}

class _RowActionsBody extends StatelessWidget {
  const _RowActionsBody({required this.label, required this.isHome});

  final String label;
  final bool isHome;

  @override
  Widget build(BuildContext context) {
    // Fixed rather than draggable: three options, and a sheet that opened at
    // 70% of the screen for them would be mostly empty surface.
    return TimeBuddyPickerSheet.fixed(
      title: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TimeBuddyPickerRow(
            leading: const Icon(Icons.home_outlined),
            title: t.locations.setAsHome,
            // Already home reads as the selected option, which is what the
            // check mark means everywhere else in the app. Tapping it closes
            // the sheet without reporting an action.
            isSelected: isHome,
            onTap: () =>
                _close(context, isHome ? null : LocationRowAction.setHome),
          ),
          TimeBuddyPickerRow(
            leading: const Icon(Icons.swap_horiz_outlined),
            title: t.locations.replaceZone,
            onTap: () => _close(context, LocationRowAction.replaceZone),
          ),
          TimeBuddyPickerRow(
            leading: const Icon(Icons.delete_outline),
            title: t.common.remove,
            onTap: () => _close(context, LocationRowAction.remove),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }

  void _close(BuildContext context, LocationRowAction? action) =>
      Navigator.of(context).pop(action);
}

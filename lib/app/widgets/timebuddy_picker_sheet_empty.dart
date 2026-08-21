import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// The placeholder a picker body shows when it has nothing to list: no data
/// yet, or no hit for the current query.
///
/// Deliberately smaller than `FeatureEmptyState`, which owns a whole screen
/// and sells a feature. Inside a sheet the user is mid-task and already knows
/// what they were looking for; one muted line telling them it is not there is
/// the entire job, and an illustration plus a CTA would only push the search
/// field they need to edit further away.
///
/// ```dart
/// TimeBuddyPickerSheet(
///   title: t.locations.addTitle,
///   header: searchField,
///   bodyBuilder: (context, scrollController) => TimeBuddyPickerSheetEmpty(
///     message: t.locations.searchNoResults,
///     scrollController: scrollController,
///   ),
/// );
/// ```
class TimeBuddyPickerSheetEmpty extends StatelessWidget {
  const TimeBuddyPickerSheetEmpty({
    required this.message,
    this.scrollController,
    super.key,
  });

  /// The finished, localized line. Name the thing that was not found; "No
  /// city matches that" beats "No results".
  final String message;

  /// The controller handed to `bodyBuilder` by the draggable
  /// `TimeBuddyPickerSheet`. Pass it and the placeholder becomes a scrollable
  /// attached to the sheet, so dragging still resizes it: a sheet that goes
  /// rigid exactly when the list empties out feels broken, and an empty list
  /// is the moment the user most wants to pull the sheet down and see the
  /// page again. Leave it null inside a fixed sheet, which does not drag.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.appColors.onBackgroundLight,
          ),
        ),
      ),
    );
    final controller = scrollController;
    if (controller == null) return content;
    return CustomScrollView(
      controller: controller,
      // Always scrollable, though nothing overflows: the drag gesture is the
      // point, not the scroll.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // The one sliver that both fills the viewport and centres a child
        // inside it, which a SingleChildScrollView cannot do without a
        // LayoutBuilder measuring the sheet by hand.
        SliverFillRemaining(
          hasScrollBody: false,
          child: content,
        ),
      ],
    );
  }
}

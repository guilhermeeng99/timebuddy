import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// How much of the screen [TimeBuddyPickerSheet.fixed] may take before its
/// body scrolls. Short content still shrink-wraps; the cap only catches the
/// case where "short" turns out to be twelve rows on a small phone.
const double _maxFixedHeightFraction = 0.7;

/// Resting, minimum and maximum extents of the draggable variant, as
/// fractions of the height the sheet is given.
const double _defaultInitialSize = 0.7;
const double _defaultMinSize = 0.4;
const double _defaultMaxSize = 0.95;

/// The drag handle, sized to the Material 3 default.
const double _handleWidth = 32;
const double _handleHeight = 4;

/// Bottom padding that keeps a sheet body clear of the on-screen keyboard.
///
/// Nothing in a bottom-anchored modal moves out of the keyboard's way by
/// itself, and a picker whose header is a search field spends most of its
/// life with the keys up. It is paid inside the body rather than around the
/// whole sheet on purpose: an inset taller than the sheet then squeezes the
/// list, where padding the column would overflow it instead.
EdgeInsets _keyboardInset(BuildContext context) =>
    EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom);

/// Opens [builder] as a modal picker sheet, resolving to the value the sheet
/// pops or to `null` when it is dismissed.
///
/// Every picker goes through this helper instead of calling
/// `showModalBottomSheet` itself. Three settings have to agree across sheets
/// for them to read as one app — `isScrollControlled`, the rounded top and
/// the safe-area inset — and the cost of forgetting the first one is not
/// cosmetic: the sheet gets capped at half the screen, so a search field in
/// the header ends up under the keyboard the moment it is focused.
///
/// ```dart
/// final city = await showTimeBuddyPickerSheet<CityEntity>(
///   context,
///   builder: (_) => TimeBuddyPickerSheet(
///     title: t.locations.addCity,
///     header: TimeBuddySearchField(
///       hintText: t.locations.searchHint,
///       onChanged: cubit.search,
///     ),
///     bodyBuilder: (context, scrollController) => ListView.builder(
///       controller: scrollController,
///       itemCount: cities.length,
///       itemBuilder: (context, index) => TimeBuddyPickerRow(
///         title: cities[index].name,
///         onTap: () => Navigator.of(context).pop(cities[index]),
///       ),
///     ),
///   ),
/// );
/// ```
Future<T?> showTimeBuddyPickerSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // Keeps a near-full-height sheet off the status bar and the notch, where
    // the drag handle would otherwise land.
    useSafeArea: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: builder,
  );
}

/// The chrome every modal picker wears: rounded surface, drag handle,
/// left-aligned title and an optional header slot for a search field.
///
/// Two shapes, because picker bodies come in two sizes:
///
/// * the default constructor is **draggable**. It hands `bodyBuilder` the
///   [ScrollController] the sheet resizes with, for a body that may be
///   hundreds of rows long (the city picker). Attach that controller to the
///   scroll view, or dragging the list stops resizing the sheet;
/// * [TimeBuddyPickerSheet.fixed] **shrink-wraps** a short body — a handful
///   of options, where a sheet opening at 70% of the screen would be mostly
///   empty surface.
///
/// The sheet owns no copy and no state: [title] arrives finished and the rows
/// pop their own value, so it can be opened from anywhere and tested alone.
/// Fill it with `TimeBuddyPickerRow`s, or with `TimeBuddyPickerSheetEmpty`
/// when there is nothing to list, and open it with
/// [showTimeBuddyPickerSheet].
class TimeBuddyPickerSheet extends StatelessWidget {
  const TimeBuddyPickerSheet({
    required this.title,
    required ScrollableWidgetBuilder bodyBuilder,
    this.header,
    this.initialSize = _defaultInitialSize,
    this.minSize = _defaultMinSize,
    this.maxSize = _defaultMaxSize,
    super.key,
  }) : _bodyBuilder = bodyBuilder,
       _fixedChild = null;

  /// A sheet only as tall as its content, up to 70% of the screen.
  ///
  /// Use it for a body that cannot grow — a mode picker, the palette list.
  /// Anything list-shaped and open-ended wants the draggable constructor.
  ///
  /// ```dart
  /// TimeBuddyPickerSheet.fixed(
  ///   title: t.settings.lightPalette,
  ///   child: ListView(shrinkWrap: true, children: rows),
  /// );
  /// ```
  const TimeBuddyPickerSheet.fixed({
    required this.title,
    required Widget child,
    this.header,
    super.key,
  }) : _fixedChild = child,
       _bodyBuilder = null,
       // Inert here: the fixed variant is sized by its content, never by an
       // extent. They are still assigned so one field set serves both
       // constructors.
       initialSize = _defaultInitialSize,
       minSize = _defaultMinSize,
       maxSize = _defaultMaxSize;

  /// Sheet title, already localized, left-aligned under the handle.
  final String title;

  /// Optional widget between the title and the body, most often a
  /// `TimeBuddySearchField`. Stack several in a `Column` if a picker ever
  /// needs more than one.
  final Widget? header;

  /// Resting height of the draggable variant, as a fraction of the height
  /// available to it. Ignored by [TimeBuddyPickerSheet.fixed].
  final double initialSize;

  /// How far down the draggable variant may be pulled before it stops.
  final double minSize;

  /// How far up the draggable variant may be pushed.
  final double maxSize;

  final ScrollableWidgetBuilder? _bodyBuilder;
  final Widget? _fixedChild;

  @override
  Widget build(BuildContext context) {
    final bodyBuilder = _bodyBuilder;
    if (bodyBuilder != null) {
      return _DraggableSheetBody(
        title: title,
        header: header,
        bodyBuilder: bodyBuilder,
        initialSize: initialSize,
        minSize: minSize,
        maxSize: maxSize,
      );
    }
    return _SheetSurface(
      child: _SheetColumn(
        title: title,
        header: header,
        maxHeight: context.screenSize.height * _maxFixedHeightFraction,
        // Flexible rather than Expanded: a two-row body keeps its natural
        // height instead of stretching the sheet up to the cap.
        body: Flexible(
          child: Padding(
            padding: _keyboardInset(context),
            child: _fixedChild,
          ),
        ),
      ),
    );
  }
}

/// The draggable variant's body, split out so the builder it needs can be
/// non-nullable here rather than null-asserted at every use.
class _DraggableSheetBody extends StatelessWidget {
  const _DraggableSheetBody({
    required this.title,
    required this.header,
    required this.bodyBuilder,
    required this.initialSize,
    required this.minSize,
    required this.maxSize,
  });

  final String title;
  final Widget? header;
  final ScrollableWidgetBuilder bodyBuilder;
  final double initialSize;
  final double minSize;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      // The modal route already sizes itself around this sheet; expanding
      // would stretch it to the full screen and throw [initialSize] away.
      expand: false,
      builder: _buildSurface,
    );
  }

  Widget _buildSurface(
    BuildContext context,
    ScrollController scrollController,
  ) {
    return _SheetSurface(
      child: _SheetColumn(
        title: title,
        header: header,
        body: Expanded(
          child: Padding(
            padding: _keyboardInset(context),
            child: bodyBuilder(context, scrollController),
          ),
        ),
      ),
    );
  }
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A Material, not a DecoratedBox carrying the surface colour. InkWell and
    // ListTile paint their ink on the nearest Material ancestor, so a plain
    // coloured box between a picker row and the scaffold swallows every
    // ripple: the row still fires onTap, it just looks dead under the finger.
    // That is a real M1 bug, not a hypothetical, and it survives review
    // because it only shows up under a thumb. clipBehavior keeps the ink
    // inside the rounded corners.
    return Material(
      color: context.appColors.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        // Bottom edge only: showTimeBuddyPickerSheet already keeps the top
        // clear, and a second top inset would push the handle down the sheet.
        top: false,
        child: child,
      ),
    );
  }
}

class _SheetColumn extends StatelessWidget {
  const _SheetColumn({
    required this.title,
    required this.header,
    required this.body,
    this.maxHeight,
  });

  final String title;
  final Widget? header;

  /// Already wrapped in the `Expanded` or `Flexible` the variant needs: only
  /// a direct child of the column can claim the space left over.
  final Widget body;

  /// Caps the column's height. Null for the draggable variant, whose extent
  /// is the sheet's own business.
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final headerSlot = header;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHandle(),
        _SheetTitle(title: title),
        if (headerSlot != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: headerSlot,
          ),
        body,
      ],
    );
    final cap = maxHeight;
    if (cap == null) return column;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: cap),
      child: column,
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Text(title, style: context.textTheme.headlineSmall),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Center(
        child: Container(
          width: _handleWidth,
          height: _handleHeight,
          decoration: BoxDecoration(
            color: context.appColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
      ),
    );
  }
}

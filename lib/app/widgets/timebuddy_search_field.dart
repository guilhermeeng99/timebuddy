import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';

/// The app's search-as-you-type input, used by every picker that filters a
/// list — first and foremost the city picker.
///
/// **Debouncing is the caller's business.** This field reports every
/// keystroke through [onChanged], immediately. The right delay depends on
/// what a query costs, and only the caller knows that: filtering ~600 cities
/// already in memory wants none, while a query that hits the network wants
/// the 200 ms `LocationSearchCubit` applies (docs/specs/locations.md). A
/// field that debounced internally would make the cheap case feel laggy for
/// nothing, and would hide the delay from the tests that care about it.
///
/// ```dart
/// TimeBuddySearchField(
///   hintText: t.locations.searchHint,
///   autofocus: true,
///   clearTooltip: t.common.clear,
///   onChanged: context.read<LocationSearchCubit>().search,
/// );
/// ```
class TimeBuddySearchField extends StatefulWidget {
  const TimeBuddySearchField({
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    this.clearTooltip,
    super.key,
  });

  /// Placeholder copy, already localized. Say what is searched ("Search a
  /// city"), not what to do ("Type here").
  final String hintText;

  /// Called on every keystroke, and once with an empty string when the clear
  /// button is tapped.
  final ValueChanged<String> onChanged;

  /// Optional external controller, for a caller that needs to seed or read
  /// the query (restoring a previous search, say). When it is null the field
  /// makes and owns one. It is read once, on mount: handing the field a
  /// different controller later has no effect, and a caller that needs that
  /// should key the field instead.
  final TextEditingController? controller;

  /// Whether to raise the keyboard on mount. True for a search sheet the user
  /// opened *in order to* type; false for a search box on a page that has
  /// other content worth seeing first.
  final bool autofocus;

  /// Localized tooltip for the clear button. Null renders the button without
  /// one, which is why the copy lives here rather than in this widget: a
  /// design-system component holds no strings.
  final String? clearTooltip;

  @override
  State<TimeBuddySearchField> createState() => _TimeBuddySearchFieldState();
}

class _TimeBuddySearchFieldState extends State<TimeBuddySearchField> {
  late final TextEditingController _controller;

  /// Whether [_controller] is ours to dispose. Disposing an injected one
  /// would kill a controller the caller still owns and may reuse on the next
  /// build, which surfaces as a "used after disposed" crash far from here.
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    _ownsController = injected == null;
    _controller = injected ?? TextEditingController();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    // `clear()` does not fire the field's onChanged: that only runs for user
    // edits. Without this the box would empty while the results below kept
    // showing the hits for the query the user just wiped.
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      style: context.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: context.textTheme.bodyMedium?.copyWith(
          color: colors.onBackgroundLight,
        ),
        prefixIcon: AppIcon(
          FontAwesomeIcons.magnifyingGlass,
          color: colors.onBackgroundLight,
        ),
        suffixIcon: _ClearButton(
          controller: _controller,
          tooltip: widget.clearTooltip,
          onClear: _clear,
        ),
      ),
    );
  }
}

/// The trailing clear button, shown only while there is something to clear.
///
/// It listens to the controller itself instead of the field calling
/// `setState`, so a keystroke repaints one icon rather than the whole input.
class _ClearButton extends StatelessWidget {
  const _ClearButton({
    required this.controller,
    required this.tooltip,
    required this.onClear,
  });

  final TextEditingController controller;
  final String? tooltip;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        return IconButton(
          icon: const AppIcon(FontAwesomeIcons.xmark),
          color: context.appColors.onBackgroundLight,
          tooltip: tooltip,
          onPressed: onClear,
        );
      },
    );
  }
}

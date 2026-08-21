import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/app/widgets/feature_empty_state.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The grid with nothing to compare yet.
///
/// A board with no cities is a valid state and not an error (locations.md rule
/// 6), so it gets the shared invitation rather than `ErrorView`'s apology. All
/// this widget picks is the grid's own copy and the one way out of it, which
/// is why it takes no parameters.
///
/// ```dart
/// TimeGridEmpty() => const GridEmptyBoard(),
/// ```
class GridEmptyBoard extends StatelessWidget {
  const GridEmptyBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureEmptyState(
      icon: FontAwesomeIcons.earthAmericas,
      title: t.grid.emptyTitle,
      message: t.grid.emptyMessage,
      ctaLabel: t.grid.emptyCta,
      onCta: () => context.push(AppRoutes.addLocation),
    );
  }
}

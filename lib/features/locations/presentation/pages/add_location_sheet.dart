import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_row.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_sheet.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_sheet_empty.dart';
import 'package:timebuddy/app/widgets/timebuddy_search_field.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/locations/presentation/cubit/location_search_cubit.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// How many placeholder rows stand in for the catalog while it loads.
const int _loadingRowCount = 6;

/// The localized sentence for a board write the cubit refused.
///
/// It lives beside the picker because this is where the two interesting
/// rejections are provoked — every selection can collide with an existing row
/// or hit the cap — but the board list needs the same mapping for its undo,
/// which can be refused for exactly those two reasons a few seconds later
/// (`BoardCubit.undoRemove`). One switch, so the two screens cannot end up
/// explaining the same refusal differently.
///
/// A duplicate and a full board are ordinary answers rather than errors, and
/// both are worth their own sentence: "already covered by Sao Paulo" tells the
/// user which of their rows collided, and the cap message tells them why a
/// perfectly valid city was refused (docs/specs/locations.md rules 2 and 4).
///
/// ```dart
/// final failure = await context.read<BoardCubit>().addCity(city);
/// if (failure != null) context.showSnack(boardWriteFailureMessage(failure));
/// ```
String boardWriteFailureMessage(Failure failure) => switch (failure) {
  DuplicateZoneFailure(:final existingLabel) => t.locations.duplicateZone(
    city: existingLabel,
  ),
  BoardFullFailure(:final max) => t.locations.boardFull(max: max),
  // Anything else is a write that did not land. The cubit has already rolled
  // the board back, so the generic message is the honest one.
  ServerFailure() ||
  AuthFailure() ||
  ValidationFailure() ||
  StorageFailure() ||
  NotFoundFailure() => t.common.errorBody,
};

/// Opens the city picker over the current page.
///
/// A modal rather than a pushed page, and deliberately: the sheet writes
/// through the `BoardCubit` the *shell* provides, and this helper captures it
/// from the caller's context and re-provides it inside the route. A route is
/// not a descendant of the widget that pushed it, so without that hand-off
/// the sheet could not read the cubit at all.
///
/// Resolves when the sheet closes. The board is already updated by then; the
/// caller has nothing to do with the result.
///
/// Pass [replaces] to repoint an existing row at a different zone instead of
/// adding one — the repair offered for a row whose zone the tzdata dropped
/// (docs/specs/locations.md rule 11).
///
/// ```dart
/// FloatingActionButton(
///   onPressed: () => unawaited(showAddLocationSheet(context)),
///   child: AppIcon(FontAwesomeIcons.plus),
/// );
/// ```
Future<void> showAddLocationSheet(
  BuildContext context, {
  SavedLocationEntity? replaces,
}) {
  final boardCubit = context.read<BoardCubit>();
  return showTimeBuddyPickerSheet<void>(
    context,
    builder: (_) => BlocProvider<BoardCubit>.value(
      value: boardCubit,
      child: AddLocationSheet(replaces: replaces),
    ),
  );
}

/// The city picker body: search field, ranked results, one tap to commit.
///
/// Public so a host route can render it as a page. Whatever hosts it must
/// have a `BoardCubit` above it — the selection is written through that cubit
/// and nowhere else (docs/specs/locations.md) — and must be inside a
/// [Navigator] it is willing to have popped, because a committed selection
/// closes whatever route it is sitting in.
class AddLocationSheet extends StatelessWidget {
  const AddLocationSheet({this.replaces, super.key});

  /// The row being repointed, or `null` when adding a new one.
  final SavedLocationEntity? replaces;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LocationSearchCubit>(
      // Page-scoped: created with the sheet and closed with it (CLAUDE.md,
      // Lifecycle). The catalog behind it is the singleton, so opening the
      // sheet a second time costs a search, not a parse.
      create: (_) => _createSearchCubit(),
      child: _PickerChrome(replaces: replaces),
    );
  }

  /// Builds the sheet's cubit and starts its first read.
  ///
  /// The default list is fetched here rather than from the search field's
  /// first keystroke, because the sheet has to be useful before anything is
  /// typed (docs/specs/locations.md, State Machine).
  LocationSearchCubit _createSearchCubit() {
    final cubit = LocationSearchCubit(repository: sl<CityCatalogRepository>());
    unawaited(cubit.loadDefaults());
    return cubit;
  }
}

class _PickerChrome extends StatelessWidget {
  const _PickerChrome({required this.replaces});

  final SavedLocationEntity? replaces;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LocationSearchCubit>();
    return TimeBuddyPickerSheet(
      title: replaces == null ? t.locations.addTitle : t.locations.replaceZone,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TimeBuddySearchField(
            hintText: t.locations.searchHint,
            // The user opened this sheet in order to type; anything else is a
            // tap they should not have had to make.
            autofocus: true,
            clearTooltip: t.common.clear,
            // Undebounced by design: the field reports keystrokes and the
            // cubit owns the 200 ms wait, which is the only place a test can
            // see it.
            onChanged: cubit.search,
          ),
          // How full the board is, stated where it is about to matter
          // (docs/specs/locations.md rule 4): a user who meets
          // `BoardFullFailure` at the twenty-first city should have been able
          // to see it coming. The board page's header used to carry this and
          // the board page is gone; the moment before choosing a city is a
          // better place for it than a screen the user had to visit on
          // purpose.
          //
          // Absent while replacing a zone, which swaps a row rather than
          // adding one and so cannot reach the cap.
          if (replaces == null) const _BoardCount(),
        ],
      ),
      bodyBuilder: (_, scrollController) => _PickerBody(
        scrollController: scrollController,
        replaces: replaces,
      ),
    );
  }
}

/// How many of the twenty places are already taken.
///
/// Reads `BoardCubit` rather than taking a count as an argument: the sheet is
/// open across the add that changes it, so a number passed in at open time
/// would be stale the moment it mattered.
class _BoardCount extends StatelessWidget {
  const _BoardCount();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BoardCubit, BoardState>(
      builder: (context, state) {
        // Silent until the board is there. A count rendered from a state that
        // has not loaded would read "0 of 20" over a board that is full.
        if (state is! BoardLoaded) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            t.locations.countLabel(
              count: state.board.locations.length,
              max: BoardEntity.maxLocations,
            ),
            style: context.textTheme.bodySmall?.copyWith(
              color: context.appColors.onBackgroundLight,
            ),
          ),
        );
      },
    );
  }
}

/// Every state of the search, drawn into the same scroll view.
///
/// One `CustomScrollView` for all four rather than a widget per state, because
/// the sheet resizes by way of the controller it hands down: a body that stops
/// being scrollable — while loading, or when a query matches nothing — is a
/// sheet that goes rigid exactly when the user wants to pull it back down.
class _PickerBody extends StatelessWidget {
  const _PickerBody({required this.scrollController, required this.replaces});

  final ScrollController scrollController;
  final SavedLocationEntity? replaces;

  @override
  Widget build(BuildContext context) {
    // A messenger and a Scaffold of this sheet's own, so a refused selection
    // is actually *seen*. The app's messenger draws into the page's Scaffold,
    // which is a sibling route sitting behind this one: a duplicate-zone
    // snackbar shown through it lands under the sheet and is invisible, and a
    // rejection the user cannot read is the same as no rejection at all
    // (docs/specs/locations.md rules 2 and 4). Scoped to the body rather than
    // wrapped around the whole sheet on purpose — a Scaffold above
    // `TimeBuddyPickerSheet` would expand to the full route and paint over
    // the page the sheet is supposed to float on.
    return ScaffoldMessenger(
      child: Scaffold(
        // Not a second surface: the same token the sheet already paints, so
        // the Scaffold is invisible without reaching for a literal colour.
        backgroundColor: context.appColors.surface,
        // The sheet already pads its body by the keyboard inset; a Scaffold
        // that also resized would pay for it twice.
        resizeToAvoidBottomInset: false,
        body: BlocBuilder<LocationSearchCubit, LocationSearchState>(
          builder: (context, state) => CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [_sliverFor(context, state)],
          ),
        ),
      ),
    );
  }

  Widget _sliverFor(BuildContext context, LocationSearchState state) {
    return switch (state) {
      LocationSearchInitial() || LocationSearchLoading() => _loadingSliver,
      // Only the picker reports a broken catalog: the board itself still
      // renders from its stored labels (docs/specs/locations.md, Edge Cases).
      LocationSearchError(:final failure) => _errorSliver(context, failure),
      LocationSearchEmpty() => _emptySliver,
      LocationSearchResults(:final cities) => _resultsSliver(cities),
    };
  }

  static const Widget _loadingSliver = SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: LoadingShimmer(rowCount: _loadingRowCount),
    ),
  );

  Widget get _emptySliver => SliverFillRemaining(
    hasScrollBody: false,
    child: TimeBuddyPickerSheetEmpty(message: t.locations.searchNoResults),
  );

  Widget _errorSliver(BuildContext context, Failure failure) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: ErrorView(
        failure: failure,
        // Retrying the default list, not the query: the catalog is what
        // failed, and it is the same read either way.
        onRetry: () =>
            unawaited(context.read<LocationSearchCubit>().loadDefaults()),
      ),
    );
  }

  /// Lazy, because a query can return thirty rows and the default list is
  /// one per IANA region (CLAUDE.md, Performance).
  Widget _resultsSliver(List<CityEntity> cities) => SliverList.builder(
    itemCount: cities.length,
    itemBuilder: (context, index) =>
        _CityRow(city: cities[index], replaces: replaces),
  );
}

class _CityRow extends StatelessWidget {
  const _CityRow({required this.city, required this.replaces});

  final CityEntity city;
  final SavedLocationEntity? replaces;

  @override
  Widget build(BuildContext context) {
    return TimeBuddyPickerRow(
      title: city.name,
      subtitle: _subtitle,
      // Nothing in this list is "current": a city already on the board is
      // rejected on selection with the row it collides with named, which says
      // more than a check mark would.
      onTap: () => unawaited(_select(context)),
    );
  }

  /// Where the city is, then which clock it keeps.
  ///
  /// The zone id earns its place next to the country: it is what the user is
  /// actually adding, it is what tells two same-country cities apart, and it
  /// is the string a power user pasted into the search field to get here
  /// (docs/specs/locations.md rule 10).
  String get _subtitle {
    final admin1 = city.admin1;
    final place = admin1 == null
        ? city.countryName
        : '$admin1, ${city.countryName}';
    return '$place · ${city.zoneId}';
  }

  Future<void> _select(BuildContext context) async {
    final board = context.read<BoardCubit>();
    final navigator = Navigator.of(context);
    final row = replaces;
    final failure = row == null
        ? await board.addCity(city)
        : await board.replaceZone(locationId: row.id, city: city);
    if (!context.mounted) return;
    if (failure == null) {
      navigator.pop();
      return;
    }
    // A duplicate or a full board is feedback, not a broken screen: the sheet
    // stays open so the user can pick something else without reopening it.
    context.showSnack(boardWriteFailureMessage(failure));
  }
}

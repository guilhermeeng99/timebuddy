import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/time_grid/domain/entities/grid_view_model.dart';

/// State of `TimeGridCubit` (docs/specs/time_grid.md, State Machine).
///
/// The grid owns no data of its own: it is a view over the board and the
/// preferences, so the only thing worth carrying in the ready state is the
/// finished [GridViewModel]. Cursor, reference date and "now" all live inside
/// it rather than beside it, which is what lets a tick or a cursor move be one
/// `copyWith` instead of a second source of truth the widgets have to
/// reconcile.
sealed class TimeGridState extends Equatable {
  const TimeGridState();

  @override
  List<Object?> get props => const [];
}

/// Before the board has resolved. The page renders `LoadingShimmer`.
final class TimeGridLoading extends TimeGridState {
  const TimeGridLoading();
}

/// The board loaded and holds no locations (locations.md rule 6).
///
/// A distinct state rather than a `TimeGridReady` with zero rows, because the
/// page must render `FeatureEmptyState` and *not* a header strip over nothing
/// (time_grid.md, edge cases).
final class TimeGridEmpty extends TimeGridState {
  const TimeGridEmpty();
}

/// The grid has something to draw.
final class TimeGridReady extends TimeGridState {
  const TimeGridReady({required this.model});

  final GridViewModel model;

  @override
  List<Object?> get props => [model];
}

/// The board could not be read at all.
///
/// Carries the [Failure] so `ErrorView` can pick its icon from the type; the
/// message it renders is localized copy, never `Failure.message`.
final class TimeGridError extends TimeGridState {
  const TimeGridError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

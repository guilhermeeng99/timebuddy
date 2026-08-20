import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/world_clock/domain/entities/world_clock_view_model.dart';

/// State of `WorldClockCubit` (docs/specs/world_clock.md, State Machine).
///
/// The page owns no data of its own: it is a view over the board and the
/// preferences, so the only thing worth carrying in the ready state is the
/// finished [WorldClockViewModel]. "Now" lives inside the model rather than
/// beside it, which is what lets a tick be one rebuild instead of a second
/// source of truth the widgets have to reconcile.
///
/// There is deliberately **no** `WorldClockEmpty`. A board with no saved
/// cities is a valid [WorldClockReady] with an empty `tiles` list and a present
/// `home` (rule 11): the user's own clock is never hidden behind an empty
/// state.
sealed class WorldClockState extends Equatable {
  const WorldClockState();

  @override
  List<Object?> get props => const [];
}

/// Before the board has resolved. The page renders `LoadingShimmer`.
final class WorldClockLoading extends WorldClockState {
  const WorldClockLoading();
}

/// The page has clocks to draw — at minimum the home hero.
final class WorldClockReady extends WorldClockState {
  const WorldClockReady({required this.model});

  final WorldClockViewModel model;

  @override
  List<Object?> get props => [model];
}

/// The board could not be read at all.
///
/// Carries the [Failure] so `ErrorView` can pick its icon from the type; the
/// message it renders is localized copy, never `Failure.message`.
final class WorldClockError extends WorldClockState {
  const WorldClockError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

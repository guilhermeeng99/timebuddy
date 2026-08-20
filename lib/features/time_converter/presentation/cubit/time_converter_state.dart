import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/time_converter/domain/entities/conversion_result.dart';

/// State of `TimeConverterCubit` (docs/specs/time_converter.md, State
/// Machine).
///
/// The converter owns no data of its own: it is one question asked of the
/// board, so the only thing worth carrying in the ready state is the finished
/// [ConversionResult]. The input lives inside it rather than beside it, which
/// is what lets every setter be one recompute instead of a second source of
/// truth the fields have to reconcile.
///
/// There is deliberately **no state for a conversion in flight**. Every input
/// change recomputes synchronously from data already in memory, and a spinner
/// for a microsecond of arithmetic is worse than none (spec, State Machine).
sealed class TimeConverterState extends Equatable {
  const TimeConverterState();

  @override
  List<Object?> get props => const [];
}

/// The frames before the board has resolved, and only those.
///
/// Not the loading state the spec rules out: nothing here is waiting on the
/// conversion, which is pure arithmetic over in-memory data. It is the board
/// document that may still be arriving, and the page renders a shimmer for it
/// exactly as the grid and the world clock do. No setter ever emits it, so a
/// later change cannot quietly turn it into a spinner over a keystroke.
final class ConverterPreparing extends TimeConverterState {
  const ConverterPreparing();
}

/// There is an answer on screen. The only state a working converter is in.
final class ConverterReady extends TimeConverterState {
  const ConverterReady({required this.result});

  /// The whole answer: the input that produced it, the instant it resolved
  /// to, how faithfully it resolved (rules 4 and 5) and every line.
  final ConversionResult result;

  @override
  List<Object?> get props => [result];
}

/// The board could not be read at all.
///
/// Reachable only from a board load that failed (spec, State Machine): the
/// conversion itself cannot fail, because an unresolvable zone degrades
/// inside the use case rather than throwing.
///
/// Carries the [Failure] so `ErrorView` can pick its icon from the type; the
/// message it renders is localized copy, never `Failure.message`.
final class ConverterError extends TimeConverterState {
  const ConverterError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// Which shape the pasteable text takes (docs/specs/meeting_planner.md rule
/// 9). The choice is a preference, which is why it lives beside the entities
/// rather than inside `FormatMeetingTextUseCase`: the preferences document
/// must be able to name it without importing a use case.
enum MeetingTextStyle {
  /// One line per location: label, date when it differs, and the range.
  compact,

  /// The same lines with the date always present and the UTC offset spelled
  /// out, for a message whose reader is not in any of the zones.
  verbose,
}

/// A contiguous range of grid slots, expressed as the two UTC instants that
/// bound it.
///
/// Rule 1: a selection is never a local hour. `14:00` is meaningless without a
/// zone and a date, and the same range reads as a different wall clock in
/// every row of the board, so the only representation that survives being
/// looked at from twenty places is the pair of instants.
///
/// [startInstant] is inclusive and [endInstant] exclusive. [slotCount] counts
/// the columns the gesture covered and is **not** a duration: on a transition
/// day three columns can read four wall-clock hours apart (rule 8). Anything
/// that needs the real length subtracts the instants.
///
/// ```dart
/// final selection = MeetingSelection.fromSlots(
///   slots: model.slots,
///   anchorIndex: dragStart,
///   cursorIndex: dragEnd,
/// );
/// selection.endInstant.difference(selection.startInstant); // real length
/// ```
class MeetingSelection extends Equatable {
  const MeetingSelection({
    required this.startInstant,
    required this.endInstant,
    required this.slotCount,
  }) : assert(
         slotCount >= minSlots && slotCount <= maxSlots,
         'rule 3: a selection covers 1 to 12 slots',
       );

  /// The selection a drag from [anchorIndex] to [cursorIndex] produces.
  ///
  /// [slots] is the column set the gesture happened on: ascending UTC
  /// instants, normally `GridViewModel.slots`. Both indexes are clamped into
  /// the list, and a backwards drag is the same range read the other way
  /// round.
  ///
  /// Rule 3: past [maxSlots] the gesture **stops at the cap** instead of being
  /// refused, and the cap is measured from the anchor, so the end the user is
  /// holding still stays where they put it.
  ///
  /// ```dart
  /// MeetingSelection.fromSlots(slots: slots, anchorIndex: 9, cursorIndex: 40)
  ///     .slotCount; // 12, not 32
  /// ```
  factory MeetingSelection.fromSlots({
    required List<DateTime> slots,
    required int anchorIndex,
    required int cursorIndex,
  }) {
    if (slots.isEmpty) {
      throw ArgumentError.value(
        slots,
        'slots',
        'a selection needs at least one slot to sit on',
      );
    }

    final anchor = _indexIn(slots, anchorIndex);
    final cursor = _indexIn(slots, cursorIndex);
    final capped = cursor >= anchor
        ? math.min(cursor, anchor + maxSlots - 1)
        : math.max(cursor, anchor - maxSlots + 1);
    final first = math.min(anchor, capped);
    final last = math.max(anchor, capped);

    return MeetingSelection(
      startInstant: slots[first],
      endInstant: _slotEndIn(slots, last),
      slotCount: last - first + 1,
    );
  }

  /// Rule 3's floor: one slot is a valid meeting.
  static const int minSlots = 1;

  /// Rule 3's cap. Past half a day the "meeting" framing stops meaning
  /// anything and the summary becomes unreadable.
  static const int maxSlots = 12;

  /// One column is one **real** hour, exactly as on the grid
  /// (`BuildGridUseCase.slotDuration`): on a fall-back day two neighbouring
  /// columns show the same wall clock, which is the point. Used only to close
  /// a range that ends on the last column its caller handed over, and to step
  /// the hours a range occupies.
  static const Duration slotDuration = Duration(hours: 1);

  /// UTC, inclusive. The moment the meeting starts, in every zone at once.
  final DateTime startInstant;

  /// UTC, exclusive. The moment it is over.
  final DateTime endInstant;

  /// How many grid columns the selection covers, `1..12`.
  final int slotCount;

  MeetingSelection copyWith({
    DateTime? startInstant,
    DateTime? endInstant,
    int? slotCount,
  }) {
    return MeetingSelection(
      startInstant: startInstant ?? this.startInstant,
      endInstant: endInstant ?? this.endInstant,
      slotCount: slotCount ?? this.slotCount,
    );
  }

  @override
  List<Object?> get props => [startInstant, endInstant, slotCount];
}

/// One location's answer to "when is this meeting for you?".
///
/// Every field is already decided: the widget layer renders a line and
/// computes nothing from it, the same contract the grid's `GridCell` carries.
class MeetingLine extends Equatable {
  const MeetingLine({
    required this.location,
    required this.localStart,
    required this.localEnd,
    required this.dayDelta,
    required this.verdict,
    required this.crossesDst,
    required this.offsetFromUtc,
  });

  /// The board row this line stands for.
  ///
  /// The home line may carry a stand-in row when the home zone has no board
  /// entry of its own (locations rule 3); such a row has an empty
  /// [SavedLocationEntity.id] and must never be written back to the board.
  final SavedLocationEntity location;

  /// Wall clock in this line's zone at [MeetingSelection.startInstant]. A
  /// field carrier: read its fields, never its epoch value.
  final DateTime localStart;

  /// Wall clock at [MeetingSelection.endInstant].
  ///
  /// `localEnd - localStart` is **not** the meeting's length across a
  /// transition (rule 8); `MeetingSummary.duration` is.
  final DateTime localEnd;

  /// Calendar days from the home line's local date to this one's: `+1` for a
  /// row already on tomorrow, `-1` for one still on yesterday, `0` otherwise.
  final int dayDelta;

  /// Rule 6: the **worst** band across every hour the range occupies. A
  /// meeting is only as good as its worst hour for that person.
  final HourBand verdict;

  /// This zone's clocks move inside the range, so the line's local times span
  /// two offsets and its wall-clock length lies about the real one (rule 8).
  final bool crossesDst;

  /// Offset from UTC at [MeetingSelection.startInstant].
  ///
  /// A snapshot for that instant and never an identity (engine rule 2), kept
  /// on the line so the verbose text and the row badge do not each re-ask the
  /// engine for an answer the summary already has.
  final Duration offsetFromUtc;

  MeetingLine copyWith({
    SavedLocationEntity? location,
    DateTime? localStart,
    DateTime? localEnd,
    int? dayDelta,
    HourBand? verdict,
    bool? crossesDst,
    Duration? offsetFromUtc,
  }) {
    return MeetingLine(
      location: location ?? this.location,
      localStart: localStart ?? this.localStart,
      localEnd: localEnd ?? this.localEnd,
      dayDelta: dayDelta ?? this.dayDelta,
      verdict: verdict ?? this.verdict,
      crossesDst: crossesDst ?? this.crossesDst,
      offsetFromUtc: offsetFromUtc ?? this.offsetFromUtc,
    );
  }

  @override
  List<Object?> get props => [
    location,
    localStart,
    localEnd,
    dayDelta,
    verdict,
    crossesDst,
    offsetFromUtc,
  ];
}

/// Everything the summary panel and the copy action need, and nothing else.
///
/// ```dart
/// final summary = BuildMeetingSummaryUseCase(engine: engine)(
///   board: board,
///   selection: selection,
///   workingHours: preferences.workingHours,
/// );
/// ```
class MeetingSummary extends Equatable {
  const MeetingSummary({
    required this.selection,
    required this.duration,
    required this.home,
    required this.lines,
    this.suggestion,
  });

  final MeetingSelection selection;

  /// The **real** elapsed time between the selection's instants (rule 8).
  ///
  /// Never derived from [MeetingSelection.slotCount] and never from the local
  /// times: a range crossing a transition reads three columns and one hour
  /// more or less than three hours.
  final Duration duration;

  /// The home zone's line, listed first (rule 5) and the date every other
  /// line's [MeetingLine.dayDelta] is measured against.
  final MeetingLine home;

  /// The board rows, in board order, **without** the home row: it is already
  /// [home], and listing a place twice in a pasted message is a bug the
  /// reader has to decode.
  final List<MeetingLine> lines;

  /// The alternative range from `FindBestSlotUseCase` (rule 7), or `null`
  /// when there is nothing better to offer.
  final MeetingSelection? suggestion;

  /// Home first, then board order: the reading order of the panel and of the
  /// pasteable text.
  List<MeetingLine> get allLines => [home, ...lines];

  /// Any line's clocks move inside the range, so the panel raises `DstBadge`
  /// and the duration deserves to be read out loud (rule 8).
  bool get crossesDst =>
      home.crossesDst || lines.any((line) => line.crossesDst);

  /// Pass `clearSuggestion: true` to drop the suggestion; passing
  /// `suggestion: null` cannot say that, being indistinguishable from "leave
  /// it alone".
  MeetingSummary copyWith({
    MeetingSelection? selection,
    Duration? duration,
    MeetingLine? home,
    List<MeetingLine>? lines,
    MeetingSelection? suggestion,
    bool clearSuggestion = false,
  }) {
    return MeetingSummary(
      selection: selection ?? this.selection,
      duration: duration ?? this.duration,
      home: home ?? this.home,
      lines: lines ?? this.lines,
      suggestion: clearSuggestion ? null : suggestion ?? this.suggestion,
    );
  }

  @override
  List<Object?> get props => [selection, duration, home, lines, suggestion];
}

/// How bad a band is for a meeting; higher is worse.
///
/// Rule 6 needs an order over [HourBand] and the enum does not carry one.
/// `night` sits above `poor` because a person asleep is less reachable than a
/// person merely outside their working window, and the whole point of the
/// verdict is to say who the meeting costs the most.
///
/// The switch is exhaustive on purpose: a band added to [HourBand] becomes a
/// compile error here rather than a silent zero.
int meetingBandSeverity(HourBand band) => switch (band) {
  HourBand.good => 0,
  HourBand.fair => 1,
  HourBand.poor => 2,
  HourBand.night => 3,
};

/// The worst of [bands] under [meetingBandSeverity], or [HourBand.good] when
/// there are none.
///
/// An empty range answers `good` rather than throwing: the only caller that
/// can produce one is a zero-length selection, and refusing to score it would
/// take down a panel over a case the user cannot even see.
HourBand worstMeetingBand(Iterable<HourBand> bands) {
  var worst = HourBand.good;
  for (final band in bands) {
    if (meetingBandSeverity(band) > meetingBandSeverity(worst)) worst = band;
  }
  return worst;
}

/// The board rows a summary lists after the home line (rule 5).
///
/// Board order, with the home row removed because it is already the first
/// line. Matched canonically through `BoardEntity.locationForZone`, so a row
/// saved as `Brazil/East` against a home of `America/Sao_Paulo` is recognised
/// as the same clock and is not listed twice.
List<SavedLocationEntity> meetingBoardRows(BoardEntity board) {
  final homeRow = board.locationForZone(board.homeZoneId);
  return [
    for (final location in board.locations)
      if (location.id != homeRow?.id) location,
  ];
}

/// [index] pulled inside the bounds of [slots].
int _indexIn(List<DateTime> slots, int index) =>
    math.max(0, math.min(index, slots.length - 1));

/// The exclusive end of a range whose last column is [lastIndex].
///
/// The next column's instant when [slots] carries one, so the end is a real
/// slot boundary rather than an hour added to a local time. A range ending on
/// the last column has nothing to point at and runs one slot duration past
/// it: the caller's list stops at the day's edge and the meeting still has to
/// end at a real moment.
DateTime _slotEndIn(List<DateTime> slots, int lastIndex) {
  final next = lastIndex + 1;
  if (next < slots.length) return slots[next];
  return slots[lastIndex].add(MeetingSelection.slotDuration);
}

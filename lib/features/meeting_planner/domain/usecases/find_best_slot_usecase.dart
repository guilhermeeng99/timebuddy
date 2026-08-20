import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';
import 'package:timebuddy/features/meeting_planner/domain/usecases/build_meeting_summary_usecase.dart';

/// Rule 7's alternative-range search. Pure and synchronous.
///
/// It walks every range of `slotCount` columns inside one reference day and
/// keeps the one that costs the fewest people the most, scoring each row with
/// the very verdict `BuildMeetingSummaryUseCase` will display, so the panel
/// never recommends a range it then contradicts.
///
/// ```dart
/// final better = FindBestSlotUseCase(engine: engine)(
///   board: board,
///   daySlots: engine.dayIn(zoneId: home, localDate: referenceDate).hours,
///   slotCount: selection.slotCount,
///   workingHours: preferences.workingHours,
/// );
/// ```
class FindBestSlotUseCase {
  const FindBestSlotUseCase({required TimeZoneEngine engine})
    : _engine = engine;

  final TimeZoneEngine _engine;

  /// The best range of [slotCount] columns inside [daySlots], or `null` when
  /// there is nothing worth offering.
  ///
  /// [daySlots] is the reference day's own ascending UTC instants, normally
  /// `ZoneDay.hours`. Its length is the day's real hour count, so a 23 or 25
  /// hour day narrows or widens the search with no arithmetic here (rule 7
  /// bounds the search to the same reference day).
  ///
  /// Returns `null` when:
  ///
  /// * [slotCount] is outside `1..12` or longer than the day;
  /// * every range in the day scores identically, which is the "every row is
  ///   poor all day" case. Offering an equally bad alternative is worse than
  ///   offering none, so the panel says there is none instead.
  ///
  /// The caller drops a suggestion equal to the range already selected: this
  /// signature deliberately does not take the current selection, and the
  /// cubit that owns it can compare in one line.
  MeetingSelection? call({
    required BoardEntity board,
    required List<DateTime> daySlots,
    required int slotCount,
    required WorkingHours workingHours,
  }) {
    if (slotCount < MeetingSelection.minSlots) return null;
    if (slotCount > MeetingSelection.maxSlots) return null;
    if (slotCount > daySlots.length) return null;

    final zoneIds = _scoredZoneIdsOf(board);
    MeetingSelection? best;
    _RangeCost? bestCost;
    _RangeCost? firstCost;
    var everyRangeCostsTheSame = true;

    for (var start = 0; start + slotCount <= daySlots.length; start++) {
      final candidate = MeetingSelection.fromSlots(
        slots: daySlots,
        anchorIndex: start,
        cursorIndex: start + slotCount - 1,
      );
      final cost = _costOf(candidate, zoneIds, workingHours);
      firstCost ??= cost;
      if (cost != firstCost) everyRangeCostsTheSame = false;

      // Ties break toward the earlier start, so only a strictly cheaper range
      // displaces the one already held and the walk runs forwards.
      if (bestCost == null || cost.isCheaperThan(bestCost)) {
        best = candidate;
        bestCost = cost;
      }
    }

    if (everyRangeCostsTheSame) return null;
    return best;
  }

  _RangeCost _costOf(
    MeetingSelection selection,
    List<String> zoneIds,
    WorkingHours workingHours,
  ) {
    var nightRows = 0;
    var poorRows = 0;
    var fairRows = 0;

    for (final zoneId in zoneIds) {
      final verdict = meetingVerdictFor(
        engine: _engine,
        zoneId: zoneId,
        selection: selection,
        workingHours: workingHours,
      );
      if (verdict == HourBand.night) nightRows++;
      if (verdict == HourBand.poor) poorRows++;
      if (verdict == HourBand.fair) fairRows++;
    }

    return _RangeCost(
      nightRows: nightRows,
      poorRows: poorRows,
      fairRows: fairRows,
    );
  }

  /// The zones the cost is taken over: home first, then the rows the summary
  /// would list (rule 5), with unresolvable ids dropped exactly as
  /// `BuildMeetingSummaryUseCase` drops them.
  ///
  /// Home is scored like anyone else because the user is one of the people
  /// the meeting costs, and a suggestion that ignores them would move the
  /// meeting into their own night.
  List<String> _scoredZoneIdsOf(BoardEntity board) {
    final zoneIds = <String>[zoneOrNull(board.homeZoneId)?.id ?? utcZoneId];
    for (final location in meetingBoardRows(board)) {
      final zone = zoneOrNull(location.zoneId);
      if (zone != null) zoneIds.add(zone.id);
    }
    return zoneIds;
  }
}

/// What one candidate range costs: how many rows it lands badly on.
///
/// Rule 7 names two buckets, poor then fair, because rule 6 names three
/// verdicts. [HourBand] carries a fourth, and a row asleep is worse than a row
/// merely outside its working window, so [nightRows] is weighed ahead of
/// [poorRows]. On a board with no night row the ordering is exactly the one
/// the spec writes.
class _RangeCost extends Equatable {
  const _RangeCost({
    required this.nightRows,
    required this.poorRows,
    required this.fairRows,
  });

  final int nightRows;
  final int poorRows;
  final int fairRows;

  /// Strictly cheaper, lexicographically from the worst bucket down. Strict
  /// on purpose: an equal cost must not displace an earlier start.
  bool isCheaperThan(_RangeCost other) {
    if (nightRows != other.nightRows) return nightRows < other.nightRows;
    if (poorRows != other.poorRows) return poorRows < other.poorRows;
    return fairRows < other.fairRows;
  }

  @override
  List<Object?> get props => [nightRows, poorRows, fairRows];
}

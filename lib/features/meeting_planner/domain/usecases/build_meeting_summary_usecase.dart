import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/meeting_planner/domain/entities/meeting_summary.dart';

/// Turns a selection into the summary the panel renders and the copy action
/// pastes. Pure and synchronous.
///
/// It takes instants rather than a `Clock` for the same reason
/// `BuildGridUseCase` does: every rule in docs/specs/meeting_planner.md is
/// then pinnable by a unit test at a real historical transition.
///
/// ```dart
/// final summary = BuildMeetingSummaryUseCase(engine: engine)(
///   board: board,
///   selection: selection,
///   workingHours: preferences.workingHours,
///   suggestion: findBestSlot(
///     board: board,
///     daySlots: referenceDay.hours,
///     slotCount: selection.slotCount,
///     workingHours: preferences.workingHours,
///   ),
/// );
/// ```
class BuildMeetingSummaryUseCase {
  const BuildMeetingSummaryUseCase({required TimeZoneEngine engine})
    : _engine = engine;

  final TimeZoneEngine _engine;

  /// Builds the summary of [selection] over [board].
  ///
  /// [suggestion] is the rule 7 alternative, handed in rather than searched
  /// for here: that search needs the reference day's whole slot list, which a
  /// summary of one range has no business knowing, and the cubit already
  /// holds both.
  MeetingSummary call({
    required BoardEntity board,
    required MeetingSelection selection,
    required WorkingHours workingHours,
    MeetingSelection? suggestion,
  }) {
    // zoneOrNull rather than the engine: the engine degrades an unknown zone
    // to UTC silently, and the home line has to name the id it resolved.
    final homeZoneId = zoneOrNull(board.homeZoneId)?.id ?? utcZoneId;
    final home = _lineFor(
      location:
          board.locationForZone(board.homeZoneId) ??
          standInRowFor(homeZoneId, selection.startInstant),
      zoneId: homeZoneId,
      selection: selection,
      workingHours: workingHours,
    );

    return MeetingSummary(
      selection: selection,
      // Rule 8: the real length, taken off the instants. Neither slotCount
      // nor `localEnd - localStart` can answer this across a transition.
      duration: selection.endInstant.difference(selection.startInstant),
      home: home,
      lines: _linesFor(
        board: board,
        selection: selection,
        workingHours: workingHours,
        homeLocalStart: home.localStart,
      ),
      suggestion: suggestion,
    );
  }

  List<MeetingLine> _linesFor({
    required BoardEntity board,
    required MeetingSelection selection,
    required WorkingHours workingHours,
    required DateTime homeLocalStart,
  }) {
    final lines = <MeetingLine>[];
    for (final location in meetingBoardRows(board)) {
      // A summary gets pasted into a message. A row whose zone the shipped
      // tzdata no longer carries would degrade to UTC and paste a plausible,
      // wrong hour that nobody can catch by reading it, so it is left out
      // here. The grid still shows the row, flagged (time_grid rule 14).
      final zone = zoneOrNull(location.zoneId);
      if (zone == null) continue;
      lines.add(
        _lineFor(
          location: location,
          zoneId: zone.id,
          selection: selection,
          workingHours: workingHours,
          homeLocalStart: homeLocalStart,
        ),
      );
    }
    return List.unmodifiable(lines);
  }

  /// One line, every field resolved for [selection]'s own instants.
  ///
  /// [homeLocalStart] is `null` for the home line itself, whose
  /// [MeetingLine.dayDelta] is 0 by definition because it is the reference.
  MeetingLine _lineFor({
    required SavedLocationEntity location,
    required String zoneId,
    required MeetingSelection selection,
    required WorkingHours workingHours,
    DateTime? homeLocalStart,
  }) {
    final startState = _engine.stateAt(
      zoneId: zoneId,
      instant: selection.startInstant,
    );
    final localStart = _engine.wallTimeAt(
      zoneId: zoneId,
      instant: selection.startInstant,
    );

    return MeetingLine(
      location: location,
      localStart: localStart,
      localEnd: _engine.wallTimeAt(
        zoneId: zoneId,
        instant: selection.endInstant,
      ),
      dayDelta: homeLocalStart == null
          ? 0
          : wholeDaysBetween(homeLocalStart, localStart),
      verdict: meetingVerdictFor(
        engine: _engine,
        zoneId: zoneId,
        selection: selection,
        workingHours: workingHours,
      ),
      crossesDst: _crossesDst(zoneId, selection, startState.offset),
      offsetFromUtc: startState.offset,
    );
  }

  /// Whether this zone's clocks move **inside** the range.
  ///
  /// Measured as the offset at the start against the offset an instant before
  /// the exclusive end, so a change landing exactly on either bound is
  /// correctly not a crossing: on the start the range is already running on
  /// the new offset, and on the end the meeting is over. An abbreviation-only
  /// rename moves no clock and is not flagged, which matches what the engine
  /// itself calls a transition.
  bool _crossesDst(
    String zoneId,
    MeetingSelection selection,
    Duration offsetAtStart,
  ) {
    final lastInstant = selection.endInstant.subtract(
      const Duration(milliseconds: 1),
    );
    if (!lastInstant.isAfter(selection.startInstant)) return false;
    return _engine.stateAt(zoneId: zoneId, instant: lastInstant).offset !=
        offsetAtStart;
  }
}

/// The worst band [zoneId] sees across [selection] (rule 6).
///
/// Top-level and shared with `FindBestSlotUseCase`, which scores every
/// candidate range with exactly this verdict: a suggestion judged by a
/// different measure than the summary displays would recommend a range the
/// panel then contradicts.
HourBand meetingVerdictFor({
  required TimeZoneEngine engine,
  required String zoneId,
  required MeetingSelection selection,
  required WorkingHours workingHours,
}) {
  return worstMeetingBand([
    for (final instant in _hoursCovered(selection))
      hourBandFor(
        engine.wallTimeAt(zoneId: zoneId, instant: instant).hour,
        workingHours,
      ),
  ]);
}

/// The stand-in row for a zone that has no entry on the board.
///
/// Locations rule 3 lets the home zone exist without a row of its own, and
/// meeting rule 5 still puts home first, so the line needs *some* location.
/// The empty [SavedLocationEntity.id] marks a row that is not on the board
/// and must never be written back to one.
///
/// The label is the last segment of the id because the city catalog is a
/// presentation dependency the domain cannot reach; a caller that holds the
/// catalog entry should replace it through `copyWith`, which is the only
/// place `America/Sao_Paulo` is allowed to become "Sao Paulo" by string
/// surgery rather than by lookup.
SavedLocationEntity standInRowFor(String zoneId, DateTime addedAt) {
  return SavedLocationEntity(
    id: '',
    zoneId: zoneId,
    label: zoneId.split('/').last.replaceAll('_', ' '),
    countryCode: '',
    sortIndex: -1,
    // A row that was never added has no add time. Passing the caller's own
    // instant keeps the value deterministic, which entity equality needs.
    addedAt: addedAt,
  );
}

/// Calendar days from [from]'s local date to [to]'s, both field carriers.
///
/// The dates are rebuilt as UTC midnights before subtracting, and UTC has no
/// DST to distort the difference, so this is calendar arithmetic rather than
/// the local-time arithmetic CLAUDE.md rule 3 forbids.
int wholeDaysBetween(DateTime from, DateTime to) {
  final fromDate = DateTime.utc(from.year, from.month, from.day);
  final toDate = DateTime.utc(to.year, to.month, to.day);
  return toDate.difference(fromDate).inDays;
}

/// One instant per real hour the selection occupies, its start included.
///
/// Walked from the instants rather than counted off
/// [MeetingSelection.slotCount], because a range crossing a transition holds
/// fewer or more real hours than it holds columns (rule 8).
///
/// A range whose instants collapse to nothing is still a moment somebody has
/// to attend, so it is scored at its start rather than not scored at all. The
/// length guard is a safety stop, not a rule: rule 3 already caps a selection
/// at twelve slots, which is twelve real hours.
List<DateTime> _hoursCovered(MeetingSelection selection) {
  final instants = <DateTime>[selection.startInstant];
  var cursor = selection.startInstant.add(MeetingSelection.slotDuration);
  while (cursor.isBefore(selection.endInstant) &&
      instants.length < MeetingSelection.maxSlots) {
    instants.add(cursor);
    cursor = cursor.add(MeetingSelection.slotDuration);
  }
  return instants;
}

import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';
import 'package:timebuddy/features/time_converter/domain/entities/conversion_result.dart';

/// Answers "it is 15:00 on 12 March in Lisbon, what time is that everywhere
/// else?". Pure and synchronous.
///
/// Every rule in docs/specs/time_converter.md is testable here. The order of
/// the two steps is the whole feature: local fields become an instant first
/// (rule 1), and every line is then read off that one instant (rule 6), so a
/// target whose DST rules differ on the chosen date is handled by the tzdata
/// rather than by a branch.
///
/// ```dart
/// final result = ConvertTimeUseCase(engine: engine)(
///   board: board,
///   input: input,
///   workingHours: preferences.workingHours,
/// );
/// ```
class ConvertTimeUseCase {
  const ConvertTimeUseCase({required TimeZoneEngine engine}) : _engine = engine;

  final TimeZoneEngine _engine;

  ConversionResult call({
    required BoardEntity board,
    required ConversionInput input,
    required WorkingHours workingHours,
  }) {
    // zoneOrNull rather than the engine: the engine degrades an unknown zone
    // to UTC silently, and the source line has to name the id it resolved.
    final sourceZoneId = zoneOrNull(input.sourceZoneId)?.id ?? utcZoneId;
    final resolved = _engine.instantFor(
      zoneId: sourceZoneId,
      year: input.year,
      month: input.month,
      day: input.day,
      hour: input.hour,
      minute: input.minute,
    );
    final instant = _pickedInstant(sourceZoneId, resolved, input.ambiguousPick);
    final source = _lineFor(
      location:
          board.locationForZone(sourceZoneId) ??
          _standInRowFor(sourceZoneId, instant),
      zoneId: sourceZoneId,
      sourceZoneId: sourceZoneId,
      instant: instant,
      workingHours: workingHours,
    );

    return ConversionResult(
      input: input,
      instant: instant,
      resolution: resolved.resolution,
      source: source,
      lines: _targetLines(
        board: board,
        sourceZoneId: sourceZoneId,
        sourceLocalTime: source.localTime,
        instant: instant,
        workingHours: workingHours,
      ),
    );
  }

  /// The instant the user actually meant, once rule 5's toggle is applied.
  ///
  /// The engine always hands back the earlier of two occurrences, so the
  /// later one is that instant plus the offset the transition drops. The drop
  /// is read off the transition rather than probed at a fixed hour, because
  /// the repeated window is 30 minutes on Australia/Lord_Howe and an hour
  /// nearly everywhere else. Anything that does not look like a fall-back
  /// leaves the resolved instant alone: a toggle left over from a previous
  /// date must not be able to move an unambiguous answer.
  DateTime _pickedInstant(
    String zoneId,
    ResolvedInstant resolved,
    AmbiguousPick pick,
  ) {
    if (pick == AmbiguousPick.first) return resolved.utcInstant;
    if (resolved.resolution != TimeResolution.ambiguousFirst) {
      return resolved.utcInstant;
    }

    final change = _engine.nextTransition(
      zoneId: zoneId,
      instant: resolved.utcInstant,
    );
    if (change == null) return resolved.utcInstant;
    final drop = change.before - change.after;
    if (drop <= Duration.zero) return resolved.utcInstant;
    return resolved.utcInstant.add(drop);
  }

  List<ConversionLine> _targetLines({
    required BoardEntity board,
    required String sourceZoneId,
    required DateTime sourceLocalTime,
    required DateTime instant,
    required WorkingHours workingHours,
  }) {
    final lines = <ConversionLine>[];
    for (final location in board.locations) {
      final zone = zoneOrNull(location.zoneId);
      // Rule 3 excludes the source, and canonically: `Brazil/East` and
      // `America/Sao_Paulo` are one clock, so a literal comparison would list
      // the source as a target of itself. An id the tzdata no longer carries
      // is left out rather than degraded to UTC, which would print a
      // plausible, wrong time nobody can catch by reading it.
      if (zone == null || zone.id == sourceZoneId) continue;
      lines.add(
        _lineFor(
          location: location,
          zoneId: zone.id,
          sourceZoneId: sourceZoneId,
          instant: instant,
          workingHours: workingHours,
          sourceLocalTime: sourceLocalTime,
        ),
      );
    }
    return List.unmodifiable(lines);
  }

  /// One line, every field read off [instant] (rule 6).
  ///
  /// [sourceLocalTime] is `null` for the source line itself, whose
  /// [ConversionLine.dayDelta] is 0 by definition because it is the reference
  /// date every other line is compared against.
  ConversionLine _lineFor({
    required SavedLocationEntity location,
    required String zoneId,
    required String sourceZoneId,
    required DateTime instant,
    required WorkingHours workingHours,
    DateTime? sourceLocalTime,
  }) {
    final state = _engine.stateAt(zoneId: zoneId, instant: instant);
    final localTime = _engine.wallTimeAt(zoneId: zoneId, instant: instant);

    return ConversionLine(
      location: location,
      localTime: localTime,
      dayDelta: sourceLocalTime == null
          ? 0
          : _wholeDaysBetween(sourceLocalTime, localTime),
      offsetFromSource: _engine.relativeOffset(
        fromZoneId: sourceZoneId,
        toZoneId: zoneId,
        instant: instant,
      ),
      offsetFromUtc: state.offset,
      band: hourBandFor(localTime.hour, workingHours),
      isDst: state.isDst,
      abbreviation: state.abbreviation,
    );
  }
}

/// The stand-in row for a source zone that is not on the board.
///
/// The picker searches the whole city catalog, so the source may legitimately
/// be a place the user never saved (Edge cases), and the result still owes a
/// source line. The empty [SavedLocationEntity.id] marks a row that is not on
/// the board and must never be written back to one.
///
/// The label is the last segment of the id because the catalog is a
/// presentation dependency the domain cannot reach; the page that picked the
/// zone holds the catalog entry and should replace it through `copyWith`.
///
/// Deliberately a private twin of the planner's `standInRowFor` rather than a
/// shared import: the converter has no other reason to depend on the meeting
/// planner, and four lines of construction are cheaper than that edge.
SavedLocationEntity _standInRowFor(String zoneId, DateTime addedAt) {
  return SavedLocationEntity(
    id: '',
    zoneId: zoneId,
    label: zoneId.split('/').last.replaceAll('_', ' '),
    countryCode: '',
    sortIndex: -1,
    // A row that was never added has no add time. Passing the resolved
    // instant keeps the value deterministic, which entity equality needs.
    addedAt: addedAt,
  );
}

/// Calendar days from [from]'s local date to [to]'s, both field carriers.
///
/// The dates are rebuilt as UTC midnights before subtracting, and UTC has no
/// DST to distort the difference, so this is calendar arithmetic rather than
/// the local-time arithmetic CLAUDE.md rule 3 forbids.
int _wholeDaysBetween(DateTime from, DateTime to) {
  final fromDate = DateTime.utc(from.year, from.month, from.day);
  final toDate = DateTime.utc(to.year, to.month, to.day);
  return toDate.difference(fromDate).inDays;
}

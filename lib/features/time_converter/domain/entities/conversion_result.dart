import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/time/hour_band.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// Which of two legitimate answers an ambiguous local time means
/// (docs/specs/time_converter.md rule 5).
///
/// On a fall-back date the same wall clock happens twice and only the user
/// knows which one they meant, so the converter answers the first and offers
/// a toggle rather than picking silently.
enum AmbiguousPick {
  /// The earlier, pre-transition occurrence. The default, and what
  /// `TimeZoneEngine.instantFor` hands back (engine rule 7).
  first,

  /// The later, post-transition occurrence.
  second,
}

/// What the user typed: a zone and a set of local calendar fields.
///
/// Rule 1: never an instant. A person thinks "15:00 in Lisbon", not "14:00
/// UTC", and turning one into the other is the first thing the use case does.
/// Keeping the input in the shape the picker produces is also what lets a
/// date six months out be resolved under *that* date's rules rather than
/// today's.
///
/// ```dart
/// const input = ConversionInput(
///   sourceZoneId: 'Europe/Lisbon',
///   year: 2026,
///   month: 3,
///   day: 12,
///   hour: 15,
///   minute: 0,
/// );
/// ```
class ConversionInput extends Equatable {
  const ConversionInput({
    required this.sourceZoneId,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    this.ambiguousPick = AmbiguousPick.first,
  });

  /// Rule 8's bound, in years either side of now.
  ///
  /// Beyond a decade tzdata carries projections rather than law: a zone can
  /// abolish, adopt or reschedule DST at a few months' notice, and presenting
  /// a 2050 conversion as an answer is overconfident about a rule nobody has
  /// written yet.
  static const int rangeYears = 10;

  /// The earliest date rule 8 allows, given [nowUtc].
  ///
  /// A 29 February start normalises onto 1 March in a non-leap year, which is
  /// the same rounding the date picker does and a day nobody can reach by
  /// stepping anyway.
  static DateTime earliestDate(DateTime nowUtc) =>
      DateTime.utc(nowUtc.year - rangeYears, nowUtc.month, nowUtc.day);

  /// The latest date rule 8 allows, given [nowUtc].
  static DateTime latestDate(DateTime nowUtc) =>
      DateTime.utc(nowUtc.year + rangeYears, nowUtc.month, nowUtc.day);

  /// Canonical IANA id of the zone the local fields are read in. Defaults to
  /// the home zone (rule 2) and is the one input remembered in preferences
  /// (rule 10).
  final String sourceZoneId;

  final int year;
  final int month;
  final int day;

  /// `0..23`. The picker enforces the range; nothing downstream re-reads a
  /// 12-hour clock, because the user's format preference is a rendering
  /// choice and not part of the question.
  final int hour;

  /// `0..59`.
  final int minute;

  /// Which occurrence an ambiguous local time means (rule 5). Ignored when
  /// the local time is not ambiguous.
  final AmbiguousPick ambiguousPick;

  /// The chosen calendar date as a field carrier. Its epoch value means
  /// nothing: it is not an instant until a zone resolves it.
  DateTime get localDate => DateTime.utc(year, month, day);

  /// Whether [localDate] sits inside rule 8's window around [nowUtc].
  ///
  /// The bound is checked against the chosen date rather than the resolved
  /// instant, because it is the *picker* rule 8 constrains and a zone offset
  /// must not be able to push a legal date over the edge.
  bool isWithinRange(DateTime nowUtc) =>
      !localDate.isBefore(earliestDate(nowUtc)) &&
      !localDate.isAfter(latestDate(nowUtc));

  ConversionInput copyWith({
    String? sourceZoneId,
    int? year,
    int? month,
    int? day,
    int? hour,
    int? minute,
    AmbiguousPick? ambiguousPick,
  }) {
    return ConversionInput(
      sourceZoneId: sourceZoneId ?? this.sourceZoneId,
      year: year ?? this.year,
      month: month ?? this.month,
      day: day ?? this.day,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      ambiguousPick: ambiguousPick ?? this.ambiguousPick,
    );
  }

  @override
  List<Object?> get props => [
    sourceZoneId,
    year,
    month,
    day,
    hour,
    minute,
    ambiguousPick,
  ];
}

/// One place's reading of the resolved instant.
///
/// Every field is already decided, so the row widget renders and computes
/// nothing, the same contract the grid's `GridCell` carries.
class ConversionLine extends Equatable {
  const ConversionLine({
    required this.location,
    required this.localTime,
    required this.dayDelta,
    required this.offsetFromSource,
    required this.offsetFromUtc,
    required this.band,
    required this.isDst,
    required this.abbreviation,
  });

  /// The board row this line stands for.
  ///
  /// The source line may carry a stand-in row when the chosen zone is not on
  /// the board, which the picker allows (Edge cases); such a row has an empty
  /// [SavedLocationEntity.id] and must never be written back to the board.
  final SavedLocationEntity location;

  /// Wall clock in this line's zone at the resolved instant. A field carrier:
  /// read its fields, never its epoch value.
  final DateTime localTime;

  /// Calendar days from the source's local date to this one's: `+1` for a
  /// place already on tomorrow, `-1` for one still on yesterday (rule 7).
  final int dayDelta;

  /// `offset(this zone) - offset(source)` **at the resolved instant**, so it
  /// answers for the chosen date and not for today (engine rule 10). May be
  /// negative and may carry minutes.
  final Duration offsetFromSource;

  /// Offset from UTC at the same instant, kept so the copy path and an
  /// absolute badge do not re-ask the engine for what the result already
  /// holds. A snapshot, never an identity (engine rule 2).
  final Duration offsetFromUtc;

  /// How reachable that local hour is, from `hourBandFor`.
  final HourBand band;

  /// The zone is off its own standard time at that instant. Note this is a
  /// fact about the *chosen date*: a zone can be on DST in July 2018 and not
  /// in July 2025, which is the converter's whole reason to exist.
  final bool isDst;

  /// The short name in force at that instant: `IST`, `EDT`, `-03`.
  final String abbreviation;

  ConversionLine copyWith({
    SavedLocationEntity? location,
    DateTime? localTime,
    int? dayDelta,
    Duration? offsetFromSource,
    Duration? offsetFromUtc,
    HourBand? band,
    bool? isDst,
    String? abbreviation,
  }) {
    return ConversionLine(
      location: location ?? this.location,
      localTime: localTime ?? this.localTime,
      dayDelta: dayDelta ?? this.dayDelta,
      offsetFromSource: offsetFromSource ?? this.offsetFromSource,
      offsetFromUtc: offsetFromUtc ?? this.offsetFromUtc,
      band: band ?? this.band,
      isDst: isDst ?? this.isDst,
      abbreviation: abbreviation ?? this.abbreviation,
    );
  }

  @override
  List<Object?> get props => [
    location,
    localTime,
    dayDelta,
    offsetFromSource,
    offsetFromUtc,
    band,
    isDst,
    abbreviation,
  ];
}

/// One point-in-time question, answered everywhere at once.
///
/// ```dart
/// final result = ConvertTimeUseCase(engine: engine)(
///   board: board,
///   input: input,
///   workingHours: preferences.workingHours,
/// );
/// ```
class ConversionResult extends Equatable {
  const ConversionResult({
    required this.input,
    required this.instant,
    required this.resolution,
    required this.source,
    required this.lines,
  });

  final ConversionInput input;

  /// The UTC instant every line is computed from (rule 6), so a target whose
  /// own DST state differs on that date needs no special case.
  ///
  /// This is the instant actually shown: on an ambiguous local time with
  /// [ConversionInput.ambiguousPick] set to [AmbiguousPick.second] it is the
  /// later of the two occurrences.
  final DateTime instant;

  /// How faithfully the local fields mapped onto [instant].
  ///
  /// It describes the *local time*, not which occurrence was picked:
  /// [TimeResolution.ambiguousFirst] means "this wall clock happens twice
  /// here", and `input.ambiguousPick` says which of the two is on screen. The
  /// engine's enum has no `ambiguousSecond`, and adding one would make every
  /// caller handle a value that answers a different question.
  final TimeResolution resolution;

  /// The source zone's own line. Always present, even when the zone is not on
  /// the board.
  final ConversionLine source;

  /// The board, in board order, minus the source zone (rule 3). Empty is a
  /// valid answer: a board holding only the source gets the "add another
  /// city" note rather than an error.
  final List<ConversionLine> lines;

  /// The local time the user typed does not map cleanly onto one instant, so
  /// the page owes them a disclosure banner (rules 4 and 5). It never answers
  /// a different question silently.
  bool get isDisclosed => resolution != TimeResolution.exact;

  /// The local time happens twice here, so the banner carries the toggle
  /// between the two occurrences (rule 5).
  bool get isAmbiguous => resolution == TimeResolution.ambiguousFirst;

  ConversionResult copyWith({
    ConversionInput? input,
    DateTime? instant,
    TimeResolution? resolution,
    ConversionLine? source,
    List<ConversionLine>? lines,
  }) {
    return ConversionResult(
      input: input ?? this.input,
      instant: instant ?? this.instant,
      resolution: resolution ?? this.resolution,
      source: source ?? this.source,
      lines: lines ?? this.lines,
    );
  }

  @override
  List<Object?> get props => [input, instant, resolution, source, lines];
}

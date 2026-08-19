import 'package:equatable/equatable.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// How faithfully a requested local wall-clock time maps onto a real instant.
enum TimeResolution {
  /// The requested local time exists exactly once.
  exact,

  /// The requested local time falls inside a spring-forward gap and was moved
  /// forward past it. See rule 6 of `docs/specs/timezone_engine.md`.
  shiftedForward,

  /// The requested local time happens twice on a fall-back day; the earlier,
  /// pre-transition instant was returned. See rule 7.
  ambiguousFirst,
}

/// A UTC instant together with how cleanly it was derived from local fields.
class ResolvedInstant extends Equatable {
  const ResolvedInstant({required this.utcInstant, required this.resolution});

  final DateTime utcInstant;
  final TimeResolution resolution;

  @override
  List<Object?> get props => [utcInstant, resolution];
}

/// The device's own zone, and whether it had to be guessed.
///
/// [isFallback] is `true` when the platform refused to answer or named a zone
/// the tzdata does not carry. The UI uses it to prompt for a home city instead
/// of silently pretending the user lives in UTC.
class DeviceZone extends Equatable {
  const DeviceZone({required this.zoneId, required this.isFallback});

  final String zoneId;
  final bool isFallback;

  @override
  List<Object?> get props => [zoneId, isFallback];
}

/// A zone's state **at one instant**.
///
/// This is a snapshot, never an identity: [offset] and [isDst] are answers to
/// "what was true at that moment", so caching one of these across instants
/// reintroduces exactly the bug the engine exists to prevent (rule 2).
class ZoneState extends Equatable {
  const ZoneState({
    required this.zoneId,
    required this.abbreviation,
    required this.offset,
    required this.isDst,
  });

  final String zoneId;

  /// The short name in force at that instant: `IST`, `PDT`, `-03`.
  final String abbreviation;

  /// Offset from UTC, which may carry minutes (`+05:45`, `+12:45`).
  final Duration offset;

  final bool isDst;

  @override
  List<Object?> get props => [zoneId, abbreviation, offset, isDst];
}

/// One offset change in a zone's history or schedule.
///
/// Exactly one of [skippedHour] and [repeatedHour] is set: a forward jump
/// deletes a local hour, a backward jump plays one twice.
class DstTransition extends Equatable {
  const DstTransition({
    required this.atUtc,
    required this.before,
    required this.after,
    this.skippedHour,
    this.repeatedHour,
  });

  final DateTime atUtc;
  final Duration before;
  final Duration after;

  /// The local hour that never happens, on a spring-forward day.
  final int? skippedHour;

  /// The local hour that happens twice, on a fall-back day.
  final int? repeatedHour;

  @override
  List<Object?> get props => [atUtc, before, after, skippedHour, repeatedHour];
}

/// The shape of one calendar day in one zone.
///
/// [hours] holds one UTC instant per local hour slot, ascending. Its length is
/// 23, 24 or 25 and is the only legitimate source of a day's column count:
/// `for (var h = 0; h < 24; h++)` is wrong twice a year (rule 8).
class ZoneDay extends Equatable {
  const ZoneDay({
    required this.zoneId,
    required this.date,
    required this.hourCount,
    required this.hours,
    this.transition,
  });

  final String zoneId;

  /// The local calendar date at midnight, date part only. Like every value
  /// this engine returns for display, it is a field carrier: read `year`,
  /// `month` and `day`, never its epoch value.
  final DateTime date;

  /// `hours.length`, kept explicit because it is what callers reason about.
  final int hourCount;

  final List<DateTime> hours;

  /// The transition falling inside this day, when there is one.
  final DstTransition? transition;

  @override
  List<Object?> get props => [zoneId, date, hourCount, hours, transition];
}

/// Every timezone question the app can ask.
///
/// Synchronous by design: after [initialize] every answer is an in-memory
/// lookup, and wrapping those in futures would put an `await` in the middle of
/// every widget build. Only [initialize] and [deviceZone] are asynchronous,
/// because loading tzdata and talking to the platform channel genuinely are.
abstract class TimeZoneEngine {
  /// Loads the IANA database. Idempotent, and must complete before any other
  /// call. `StartupCubit` owns it.
  Future<void> initialize();

  /// The zone's offset, abbreviation and DST flag at [instant].
  ZoneState stateAt({required String zoneId, required DateTime instant});

  /// The wall-clock reading a person in [zoneId] sees at [instant].
  DateTime wallTimeAt({required String zoneId, required DateTime instant});

  /// The UTC instant behind a set of local calendar fields. Never throws: a
  /// nonexistent or repeated local time is reported through
  /// [ResolvedInstant.resolution] instead.
  ResolvedInstant instantFor({
    required String zoneId,
    required int year,
    required int month,
    required int day,
    int hour = 0,
    int minute = 0,
  });

  /// `offset(to) - offset(from)` at [instant].
  ///
  /// Computed pairwise for that instant, never as the difference of two stored
  /// offsets: London is 4 hours from New York for two weeks each spring and 5
  /// hours the rest of the year (rule 10).
  Duration relativeOffset({
    required String fromZoneId,
    required String toZoneId,
    required DateTime instant,
  });

  /// The structure of one local calendar day, including its real hour count.
  ZoneDay dayIn({required String zoneId, required DateTime localDate});

  /// The next offset change at or after [instant], or `null` when none is
  /// scheduled within the next year or so.
  DstTransition? nextTransition({
    required String zoneId,
    required DateTime instant,
  });

  /// Best-effort device zone. Falls back to UTC and says so (rule 11).
  Future<DeviceZone> deviceZone();
}

/// [TimeZoneEngine] backed by the `timezone` package's embedded IANA data.
class TzTimeZoneEngine implements TimeZoneEngine {
  TzTimeZoneEngine();

  /// tzdata lives in a process-wide singleton inside the `timezone` package,
  /// so the guard has to be static too: a second engine instance must not
  /// clear and rebuild the database out from under the first one.
  static bool _tzDataLoaded = false;

  /// How far [nextTransition] looks ahead. Thirteen months covers the next
  /// change in either hemisphere; beyond that it is not a UI concern, and an
  /// unbounded search would walk a zone's entire future schedule.
  static const Duration _transitionHorizon = Duration(days: 400);

  /// Safety stop for the [dayIn] walk. A real local day is 23 to 25 slots.
  static const int _maxHourSlots = 26;

  @override
  Future<void> initialize() async {
    if (_tzDataLoaded) return;
    // The test harness loads tzdata directly; reloading would clear and
    // rebuild the global database for no reason.
    if (!tz.timeZoneDatabase.isInitialized) {
      tzdata.initializeTimeZones();
    }
    _tzDataLoaded = true;
  }

  @override
  ZoneState stateAt({required String zoneId, required DateTime instant}) {
    _assertInitialized();
    final zone = _resolve(zoneId);
    final zoned = tz.TZDateTime.from(instant, zone.location);
    final offset = zoned.timeZoneOffset;
    return ZoneState(
      zoneId: zone.id,
      abbreviation: zoned.timeZoneName,
      offset: offset,
      isDst: offset > _standardOffsetIn(zone.location, zoned.year),
    );
  }

  @override
  DateTime wallTimeAt({required String zoneId, required DateTime instant}) {
    _assertInitialized();
    final zoned = tz.TZDateTime.from(instant, _resolve(zoneId).location);
    return _wallClockOf(zoned);
  }

  @override
  ResolvedInstant instantFor({
    required String zoneId,
    required int year,
    required int month,
    required int day,
    int hour = 0,
    int minute = 0,
  }) {
    _assertInitialized();
    final location = _resolve(zoneId).location;
    final candidate = tz.TZDateTime(location, year, month, day, hour, minute);
    final at = candidate.millisecondsSinceEpoch;

    // A local time inside a spring-forward gap comes back normalised past the
    // gap, which is precisely rule 6's "resolve forward". Comparing the fields
    // we asked for against the ones we got is how that is detected: tz has no
    // "this did not exist" signal.
    if (candidate.hour != hour ||
        candidate.minute != minute ||
        candidate.day != day) {
      return ResolvedInstant(
        utcInstant: _utcAt(at),
        resolution: TimeResolution.shiftedForward,
      );
    }

    final first = _firstOccurrenceOf(location, at);
    if (first != null) {
      return ResolvedInstant(
        utcInstant: _utcAt(first),
        resolution: TimeResolution.ambiguousFirst,
      );
    }

    return ResolvedInstant(
      utcInstant: _utcAt(at),
      resolution: TimeResolution.exact,
    );
  }

  @override
  Duration relativeOffset({
    required String fromZoneId,
    required String toZoneId,
    required DateTime instant,
  }) {
    _assertInitialized();
    final at = instant.millisecondsSinceEpoch;
    return _resolve(toZoneId).location.timeZone(at).offset -
        _resolve(fromZoneId).location.timeZone(at).offset;
  }

  @override
  ZoneDay dayIn({required String zoneId, required DateTime localDate}) {
    _assertInitialized();
    final zone = _resolve(zoneId);
    final start = instantFor(
      zoneId: zoneId,
      year: localDate.year,
      month: localDate.month,
      day: localDate.day,
    ).utcInstant;

    // Walking real hours from local midnight is what makes 23 and 25 fall out
    // naturally; deriving the count from the date arithmetic instead would
    // reintroduce the "every day has 24 hours" assumption.
    final hours = <DateTime>[];
    var cursor = start;
    while (hours.length < _maxHourSlots &&
        _isSameLocalDate(zone.location, cursor, localDate)) {
      hours.add(cursor);
      cursor = cursor.add(const Duration(hours: 1));
    }

    return ZoneDay(
      zoneId: zone.id,
      date: DateTime.utc(localDate.year, localDate.month, localDate.day),
      hourCount: hours.length,
      hours: List.unmodifiable(hours),
      transition: _firstChangeBetween(
        zone.location,
        start.millisecondsSinceEpoch,
        cursor.millisecondsSinceEpoch,
      ),
    );
  }

  @override
  DstTransition? nextTransition({
    required String zoneId,
    required DateTime instant,
  }) {
    _assertInitialized();
    final from = instant.millisecondsSinceEpoch;
    return _firstChangeBetween(
      _resolve(zoneId).location,
      from,
      from + _transitionHorizon.inMilliseconds,
    );
  }

  @override
  Future<DeviceZone> deviceZone() async {
    _assertInitialized();
    try {
      final reported = await FlutterTimezone.getLocalTimezone();
      final ref = zoneOrNull(reported.identifier);
      if (ref != null) return DeviceZone(zoneId: ref.id, isFallback: false);
    } on Object {
      // Rule 11: detection is best effort and must never block startup, so a
      // missing platform channel, a permission refusal and a vendor id the
      // tzdata never heard of all land on the same fallback.
    }
    return const DeviceZone(zoneId: utcZoneId, isFallback: true);
  }

  /// Resolves [zoneId] to a canonical id and its tz location, degrading to UTC
  /// rather than throwing (rule 3): one stale row in a synced board must not
  /// be able to take down the screen it appears on.
  ({String id, tz.Location location}) _resolve(String zoneId) {
    final ref = zoneOrNull(zoneId);
    final location = ref == null ? null : locationOrNull(ref.id);
    if (ref == null || location == null) {
      return (id: utcZoneId, location: tz.UTC);
    }
    return (id: ref.id, location: location);
  }

  /// The zone's non-DST offset for [year], derived rather than read.
  ///
  /// tzdata does carry a per-period DST bit, but it encodes *legal* DST, and
  /// that reads backwards in a clock app: Europe/Dublin models winter as
  /// negative DST, so the bit says "DST is on" in January. Comparing against
  /// the year's smaller offset answers the question a user is actually asking
  /// ("is this city shifted off its normal time right now?"). Probing January
  /// and July also survives southern-hemisphere zones, whose DST season spans
  /// the new year: whichever hemisphere it is, one probe lands in the DST
  /// season and the other outside it.
  Duration _standardOffsetIn(tz.Location location, int year) {
    final winter = location.timeZone(_utcMillisOf(year, 1)).offset;
    final summer = location.timeZone(_utcMillisOf(year, 7)).offset;
    return winter <= summer ? winter : summer;
  }

  /// The earliest instant sharing [at]'s wall clock, or `null` when that wall
  /// clock happens only once.
  ///
  /// The repeated window is exactly as long as the offset drop that caused it,
  /// which is 30 minutes on Australia/Lord_Howe and an hour nearly everywhere
  /// else, so it is measured from the transition rather than probed at a fixed
  /// one-hour distance. Both directions are checked because tz resolves an
  /// ambiguous local time to the later occurrence in positive-offset zones
  /// (Europe/London) and to the earlier one in negative-offset zones
  /// (America/New_York); rule 7 wants the earlier one either way.
  int? _firstOccurrenceOf(tz.Location location, int at) {
    final period = location.lookupTimeZone(at);
    final offset = period.timeZone.offset.inMilliseconds;

    // The change that opened this period dropped the offset and [at] is still
    // inside the window it repeated, so the twin sits one drop earlier.
    if (period.start > tz.minTime) {
      final before = location.timeZone(period.start - 1).offset.inMilliseconds;
      final drop = before - offset;
      if (drop > 0 && at < period.start + drop) return at - drop;
    }

    // The change that closes this period will drop the offset and [at] is
    // already inside the window about to be repeated, so [at] is the first of
    // the two occurrences.
    if (period.end < tz.maxTime) {
      final after = location.timeZone(period.end).offset.inMilliseconds;
      final drop = offset - after;
      if (drop > 0 && at >= period.end - drop) return at;
    }

    return null;
  }

  /// The first real offset change in `[from, until)`, or `null`.
  ///
  /// tzdata stores transitions as a sorted array, so each step is a binary
  /// search: scanning hour by hour would do thousands of times the work for
  /// the same answer. The loop only advances when a stored change turns out to
  /// be an abbreviation-only rename, which is not a transition to a user.
  DstTransition? _firstChangeBetween(
    tz.Location location,
    int from,
    int until,
  ) {
    if (from >= until) return null;
    final opening = _changeOpeningAt(location, from);
    if (opening != null) return opening;

    var cursor = from;
    while (cursor < until) {
      final period = location.lookupTimeZone(cursor);
      final boundary = period.end;
      if (boundary >= tz.maxTime || boundary >= until) return null;

      final after = location.timeZone(boundary).offset;
      if (after != period.timeZone.offset) {
        return _transitionAt(boundary, period.timeZone.offset, after);
      }
      cursor = boundary;
    }
    return null;
  }

  /// The change that opens the period containing [at], but only when [at] sits
  /// exactly on it.
  ///
  /// A zone that springs forward at 00:00 (America/Santiago, America/Havana,
  /// Asia/Beirut) makes the local day *begin* at the change: midnight never
  /// happens, so the day's first instant is the transition itself. Since
  /// `lookupTimeZone` reports the period that starts there, a scan anchored at
  /// that instant would otherwise step straight over the change it exists to
  /// find, and the day would come back as 23 hours with no transition
  /// attached.
  DstTransition? _changeOpeningAt(tz.Location location, int at) {
    if (at <= tz.minTime) return null;
    final period = location.lookupTimeZone(at);
    if (period.start != at) return null;

    final before = location.timeZone(at - 1).offset;
    final after = period.timeZone.offset;
    if (before == after) return null;
    return _transitionAt(at, before, after);
  }

  DstTransition _transitionAt(int at, Duration before, Duration after) {
    final springsForward = after > before;
    return DstTransition(
      atUtc: _utcAt(at),
      before: before,
      after: after,
      // The clock jumps from `at + before` to `at + after`, so the local hour
      // named by the offset being left behind is the one that disappears, and
      // the hour named by the incoming offset is the one that starts over.
      skippedHour: springsForward ? _localHourAt(at, before) : null,
      repeatedHour: springsForward ? null : _localHourAt(at, after),
    );
  }

  bool _isSameLocalDate(
    tz.Location location,
    DateTime instant,
    DateTime localDate,
  ) {
    final zoned = tz.TZDateTime.from(instant, location);
    return zoned.year == localDate.year &&
        zoned.month == localDate.month &&
        zoned.day == localDate.day;
  }

  /// Packs a zoned time's calendar fields into a plain [DateTime].
  ///
  /// The result is a *field carrier*, not an instant: its fields are the
  /// zone's wall clock and its epoch value means nothing. `isUtc` is set only
  /// to keep Dart from re-reading those fields through the **device's** zone
  /// rules, which silently moves any wall time sitting in the device's own DST
  /// gap: a user in New York asking for London's 02:30 on the second Sunday in
  /// March would otherwise be shown 03:30. Read and format its fields; never
  /// do arithmetic with it and never call `toLocal()`.
  DateTime _wallClockOf(tz.TZDateTime zoned) => DateTime.utc(
    zoned.year,
    zoned.month,
    zoned.day,
    zoned.hour,
    zoned.minute,
    zoned.second,
  );

  /// The wall-clock hour a zone sitting at [offset] shows at instant [at].
  int _localHourAt(int at, Duration offset) =>
      _utcAt(at + offset.inMilliseconds).hour;

  DateTime _utcAt(int millisecondsSinceEpoch) =>
      DateTime.fromMillisecondsSinceEpoch(
        millisecondsSinceEpoch,
        isUtc: true,
      );

  int _utcMillisOf(int year, int month) =>
      DateTime.utc(year, month).millisecondsSinceEpoch;

  /// Rule 1: nothing works before the database is loaded. The [StateError]
  /// only fires in debug; in release the assert is stripped and unknown zones
  /// degrade to UTC through [_resolve], which is the safer failure for a user.
  void _assertInitialized() {
    assert(
      () {
        if (_tzDataLoaded || tz.timeZoneDatabase.isInitialized) return true;
        throw StateError(
          'TimeZoneEngine.initialize() must complete before any other call. '
          'StartupCubit owns it in the app; tests call initTestTimeZones().',
        );
      }(),
      'timezone database not loaded',
    );
  }
}

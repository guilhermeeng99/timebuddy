import 'package:equatable/equatable.dart';
import 'package:timebuddy/core/time/zone_lookup.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// The whole board: which zone is home, and which places are being watched.
///
/// Persisted and synced as one document (docs/specs/sync.md): [revision] is
/// what conflict resolution compares, never the individual rows, so every
/// mutation goes through `BoardCubit`, which bumps it.
///
/// ```dart
/// final board = BoardEntity.empty(
///   homeZoneId: deviceZone.zoneId,
///   now: clock.nowUtc(),
/// );
/// board.containsZone('Europe/Oslo'); // false on an empty board
/// ```
class BoardEntity extends Equatable {
  const BoardEntity({
    required this.homeZoneId,
    required this.locations,
    required this.revision,
    required this.updatedAt,
  });

  /// The board a first launch starts from (sync.md, Provisioning).
  ///
  /// `revision: 0` is load-bearing: a missing remote document is treated as
  /// `-1`, so this local seed always wins the first reconciliation and is
  /// written up rather than overwritten.
  factory BoardEntity.empty({
    required String homeZoneId,
    required DateTime now,
  }) {
    return BoardEntity(
      homeZoneId: homeZoneId,
      locations: const [],
      revision: 0,
      updatedAt: now.toUtc(),
    );
  }

  /// The cap, and the number `BoardFullFailure` reports.
  ///
  /// Twenty because past roughly that many rows the grid stops being readable
  /// and the per-tick rebuild cost stops being trivial
  /// (docs/specs/locations.md rule 4). It lives here rather than as a literal
  /// at each guard so the domain, the failure and the "3 of 20" header can
  /// only ever disagree by someone editing this line.
  static const int maxLocations = 20;

  /// The reference zone every relative offset is measured against.
  ///
  /// Independent of [locations] (rule 3): it may or may not have a row, and
  /// removing that row does not clear it (rule 8). Seeded from the device
  /// zone on first launch.
  final String homeZoneId;

  /// The saved places, ordered by [SavedLocationEntity.sortIndex], which is
  /// dense and 0-based.
  final List<SavedLocationEntity> locations;

  /// Monotonic per document, bumped on every write (sync.md rules 5 and 7).
  final int revision;

  /// UTC. Only ever breaks a [revision] tie (sync.md rule 8).
  final DateTime updatedAt;

  /// Whether another location would exceed [maxLocations].
  bool get isFull => locations.length >= maxLocations;

  /// Whether a row already covers [zoneId] (rule 2).
  bool containsZone(String zoneId) => locationForZone(zoneId) != null;

  /// The row covering [zoneId], or `null` when none does.
  ///
  /// The comparison is canonical, never literal: `Europe/Oslo` and
  /// `Europe/Berlin` are one clock, and a literal comparison would let them
  /// onto the board as two rows showing identical times (rule 2). An id the
  /// tzdata cannot resolve falls back to a literal comparison, so two rows
  /// with two genuinely unknown zones stay distinct instead of collapsing
  /// into each other.
  ///
  /// Pass [excludingId] to ignore one row, which is what repointing a row at
  /// a new zone needs: it must not collide with itself.
  SavedLocationEntity? locationForZone(String zoneId, {String? excludingId}) {
    final canonical = _canonicalZoneId(zoneId);
    for (final location in locations) {
      if (location.id == excludingId) continue;
      if (_canonicalZoneId(location.zoneId) == canonical) return location;
    }
    return null;
  }

  BoardEntity copyWith({
    String? homeZoneId,
    List<SavedLocationEntity>? locations,
    int? revision,
    DateTime? updatedAt,
  }) {
    return BoardEntity(
      homeZoneId: homeZoneId ?? this.homeZoneId,
      locations: locations ?? this.locations,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [homeZoneId, locations, revision, updatedAt];
}

/// [zoneId] as the tzdata names it, or unchanged when it is unknown.
String _canonicalZoneId(String zoneId) => zoneOrNull(zoneId)?.id ?? zoneId;

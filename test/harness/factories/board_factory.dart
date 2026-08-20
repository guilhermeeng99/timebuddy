import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// The instant every factory-built row was added at, and every board stamped.
///
/// Fixed, and deliberately mid-January so it sits far from any DST
/// transition. Both timestamps are part of entity equality, so a factory that
/// called `DateTime.now()` would make a board unequal to itself between two
/// frames of the same test.
final DateTime boardFixtureInstant = DateTime.utc(2024, 1, 15, 12);

/// Builds a [SavedLocationEntity], overriding only the fields a test cares
/// about.
///
/// The defaults describe one real row rather than a placeholder: the zone id
/// is canonical and resolvable, which is what most of these tests are about.
///
/// ```dart
/// final tokyo = aSavedLocation(
///   id: 'row-tokyo',
///   zoneId: 'Asia/Tokyo',
///   label: 'Tokyo',
///   countryCode: 'JP',
///   sortIndex: 1,
/// );
/// ```
SavedLocationEntity aSavedLocation({
  String id = 'row-sao-paulo',
  String zoneId = 'America/Sao_Paulo',
  String label = 'Sao Paulo',
  String countryCode = 'BR',
  int sortIndex = 0,
  DateTime? addedAt,
}) {
  return SavedLocationEntity(
    id: id,
    zoneId: zoneId,
    label: label,
    countryCode: countryCode,
    sortIndex: sortIndex,
    addedAt: addedAt ?? boardFixtureInstant,
  );
}

/// Builds a [BoardEntity]. Defaults to an empty board, which is a valid state
/// rather than an edge case (docs/specs/locations.md rule 6), so a test that
/// wants rows has to say which ones.
///
/// [revision] defaults to 1 rather than 0 so a test asserting that a mutation
/// bumped it cannot pass against a freshly seeded board.
///
/// ```dart
/// final board = aBoard(
///   homeZoneId: 'Europe/Berlin',
///   locations: [aSavedLocation(), aSavedLocation(id: 'row-tokyo')],
/// );
/// ```
BoardEntity aBoard({
  String homeZoneId = 'America/Sao_Paulo',
  List<SavedLocationEntity> locations = const [],
  int revision = 1,
  DateTime? updatedAt,
}) {
  return BoardEntity(
    homeZoneId: homeZoneId,
    locations: locations,
    revision: revision,
    updatedAt: updatedAt ?? boardFixtureInstant,
  );
}

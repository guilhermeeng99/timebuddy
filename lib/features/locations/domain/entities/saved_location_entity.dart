import 'package:equatable/equatable.dart';

/// One place the user is watching, as stored on their board.
///
/// [zoneId] is the only field the engine ever reads. [label] and
/// [countryCode] are denormalised from the city catalog at add time, because
/// the catalog is regenerated between app versions and a board must keep
/// rendering when an entry is renamed or dropped
/// (docs/specs/locations.md rule 12).
///
/// ```dart
/// final row = SavedLocationEntity(
///   id: uuid.v4(),
///   zoneId: 'America/Sao_Paulo',
///   label: 'Sao Paulo',
///   countryCode: 'BR',
///   sortIndex: 0,
///   addedAt: clock.nowUtc(),
/// );
/// ```
class SavedLocationEntity extends Equatable {
  const SavedLocationEntity({
    required this.id,
    required this.zoneId,
    required this.label,
    required this.countryCode,
    required this.sortIndex,
    required this.addedAt,
  });

  /// uuid v4, generated on add and stable for the row's whole life.
  ///
  /// Neither of the other candidates can be the identity: [sortIndex] changes
  /// on every reorder, and [zoneId] changes when a dropped zone is repaired
  /// (rule 11), so a UI keyed on either would animate the wrong row.
  final String id;

  /// Canonical IANA identifier, resolved through `zoneOrNull` before it is
  /// ever stored, so two spellings of one clock cannot become two rows.
  final String zoneId;

  /// Display name, e.g. `Sao Paulo`. Never derived from [zoneId] at render
  /// time: `America/Sao_Paulo` is an identifier, not a label (CLAUDE.md).
  final String label;

  /// ISO 3166-1 alpha-2, e.g. `BR`. Display data, like [label].
  final String countryCode;

  /// Dense, 0-based position on the board (rule 5).
  final int sortIndex;

  /// UTC. Kept so a future "recently added" affordance has an ordering that
  /// survives a reorder.
  final DateTime addedAt;

  SavedLocationEntity copyWith({
    String? id,
    String? zoneId,
    String? label,
    String? countryCode,
    int? sortIndex,
    DateTime? addedAt,
  }) {
    return SavedLocationEntity(
      id: id ?? this.id,
      zoneId: zoneId ?? this.zoneId,
      label: label ?? this.label,
      countryCode: countryCode ?? this.countryCode,
      sortIndex: sortIndex ?? this.sortIndex,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    zoneId,
    label,
    countryCode,
    sortIndex,
    addedAt,
  ];
}

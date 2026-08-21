import 'package:timebuddy/core/utils/json_parse.dart';
import 'package:timebuddy/features/locations/data/models/saved_location_model.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';
import 'package:timebuddy/features/locations/domain/entities/saved_location_entity.dart';

/// Serialization for [BoardEntity].
///
/// The same JSON shape is used for `shared_preferences` and, from M3, for
/// Firestore, so there is one serializer rather than two (docs/specs/sync.md).
///
/// ```dart
/// final model = BoardModel.fromEntity(board);
/// await store.writeRaw(StorageKeys.board, jsonEncode(model.toJson()));
/// ```
class BoardModel extends BoardEntity {
  const BoardModel({
    required super.homeZoneId,
    required super.locations,
    required super.revision,
    required super.updatedAt,
  });

  /// Parses a stored board, degrading every field rather than throwing.
  ///
  /// [homeZoneIdFallback] fills in only for a *missing* `homeZoneId`, and is
  /// normally the device zone. An id that is present but that the tzdata
  /// cannot resolve is kept verbatim: the grid detects exactly that case and
  /// shows a banner prompting the user to fix their home city
  /// (docs/specs/time_grid.md, Edge Cases), which swapping in the device zone
  /// here would make unreachable — and would silently move the reference zone
  /// of every offset on screen.
  factory BoardModel.fromJson(
    Map<String, dynamic> json, {
    required String homeZoneIdFallback,
  }) {
    return BoardModel(
      homeZoneId: filledStringOrNull(json['homeZoneId']) ?? homeZoneIdFallback,
      locations: _locationsFrom(json['locations']),
      revision: intOrNull(json['revision']) ?? 0,
      updatedAt: timestampFromJson(json['updatedAt']),
    );
  }

  factory BoardModel.fromEntity(BoardEntity entity) {
    return BoardModel(
      homeZoneId: entity.homeZoneId,
      locations: entity.locations,
      revision: entity.revision,
      updatedAt: entity.updatedAt,
    );
  }

  /// Parses the rows, drops the ones that cannot be salvaged, and hands back
  /// a list that satisfies the entity's own invariant: ordered by
  /// `sortIndex`, dense and 0-based (docs/specs/locations.md rule 5).
  ///
  /// Re-densifying here rather than leaving it to a caller is what keeps a
  /// dropped row from leaving a hole: with rows at 0, 2, 3 the next add would
  /// take index 3 and collide with an existing one. The repaired order is
  /// written back on the next save, so the document heals itself.
  static List<SavedLocationEntity> _locationsFrom(Object? raw) {
    if (raw is! List) return const [];

    final rows = <SavedLocationEntity>[];
    for (final entry in raw) {
      final row = SavedLocationModel.tryFromJson(entry);
      if (row != null) rows.add(row);
    }
    rows.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    return List.unmodifiable([
      for (var position = 0; position < rows.length; position++)
        rows[position].copyWith(sortIndex: position),
    ]);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'homeZoneId': homeZoneId,
      'locations': [
        for (final location in locations)
          SavedLocationModel.fromEntity(location).toJson(),
      ],
      'revision': revision,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

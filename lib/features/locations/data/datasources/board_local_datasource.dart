import 'dart:convert';

import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';

/// Reads and writes the board document held in [LocalStore].
///
/// ```dart
/// final stored = await dataSource.read(homeZoneIdFallback: deviceZoneId);
/// await dataSource.write(BoardModel.fromEntity(board));
/// ```
abstract class BoardLocalDataSource {
  /// Returns the stored board, or `null` when nothing was ever written.
  ///
  /// [homeZoneIdFallback] is only consulted for a document with no
  /// `homeZoneId`; see `BoardModel.fromJson`.
  ///
  /// Throws [CacheException] when the stored string is not a JSON object.
  /// A malformed *row* never throws: it is dropped and the rest of the board
  /// survives (docs/specs/locations.md, Model Serialization).
  Future<BoardModel?> read({required String homeZoneIdFallback});

  /// Overwrites the document. Throws [StorageException] if the platform
  /// refuses the write.
  Future<void> write(BoardModel board);
}

class BoardLocalDataSourceImpl implements BoardLocalDataSource {
  const BoardLocalDataSourceImpl(this._store);

  final LocalStore _store;

  @override
  Future<BoardModel?> read({required String homeZoneIdFallback}) async {
    // The message names the document because `readJsonObject` cannot: a
    // document that is not even a JSON object cannot be salvaged row by row,
    // so it is reported rather than silently replaced, and the repository
    // decides whether to seed a fresh board or surface the failure.
    final json = await _store.readJsonObject(
      StorageKeys.board,
      malformedMessage: 'The stored board is not a readable JSON object.',
    );
    if (json == null) return null;
    return BoardModel.fromJson(json, homeZoneIdFallback: homeZoneIdFallback);
  }

  @override
  Future<void> write(BoardModel board) {
    return _store.writeRaw(StorageKeys.board, jsonEncode(board.toJson()));
  }
}

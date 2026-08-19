import 'dart:convert';

import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';

/// Reads and writes the preferences document held in [LocalStore].
///
/// ```dart
/// final stored = await dataSource.read();   // null on a fresh install
/// await dataSource.write(PreferencesModel.fromEntity(preferences));
/// ```
abstract class PreferencesLocalDataSource {
  /// Returns the stored preferences, or `null` when nothing was ever written.
  ///
  /// Throws [CacheException] when the stored string is not a JSON object.
  /// Unknown or malformed *fields* never throw: they degrade in
  /// [PreferencesModel.fromJson].
  Future<PreferencesModel?> read();

  /// Overwrites the document. Throws [StorageException] if the platform
  /// refuses the write.
  Future<void> write(PreferencesModel preferences);
}

class PreferencesLocalDataSourceImpl implements PreferencesLocalDataSource {
  const PreferencesLocalDataSourceImpl(this._store);

  final LocalStore _store;

  @override
  Future<PreferencesModel?> read() async {
    final raw = await _store.readRaw(StorageKeys.preferences);
    if (raw == null) return null;
    return PreferencesModel.fromJson(_decodeObject(raw));
  }

  @override
  Future<void> write(PreferencesModel preferences) {
    return _store.writeRaw(
      StorageKeys.preferences,
      jsonEncode(preferences.toJson()),
    );
  }

  /// A document that is not even a JSON object cannot be salvaged field by
  /// field, so it is reported rather than silently replaced: the repository
  /// decides whether to fall back to defaults or surface the failure.
  Map<String, dynamic> _decodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw) as Object?;
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException catch (_) {
      // Falls through to the exception below: the message is the same either
      // way, and the caller cannot act on the difference.
    }
    throw const CacheException(
      'Stored preferences are not a readable JSON object.',
    );
  }
}

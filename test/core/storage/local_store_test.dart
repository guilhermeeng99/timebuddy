import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/storage/local_store.dart';

void main() {
  // `setMockInitialValues` swaps the platform store for an in-memory one, so
  // no test here touches a real device channel. The binding still has to exist
  // before any plugin surface is used.
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  Future<LocalStore> storeSeededWith(Map<String, Object> documents) async {
    SharedPreferences.setMockInitialValues(documents);
    return SharedPreferencesLocalStore(await SharedPreferences.getInstance());
  }

  setUp(() async {
    store = await storeSeededWith(<String, Object>{});
  });

  group('SharedPreferencesLocalStore', () {
    test('round-trips a written document', () async {
      await store.writeRaw(StorageKeys.preferences, '{"revision":3}');

      expect(await store.readRaw(StorageKeys.preferences), '{"revision":3}');
    });

    test('returns null for a key that was never written', () async {
      expect(await store.readRaw(StorageKeys.board), isNull);
    });

    test('reads documents seeded before the store was built', () async {
      final seeded = await storeSeededWith(<String, Object>{
        StorageKeys.board: '{"homeZoneId":"America/Sao_Paulo"}',
      });

      expect(
        await seeded.readRaw(StorageKeys.board),
        '{"homeZoneId":"America/Sao_Paulo"}',
      );
    });

    // The document is the unit of storage (sync.md rule 6): a second write
    // replaces the first outright, it never merges into it.
    test('a second write replaces the first', () async {
      await store.writeRaw(StorageKeys.preferences, '{"revision":1}');
      await store.writeRaw(StorageKeys.preferences, '{"revision":2}');

      expect(await store.readRaw(StorageKeys.preferences), '{"revision":2}');
    });

    test('remove drops only the requested key', () async {
      await store.writeRaw(StorageKeys.preferences, 'prefs');
      await store.writeRaw(StorageKeys.board, 'board');

      await store.remove(StorageKeys.preferences);

      expect(await store.readRaw(StorageKeys.preferences), isNull);
      expect(await store.readRaw(StorageKeys.board), 'board');
    });

    test('remove of an absent key is not an error', () async {
      await expectLater(store.remove(StorageKeys.boardDirty), completes);

      expect(await store.readRaw(StorageKeys.boardDirty), isNull);
    });

    // sync.md rule 10: sign-out must leave nothing behind, dirty flags
    // included. A pending write for an account that just signed out must not
    // be flushed into the next session.
    test('clearAll wipes every key, dirty flags included', () async {
      await store.writeRaw(StorageKeys.board, 'board');
      await store.writeRaw(StorageKeys.preferences, 'prefs');
      await store.writeRaw(StorageKeys.boardDirty, 'true');
      await store.writeRaw(StorageKeys.preferencesDirty, 'true');

      await store.clearAll();

      expect(await store.readRaw(StorageKeys.board), isNull);
      expect(await store.readRaw(StorageKeys.preferences), isNull);
      expect(await store.readRaw(StorageKeys.boardDirty), isNull);
      expect(await store.readRaw(StorageKeys.preferencesDirty), isNull);
    });

    test('a store rebuilt over the same prefs sees the written data', () async {
      await store.writeRaw(StorageKeys.preferences, '{"revision":9}');

      final reopened = SharedPreferencesLocalStore(
        await SharedPreferences.getInstance(),
      );

      expect(await reopened.readRaw(StorageKeys.preferences), '{"revision":9}');
    });
  });

  group('LocalStoreJson.readJsonObject', () {
    // The message is the caller's, because it names the document. Repeating
    // the real ones here keeps the tests honest about what a user's log says.
    const boardMalformed = 'The stored board is not a readable JSON object.';

    test('decodes a stored object', () async {
      await store.writeRaw(StorageKeys.board, '{"homeZoneId":"UTC"}');

      expect(
        await store.readJsonObject(
          StorageKeys.board,
          malformedMessage: boardMalformed,
        ),
        <String, dynamic>{'homeZoneId': 'UTC'},
      );
    });

    test('returns null for a key that was never written', () async {
      // A fresh install, not damage: the repository seeds a document rather
      // than reporting a failure, so this must not throw.
      expect(
        await store.readJsonObject(
          StorageKeys.board,
          malformedMessage: boardMalformed,
        ),
        isNull,
      );
    });

    test('throws CacheException on a string that is not JSON at all', () async {
      await store.writeRaw(StorageKeys.board, 'not json');

      await expectLater(
        store.readJsonObject(
          StorageKeys.board,
          malformedMessage: boardMalformed,
        ),
        throwsA(
          isA<CacheException>().having(
            (e) => e.message,
            'message',
            boardMalformed,
          ),
        ),
      );
    });

    test('throws CacheException on truncated JSON', () async {
      // The half-written document a killed process leaves behind.
      await store.writeRaw(StorageKeys.board, '{"homeZoneId":"UTC"');

      await expectLater(
        store.readJsonObject(
          StorageKeys.board,
          malformedMessage: boardMalformed,
        ),
        throwsA(isA<CacheException>()),
      );
    });

    test('throws CacheException on valid JSON that is not an object', () async {
      // A document that decoded fine but cannot be salvaged field by field.
      // It is reported rather than silently replaced.
      for (final raw in <String>['[1,2,3]', '"a string"', '42', 'null']) {
        await store.writeRaw(StorageKeys.board, raw);

        await expectLater(
          store.readJsonObject(
            StorageKeys.board,
            malformedMessage: boardMalformed,
          ),
          throwsA(isA<CacheException>()),
          reason: 'stored $raw',
        );
      }
    });

    test('each document reports itself by name', () async {
      const preferencesMalformed =
          'Stored preferences are not a readable JSON object.';
      await store.writeRaw(StorageKeys.preferences, 'not json');

      await expectLater(
        store.readJsonObject(
          StorageKeys.preferences,
          malformedMessage: preferencesMalformed,
        ),
        throwsA(
          isA<CacheException>().having(
            (e) => e.message,
            'message',
            preferencesMalformed,
          ),
        ),
      );
    });

    test('an empty object is a document, not damage', () async {
      // Every field of both documents degrades, so `{}` parses to defaults.
      await store.writeRaw(StorageKeys.preferences, '{}');

      expect(
        await store.readJsonObject(
          StorageKeys.preferences,
          malformedMessage: boardMalformed,
        ),
        isEmpty,
      );
    });
  });

  group('StorageKeys', () {
    // sync.md rule 11. The suffix is the whole downgrade story: a breaking
    // JSON change writes `.v2` and leaves `.v1` untouched, so an older build
    // still finds a shape it can parse. Pinning the literals makes a rename a
    // failing test here rather than a silently emptied board on a device.
    test('document keys carry the .v1 version suffix', () {
      expect(StorageKeys.board, 'timebuddy.board.v1');
      expect(StorageKeys.preferences, 'timebuddy.preferences.v1');
      expect(StorageKeys.board, endsWith('.v1'));
      expect(StorageKeys.preferences, endsWith('.v1'));
    });

    // The flags are session bookkeeping, not documents: they carry no JSON
    // shape, so there is nothing for a version suffix to protect.
    test('dirty flags are unversioned and namespaced separately', () {
      expect(StorageKeys.boardDirty, 'timebuddy.dirty.board');
      expect(StorageKeys.preferencesDirty, 'timebuddy.dirty.preferences');
    });

    test('every key is distinct', () {
      const keys = <String>[
        StorageKeys.board,
        StorageKeys.preferences,
        StorageKeys.boardDirty,
        StorageKeys.preferencesDirty,
      ];

      expect(keys.toSet(), hasLength(keys.length));
    });
  });
}

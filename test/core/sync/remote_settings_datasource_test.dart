import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_keys.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';

import '../../harness/factories/board_factory.dart';
import '../../harness/factories/preferences_factory.dart';
import '../../harness/helpers.dart';

/// The three document paths this data source owns, spelled out as literals.
///
/// Deliberately *not* built from `SyncKeys`, which is what the production code
/// builds them from: a test that reused the constants would still pass after a
/// rename that pointed the app at `users/{id}/setting/board` and left every
/// existing account looking empty forever. These are the paths the deployed
/// security rules and the documents already in production are written against,
/// so a change here has to be a deliberate edit on both sides.
const String _boardPath = 'users/uid-ada/settings/board';
const String _preferencesPath = 'users/uid-ada/settings/preferences';
const String _profilePath = 'users/uid-ada';

const String _userId = 'uid-ada';

/// A second account, used to prove that one user's read cannot see another's
/// document. Firestore's rules enforce that in production; what is asserted
/// here is that the *path* carries the account at all.
const String _otherUserId = 'uid-grace';

/// The home zone a caller offers when the remote document has none of its own.
///
/// A real, canonical id: `BoardModel.fromJson` keeps whatever it is handed,
/// and a synthetic one would leave the assertion unable to say whether the
/// fallback or the stored value came through.
const String _fallbackHomeZoneId = 'America/Sao_Paulo';

/// Rules that refuse everything, so a read and a write both fail.
///
/// This is the *non-Firebase* failure path: `fake_cloud_firestore` raises a
/// plain `Exception` here rather than a `FirebaseException`, which is exactly
/// the shape the data source's second `catch` exists for — the web and
/// platform channels surface failures that never reach the Firebase type.
const String _denyEverything = '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if false;
    }
  }
}''';

/// The instants the timestamp round trip is written against.
///
/// Both far from any DST transition and both off the hour, so a conversion
/// that silently truncated to the day or to the hour cannot pass, and neither
/// can one that dropped a sub-second component.
final DateTime _boardUpdatedAt = utcDate(2024, 5, 21, 14, 37, 5);
final DateTime _rowAddedAt = utcDate(2023, 11, 2, 8, 9, 41);

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreRemoteSettingsDataSource dataSource;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    dataSource = FirestoreRemoteSettingsDataSource(firestore);
  });

  /// The raw document at [path], exactly as Firestore holds it.
  ///
  /// Read through `doc(path)` rather than through the same
  /// `collection().doc().collection().doc()` chain the data source walks, so
  /// the assertion is about where the document *landed* and not about the two
  /// sides agreeing on how to spell a walk.
  Future<Map<String, dynamic>?> rawAt(String path) async =>
      (await firestore.doc(path).get()).data();

  Future<void> seed(String path, Map<String, dynamic> document) =>
      firestore.doc(path).set(document);

  /// The board every write test starts from: one row, so the recursion into
  /// `locations[].addedAt` is exercised, and two distinct instants, so a
  /// conversion that used one field's value for both cannot pass.
  BoardModel boardModel() => BoardModel.fromEntity(
    aBoard(
      homeZoneId: 'Europe/Berlin',
      locations: [aSavedLocation(addedAt: _rowAddedAt)],
      revision: 7,
      updatedAt: _boardUpdatedAt,
    ),
  );

  group('document paths', () {
    test('the board lands at users/{uid}/settings/board', () async {
      await dataSource.writeBoard(userId: _userId, board: boardModel());

      expect(await rawAt(_boardPath), isNotNull);
      // The two settings documents are siblings, so a data source that built
      // one path for both would still pass every round-trip assertion in this
      // file while overwriting the user's preferences with their board.
      expect(await rawAt(_preferencesPath), isNull);
    });

    test('preferences land at users/{uid}/settings/preferences', () async {
      await dataSource.writePreferences(
        userId: _userId,
        preferences: PreferencesModel.fromEntity(aPreferences()),
      );

      expect(await rawAt(_preferencesPath), isNotNull);
      expect(await rawAt(_boardPath), isNull);
    });

    test('the profile is the parent document, not a third settings doc', () {
      // `users/{uid}` itself: the settings subcollection hangs off it, so a
      // profile written one level deeper would be invisible to the auth
      // feature that reads it (docs/specs/auth.md).
      expect(
        dataSource.writeProfile(userId: _userId, profile: {'name': 'Ada'}),
        completes,
      );
    });

    test('the profile document holds what writeProfile was given', () async {
      await dataSource.writeProfile(userId: _userId, profile: {'name': 'Ada'});

      expect(await rawAt(_profilePath), containsPair('name', 'Ada'));
    });

    test("one account never reads another account's board", () async {
      await dataSource.writeBoard(userId: _userId, board: boardModel());

      // The uid is a path segment, so a data source that dropped it would
      // hand every signed-in device the same board.
      expect(
        await dataSource.readBoard(
          userId: _otherUserId,
          homeZoneIdFallback: _fallbackHomeZoneId,
        ),
        isNull,
      );
    });
  });

  group('writing timestamps', () {
    test('updatedAt is stored as a Timestamp, not as a string', () async {
      await dataSource.writeBoard(userId: _userId, board: boardModel());

      final stored = (await rawAt(_boardPath))!;
      // `toJson` produced an ISO-8601 string; Firestore is the side that wants
      // the native type, so that a date in the console reads as a date.
      expect(stored['updatedAt'], isA<Timestamp>());
      expect(
        (stored['updatedAt'] as Timestamp).toDate().toUtc(),
        _boardUpdatedAt,
      );
    });

    test('addedAt inside locations[] is converted too', () async {
      await dataSource.writeBoard(userId: _userId, board: boardModel());

      final rows = (await rawAt(_boardPath))!['locations']! as List<dynamic>;
      final addedAt = (rows.single as Map<String, dynamic>)['addedAt'];
      // The recursion is the point: a conversion that only walked the top
      // level would leave every row's addedAt a string, and every row would
      // then lose the `updatedAt` tie-break it should have won.
      expect(addedAt, isA<Timestamp>());
      expect((addedAt! as Timestamp).toDate().toUtc(), _rowAddedAt);
    });

    test('only the two named fields are converted', () async {
      // The doc comment's claim, pinned: the fields are named rather than
      // sniffed, so a rule like "every key ending in At" cannot creep in. The
      // label is a date-shaped string a user could plausibly have on a board,
      // and it has to survive as text.
      const dateShapedLabel = '2024-01-15T12:00:00.000Z';
      await dataSource.writeBoard(
        userId: _userId,
        board: BoardModel.fromEntity(
          aBoard(
            locations: [aSavedLocation(label: dateShapedLabel)],
            updatedAt: _boardUpdatedAt,
          ),
        ),
      );

      final stored = (await rawAt(_boardPath))!;
      final row =
          (stored['locations']! as List<dynamic>).single
              as Map<String, dynamic>;
      expect(row['label'], dateShapedLabel);
      expect(row['label'], isNot(isA<Timestamp>()));
      // And nothing else in the document turned into one either.
      expect(stored['homeZoneId'], isA<String>());
      expect(stored['revision'], isA<int>());
    });

    test('preferences keep their scalars and convert only updatedAt', () async {
      await dataSource.writePreferences(
        userId: _userId,
        preferences: PreferencesModel.fromEntity(
          aPreferences(
            hourFormat: ClockFormat.h12,
            showSeconds: true,
            localeTag: 'pt-BR',
            revision: 4,
            updatedAt: _boardUpdatedAt,
          ),
        ),
      );

      final stored = (await rawAt(_preferencesPath))!;
      expect(stored['updatedAt'], isA<Timestamp>());
      expect(stored['hourFormat'], 'h12');
      expect(stored['showSeconds'], true);
      // The nested map is walked by the same recursion the board's rows use,
      // and must come back out as plain ints.
      expect(stored['workingHours'], isA<Map<String, dynamic>>());
      expect((stored['workingHours']! as Map)['start'], isA<int>());
    });
  });

  group('reading timestamps', () {
    test('a Timestamp comes back as the instant it was written', () async {
      await dataSource.writeBoard(userId: _userId, board: boardModel());

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      // The whole round trip: ISO string out of the model, Timestamp into
      // Firestore, epoch int back into the model. This is the tiebreaker the
      // conflict ladder resolves on (docs/specs/sync.md), so a lossy hop here
      // silently hands the wrong document the win.
      expect(board!.updatedAt, _boardUpdatedAt);
      expect(board.locations.single.addedAt, _rowAddedAt);
    });

    test('an ISO-8601 string is read exactly like a Timestamp', () async {
      // The dual-write contract: both stores use one serializer, so a document
      // copied from `shared_preferences` into Firestore by an older build must
      // still parse. Seeded raw, because the data source itself would have
      // converted it on the way in.
      await seed(_boardPath, {
        'homeZoneId': 'Europe/Berlin',
        'revision': 7,
        'updatedAt': _boardUpdatedAt.toIso8601String(),
        'locations': [
          {
            'id': 'row-sao-paulo',
            'zoneId': 'America/Sao_Paulo',
            'label': 'Sao Paulo',
            'countryCode': 'BR',
            'sortIndex': 0,
            'addedAt': _rowAddedAt.toIso8601String(),
          },
        ],
      });

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      expect(board!.updatedAt, _boardUpdatedAt);
      expect(board.locations.single.addedAt, _rowAddedAt);
    });

    test('a millisecond epoch int is read the same way as well', () async {
      await seed(_preferencesPath, {
        'revision': 3,
        'updatedAt': _boardUpdatedAt.millisecondsSinceEpoch,
      });

      final preferences = await dataSource.readPreferences(userId: _userId);

      expect(preferences!.updatedAt, _boardUpdatedAt);
    });

    test('a Timestamp is unwrapped before the model ever sees it', () async {
      // `Timestamp` is a cloud_firestore type and the models are shared with
      // `shared_preferences`, which never sees one. If the unwrapping were
      // skipped the model would fall back to the epoch and lose every tie
      // instead of throwing, so the failure would be silent.
      await seed(_preferencesPath, {
        'revision': 3,
        'updatedAt': Timestamp.fromDate(_boardUpdatedAt),
      });

      final preferences = await dataSource.readPreferences(userId: _userId);

      expect(preferences!.updatedAt, _boardUpdatedAt);
      expect(
        preferences.updatedAt,
        isNot(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      );
    });

    test('the profile map keeps its Timestamps, deliberately', () async {
      await seed(_profilePath, {
        'name': 'Ada',
        'createdAt': Timestamp.fromDate(_boardUpdatedAt),
      });

      final profile = await dataSource.readProfile(userId: _userId);

      // `UserModel` owns the createdAt mapping (docs/specs/auth.md), so
      // converting here would put a second parser on one document. The map is
      // handed over exactly as Firestore decoded it.
      expect(profile!['createdAt'], isA<Timestamp>());
    });
  });

  group('absent documents', () {
    test('readBoard answers null rather than an empty board', () async {
      expect(
        await dataSource.readBoard(
          userId: _userId,
          homeZoneIdFallback: _fallbackHomeZoneId,
        ),
        isNull,
      );
    });

    test('readPreferences answers null', () async {
      expect(await dataSource.readPreferences(userId: _userId), isNull);
    });

    test('readProfile answers null', () async {
      expect(await dataSource.readProfile(userId: _userId), isNull);
    });
  });

  group('the revision the conflict ladder reads', () {
    test('a readable revision is reported as stored', () async {
      await seed(_boardPath, {
        'homeZoneId': 'Europe/Berlin',
        'revision': 7,
        'updatedAt': Timestamp.fromDate(_boardUpdatedAt),
      });

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      expect(board!.revision, 7);
    });

    test('a board with no revision field loses instead of tying', () async {
      await seed(_boardPath, {
        'homeZoneId': 'Europe/Berlin',
        'updatedAt': Timestamp.fromDate(_boardUpdatedAt),
      });

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      // -1 and not 0. `BoardModel.fromJson` degrades a missing revision to 0,
      // which is right for local storage and wrong here: 0 ties with a fresh
      // local board and the tie goes to the remote, so a corrupt server copy
      // would overwrite the user's first board.
      expect(board!.revision, SyncKeys.missingRevision);
      expect(board.revision, isNot(0));
    });

    test('a revision of the wrong type loses too', () async {
      await seed(_boardPath, {
        'homeZoneId': 'Europe/Berlin',
        // A string, which is what a hand-edited console document produces.
        'revision': '7',
        'updatedAt': Timestamp.fromDate(_boardUpdatedAt),
      });

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      expect(board!.revision, SyncKeys.missingRevision);
    });

    test('a demoted board keeps every other field it carried', () async {
      await seed(_boardPath, {
        'homeZoneId': 'Europe/Berlin',
        'updatedAt': Timestamp.fromDate(_boardUpdatedAt),
        'locations': [
          {
            'id': 'row-tokyo',
            'zoneId': 'Asia/Tokyo',
            'label': 'Tokyo',
            'countryCode': 'JP',
            'sortIndex': 0,
            'addedAt': Timestamp.fromDate(_rowAddedAt),
          },
        ],
      });

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      // The demotion rebuilds the model through `copyWith`, so a rebuild that
      // dropped the rows would still satisfy the revision assertion above.
      expect(board!.homeZoneId, 'Europe/Berlin');
      expect(board.locations.single.zoneId, 'Asia/Tokyo');
      expect(board.locations.single.addedAt, _rowAddedAt);
      expect(board.updatedAt, _boardUpdatedAt);
    });

    test('preferences with no revision lose on the same terms', () async {
      await seed(_preferencesPath, {
        'themeMode': 'dark',
        'updatedAt': Timestamp.fromDate(_boardUpdatedAt),
      });

      final preferences = await dataSource.readPreferences(userId: _userId);

      expect(preferences!.revision, SyncKeys.missingRevision);
      // And the document it demoted is still the one that was read.
      expect(preferences.updatedAt, _boardUpdatedAt);
    });
  });

  group('the home-zone fallback', () {
    test('fills in only a missing homeZoneId', () async {
      await seed(_boardPath, {'revision': 2});

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      expect(board!.homeZoneId, _fallbackHomeZoneId);
    });

    test('never displaces a stored one, even an unresolvable one', () async {
      // A zone id a future tzdata retired. Substituting the fallback here
      // would silently move every offset on the board to another city's clock
      // (docs/specs/locations.md rule 11).
      await seed(_boardPath, {'homeZoneId': 'Pacific/Atlantis', 'revision': 2});

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      expect(board!.homeZoneId, 'Pacific/Atlantis');
    });
  });

  group('write semantics', () {
    test('a settings write replaces the document wholesale', () async {
      // A field the current `toJson` does not write, standing in for one an
      // older or newer build left behind. It is the only way to tell a replace
      // from a merge here: every key the model writes is written on every
      // pass, and Firestore replaces an array field even under a merge, so a
      // test that only removed a row would pass against either.
      await seed(_boardPath, {
        'homeZoneId': 'Europe/Berlin',
        'revision': 1,
        'retiredField': 'left behind by another build',
      });

      await dataSource.writeBoard(userId: _userId, board: boardModel());

      // The document is the unit of reconciliation (sync.md rule 6): what the
      // client wrote is the whole server copy, so nothing the client no longer
      // knows about can survive to be read back.
      expect(await rawAt(_boardPath), isNot(contains('retiredField')));
    });

    test('a replaced board does not resurrect a removed row', () async {
      await dataSource.writeBoard(
        userId: _userId,
        board: BoardModel.fromEntity(
          aBoard(
            locations: [
              aSavedLocation(id: 'row-a'),
              aSavedLocation(id: 'row-b', zoneId: 'Asia/Tokyo', sortIndex: 1),
            ],
          ),
        ),
      );

      await dataSource.writeBoard(
        userId: _userId,
        board: BoardModel.fromEntity(
          aBoard(locations: [aSavedLocation(id: 'row-a')]),
        ),
      );

      final board = await dataSource.readBoard(
        userId: _userId,
        homeZoneIdFallback: _fallbackHomeZoneId,
      );

      expect(board!.locations.map((row) => row.id), ['row-a']);
    });

    test(
      'a profile write merges, so a retry completes rather than blanks',
      () async {
        await dataSource.writeProfile(
          userId: _userId,
          profile: {'name': 'Ada', 'email': 'ada@example.com'},
        );

        // Provisioning has to be idempotent (docs/specs/auth.md rule 3): the
        // second attempt after a partial failure must not blank the fields the
        // first one landed.
        await dataSource.writeProfile(
          userId: _userId,
          profile: {'photoUrl': 'https://example.com/ada.png'},
        );

        final profile = (await dataSource.readProfile(userId: _userId))!;
        expect(profile['name'], 'Ada');
        expect(profile['email'], 'ada@example.com');
        expect(profile['photoUrl'], 'https://example.com/ada.png');
      },
    );
  });

  group('failures', () {
    late FirestoreRemoteSettingsDataSource refusing;

    setUp(() {
      refusing = FirestoreRemoteSettingsDataSource(
        FakeFirebaseFirestore(securityRules: _denyEverything),
      );
    });

    test(
      'a refused read is a ServerException, never a null document',
      () async {
        // The distinction the sync service depends on: `null` means "this
        // account has no board yet" and drives provisioning, so a failure that
        // came back as null would silently overwrite the server with an empty
        // board (sync.md rule 5).
        await expectLater(
          refusing.readBoard(
            userId: _userId,
            homeZoneIdFallback: _fallbackHomeZoneId,
          ),
          throwsA(isA<ServerException>()),
        );
      },
    );

    test('a refused write is a ServerException', () async {
      await expectLater(
        refusing.writeBoard(userId: _userId, board: boardModel()),
        throwsA(isA<ServerException>()),
      );
    });

    test('a refusal is not reported as merely unavailable', () async {
      // The one decision the subtype exists for (sync.md, Edge Cases): a
      // dropped connection resolves itself and the indicator says "offline",
      // while a permission denied never will and the profile page has to say
      // so. Anything that is not a known-retryable Firebase code has to fall
      // on the hard-failure side, including a failure that never reached the
      // Firebase type at all.
      await expectLater(
        refusing.readPreferences(userId: _userId),
        throwsA(
          allOf(
            isA<ServerException>(),
            isNot(isA<RemoteUnavailableException>()),
          ),
        ),
      );
    });

    test('every entry point translates, not just the board', () async {
      await expectLater(
        refusing.readProfile(userId: _userId),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        refusing.writeProfile(userId: _userId, profile: {'name': 'Ada'}),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        refusing.writePreferences(
          userId: _userId,
          preferences: PreferencesModel.fromEntity(aPreferences()),
        ),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('RemoteUnavailableException', () {
    test('is a ServerException, so one catch clause still covers it', () {
      // The reason it is a subtype rather than a sibling: every
      // `on ServerException` handler above the data layer keeps working and
      // nothing has to learn a second type.
      expect(const RemoteUnavailableException(), isA<ServerException>());
    });

    test('carries the message it was given into its toString', () {
      expect(
        const RemoteUnavailableException('unavailable: offline').toString(),
        contains('unavailable: offline'),
      );
      // Distinguishable in a log from the hard failure, which is the only
      // thing the string is for (Failure.message is never shown to a user).
      expect(
        const RemoteUnavailableException().toString(),
        startsWith('RemoteUnavailableException:'),
      );
    });
  });
}

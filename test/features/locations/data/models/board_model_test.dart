import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/features/locations/data/models/board_model.dart';
import 'package:timebuddy/features/locations/data/models/saved_location_model.dart';
import 'package:timebuddy/features/locations/domain/entities/board_entity.dart';

import '../../../../harness/factories/board_factory.dart';
import '../../../../harness/helpers.dart';

/// The zone a document with no readable `homeZoneId` falls back to.
///
/// In production this is the device zone; here it only has to be a value no
/// fixture uses, so a test cannot pass by coincidence.
const String _fallbackHomeZoneId = 'Pacific/Auckland';

Map<String, dynamic> _rowJson({
  Object? id = 'row-tokyo',
  Object? zoneId = 'Asia/Tokyo',
  Object? label = 'Tokyo',
  Object? countryCode = 'JP',
  Object? sortIndex = 0,
  Object? addedAt = '2024-01-15T12:00:00.000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'zoneId': zoneId,
    'label': label,
    'countryCode': countryCode,
    'sortIndex': sortIndex,
    'addedAt': addedAt,
  };
}

Map<String, dynamic> _boardJson({
  Object? homeZoneId = 'America/Sao_Paulo',
  Object? locations,
  Object? revision = 3,
  Object? updatedAt = '2024-01-15T12:00:00.000Z',
}) {
  return <String, dynamic>{
    'homeZoneId': homeZoneId,
    'locations': locations ?? [_rowJson()],
    'revision': revision,
    'updatedAt': updatedAt,
  };
}

BoardModel _parse(Map<String, dynamic> json) =>
    BoardModel.fromJson(json, homeZoneIdFallback: _fallbackHomeZoneId);

void main() {
  group('SavedLocationModel', () {
    test('parses a well-formed row', () {
      final row = SavedLocationModel.tryFromJson(_rowJson(sortIndex: 2));

      expect(row, isNotNull);
      expect(row!.id, 'row-tokyo');
      expect(row.zoneId, 'Asia/Tokyo');
      expect(row.label, 'Tokyo');
      expect(row.countryCode, 'JP');
      expect(row.sortIndex, 2);
      expect(row.addedAt, utcDate(2024, 1, 15, 12));
      expect(row.addedAt.isUtc, isTrue);
    });

    test('round-trips through JSON', () {
      final row = aSavedLocation(
        id: 'row-kolkata',
        zoneId: 'Asia/Kolkata',
        label: 'Kolkata',
        countryCode: 'IN',
        sortIndex: 4,
      );

      final decoded = jsonDecode(
        jsonEncode(SavedLocationModel.fromEntity(row).toJson()),
      );

      expect(SavedLocationModel.tryFromJson(decoded)?.props, row.props);
    });

    // The three fields below are load-bearing: two of them address the row
    // and place it, and the third is the only one the engine reads. A row
    // missing any of them is dropped, and the rest of the board survives.
    test('drops a row that is not a map at all', () {
      expect(SavedLocationModel.tryFromJson('Asia/Tokyo'), isNull);
      expect(SavedLocationModel.tryFromJson(null), isNull);
      expect(SavedLocationModel.tryFromJson(const <String>[]), isNull);
    });

    test('drops a row with no id', () {
      expect(SavedLocationModel.tryFromJson(_rowJson(id: null)), isNull);
      expect(SavedLocationModel.tryFromJson(_rowJson(id: '  ')), isNull);
    });

    test('drops a row with no zone id', () {
      expect(SavedLocationModel.tryFromJson(_rowJson(zoneId: null)), isNull);
      expect(SavedLocationModel.tryFromJson(_rowJson(zoneId: 7)), isNull);
    });

    test('drops a row whose sortIndex is not a number', () {
      expect(
        SavedLocationModel.tryFromJson(_rowJson(sortIndex: 'first')),
        isNull,
      );
      expect(SavedLocationModel.tryFromJson(_rowJson(sortIndex: null)), isNull);
    });

    // Display data degrades instead: deleting a location the user really
    // saved because its label went missing would cost them more than the
    // label does.
    test('falls back to the zone id when the label is missing', () {
      final row = SavedLocationModel.tryFromJson(_rowJson(label: null));

      expect(row?.label, 'Asia/Tokyo');
    });

    test('falls back to an empty country code', () {
      final row = SavedLocationModel.tryFromJson(_rowJson(countryCode: 42));

      expect(row?.countryCode, '');
    });

    // Both halves of the dual encoding (sync.md): an ISO-8601 string from
    // shared_preferences, a millisecond epoch from an unwrapped Firestore
    // Timestamp.
    test('reads addedAt from an epoch millisecond int', () {
      final row = SavedLocationModel.tryFromJson(
        _rowJson(addedAt: DateTime.utc(2024, 1, 15, 12).millisecondsSinceEpoch),
      );

      expect(row?.addedAt, utcDate(2024, 1, 15, 12));
    });

    test('reads a non-UTC ISO addedAt as the same instant in UTC', () {
      final row = SavedLocationModel.tryFromJson(
        _rowJson(addedAt: '2024-01-15T09:00:00.000-03:00'),
      );

      expect(row?.addedAt, utcDate(2024, 1, 15, 12));
      expect(row?.addedAt.isUtc, isTrue);
    });

    // The epoch, never "now": a stamp nobody can read must lose every
    // conflict it enters (sync.md rule 5) rather than win them by looking
    // freshly written.
    test('falls back to the epoch for an unreadable addedAt', () {
      final row = SavedLocationModel.tryFromJson(_rowJson(addedAt: 'never'));

      expect(row?.addedAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });
  });

  group('BoardModel', () {
    test('round-trips a whole board through JSON', () {
      final board = aBoard(
        homeZoneId: 'Europe/Berlin',
        locations: [
          aSavedLocation(),
          aSavedLocation(
            id: 'row-tokyo',
            zoneId: 'Asia/Tokyo',
            label: 'Tokyo',
            countryCode: 'JP',
            sortIndex: 1,
          ),
        ],
        revision: 7,
      );

      final decoded =
          jsonDecode(jsonEncode(BoardModel.fromEntity(board).toJson()))
              as Map<String, dynamic>;

      expect(_parse(decoded).props, board.props);
    });

    test('writes the field names sync.md documents', () {
      final json = BoardModel.fromEntity(
        aBoard(locations: [aSavedLocation()]),
      ).toJson();

      expect(json.keys, ['homeZoneId', 'locations', 'revision', 'updatedAt']);
      expect((json['locations'] as List).first, {
        'id': 'row-sao-paulo',
        'zoneId': 'America/Sao_Paulo',
        'label': 'Sao Paulo',
        'countryCode': 'BR',
        'sortIndex': 0,
        'addedAt': '2024-01-15T12:00:00.000Z',
      });
    });

    // One bad row must not cost the user the other nineteen.
    test('skips a malformed row and keeps the rest', () {
      final board = _parse(
        _boardJson(
          locations: [
            _rowJson(id: 'row-a'),
            'not a row at all',
            _rowJson(id: 'row-b', zoneId: 'Europe/Berlin', sortIndex: 1),
            _rowJson(id: null),
          ],
        ),
      );

      expect(board.locations.map((row) => row.id), ['row-a', 'row-b']);
    });

    // A dropped row would otherwise leave a hole at index 1, and the next add
    // would take the length as its index and collide with an existing row.
    test('re-densifies the indices after a row is dropped', () {
      final board = _parse(
        _boardJson(
          locations: [
            _rowJson(id: 'row-a'),
            _rowJson(id: null, sortIndex: 1),
            _rowJson(id: 'row-c', sortIndex: 2),
          ],
        ),
      );

      expect(board.locations.map((row) => row.sortIndex), [0, 1]);
    });

    test('orders the rows by their stored sortIndex', () {
      final board = _parse(
        _boardJson(
          locations: [
            _rowJson(id: 'row-third', sortIndex: 9),
            _rowJson(id: 'row-first', sortIndex: 1),
            _rowJson(id: 'row-second', sortIndex: 4),
          ],
        ),
      );

      expect(board.locations.map((row) => row.id), [
        'row-first',
        'row-second',
        'row-third',
      ]);
      expect(board.locations.map((row) => row.sortIndex), [0, 1, 2]);
    });

    test('reads a missing or malformed locations array as an empty board', () {
      expect(_parse(_boardJson(locations: 'nope')).locations, isEmpty);
      expect(_parse(const <String, dynamic>{}).locations, isEmpty);
    });

    // A document that predates the field, or one whose revision was clobbered,
    // must lose reconciliation rather than win it (sync.md rule 5).
    test('defaults a missing revision to zero', () {
      expect(_parse(_boardJson(revision: null)).revision, 0);
      expect(_parse(_boardJson(revision: 'three')).revision, 0);
    });

    test('falls back to the epoch for an unreadable updatedAt', () {
      expect(
        _parse(_boardJson(updatedAt: null)).updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('reads updatedAt from either encoding', () {
      final fromIso = _parse(_boardJson()).updatedAt;
      final fromEpoch = _parse(
        _boardJson(
          updatedAt: DateTime.utc(2024, 1, 15, 12).millisecondsSinceEpoch,
        ),
      ).updatedAt;

      expect(fromIso, utcDate(2024, 1, 15, 12));
      expect(fromEpoch, fromIso);
    });

    test('falls back to the given home zone when the field is missing', () {
      const fallback = _fallbackHomeZoneId;
      expect(_parse(_boardJson(homeZoneId: null)).homeZoneId, fallback);
      expect(_parse(_boardJson(homeZoneId: '   ')).homeZoneId, fallback);
      expect(_parse(_boardJson(homeZoneId: 12)).homeZoneId, fallback);
    });

    // Deliberately *not* degraded to the fallback. The grid detects an
    // unresolvable home zone and prompts the user to fix their home city
    // (time_grid.md, Edge Cases); swapping in the device zone here would make
    // that unreachable and would silently move the reference zone every
    // offset on screen is measured against.
    test('keeps a home zone the tzdata cannot resolve', () {
      final board = _parse(_boardJson(homeZoneId: 'Pacific/Atlantis'));

      expect(board.homeZoneId, 'Pacific/Atlantis');
    });

    test('is a BoardEntity, so consumers never see the model', () {
      expect(_parse(_boardJson()), isA<BoardEntity>());
    });
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/features/locations/data/models/city_model.dart';
import 'package:timebuddy/features/locations/data/repositories/city_catalog_repository_impl.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';

/// The catalog asset, served from memory.
///
/// A hand-rolled bundle rather than a mock message handler on
/// `flutter/assets`: this one counts its reads, which is the only way to prove
/// the repository parses the file once instead of on every keystroke, and it
/// never depends on the real asset, so a regenerated catalog cannot silently
/// change what these tests assert.
class _FakeAssetBundle extends AssetBundle {
  _FakeAssetBundle(this._byKey);

  final Map<String, String> _byKey;

  /// How many times the asset was actually fetched.
  int loadCount = 0;

  @override
  Future<ByteData> load(String key) async {
    loadCount++;
    final value = _byKey[key];
    if (value == null) {
      // The shape `PlatformAssetBundle` throws for a missing or misdeclared
      // asset, which is an Error and not an Exception: reproducing it exactly
      // is the point of the failure tests below.
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

/// The catalog asset served by a bundle that caches the way the real one does,
/// after failing its first [failures] reads.
///
/// `rootBundle` is a [CachingAssetBundle], and its `loadString` memoizes the
/// future under the key without ever evicting a failed one. [_FakeAssetBundle]
/// above cannot show that: a plain [AssetBundle] has no cache, so a repository
/// that asks to be cached still looks like it retries. A read that fails and
/// then succeeds is the shape of a web asset request that hit a network blip.
class _FlakyCachingBundle extends CachingAssetBundle {
  _FlakyCachingBundle(this._payload, {required this.failures});

  final String _payload;

  /// How many reads fail before the file is served.
  final int failures;

  /// How many times the read reached past the bundle's own cache.
  int loadCount = 0;

  @override
  Future<ByteData> load(String key) async {
    loadCount++;
    if (loadCount <= failures) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(_payload)));
  }
}

/// The most prominent fixture, and the one with an accented real spelling.
const CityModel _saoPaulo = CityModel(
  zoneId: 'America/Sao_Paulo',
  name: 'Sao Paulo',
  countryCode: 'BR',
  countryName: 'Brazil',
  prominence: 100,
  aliases: ['Sampa', 'SP'],
);

/// Shares [_saoPaulo]'s zone, which is legal in the catalog and rejected only
/// at the board (docs/specs/locations.md rule 2). Present so a zone-id query
/// has to return both, in prominence order.
const CityModel _rio = CityModel(
  zoneId: 'America/Sao_Paulo',
  name: 'Rio de Janeiro',
  countryCode: 'BR',
  countryName: 'Brazil',
  admin1: 'Rio de Janeiro',
  prominence: 95,
  aliases: ['Rio'],
);

/// Same 'sa' prefix as [_saoPaulo], lower prominence: the ranking tie-break.
const CityModel _salvador = CityModel(
  zoneId: 'America/Bahia',
  name: 'Salvador',
  countryCode: 'BR',
  countryName: 'Brazil',
  admin1: 'Bahia',
  prominence: 82,
);

/// A derived row: prominence 0 keeps it out of the default list, and its
/// country name shares the 'sao' prefix with two other fixtures.
const CityModel _saoTome = CityModel(
  zoneId: 'Africa/Sao_Tome',
  name: 'Sao Tome',
  countryCode: 'ST',
  countryName: 'Sao Tome and Principe',
  prominence: 0,
);

const CityModel _newYork = CityModel(
  zoneId: 'America/New_York',
  name: 'New York',
  countryCode: 'US',
  countryName: 'United States',
  prominence: 100,
  aliases: ['NYC'],
);

const CityModel _tokyo = CityModel(
  zoneId: 'Asia/Tokyo',
  name: 'Tokyo',
  countryCode: 'JP',
  countryName: 'Japan',
  prominence: 96,
);

const List<CityModel> _fixture = [
  _saoPaulo,
  _rio,
  _salvador,
  _saoTome,
  _newYork,
  _tokyo,
];

/// The fixture as the asset would hold it, for the bundles that serve bytes.
final String _serialized = jsonEncode(<String, Object?>{
  'version': 1,
  'cities': _fixture.map((city) => city.toJson()).toList(),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAssetBundle bundle;
  late CityCatalogRepositoryImpl repository;

  /// Serves [entries] verbatim, so a test can put a non-map or a half-written
  /// row into the array the way a bad regeneration would.
  void bundleServes(List<Object?> entries) {
    bundle = _FakeAssetBundle({
      CityCatalogRepositoryImpl.assetPath: jsonEncode(<String, Object?>{
        'version': 1,
        'cities': entries,
      }),
    });
    repository = CityCatalogRepositoryImpl(bundle: bundle);
  }

  void bundleServesFixture() {
    bundleServes(_fixture.map((city) => city.toJson()).toList());
  }

  setUp(bundleServesFixture);

  List<CityEntity> valueOf(Either<Failure, List<CityEntity>> result) =>
      result.getOrElse(() => fail('expected a Right, got $result'));

  Failure failureOf(Either<Failure, List<CityEntity>> result) =>
      result.fold((failure) => failure, (_) => fail('expected a Left'));

  Future<List<String>> namesFor(String query, {int limit = 30}) async {
    final result = await repository.search(query, limit: limit);
    return valueOf(result).map((city) => city.name).toList();
  }

  group('load', () {
    test('parses every well-formed row of the asset', () async {
      final cities = valueOf(await repository.load());

      expect(cities, hasLength(_fixture.length));
      expect(cities.first.name, 'Sao Paulo');
    });

    test('reads the asset once and answers later calls from memory', () async {
      await repository.load();
      await repository.search('tokyo');
      await repository.load();

      expect(bundle.loadCount, 1);
    });

    test('skips a malformed entry instead of failing the catalog', () async {
      bundleServes(<Object?>[
        _tokyo.toJson(),
        'not a map at all',
        <String, Object?>{'name': 'Zoneless', 'countryCode': 'BR'},
        <String, Object?>{
          'zoneId': 'America/Nowhere',
          'name': 42,
          'countryCode': 'BR',
          'countryName': 'Brazil',
          'prominence': 10,
        },
        _newYork.toJson(),
      ]);

      final cities = valueOf(await repository.load());

      expect(cities.map((city) => city.name), ['Tokyo', 'New York']);
    });

    test('tolerates a row with no admin1 and no aliases', () async {
      bundleServes(<Object?>[
        <String, Object?>{
          'zoneId': 'Asia/Tokyo',
          'name': 'Tokyo',
          'countryCode': 'JP',
          'countryName': 'Japan',
          'prominence': 96,
        },
      ]);

      final cities = valueOf(await repository.load());

      expect(cities.single.admin1, isNull);
      expect(cities.single.aliases, isEmpty);
    });

    test('a missing asset is a ServerFailure, not a crash', () async {
      repository = CityCatalogRepositoryImpl(
        bundle: _FakeAssetBundle(const {}),
      );

      expect(failureOf(await repository.load()), isA<ServerFailure>());
    });

    test('a corrupt asset is a ServerFailure', () async {
      repository = CityCatalogRepositoryImpl(
        bundle: _FakeAssetBundle({
          CityCatalogRepositoryImpl.assetPath: '{"version": 1, "cities": ',
        }),
      );

      expect(failureOf(await repository.load()), isA<ServerFailure>());
    });

    test('one blip on the fetch is absorbed without the caller seeing it', () {
      return fakeAsync((async) {
        final flaky = _FlakyCachingBundle(_serialized, failures: 1);
        repository = CityCatalogRepositoryImpl(bundle: flaky);

        Either<Failure, List<CityEntity>>? result;
        unawaited(repository.load().then((value) => result = value));
        async.elapse(const Duration(seconds: 1));

        expect(valueOf(result!), isNotEmpty);
        expect(flaky.loadCount, 2);
      });
    });

    // Regression: the splash's "Try again" and the sheet's retry both replayed
    // the first failure forever, because `CachingAssetBundle.loadString`
    // memoizes the failed future and never evicts it. On web that turned one
    // failed asset request into an app that only a page reload could start.
    test('a read that used up its attempts is not replayed from cache', () {
      return fakeAsync((async) {
        // One more failure than a single call is allowed to absorb, so the
        // first `load` genuinely gives up and the second has to fetch again.
        final flaky = _FlakyCachingBundle(_serialized, failures: 2);
        repository = CityCatalogRepositoryImpl(bundle: flaky);

        Either<Failure, List<CityEntity>>? first;
        unawaited(repository.load().then((value) => first = value));
        async.elapse(const Duration(seconds: 1));
        expect(failureOf(first!), isA<ServerFailure>());
        expect(flaky.loadCount, 2);

        Either<Failure, List<CityEntity>>? second;
        unawaited(repository.load().then((value) => second = value));
        async.elapse(const Duration(seconds: 1));
        expect(valueOf(second!), isNotEmpty);
        expect(flaky.loadCount, 3);
      });
    });

    test('an asset without a cities array is a ServerFailure', () async {
      repository = CityCatalogRepositoryImpl(
        bundle: _FakeAssetBundle({
          CityCatalogRepositoryImpl.assetPath: '{"version": 1}',
        }),
      );

      expect(failureOf(await repository.load()), isA<ServerFailure>());
    });
  });

  group('search', () {
    test('folds accents on both sides of the comparison', () async {
      // The catalog stores the plain spelling; the user types the real one.
      expect(await namesFor('são paulo'), ['Sao Paulo']);
      expect(await namesFor('SAO PAULO'), ['Sao Paulo']);
      expect(await namesFor('  sao   paulo '), ['Sao Paulo']);
    });

    test('matches an alias without ever showing it', () async {
      final cities = valueOf(await repository.search('sampa'));

      expect(cities.single.name, 'Sao Paulo');
      expect(await namesFor('nyc'), ['New York']);
    });

    test('matches a raw IANA id, in any casing', () async {
      expect(await namesFor('Asia/Tokyo'), ['Tokyo']);
      expect(await namesFor('asia/tokyo'), ['Tokyo']);
    });

    test('a zone id returns every city on that clock, best first', () async {
      const onThatClock = ['Sao Paulo', 'Rio de Janeiro'];
      expect(await namesFor('America/Sao_Paulo'), onThatClock);
      // The underscore is read as a space, so the spaced spelling works too.
      expect(await namesFor('america/sao paulo'), onThatClock);
    });

    test('ranks exact name, then prefix, then substring', () async {
      // 'sao tome' is an exact name; 'Sao Paulo' only a prefix match.
      expect(await namesFor('sao tome'), ['Sao Tome']);
      expect(await namesFor('sao'), ['Sao Paulo', 'Sao Tome']);
      // 'ork' appears inside New York and nowhere else.
      expect(await namesFor('ork'), ['New York']);
    });

    test('breaks a rank tie by descending prominence', () async {
      expect(await namesFor('sa'), ['Sao Paulo', 'Salvador', 'Sao Tome']);
    });

    test('matches the country name too', () async {
      expect(await namesFor('japan'), ['Tokyo']);
      expect(await namesFor('brazil'), [
        'Sao Paulo',
        'Rio de Janeiro',
        'Salvador',
      ]);
    });

    test('matches the state, which is what tells two rows apart', () async {
      expect(await namesFor('bahia'), ['Salvador']);
    });

    test('respects limit', () async {
      expect(await namesFor('brazil', limit: 2), [
        'Sao Paulo',
        'Rio de Janeiro',
      ]);
      expect(await namesFor('brazil', limit: 0), isEmpty);
    });

    test('an unmatched query is an empty list, not a failure', () async {
      expect(await namesFor('atlantis'), isEmpty);
    });

    test('an empty query returns the curated default list', () async {
      // Prominence 0 marks a derived row, which is a fine search hit and a
      // poor suggestion, so Sao Tome must not be offered here.
      expect(await namesFor(''), [
        'New York',
        'Sao Paulo',
        'Tokyo',
        'Rio de Janeiro',
        'Salvador',
      ]);
      expect(await namesFor('   '), await namesFor(''));
    });

    test('the default list respects limit', () async {
      expect(await namesFor('', limit: 2), ['New York', 'Sao Paulo']);
    });

    test('a broken asset fails the search as well as the load', () async {
      repository = CityCatalogRepositoryImpl(
        bundle: _FakeAssetBundle(const {}),
      );

      expect(failureOf(await repository.search('tokyo')), isA<ServerFailure>());
    });

    test('a failed read is retried rather than cached', () {
      return fakeAsync((async) {
        final empty = _FakeAssetBundle(<String, String>{});
        repository = CityCatalogRepositoryImpl(bundle: empty);

        unawaited(repository.load());
        async.elapse(const Duration(seconds: 1));
        unawaited(repository.load());
        async.elapse(const Duration(seconds: 1));

        // Two calls, and each one spends both of its attempts on a bundle that
        // never serves the file: the second call is what this pins, and it has
        // to reach the bundle rather than replay the first call's failure.
        expect(empty.loadCount, 4);
      });
    });
  });
}

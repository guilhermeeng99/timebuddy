import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/utils/string_normalize.dart';
import 'package:timebuddy/features/locations/data/models/city_model.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';

/// Match quality, best first. Search sorts by this before prominence.
///
/// Name matches outrank alias, country and state matches of the same shape, so
/// typing `paris` puts the city above every row in a country whose name merely
/// contains it. Within one rank the tie-break is descending prominence
/// (docs/specs/locations.md rule 9).
enum _MatchRank {
  exactName,
  exactOther,
  namePrefix,
  otherPrefix,
  nameSubstring,
  otherSubstring,
}

/// Asset-backed [CityCatalogRepository].
///
/// The asset is read once and kept as a pre-folded index. Search runs on every
/// keystroke of the add-location sheet, and folding 500 names per keystroke
/// would put `normalizeForSearch` on the critical path of typing; folding at
/// parse time makes a keystroke a walk over strings that are already index
/// keys (CLAUDE.md, Performance).
///
/// The bundle is injectable so a test never touches the real asset. Production
/// leaves it unset and gets `rootBundle`, which is why the DI container can
/// register `CityCatalogRepositoryImpl.new` with no arguments.
///
/// ```dart
/// final catalog = CityCatalogRepositoryImpl();
/// await catalog.search('sampa'); // -> [Sao Paulo]
/// ```
class CityCatalogRepositoryImpl implements CityCatalogRepository {
  CityCatalogRepositoryImpl({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  /// Where the generated catalog lives, as declared in `pubspec.yaml`.
  static const String assetPath = 'lib/app/assets/data/cities.json';

  /// How many times one cold read may reach the bundle before it gives up.
  ///
  /// Two, and deliberately not a ladder. On web this asset is an HTTP request
  /// like any other, and the failure worth absorbing is a single blip on it,
  /// not an outage: a longer chain would sit on the splash to arrive at the
  /// same answer. A genuine outage still ends in a [ServerFailure], which the
  /// add-location sheet reports with a retry of its own.
  static const int _readAttempts = 2;

  /// The pause between those two attempts.
  ///
  /// Long enough for a connection that dropped mid-request to be re-made,
  /// short enough that a real failure is still reported within one animation
  /// of the splash rather than after a visible stall.
  static const Duration _retryBackoff = Duration(milliseconds: 300);

  final AssetBundle _bundle;

  List<_IndexedCity>? _cache;
  Future<List<_IndexedCity>>? _pending;

  @override
  Future<Either<Failure, List<CityEntity>>> load() {
    return _guarded(() async {
      final indexed = await _catalog();
      return indexed.map((entry) => entry.city).toList(growable: false);
    });
  }

  @override
  Future<Either<Failure, List<CityEntity>>> search(
    String query, {
    int limit = 30,
  }) {
    return _guarded(() async {
      final indexed = await _catalog();
      final folded = _foldQuery(query);
      if (folded.isEmpty) return _defaults(indexed, limit);
      return _ranked(indexed, folded, limit);
    });
  }

  /// Runs [read] and turns anything it throws into a [ServerFailure].
  ///
  /// Three shapes reach here: a missing or misdeclared asset, a corrupt file
  /// (`FormatException` from the decoder) and platform-channel noise. All
  /// three mean one thing to the caller - the catalog is unusable - and none
  /// may take the app down, because the board still renders from the labels it
  /// stored at add time (docs/specs/locations.md, Edge Cases).
  Future<Either<Failure, List<CityEntity>>> _guarded(
    Future<List<CityEntity>> Function() read,
  ) async {
    try {
      return Right(await read());
      // The bundle reports a missing or misdeclared asset by throwing
      // `FlutterError`, which is an Error rather than an Exception. Letting it
      // through would crash the whole app over one broken asset, which is
      // exactly the outcome the spec forbids, so this one catch is deliberate.
      // ignore: avoid_catching_errors
    } on FlutterError catch (error) {
      return Left(ServerFailure('City catalog unavailable: ${error.message}'));
    } on FormatException catch (error) {
      return Left(ServerFailure('City catalog is corrupt: ${error.message}'));
    } on Exception catch (error) {
      return Left(ServerFailure('City catalog could not be read: $error'));
    }
  }

  Future<List<_IndexedCity>> _catalog() {
    final cached = _cache;
    if (cached != null) return Future<List<_IndexedCity>>.value(cached);
    // Shared so two keystrokes racing a cold catalog decode the asset once.
    return _pending ??= _readAsset();
  }

  Future<List<_IndexedCity>> _readAsset() async {
    try {
      final parsed = _parse(await _fetch());
      _cache = parsed;
      return parsed;
    } finally {
      // Cleared on both paths: on success the value cache takes over, and on
      // failure the next search must be free to retry rather than replay a
      // stored error forever.
      _pending = null;
    }
  }

  /// The asset's text, fetched up to [_readAttempts] times.
  ///
  /// Only the fetch is repeated. Parsing lives in [_readAsset] on purpose: a
  /// file that decoded into nonsense will decode into the same nonsense a
  /// second time, so retrying a `FormatException` would only spend
  /// [_retryBackoff] to reach the identical answer.
  Future<String> _fetch() async {
    for (var attempt = 1; ; attempt++) {
      try {
        // `cache: false`, and it is load-bearing. `rootBundle` is a
        // `CachingAssetBundle`, whose `loadString` memoizes the *future* under
        // the key and — unlike its own `loadStructuredData`, which evicts on
        // error precisely so a later attempt can try again — never drops a
        // failed one. On web the asset is an HTTP request, so one blip would
        // pin that failure for the life of the page: clearing `_pending` above
        // lets a later read back in, and the bundle would hand it the same
        // error without touching the network. That is what made the splash's
        // "Try again" and the sheet's retry inert, against what
        // docs/specs/locations.md promises in two places. This repository owns
        // the only cache the file needs (`_cache`); the bundle's second one
        // bought nothing but a retained copy of the raw JSON.
        return await _bundle.loadString(assetPath, cache: false);
        // Every shape is retried, because at this point none of them can be
        // told apart from a dropped request: the bundle reports a failed fetch
        // and a misdeclared asset with the same `FlutterError`. The attempt
        // count is what bounds it, not the type.
      } on Object {
        if (attempt >= _readAttempts) rethrow;
        await Future<void>.delayed(_retryBackoff);
      }
    }
  }

  List<_IndexedCity> _parse(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Catalog root is not an object.');
    }
    final entries = decoded['cities'];
    if (entries is! List<dynamic>) {
      throw const FormatException('Catalog has no "cities" array.');
    }
    final indexed = <_IndexedCity>[];
    for (final entry in entries) {
      final city = cityOrNull(entry);
      if (city != null) indexed.add(_IndexedCity.of(city));
    }
    return List<_IndexedCity>.unmodifiable(indexed);
  }

  /// The list the sheet shows before anything is typed.
  ///
  /// Curated rows only. A derived row carries a mechanically-derived name and
  /// a best-effort country, which is fine as a search hit and poor as a
  /// suggestion.
  List<CityEntity> _defaults(List<_IndexedCity> indexed, int limit) {
    final curated =
        indexed.where((entry) => entry.city.isCurated).toList(growable: false)
          ..sort((a, b) => _byProminenceThenName(a.city, b.city));
    return curated
        .take(limit)
        .map((entry) => entry.city)
        .toList(growable: false);
  }

  List<CityEntity> _ranked(
    List<_IndexedCity> indexed,
    String query,
    int limit,
  ) {
    final hits = <_RankedCity>[];
    for (final entry in indexed) {
      final rank = entry.rankFor(query);
      if (rank != null) hits.add(_RankedCity(rank: rank, city: entry.city));
    }
    hits.sort(_byRankThenProminence);
    return hits.take(limit).map((hit) => hit.city).toList(growable: false);
  }

  /// Folds the typed text the way the index was folded, and additionally reads
  /// `_` as a space so both `America/Sao_Paulo` and `America/Sao Paulo` find
  /// the city (docs/specs/locations.md rule 10).
  String _foldQuery(String query) =>
      normalizeForSearch(query.replaceAll('_', ' '));

  static int _byRankThenProminence(_RankedCity a, _RankedCity b) {
    final byRank = a.rank.index.compareTo(b.rank.index);
    if (byRank != 0) return byRank;
    return _byProminenceThenName(a.city, b.city);
  }

  /// Name breaks the remaining ties so results are stable across runs, which
  /// matters for the many derived rows that all sit at prominence 0.
  static int _byProminenceThenName(CityEntity a, CityEntity b) {
    final byProminence = b.prominence.compareTo(a.prominence);
    if (byProminence != 0) return byProminence;
    return a.name.compareTo(b.name);
  }
}

/// One catalog row with its search keys already folded.
class _IndexedCity {
  const _IndexedCity({
    required this.city,
    required this.nameKey,
    required this.zoneKey,
    required this.otherKeys,
  });

  factory _IndexedCity.of(CityEntity city) {
    final admin1 = city.admin1;
    return _IndexedCity(
      city: city,
      nameKey: normalizeForSearch(city.name),
      // `_` reads as a space so `sao paulo` also matches the id; the raw id
      // spelling still matches because `/` survives folding untouched.
      zoneKey: normalizeForSearch(city.zoneId.replaceAll('_', ' ')),
      otherKeys: <String>[
        ...city.aliases.map(normalizeForSearch),
        normalizeForSearch(city.countryName),
        if (admin1 != null) normalizeForSearch(admin1),
      ],
    );
  }

  final CityEntity city;
  final String nameKey;
  final String zoneKey;
  final List<String> otherKeys;

  /// The best rank this row reaches for the already-folded [query], or `null`
  /// when it does not match at all.
  _MatchRank? rankFor(String query) {
    if (nameKey == query || zoneKey == query) return _MatchRank.exactName;
    var best = _rankAgainst(
      nameKey,
      query,
      _MatchRank.namePrefix,
      _MatchRank.nameSubstring,
    );
    for (final key in otherKeys) {
      if (key == query) return _MatchRank.exactOther;
      best = _better(
        best,
        _rankAgainst(
          key,
          query,
          _MatchRank.otherPrefix,
          _MatchRank.otherSubstring,
        ),
      );
    }
    // A partial id (`america/arg`) is a power-user affordance, so it ranks
    // last instead of competing with a real name match. Gated on the slash
    // because without it every city sharing a zone would answer the name of
    // whichever city the id is spelled after: `sao paulo` would return Rio de
    // Janeiro too, which reads as a bug rather than as a feature.
    if (best == null && query.contains('/') && zoneKey.contains(query)) {
      return _MatchRank.otherSubstring;
    }
    return best;
  }

  static _MatchRank? _rankAgainst(
    String key,
    String query,
    _MatchRank prefix,
    _MatchRank substring,
  ) {
    if (key.startsWith(query)) return prefix;
    if (key.contains(query)) return substring;
    return null;
  }

  static _MatchRank? _better(_MatchRank? a, _MatchRank? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index <= b.index ? a : b;
  }
}

class _RankedCity {
  const _RankedCity({required this.rank, required this.city});

  final _MatchRank rank;
  final CityEntity city;
}

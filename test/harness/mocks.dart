/// Centralized mocks for the boundaries that exist in this milestone.
///
/// Mock at boundaries only (CLAUDE.md): repositories for cubits, datasources
/// and stores for repositories. Anything a test could build for real instead
/// (an entity, a value object, `WorkingHours`) belongs in a factory, never in
/// a mock.
///
/// Stubs need fallback values for non-primitive arguments; call
/// `registerCommonFallbacks()` from `test/harness/helpers.dart` in `setUpAll`.
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';
import 'package:uuid/uuid.dart';

/// The key/value boundary under `PreferencesRepository` and `BoardRepository`.
///
/// Mocked rather than faked with an in-memory map so a test can assert *how*
/// storage was used, e.g. that a failed write left the dirty flag set.
///
/// ```dart
/// final store = MockLocalStore();
/// when(() => store.readRaw(StorageKeys.preferences))
///     .thenAnswer((_) async => null);
/// ```
class MockLocalStore extends Mock implements LocalStore {}

/// The repository boundary for `PreferencesCubit` tests.
///
/// Its methods return `Future<Either<Failure, PreferencesEntity>>`, so stubs
/// must answer with `Right(aPreferences())` or a `Left(...)` failure; there is
/// no sensible zero value for mocktail to invent.
class MockPreferencesRepository extends Mock implements PreferencesRepository {}

/// The timezone boundary for anything that must not depend on real tzdata.
///
/// Prefer the real `TzTimeZoneEngine` plus `initTestTimeZones()` when the test
/// is about time behaviour: CLAUDE.md requires DST rules to be pinned against
/// real historical transitions, and a mock can only confirm the assumptions
/// the test already made. Use this mock when the engine is incidental, or to
/// force a shape real tzdata will not produce on demand.
class MockTimeZoneEngine extends Mock implements TimeZoneEngine {}

/// A [Clock] for tests that assert *whether* the time was read.
///
/// For tests that care about *what* time it is, use `FakeClock` instead: it
/// carries a real instant and can be advanced, which is what almost every
/// time-dependent test needs.
class MockClock extends Mock implements Clock {}

/// The session, for anything mounted through `pumpApp`.
///
/// `MockBloc` rather than a plain `Mock` so `whenListen` can seed both the
/// current state and the stream a `BlocBuilder` subscribes to; a bare mock
/// answers `state` and then hands the widget a null stream, which throws on
/// the first build.
///
/// It is read-only in almost every test: the pages that show a session read
/// it, and the one that starts one (`OnboardingPage`) is asserted on by the
/// event it added, never by a state it was handed.
class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

/// The board boundary for repository tests, and for `BoardCubit`'s own.
///
/// Mocked rather than backed by an in-memory board so a refused write is a
/// stubbed answer instead of a full disk: every rule in
/// docs/specs/locations.md about a rollback needs a `save` that says no.
class MockBoardRepository extends Mock implements BoardRepository {}

/// The board *cubit*, for the screens and helpers that only read it.
///
/// A `MockCubit` and not a plain `Mock`, so `whenListen` can seed both the
/// current state and the stream a `BlocBuilder` subscribes to; a bare mock
/// answers `state` and then hands the widget a null stream, which throws on
/// the first build.
///
/// This is the right double for a *page* or a presentation helper, whose
/// contract is "which mutation did it ask for": the real cubit would answer
/// that question through a repository two layers away.
///
/// ```dart
/// final board = MockBoardCubit();
/// whenListen(board, const Stream<BoardState>.empty(), initialState: loaded);
/// when(() => board.reorder(any(), any())).thenAnswer((_) async => null);
/// ```
class MockBoardCubit extends MockCubit<BoardState> implements BoardCubit {}

/// The city catalog boundary.
///
/// Mocked so a search result set is three rows a test wrote rather than
/// whatever the shipped 500-row asset happens to contain — and so a catalog
/// that fails to load is a stub instead of a deleted asset.
class MockCityCatalogRepository extends Mock implements CityCatalogRepository {}

/// The Firestore boundary, for everything above the data layer.
///
/// The concrete `FirestoreRemoteSettingsDataSource` is tested against a real
/// in-memory Firestore instead (see
/// `test/core/sync/remote_settings_datasource_test.dart`); this double is for
/// the callers, where "the document is absent", "the document is malformed"
/// and "the radio is off" are three stubs rather than three fixtures.
class MockRemoteSettingsDataSource extends Mock
    implements RemoteSettingsDataSource {}

/// The id generator, so a new board row's id is an assertion rather than a
/// surprise.
///
/// `Uuid` is injected rather than called statically for exactly this reason
/// (CLAUDE.md, Lifecycle): a test hands `BoardCubit` a counter and asserts on
/// the ids it wrote.
///
/// ```dart
/// var issued = 0;
/// when(() => uuid.v4()).thenAnswer((_) => 'new-row-${issued++}');
/// ```
class MockUuid extends Mock implements Uuid {}

/// A [TickerService] that records the lifecycle calls made against it.
///
/// A real subclass and **not** a mocktail mock, deliberately: `TickerService`
/// is a concrete class whose `stream` a subscriber listens to on the first
/// build, and a mocked getter would hand it `null` and throw before any
/// assertion could run. Extending keeps the real stream, the real rate switch
/// and the real "resume emits immediately" behaviour, and adds only the
/// counters.
///
/// Counters rather than a flag, because the assertions that matter are about
/// *how often*: a lifecycle hook that paused twice for one trip to the
/// background is a hook that will resume once and leave the app at a
/// standstill.
///
/// The constructor starts a `Timer`, which `flutter_test` fails a test for if
/// it is still pending when the body returns, so a widget test either pauses
/// it immediately (as `pumpApp` does) or disposes it in a tear-down.
///
/// ```dart
/// final ticker = RecordingTickerService(clock: FakeClock(utcDate(2024)))
///   ..pause();
/// addTearDown(ticker.dispose);
/// expect(ticker.resumes, 1);
/// ```
class RecordingTickerService extends TickerService {
  RecordingTickerService({required super.clock});

  int pauses = 0;
  int resumes = 0;

  /// How many subscriptions to [stream] are alive right now.
  ///
  /// The number is the whole point of one ticker for the whole app: every
  /// clock on screen hangs off this single broadcast stream, so the count must
  /// equal the number of rendered clocks and must drop back to zero when they
  /// leave. It is also the only way to prove a `close()` released its
  /// subscription — a leaked one keeps calling `emit` on a closed cubit, which
  /// surfaces as an unhandled error in a later, unrelated test.
  int liveSubscriptions = 0;

  /// Built once and cached, so its identity is stable across rebuilds: a fresh
  /// stream object per build would make `StreamBuilder` resubscribe and the
  /// counter would then be measuring rebuilds instead of subscriptions.
  late final Stream<DateTime> _observed = Stream<DateTime>.multi(
    _onListen,
    isBroadcast: true,
  );

  @override
  Stream<DateTime> get stream => _observed;

  void _onListen(MultiStreamController<DateTime> controller) {
    liveSubscriptions++;
    final source = super.stream.listen(controller.add);
    controller.onCancel = () {
      liveSubscriptions--;
      return source.cancel();
    };
  }

  /// Every value handed to [setNeedsSeconds], in call order, **including**
  /// the ones the real setter no-ops on. The wiring under test is the call
  /// itself (docs/specs/preferences.md rule 10); whether the ticker then
  /// bothers to restart its timer is `ticker_service_test.dart`'s question.
  final List<bool> secondsRequests = <bool>[];

  @override
  void pause() {
    pauses++;
    super.pause();
  }

  @override
  void resume() {
    resumes++;
    super.resume();
  }

  @override
  void setNeedsSeconds({required bool value}) {
    secondsRequests.add(value);
    super.setNeedsSeconds(value: value);
  }
}

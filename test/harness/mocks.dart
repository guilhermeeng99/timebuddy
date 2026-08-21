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

import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';

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
class MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/core/platform/app_platform.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_coordinator.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:timebuddy/features/auth/domain/repositories/auth_repository.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/locations/data/datasources/board_local_datasource.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/preferences/data/datasources/preferences_local_datasource.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';
import 'package:timebuddy/features/time_converter/domain/usecases/convert_time_usecase.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/world_clock/domain/usecases/build_world_clock_usecase.dart';
import 'package:uuid/uuid.dart';

/// Asks the container for [T] twice and reports whether it answered with the
/// same object.
///
/// This is how "lazy **singleton**, never a factory" is tested at all: `GetIt`
/// exposes no way to ask which kind a registration is, and the difference only
/// shows up as two objects where the app assumes one.
bool _isSingleton<T extends Object>() => identical(sl<T>(), sl<T>());

void main() {
  // `SharedPreferences.getInstance()` is the one await in the graph and it
  // goes through a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await sl.reset();
    await configureDependencies();
  });

  tearDown(() async {
    // `TickerService` starts a `Timer` the moment it is resolved, and the
    // locator is process-wide, so a container left standing would keep a live
    // timer running through the rest of the suite.
    if (sl.isRegistered<TickerService>()) await sl<TickerService>().dispose();
    await sl.reset();
  });

  group('every singleton CLAUDE.md documents is registered', () {
    // Asserted through `isRegistered` rather than by resolving, deliberately:
    // resolution is what runs the factory, and the Firebase handles below
    // reach for `.instance` on an SDK a unit test has not initialised. The
    // registration is the contract; `main` awaits `Firebase.initializeApp`
    // before anything resolves one.
    test('the core services', () {
      expect(sl.isRegistered<Clock>(), isTrue);
      expect(sl.isRegistered<LocalStore>(), isTrue);
      expect(sl.isRegistered<GuestSession>(), isTrue);
      expect(sl.isRegistered<TimeZoneEngine>(), isTrue);
      expect(sl.isRegistered<TickerService>(), isTrue);
      expect(sl.isRegistered<Uuid>(), isTrue);
      expect(sl.isRegistered<AppPlatform>(), isTrue);
    });

    test('the two documents and their sync', () {
      expect(sl.isRegistered<PreferencesLocalDataSource>(), isTrue);
      expect(sl.isRegistered<PreferencesRepository>(), isTrue);
      expect(sl.isRegistered<PreferencesCubit>(), isTrue);
      expect(sl.isRegistered<BoardLocalDataSource>(), isTrue);
      expect(sl.isRegistered<BoardRepository>(), isTrue);
      expect(sl.isRegistered<SyncCoordinator>(), isTrue);
      expect(sl.isRegistered<RemoteSettingsDataSource>(), isTrue);
      expect(sl.isRegistered<SyncService>(), isTrue);
    });

    test('the catalog and the three use cases', () {
      expect(sl.isRegistered<CityCatalogRepository>(), isTrue);
      expect(sl.isRegistered<BuildGridUseCase>(), isTrue);
      expect(sl.isRegistered<BuildWorldClockUseCase>(), isTrue);
      expect(sl.isRegistered<ConvertTimeUseCase>(), isTrue);
    });

    test('the session and the startup gate', () {
      expect(sl.isRegistered<AuthRemoteDataSource>(), isTrue);
      expect(sl.isRegistered<AuthRepository>(), isTrue);
      expect(sl.isRegistered<AuthBloc>(), isTrue);
      expect(sl.isRegistered<StartupCubit>(), isTrue);
    });
  });

  group('BoardCubit is deliberately absent', () {
    test('the container does not know it', () {
      // `AppShell` creates it through a `BlocProvider`, so its lifetime is the
      // shell's (CLAUDE.md, Lifecycle). Registering it here would make a stray
      // `sl<BoardCubit>()` hand out a *second* board — two owners of the list
      // of places, and a mutation applied to whichever one the caller happened
      // to hold.
      expect(sl.isRegistered<BoardCubit>(), isFalse);
    });

    test('asking for one fails loudly rather than building one', () {
      // The failure has to be an exception and not a quietly constructed
      // instance: a locator that answered would move the bug from the line
      // that asked to the screen that later shows a stale board.
      BoardCubit askTheLocatorForOne() => sl<BoardCubit>();

      expect(askTheLocatorForOne, throwsStateError);
    });
  });

  group('nothing in the graph is a factory', () {
    // Only the registrations that can be resolved without a live Firebase app
    // are checked here. That is not a gap in the rule so much as the shape of
    // it: everything downstream of a Firebase handle is constructed from these
    // same singletons, so a second copy could only come from one of them.
    test('the core services hand back one instance each', () {
      expect(_isSingleton<Clock>(), isTrue);
      expect(_isSingleton<LocalStore>(), isTrue);
      expect(_isSingleton<TimeZoneEngine>(), isTrue);
      expect(_isSingleton<Uuid>(), isTrue);
      expect(_isSingleton<AppPlatform>(), isTrue);
      expect(_isSingleton<PreferencesLocalDataSource>(), isTrue);
      expect(_isSingleton<BoardLocalDataSource>(), isTrue);
    });

    test('one ticker for the whole app', () {
      // CLAUDE.md, Performance. A factory here would give the app widget's
      // lifecycle hook a different heartbeat from the one every clock tile
      // subscribes to, so backgrounding would pause a ticker nobody reads.
      expect(_isSingleton<TickerService>(), isTrue);
    });

    test('one answer to "may this visitor use the app without an account"', () {
      // A second `GuestSession` would be a second answer, and the router's
      // redirect reads it synchronously on the first navigation
      // (docs/specs/guest_mode.md).
      expect(_isSingleton<GuestSession>(), isTrue);
    });

    test('the parsed catalog is the cache', () {
      // A factory would re-read and re-parse a 500-row asset on every
      // keystroke in the city picker.
      expect(_isSingleton<CityCatalogRepository>(), isTrue);
    });

    test('the pure use cases are shared rather than rebuilt', () {
      expect(_isSingleton<BuildGridUseCase>(), isTrue);
      expect(_isSingleton<BuildWorldClockUseCase>(), isTrue);
      expect(_isSingleton<ConvertTimeUseCase>(), isTrue);
    });
  });

  group('the production wiring behind each interface', () {
    test('is the real implementation and not a stand-in', () {
      // Named types, because these are the four places where a test double or
      // a placeholder could be left in the graph and nothing else would fail.
      expect(sl<Clock>(), isA<SystemClock>());
      expect(sl<LocalStore>(), isA<SharedPreferencesLocalStore>());
      expect(sl<TimeZoneEngine>(), isA<TzTimeZoneEngine>());
      expect(sl<AppPlatform>(), isA<FlutterAppPlatform>());
    });
  });

  group('the guest marker is restored before the container returns', () {
    test('a stored marker is readable synchronously afterwards', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        StorageKeys.guest: 'true',
      });
      await sl.reset();
      await configureDependencies();

      // `AppRouter._redirect` reads `isGuest` synchronously on the very first
      // navigation, which happens before the first frame. If the restore were
      // fired and not awaited, a returning guest would be bounced to
      // onboarding on every launch (docs/specs/guest_mode.md).
      expect(sl<GuestSession>().isGuest, isTrue);
    });

    test('an empty device leaves the visitor undecided', () async {
      expect(sl<GuestSession>().isGuest, isFalse);
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timebuddy/core/platform/app_platform.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/sync/remote_settings_datasource.dart';
import 'package:timebuddy/core/sync/sync_coordinator.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/core/sync/sync_service_impl.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:timebuddy/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:timebuddy/features/auth/domain/repositories/auth_repository.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/locations/data/datasources/board_local_datasource.dart';
import 'package:timebuddy/features/locations/data/repositories/board_repository_impl.dart';
import 'package:timebuddy/features/locations/data/repositories/city_catalog_repository_impl.dart';
import 'package:timebuddy/features/locations/domain/repositories/board_repository.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/preferences/data/datasources/preferences_local_datasource.dart';
import 'package:timebuddy/features/preferences/data/repositories/preferences_repository_impl.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';
import 'package:timebuddy/features/time_converter/domain/usecases/convert_time_usecase.dart';
import 'package:timebuddy/features/time_grid/domain/usecases/build_grid_usecase.dart';
import 'package:timebuddy/features/world_clock/domain/usecases/build_world_clock_usecase.dart';
import 'package:uuid/uuid.dart';

/// The app's service locator.
///
/// Widgets resolve session-independent singletons through it (`sl<Clock>()`),
/// while cubits and repositories take their collaborators as constructor
/// arguments so a test can hand them fakes without touching this container.
///
/// ```dart
/// final nowUtc = sl<Clock>().nowUtc();
/// ```
final GetIt sl = GetIt.instance;

/// Registers every dependency the app needs before its first frame.
///
/// Called once from `main`, before `runApp`. Everything here is
/// `registerLazySingleton`: these are the session-independent services listed
/// in CLAUDE.md (State Management, Lifecycle). Session- and page-scoped cubits
/// are created by their route or their page, not here — `BoardCubit` in
/// particular is built by `AppShell`, so its lifetime is the shell's and a
/// stray `sl<BoardCubit>()` cannot hand a second one out.
///
/// The registration order is irrelevant — the factories run on first
/// resolution — but the dependency direction is not: nothing in `core` may
/// depend on a feature.
///
/// **`Firebase.initializeApp` must have completed first.** `main` awaits it
/// before calling this, and every Firebase handle below is registered lazily,
/// so nothing here touches `.instance` while the SDK is still starting.
Future<void> configureDependencies() async {
  // The one await in the graph. `SharedPreferences.getInstance()` has to
  // resolve before a LocalStore can wrap it, and doing it here keeps the
  // asynchrony in `main` instead of forcing every caller of `sl<LocalStore>()`
  // to await `sl.isReady()` for the lifetime of the app.
  final sharedPreferences = await SharedPreferences.getInstance();

  sl
    ..registerLazySingleton<Clock>(SystemClock.new)
    ..registerLazySingleton<LocalStore>(
      () => SharedPreferencesLocalStore(sharedPreferences),
    )
    // Singleton and never a factory: it is the device's answer to "may this
    // visitor use the app without an account", and a second copy would be a
    // second answer (docs/specs/guest_mode.md).
    ..registerLazySingleton<GuestSession>(
      () => GuestSession(localStore: sl<LocalStore>()),
    )
    ..registerLazySingleton<TimeZoneEngine>(TzTimeZoneEngine.new)
    // One ticker for the whole app (CLAUDE.md, Performance). Registered as a
    // singleton so that the app widget's lifecycle hook and every clock widget
    // are talking about the same heartbeat.
    ..registerLazySingleton<TickerService>(
      () => TickerService(clock: sl<Clock>()),
    )
    // Stateless generator, but a singleton anyway: `Uuid` is injected rather
    // than called statically so a test can hand `BoardCubit` a counter and
    // assert on the ids it wrote.
    ..registerLazySingleton<Uuid>(Uuid.new)
    ..registerLazySingleton<PreferencesLocalDataSource>(
      () => PreferencesLocalDataSourceImpl(sl<LocalStore>()),
    )
    // Lazy SINGLETON, never a factory: the signed-in account is this object's
    // state, and a factory would hand every repository its own permanently
    // signed-out copy, so ordinary edits would stop pushing and nothing would
    // fail loudly enough to notice.
    ..registerLazySingleton<SyncCoordinator>(
      () => SyncCoordinator(
        remoteDataSource: sl<RemoteSettingsDataSource>(),
        localStore: sl<LocalStore>(),
      ),
    )
    ..registerLazySingleton<PreferencesRepository>(
      () => PreferencesRepositoryImpl(
        localDataSource: sl<PreferencesLocalDataSource>(),
        clock: sl<Clock>(),
        syncCoordinator: sl<SyncCoordinator>(),
      ),
    )
    // Singleton on purpose: a preference change is immediate and global
    // (docs/specs/preferences.md rule 6), and the app widget reads theme mode
    // and both palettes straight out of this cubit's state.
    ..registerLazySingleton<PreferencesCubit>(
      () => PreferencesCubit(
        repository: sl<PreferencesRepository>(),
        clock: sl<Clock>(),
      ),
    )
    ..registerLazySingleton<BoardLocalDataSource>(
      () => BoardLocalDataSourceImpl(sl<LocalStore>()),
    )
    ..registerLazySingleton<BoardRepository>(
      () => BoardRepositoryImpl(
        localDataSource: sl<BoardLocalDataSource>(),
        clock: sl<Clock>(),
        syncCoordinator: sl<SyncCoordinator>(),
      ),
    )
    // Singleton because the parsed catalog is the cache: roughly 400 entries
    // read from an asset once and kept in memory (CLAUDE.md, Performance). A
    // factory would re-parse the JSON on every keystroke in the city picker.
    ..registerLazySingleton<CityCatalogRepository>(
      CityCatalogRepositoryImpl.new,
    )
    // Pure and stateless, so sharing one instance costs nothing and saves the
    // grid cubit from constructing a use case per rebuild.
    ..registerLazySingleton<BuildGridUseCase>(
      () => BuildGridUseCase(engine: sl<TimeZoneEngine>()),
    )
    // M4's five use cases, on the same terms as `BuildGridUseCase` above:
    // every one is a `const`-constructible function object holding no state
    // between calls, so one instance is the cheapest correct lifetime and a
    // page rebuild never allocates another.
    //
    // Registered here rather than constructed by their cubits so the cubits
    // stay testable with a fake engine: `WorldClockCubit` takes the use case,
    // not a `TimeZoneEngine` it would have to build one from.
    ..registerLazySingleton<BuildWorldClockUseCase>(
      () => BuildWorldClockUseCase(engine: sl<TimeZoneEngine>()),
    )
    ..registerLazySingleton<ConvertTimeUseCase>(
      () => ConvertTimeUseCase(engine: sl<TimeZoneEngine>()),
    )
    // The three Firebase handles, registered rather than read statically so a
    // data source takes them as arguments and a test can hand it fakes. They
    // resolve lazily, which is what lets `main` finish `Firebase.initializeApp`
    // before anything touches `.instance`.
    ..registerLazySingleton<FirebaseAuth>(() => FirebaseAuth.instance)
    ..registerLazySingleton<FirebaseFirestore>(() => FirebaseFirestore.instance)
    // `GoogleSignIn` 7.x has a private constructor and one instance per
    // process; `AuthRemoteDataSourceImpl` still takes it as a parameter,
    // because the Android sign-in path is otherwise untestable.
    ..registerLazySingleton<GoogleSignIn>(() => GoogleSignIn.instance)
    // Asked one question — "is this a browser?" — by the two auth paths that
    // fork on it (docs/specs/auth.md rules 2 and 6). A `kIsWeb` at those call
    // sites would make the web half unreachable from any test.
    ..registerLazySingleton<AppPlatform>(FlutterAppPlatform.new)
    ..registerLazySingleton<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(
        firebaseAuth: sl<FirebaseAuth>(),
        firestore: sl<FirebaseFirestore>(),
        googleSignIn: sl<GoogleSignIn>(),
        platform: sl<AppPlatform>(),
        clock: sl<Clock>(),
      ),
    )
    ..registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(
        remoteDataSource: sl<AuthRemoteDataSource>(),
        localStore: sl<LocalStore>(),
        guestSession: sl<GuestSession>(),
      ),
    )
    // Singleton, and the app's only answer to "who is signed in": the router
    // redirect, the startup cubit and the profile page all read this one
    // instance, and a second would be a second answer (docs/specs/auth.md).
    // It subscribes to `authStateChanges` in its constructor, so resolving it
    // is what starts listening.
    ..registerLazySingleton<AuthBloc>(
      () => AuthBloc(
        repository: sl<AuthRepository>(),
        syncCoordinator: sl<SyncCoordinator>(),
      ),
    )
    ..registerLazySingleton<RemoteSettingsDataSource>(
      () => FirestoreRemoteSettingsDataSource(sl<FirebaseFirestore>()),
    )
    // Singleton because its status stream is: the passive indicator on the
    // profile page replays the last status it published (docs/specs/sync.md
    // rule 4), which a per-call instance could not remember.
    //
    // The device locale is read at resolution rather than captured at startup
    // because it is only ever consulted to seed a *missing* preferences
    // document (preferences.md rule 2), and the freshest reading is the
    // better guess.
    ..registerLazySingleton<SyncService>(
      () => SyncServiceImpl(
        remoteDataSource: sl<RemoteSettingsDataSource>(),
        boardRepository: sl<BoardRepository>(),
        preferencesRepository: sl<PreferencesRepository>(),
        localStore: sl<LocalStore>(),
        engine: sl<TimeZoneEngine>(),
        deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
      ),
    )
    // Singleton and provided app-wide by `TimeBuddyApp`, because the router's
    // redirect reads its state to decide whether anything but the splash may
    // render (docs/specs/startup.md, Lifecycle & DI).
    //
    // `PreferencesCubit` is passed as the sink for the reconciled preferences
    // document: it is loaded before the router exists, so without this its
    // in-memory copy would outlive the document sync just replaced. The board
    // needs no equivalent — `AppShell` builds `BoardCubit` only after the
    // router leaves `/startup`, so its load reads the reconciled document.
    ..registerLazySingleton<StartupCubit>(
      () => StartupCubit(
        authBloc: sl<AuthBloc>(),
        engine: sl<TimeZoneEngine>(),
        catalog: sl<CityCatalogRepository>(),
        syncService: sl<SyncService>(),
        guestSession: sl<GuestSession>(),
        preferencesCubit: sl<PreferencesCubit>(),
      ),
    );

  // The second await in the graph, and it has to be one. `AppRouter._redirect`
  // reads `GuestSession.isGuest` synchronously on the very first navigation,
  // which happens before the first frame; a guest whose marker had not landed
  // yet would be bounced to onboarding on every launch
  // (docs/specs/guest_mode.md, Repository Contract).
  await sl<GuestSession>().restore();
}

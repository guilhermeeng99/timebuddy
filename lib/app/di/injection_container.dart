import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/ticker_service.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/features/preferences/data/datasources/preferences_local_datasource.dart';
import 'package:timebuddy/features/preferences/data/repositories/preferences_repository_impl.dart';
import 'package:timebuddy/features/preferences/domain/repositories/preferences_repository.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';

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
/// are created by their route, not here.
///
/// The registration order is irrelevant — the factories run on first
/// resolution — but the dependency direction is not: nothing in `core` may
/// depend on a feature.
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
    ..registerLazySingleton<TimeZoneEngine>(TzTimeZoneEngine.new)
    // One ticker for the whole app (CLAUDE.md, Performance). Registered as a
    // singleton so that the app widget's lifecycle hook and every clock widget
    // are talking about the same heartbeat.
    ..registerLazySingleton<TickerService>(
      () => TickerService(clock: sl<Clock>()),
    )
    ..registerLazySingleton<PreferencesLocalDataSource>(
      () => PreferencesLocalDataSourceImpl(sl<LocalStore>()),
    )
    ..registerLazySingleton<PreferencesRepository>(
      () => PreferencesRepositoryImpl(
        localDataSource: sl<PreferencesLocalDataSource>(),
        clock: sl<Clock>(),
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
    );
}

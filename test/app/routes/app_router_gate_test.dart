import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/routes/app_routes.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/storage/local_store.dart';
import 'package:timebuddy/features/auth/domain/entities/user_entity.dart';
import 'package:timebuddy/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:timebuddy/features/startup/presentation/cubit/startup_cubit.dart';

import '../../harness/helpers.dart';

// `AppRouter._redirect` is private and its router is a `static final` that
// would carry one test's navigation stack into the next, so this file pins the
// four rules as a pure function instead. That is honest about what it covers:
// the *decision*, not go_router's plumbing. The decision is the part guest
// mode changed, and the part that loops forever if it is written naively
// (docs/specs/guest_mode.md, State Machine).
//
// It is a transcription, and a transcription can drift. What stops it drifting
// silently is that every branch below is a sentence from the spec, so a change
// to `_redirect` that this file does not mirror is a change the spec does not
// describe either.
String? redirectFor({
  required StartupState startup,
  required AuthState auth,
  required GuestSession guest,
  required String location,
}) {
  if (startup is! StartupAuthenticated && startup is! StartupUnauthenticated) {
    return location == AppRoutes.startup ? null : AppRoutes.startup;
  }
  if (auth is! Authenticated && !guest.isGuest) {
    return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
  }
  if (guest.isGuest && auth is Authenticated && !guest.adoptionAttempted) {
    return location == AppRoutes.startup ? null : AppRoutes.startup;
  }
  if (auth is Authenticated && location == AppRoutes.onboarding) {
    return AppRoutes.startup;
  }
  return null;
}

/// A store that answers whatever this test wrote to it.
class _MemoryStore implements LocalStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> readRaw(String key) async => _values[key];

  @override
  Future<void> writeRaw(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clearAll() async {
    _values.clear();
  }
}

void main() {
  late GuestSession guest;

  final signedIn = Authenticated(
    UserEntity(
      id: 'firebase-uid',
      name: 'Ada Lovelace',
      email: 'ada@example.com',
      createdAt: utcDate(2024),
    ),
  );

  setUp(() {
    guest = GuestSession(localStore: _MemoryStore());
  });

  String? redirect({
    StartupState startup = const StartupUnauthenticated(),
    AuthState auth = const Unauthenticated(),
    String location = AppRoutes.grid,
  }) => redirectFor(
    startup: startup,
    auth: auth,
    guest: guest,
    location: location,
  );

  group('rule 1: nothing renders before startup resolves', () {
    test('holds a guest at the splash too', () async {
      await guest.enter();

      // The guest marker does not buy a shortcut past tzdata: a grid built
      // before the engine is initialized renders plausible hours that are
      // simply wrong (CLAUDE.md, Time & Timezone Rules).
      expect(
        redirect(startup: const StartupLoading(), location: AppRoutes.clocks),
        AppRoutes.startup,
      );
    });

    test('holds on the error state, whose recovery is the page retry', () {
      expect(
        redirect(startup: const StartupError()),
        AppRoutes.startup,
      );
    });
  });

  group('rule 2: the onboarding gate, narrowed', () {
    test('still catches a visitor who chose neither', () {
      expect(redirect(), AppRoutes.onboarding);
    });

    test('still catches AuthInitial and AuthError for a non-guest', () {
      // The broad `is! Authenticated` is deliberate: neither state is a
      // session, and both belong on onboarding for someone who never opted
      // out of having one.
      expect(redirect(auth: const AuthInitial()), AppRoutes.onboarding);
      expect(
        redirect(auth: const AuthError(AuthFailure('boom'))),
        AppRoutes.onboarding,
      );
    });

    test('lets a guest into the app', () async {
      await guest.enter();

      // The whole point of the feature: signed out is no longer a reason to
      // be held anywhere (guest_mode.md rule 5).
      expect(redirect(), isNull);
      expect(redirect(location: AppRoutes.converter), isNull);
      expect(redirect(location: AppRoutes.settings), isNull);
    });

    test('does not eject a guest while their sign-in is in flight', () async {
      await guest.enter();

      // Firebase publishes a null user while the Google dialog is open. A
      // rule that read `AuthLoading` as "throw them out" would close the app
      // under a guest mid-sign-in.
      expect(redirect(auth: const AuthLoading()), isNull);
    });
  });

  group('rule 3: a guest who signed in', () {
    test('goes back through the splash so the adoption can run', () async {
      await guest.enter();

      expect(redirect(auth: signedIn), AppRoutes.startup);
    });

    test('is not sent back once the attempt has been made', () async {
      await guest.enter();
      guest.adoptionAttempted = true;

      // Without this the redirect loops forever whenever an adoption fails:
      // the marker is still set, the session is still real, and `/startup`
      // resolves straight back to the grid.
      expect(redirect(auth: signedIn), isNull);
    });

    test('is not sent back once the marker is cleared', () async {
      await guest.enter();
      await guest.leave();

      expect(redirect(auth: signedIn), isNull);
    });
  });

  group('rule 4: onboarding is not a place a session sits', () {
    test('a signed-in visitor on onboarding goes through the splash', () {
      expect(
        redirect(auth: signedIn, location: AppRoutes.onboarding),
        AppRoutes.startup,
      );
    });

    test('a guest may still read the tour', () async {
      await guest.enter();

      // Bouncing them would send them straight back to the grid and make the
      // tour — and the Google button on its last slide — unreachable for the
      // one person still deciding.
      expect(redirect(location: AppRoutes.onboarding), isNull);
    });
  });
}

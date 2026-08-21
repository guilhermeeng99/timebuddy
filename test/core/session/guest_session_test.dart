import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/session/guest_session.dart';
import 'package:timebuddy/core/storage/local_store.dart';

import '../../harness/mocks.dart';

void main() {
  late MockLocalStore store;
  late GuestSession session;

  setUp(() {
    store = MockLocalStore();
    session = GuestSession(localStore: store);
    when(() => store.readRaw(any())).thenAnswer((_) async => null);
    when(() => store.writeRaw(any(), any())).thenAnswer((_) async {});
    when(() => store.remove(any())).thenAnswer((_) async {});
  });

  test('starts as not a guest, before anything is read', () {
    // `AppRouter._redirect` reads this synchronously on the first navigation.
    // Defaulting to true would open the app to someone who never chose to skip
    // the account.
    expect(session.isGuest, isFalse);
    expect(session.adoptionAttempted, isFalse);
  });

  group('restore', () {
    test('reads the marker from the device', () async {
      when(
        () => store.readRaw(StorageKeys.guest),
      ).thenAnswer((_) async => 'true');

      await session.restore();

      expect(session.isGuest, isTrue);
    });

    test('an absent key means no guest session', () async {
      await session.restore();

      expect(session.isGuest, isFalse);
    });

    test('a refused read is treated as not a guest', () async {
      // A device that cannot read cannot be trusted to have stored consent,
      // and onboarding is a recoverable place to be wrong
      // (docs/specs/guest_mode.md, Repository Contract).
      when(() => store.readRaw(StorageKeys.guest)).thenThrow(
        const StorageException(),
      );

      await session.restore();

      expect(session.isGuest, isFalse);
    });

    test('does not notify when nothing changed', () async {
      var notifications = 0;
      session.addListener(() => notifications++);

      await session.restore();

      // The router rebuilds its redirect on every notification, so a restore
      // that found what it already believed must be silent.
      expect(notifications, 0);
    });
  });

  group('enter', () {
    test('writes the marker and notifies', () async {
      var notifications = 0;
      session.addListener(() => notifications++);

      await session.enter();

      expect(session.isGuest, isTrue);
      expect(notifications, 1);
      verify(() => store.writeRaw(StorageKeys.guest, any())).called(1);
    });

    test('is idempotent', () async {
      await session.enter();
      var notifications = 0;
      session.addListener(() => notifications++);

      await session.enter();

      expect(notifications, 0);
      verify(() => store.writeRaw(StorageKeys.guest, any())).called(1);
    });

    test('still enters when the device refuses the write', () async {
      // A browser in private mode gets to use the app; it just meets
      // onboarding again next launch. Refusing to open would be a worse answer.
      when(
        () => store.writeRaw(StorageKeys.guest, any()),
      ).thenThrow(const StorageException());

      await session.enter();

      expect(session.isGuest, isTrue);
    });
  });

  group('leave', () {
    test('removes the marker and notifies', () async {
      await session.enter();
      var notifications = 0;
      session.addListener(() => notifications++);

      await session.leave();

      expect(session.isGuest, isFalse);
      expect(notifications, 1);
      verify(() => store.remove(StorageKeys.guest)).called(1);
    });

    test('does nothing when there was no guest session', () async {
      await session.leave();

      verifyNever(() => store.remove(StorageKeys.guest));
    });
  });

  test('adoptionAttempted does not survive a restore', () async {
    // It is deliberately in-memory (guest_mode.md rule 8): losing it is what
    // makes the next launch retry an adoption that failed, while keeping it
    // within one process is what stops the router looping on one that is
    // still in flight.
    session.adoptionAttempted = true;

    await session.restore();

    expect(GuestSession(localStore: store).adoptionAttempted, isFalse);
  });
}

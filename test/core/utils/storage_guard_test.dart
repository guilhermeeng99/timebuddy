import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/core/errors/exceptions.dart';
import 'package:timebuddy/core/errors/failures.dart';
import 'package:timebuddy/core/utils/storage_guard.dart';

void main() {
  group('guardStorage', () {
    test('wraps a completed body in a Right', () async {
      final result = await guardStorage(() async => 'board');

      expect(result, const Right<Failure, String>('board'));
    });

    test('translates a CacheException into a StorageFailure', () async {
      // The unreadable-document case: the data source reports it, the
      // repository turns it into the one failure the UI knows how to render.
      final result = await guardStorage<String>(
        () async => throw const CacheException('The stored board is junk.'),
      );

      expect(
        result,
        const Left<Failure, String>(
          StorageFailure('The stored board is junk.'),
        ),
      );
    });

    test('translates a StorageException into a StorageFailure', () async {
      // The refused-write case. Different cause, same recovery on screen,
      // which is why both collapse onto one failure type.
      final result = await guardStorage<String>(
        () async => throw const StorageException('Local storage is full.'),
      );

      expect(
        result,
        const Left<Failure, String>(StorageFailure('Local storage is full.')),
      );
    });

    test('carries the thrown message through for the logs', () async {
      // `Failure.message` is developer-facing (failures.dart), so losing it
      // here would leave a bug report saying only "local storage".
      final result = await guardStorage<int>(
        () async => throw const CacheException('key "board.v1" was garbage'),
      );

      expect(
        result.fold((failure) => failure.message, (value) => 'no failure'),
        'key "board.v1" was garbage',
      );
    });

    test('lets anything else through', () async {
      // A bug is not a device condition. Swallowing one here would hide it
      // behind a snackbar about local storage.
      await expectLater(
        guardStorage<String>(() async => throw StateError('bug')),
        throwsStateError,
      );
    });

    test('catches a throw from anywhere inside the body', () async {
      // The guard wraps the whole sequence, not one call: a seed that writes
      // after a successful read is covered by the same ladder.
      var reads = 0;
      final result = await guardStorage<String>(() async {
        reads++;
        throw const StorageException('the seed write was refused');
      });

      expect(reads, 1);
      expect(result.isLeft(), isTrue);
    });

    test('is transparent to a body returning null', () async {
      // `read()` answers null for a document that was never written, and that
      // is a Right, not a failure: nothing went wrong.
      final result = await guardStorage<String?>(() async => null);

      expect(result, const Right<Failure, String?>(null));
    });
  });
}

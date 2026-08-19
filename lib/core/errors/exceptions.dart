/// Data-source level errors.
///
/// These are thrown by data sources and caught by the repository that owns
/// them, which translates each into the matching `Failure`. Nothing above the
/// repository layer catches them: a cubit that has to `try` around a
/// repository call means the repository leaked its transport.
library;

/// A remote call failed: transport error, timeout, or an error response.
class ServerException implements Exception {
  const ServerException([this.message = 'The server could not be reached.']);

  final String message;

  @override
  String toString() => 'ServerException: $message';
}

/// Sign-in, sign-out or token refresh failed, or the session expired.
class AuthException implements Exception {
  const AuthException([this.message = 'Authentication failed.']);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// Writing to the on-device store failed.
class StorageException implements Exception {
  const StorageException([this.message = 'Local storage is unavailable.']);

  final String message;

  @override
  String toString() => 'StorageException: $message';
}

/// A cached document is missing, or is present but unreadable.
///
/// Distinct from [StorageException] because the recovery differs: a miss is
/// routine and falls through to the remote read, while a write failure is a
/// device problem the user may need to hear about.
class CacheException implements Exception {
  const CacheException([this.message = 'No usable cached value.']);

  final String message;

  @override
  String toString() => 'CacheException: $message';
}

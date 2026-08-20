import 'package:flutter/foundation.dart';

/// Which host the app is running on, asked as a question instead of read as a
/// compile-time constant.
///
/// `kIsWeb` at a call site makes the branch it guards untestable: a test binary
/// is never a browser, so the web half of every platform-specific decision is
/// dead code no test can reach. Sign-in and sign-out both fork on it
/// (docs/specs/auth.md rules 2 and 6) and auth.md's Testing section requires
/// *both* halves to be exercised by injecting the flag, so the question goes
/// to a collaborator that a test can answer for.
///
/// ```dart
/// // production wiring
/// AuthRemoteDataSourceImpl(platform: const FlutterAppPlatform(), ...);
///
/// // a test that wants the web branch
/// class _WebPlatform extends AppPlatform {
///   const _WebPlatform();
///   @override
///   bool get isWeb => true;
/// }
/// ```
abstract class AppPlatform {
  /// `const` so an implementation can be one too, and be passed around for
  /// free rather than allocated per call site.
  const AppPlatform();

  /// Whether this build is running in a browser.
  ///
  /// The only platform question the app asks. TimeBuddy ships Android and Web
  /// (CLAUDE.md), so a second flag would only ever be `!isWeb` under another
  /// name, and two names for one bit is one edit away from disagreeing.
  bool get isWeb;
}

/// The production [AppPlatform]: whatever Flutter compiled this build for.
class FlutterAppPlatform extends AppPlatform {
  const FlutterAppPlatform();

  @override
  bool get isWeb => kIsWeb;
}

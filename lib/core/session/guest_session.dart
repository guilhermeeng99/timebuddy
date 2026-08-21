import 'package:flutter/foundation.dart';
import 'package:timebuddy/core/storage/local_store.dart';

/// Whether this device is using TimeBuddy without an account
/// (docs/specs/guest_mode.md).
///
/// A `ChangeNotifier` rather than a cubit, because its one consumer that has
/// to *react* is `AppRouter`, which takes a `Listenable` for its
/// `refreshListenable` and would otherwise need a bloc-to-listenable adapter
/// to learn the same boolean.
///
/// **Why this is not an `AuthState`.** `AuthState` answers "does Firebase have
/// a session", and for a guest the honest answer stays `Unauthenticated`. A
/// sixth state would be one `AuthBloc` invents and the repository never
/// reports.
///
/// **Why it is persisted.** On web a reload or a deep link re-runs the
/// router's redirect in a process that has never heard of this visitor. An
/// in-memory flag would bounce a guest to onboarding on every refresh.
///
/// ```dart
/// await sl<GuestSession>().restore();   // before the first redirect
/// if (sl<GuestSession>().isGuest) { /* the shell is theirs */ }
/// ```
class GuestSession extends ChangeNotifier {
  GuestSession({required LocalStore localStore}) : _localStore = localStore;

  /// The value written under [StorageKeys.guest].
  ///
  /// The key's presence is what carries the fact; the value exists so the
  /// stored document is readable by a human looking at `localStorage`.
  static const String _marker = 'true';

  final LocalStore _localStore;

  bool _isGuest = false;

  /// Whether the app may be used without a session.
  ///
  /// Synchronous on purpose: `AppRouter._redirect` is called during a
  /// navigation and cannot await anything, which is why [restore] settles
  /// before the router exists.
  bool get isGuest => _isGuest;

  /// Whether this process has already run the adopting sync for a guest who
  /// signed in (guest_mode.md rule 8).
  ///
  /// **In-memory, and deliberately not persisted.** It exists to break a
  /// redirect loop: an adoption that fails leaves [isGuest] true, and a rule
  /// keyed on the marker alone would send the user back to `/startup` forever.
  /// Losing it on restart is the point — the next launch should retry.
  bool adoptionAttempted = false;

  /// Hydrates [isGuest] from the device.
  ///
  /// Awaited inside `configureDependencies()` rather than fired and forgotten:
  /// the first `_redirect` runs before the first frame, and a guest whose
  /// marker had not landed yet would be sent to onboarding.
  ///
  /// A refused read is treated as "not a guest": a device that cannot read
  /// cannot be trusted to have stored consent, and onboarding is a recoverable
  /// place to be wrong.
  Future<void> restore() async {
    final bool restored;
    try {
      restored = await _localStore.readRaw(StorageKeys.guest) != null;
    } on Object catch (_) {
      return;
    }
    if (restored == _isGuest) return;
    _isGuest = restored;
    notifyListeners();
  }

  /// Starts a guest session, from onboarding's "continue without an account".
  ///
  /// The write is awaited before the notification so a listener that reacts by
  /// navigating cannot outrun the marker it depends on.
  Future<void> enter() async {
    if (_isGuest) return;
    try {
      await _localStore.writeRaw(StorageKeys.guest, _marker);
    } on Object catch (_) {
      // A device that refuses the write still gets to use the app; it just
      // meets onboarding again next launch. Refusing to open would be a worse
      // answer to "your browser is in private mode".
    }
    _isGuest = true;
    notifyListeners();
  }

  /// Ends the guest session, once a sign-in's adopting sync has landed.
  ///
  /// Never called on a failed adoption (guest_mode.md rule 8): the marker is
  /// what makes the next launch retry.
  Future<void> leave() async {
    if (!_isGuest) return;
    try {
      await _localStore.remove(StorageKeys.guest);
    } on Object catch (_) {
      // Same reasoning as [enter]: the in-memory truth is what the router
      // reads, and a stale key costs one retried adoption that finds nothing
      // to adopt.
    }
    _isGuest = false;
    notifyListeners();
  }
}

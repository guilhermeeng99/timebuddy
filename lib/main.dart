import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:timebuddy/app/app_widget.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/firebase_options.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Boots the app: Firebase, dependencies, locale, then the widget tree.
///
/// Deliberately four lines. Everything that used to be here and is longer than
/// a line has moved to the place that owns it: the wiring to
/// [configureDependencies], and tzdata plus the city catalog to `StartupCubit`
/// (docs/specs/startup.md rules 1 and 2), which is also the only place that can
/// *report* their failure — `main` runs before there is a screen to show one
/// on.
///
/// Firebase comes first because the DI graph registers `FirebaseAuth` and
/// `FirebaseFirestore` handles; they are lazy, so nothing resolves them here,
/// but the app must never reach a state where one could be touched before the
/// SDK has started.
///
/// The board is likewise *not* loaded here: `BoardCubit` is session-scoped and
/// owned by `AppShell` (docs/specs/locations.md, CLAUDE.md Lifecycle), which
/// the router only builds once startup has left `/startup` — so by then the
/// first sync has already written the reconciled document it reads.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await configureDependencies();
  // The stored preference (which may pin a locale) is applied by TimeBuddyApp
  // once it loads; the device locale is the right guess until then.
  await LocaleSettings.useDeviceLocale();
  runApp(TranslationProvider(child: const TimeBuddyApp()));
}

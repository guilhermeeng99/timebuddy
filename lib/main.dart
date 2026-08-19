import 'package:flutter/widgets.dart';
import 'package:timebuddy/app/app_widget.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Boots the app: dependencies, tzdata, locale, then the widget tree.
///
/// The tzdata load is awaited here rather than lazily inside the first screen
/// because every clock in the app is wrong until it lands, and one late frame
/// is cheaper than a screen that renders the wrong hour and then corrects
/// itself. Anything longer than a line belongs in [configureDependencies].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  await sl<TimeZoneEngine>().initialize();
  // The stored preference (which may pin a locale) is applied by TimeBuddyApp
  // once it loads; the device locale is the right guess until then.
  await LocaleSettings.useDeviceLocale();
  runApp(TranslationProvider(child: const TimeBuddyApp()));
}

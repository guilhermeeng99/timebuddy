///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$app$en app = Translations$app$en._(_root);
	late final Translations$common$en common = Translations$common$en._(_root);
	late final Translations$home$en home = Translations$home$en._(_root);
	late final Translations$startup$en startup = Translations$startup$en._(_root);
	late final Translations$settings$en settings = Translations$settings$en._(_root);
	late final Translations$bands$en bands = Translations$bands$en._(_root);
}

// Path: app
class Translations$app$en {
	Translations$app$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'TimeBuddy'
	String get name => 'TimeBuddy';

	/// en: 'Every time zone, side by side'
	String get tagline => 'Every time zone, side by side';
}

// Path: common
class Translations$common$en {
	Translations$common$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Try again'
	String get retry => 'Try again';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Loading...'
	String get loading => 'Loading...';

	/// en: 'Something went wrong'
	String get errorTitle => 'Something went wrong';

	/// en: 'That didn't work. Check your connection and try again.'
	String get errorBody => 'That didn\'t work. Check your connection and try again.';
}

// Path: home
class Translations$home$en {
	Translations$home$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'TimeBuddy'
	String get title => 'TimeBuddy';

	/// en: 'Your device'
	String get deviceClockLabel => 'Your device';

	/// en: 'Settings'
	String get settingsAction => 'Settings';

	/// en: 'The comparison grid arrives in the next milestone. Until then, this is your device clock.'
	String get milestoneNotice => 'The comparison grid arrives in the next milestone. Until then, this is your device clock.';

	/// en: 'Time zone not detected'
	String get deviceZoneUnknownTitle => 'Time zone not detected';

	/// en: 'Your device did not report one, so this clock is showing UTC.'
	String get deviceZoneUnknownBody => 'Your device did not report one, so this clock is showing UTC.';
}

// Path: startup
class Translations$startup$en {
	Translations$startup$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Every time zone, side by side'
	String get tagline => 'Every time zone, side by side';

	/// en: 'Loading time zone data'
	String get stepLoadingData => 'Loading time zone data';

	/// en: 'Checking your account'
	String get stepCheckingAuth => 'Checking your account';

	/// en: 'Syncing your board'
	String get stepSyncing => 'Syncing your board';

	/// en: 'Ready'
	String get stepReady => 'Ready';

	/// en: 'TimeBuddy could not start'
	String get errorTitle => 'TimeBuddy could not start';

	/// en: 'The time zone data failed to load, so the clocks would be wrong. Try again.'
	String get errorBody => 'The time zone data failed to load, so the clocks would be wrong. Try again.';

	/// en: 'Try again'
	String get errorRetry => 'Try again';
}

// Path: settings
class Translations$settings$en {
	Translations$settings$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Settings'
	String get title => 'Settings';

	/// en: 'Appearance'
	String get groupAppearance => 'Appearance';

	/// en: 'Time'
	String get groupTime => 'Time';

	/// en: 'Working hours'
	String get groupWorkingHours => 'Working hours';

	/// en: 'Language'
	String get groupLanguage => 'Language';

	/// en: 'Account'
	String get groupAccount => 'Account';

	/// en: 'About'
	String get groupAbout => 'About';

	/// en: 'Theme'
	String get themeMode => 'Theme';

	/// en: 'System'
	String get themeSystem => 'System';

	/// en: 'Light'
	String get themeLight => 'Light';

	/// en: 'Dark'
	String get themeDark => 'Dark';

	/// en: 'Light palette'
	String get lightPalette => 'Light palette';

	/// en: 'Dark palette'
	String get darkPalette => 'Dark palette';

	/// en: 'Hour format'
	String get hourFormat => 'Hour format';

	/// en: '12h'
	String get hourFormat12 => '12h';

	/// en: '24h'
	String get hourFormat24 => '24h';

	/// en: 'Show seconds'
	String get showSeconds => 'Show seconds';

	/// en: 'Clocks tick every second instead of every minute.'
	String get showSecondsHint => 'Clocks tick every second instead of every minute.';

	/// en: 'Week starts on'
	String get weekStartsOn => 'Week starts on';

	/// en: 'Monday'
	String get weekStartsMonday => 'Monday';

	/// en: 'Sunday'
	String get weekStartsSunday => 'Sunday';

	/// en: 'Starts at'
	String get workingHoursStart => 'Starts at';

	/// en: 'Ends at'
	String get workingHoursEnd => 'Ends at';

	/// en: '${start} to ${end}'
	String workingHoursSummary({required Object start, required Object end}) => '${start} to ${end}';

	/// en: 'Preview'
	String get workingHoursPreview => 'Preview';

	/// en: 'The window must be between ${min} and ${max} hours long'
	String workingHoursInvalid({required Object min, required Object max}) => 'The window must be between ${min} and ${max} hours long';

	/// en: 'System language'
	String get languageSystem => 'System language';

	/// en: 'Português (Brasil)'
	String get languagePortuguese => 'Português (Brasil)';

	/// en: 'English'
	String get languageEnglish => 'English';

	/// en: 'You are not signed in'
	String get notSignedIn => 'You are not signed in';

	/// en: 'Sign out'
	String get signOut => 'Sign out';

	/// en: 'Delete account'
	String get deleteAccount => 'Delete account';

	/// en: 'App version'
	String get appVersion => 'App version';

	/// en: 'Time zone data'
	String get tzDataVersion => 'Time zone data';

	/// en: 'Licenses'
	String get licenses => 'Licenses';
}

// Path: bands
class Translations$bands$en {
	Translations$bands$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Good'
	String get good => 'Good';

	/// en: 'Borderline'
	String get fair => 'Borderline';

	/// en: 'Off hours'
	String get poor => 'Off hours';

	/// en: 'Night'
	String get night => 'Night';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'app.name' => 'TimeBuddy',
			'app.tagline' => 'Every time zone, side by side',
			'common.retry' => 'Try again',
			'common.cancel' => 'Cancel',
			'common.save' => 'Save',
			'common.close' => 'Close',
			'common.loading' => 'Loading...',
			'common.errorTitle' => 'Something went wrong',
			'common.errorBody' => 'That didn\'t work. Check your connection and try again.',
			'home.title' => 'TimeBuddy',
			'home.deviceClockLabel' => 'Your device',
			'home.settingsAction' => 'Settings',
			'home.milestoneNotice' => 'The comparison grid arrives in the next milestone. Until then, this is your device clock.',
			'home.deviceZoneUnknownTitle' => 'Time zone not detected',
			'home.deviceZoneUnknownBody' => 'Your device did not report one, so this clock is showing UTC.',
			'startup.tagline' => 'Every time zone, side by side',
			'startup.stepLoadingData' => 'Loading time zone data',
			'startup.stepCheckingAuth' => 'Checking your account',
			'startup.stepSyncing' => 'Syncing your board',
			'startup.stepReady' => 'Ready',
			'startup.errorTitle' => 'TimeBuddy could not start',
			'startup.errorBody' => 'The time zone data failed to load, so the clocks would be wrong. Try again.',
			'startup.errorRetry' => 'Try again',
			'settings.title' => 'Settings',
			'settings.groupAppearance' => 'Appearance',
			'settings.groupTime' => 'Time',
			'settings.groupWorkingHours' => 'Working hours',
			'settings.groupLanguage' => 'Language',
			'settings.groupAccount' => 'Account',
			'settings.groupAbout' => 'About',
			'settings.themeMode' => 'Theme',
			'settings.themeSystem' => 'System',
			'settings.themeLight' => 'Light',
			'settings.themeDark' => 'Dark',
			'settings.lightPalette' => 'Light palette',
			'settings.darkPalette' => 'Dark palette',
			'settings.hourFormat' => 'Hour format',
			'settings.hourFormat12' => '12h',
			'settings.hourFormat24' => '24h',
			'settings.showSeconds' => 'Show seconds',
			'settings.showSecondsHint' => 'Clocks tick every second instead of every minute.',
			'settings.weekStartsOn' => 'Week starts on',
			'settings.weekStartsMonday' => 'Monday',
			'settings.weekStartsSunday' => 'Sunday',
			'settings.workingHoursStart' => 'Starts at',
			'settings.workingHoursEnd' => 'Ends at',
			'settings.workingHoursSummary' => ({required Object start, required Object end}) => '${start} to ${end}',
			'settings.workingHoursPreview' => 'Preview',
			'settings.workingHoursInvalid' => ({required Object min, required Object max}) => 'The window must be between ${min} and ${max} hours long',
			'settings.languageSystem' => 'System language',
			'settings.languagePortuguese' => 'Português (Brasil)',
			'settings.languageEnglish' => 'English',
			'settings.notSignedIn' => 'You are not signed in',
			'settings.signOut' => 'Sign out',
			'settings.deleteAccount' => 'Delete account',
			'settings.appVersion' => 'App version',
			'settings.tzDataVersion' => 'Time zone data',
			'settings.licenses' => 'Licenses',
			'bands.good' => 'Good',
			'bands.fair' => 'Borderline',
			'bands.poor' => 'Off hours',
			'bands.night' => 'Night',
			_ => null,
		};
	}
}

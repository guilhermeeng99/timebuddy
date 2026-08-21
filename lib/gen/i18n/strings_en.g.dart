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
	late final Translations$startup$en startup = Translations$startup$en._(_root);
	late final Translations$auth$en auth = Translations$auth$en._(_root);
	late final Translations$profile$en profile = Translations$profile$en._(_root);
	late final Translations$settings$en settings = Translations$settings$en._(_root);
	late final Translations$bands$en bands = Translations$bands$en._(_root);
	late final Translations$nav$en nav = Translations$nav$en._(_root);
	late final Translations$grid$en grid = Translations$grid$en._(_root);
	late final Translations$worldClock$en worldClock = Translations$worldClock$en._(_root);
	late final Translations$converter$en converter = Translations$converter$en._(_root);
	late final Translations$locations$en locations = Translations$locations$en._(_root);
}

// Path: app
class Translations$app$en {
	Translations$app$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'TimeBuddy'
	String get name => 'TimeBuddy';
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

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Remove'
	String get remove => 'Remove';

	/// en: 'Done'
	String get done => 'Done';

	/// en: 'Search'
	String get search => 'Search';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Previous day'
	String get previousDay => 'Previous day';

	/// en: 'Next day'
	String get nextDay => 'Next day';

	/// en: '${hour}, ${band}'
	String hourInBand({required Object hour, required Object band}) => '${hour}, ${band}';
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

// Path: auth
class Translations$auth$en {
	Translations$auth$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Every city on one board'
	String get onboardingTitle1 => 'Every city on one board';

	/// en: 'Put the places you work with side by side and read the same moment in all of them.'
	String get onboardingBody1 => 'Put the places you work with side by side and read the same moment in all of them.';

	/// en: 'Know when to call'
	String get onboardingTitle2 => 'Know when to call';

	/// en: 'Working hours are shaded on the grid, so a time that suits everyone is something you see instead of something you calculate.'
	String get onboardingBody2 => 'Working hours are shaded on the grid, so a time that suits everyone is something you see instead of something you calculate.';

	/// en: 'The same board everywhere'
	String get onboardingTitle3 => 'The same board everywhere';

	/// en: 'Sign in with Google and your cities follow you from the phone to the browser. You can also just start using it.'
	String get onboardingBody3 => 'Sign in with Google and your cities follow you from the phone to the browser. You can also just start using it.';

	/// en: 'Skip'
	String get onboardingSkip => 'Skip';

	/// en: 'Next'
	String get onboardingNext => 'Next';

	/// en: 'Skip the tour and go straight to signing in.'
	String get onboardingSkipHint => 'Skip the tour and go straight to signing in.';

	/// en: 'Sign in with Google'
	String get signInWithGoogle => 'Sign in with Google';

	/// en: 'Sign-in didn't go through. Try again.'
	String get signInFailed => 'Sign-in didn\'t go through. Try again.';

	/// en: 'This browser is blocking the storage the sign-in needs. Allow cross-site cookies for this site, or allow pop-ups, and try again.'
	String get signInStorageBlocked => 'This browser is blocking the storage the sign-in needs. Allow cross-site cookies for this site, or allow pop-ups, and try again.';

	/// en: 'The sign-in window was blocked. Allow pop-ups for this site and press the button again.'
	String get signInPopupBlocked => 'The sign-in window was blocked. Allow pop-ups for this site and press the button again.';

	/// en: 'Sign out'
	String get signOut => 'Sign out';

	/// en: 'Sign out?'
	String get signOutConfirm => 'Sign out?';

	/// en: 'Your cities stay in your account. The copy kept on this device is cleared, and you carry on without an account.'
	String get signOutConfirmBody => 'Your cities stay in your account. The copy kept on this device is cleared, and you carry on without an account.';

	/// en: 'We couldn't sign you out. Try again.'
	String get signOutFailed => 'We couldn\'t sign you out. Try again.';

	/// en: 'Delete account'
	String get deleteAccount => 'Delete account';

	/// en: 'Delete your account?'
	String get deleteAccountConfirm => 'Delete your account?';

	/// en: 'This removes your board, your preferences and your profile from every device. It cannot be undone.'
	String get deleteAccountWarning => 'This removes your board, your preferences and your profile from every device. It cannot be undone.';

	/// en: 'We couldn't delete your account. Try again.'
	String get deleteAccountFailed => 'We couldn\'t delete your account. Try again.';

	/// en: 'Continue without an account'
	String get continueAsGuest => 'Continue without an account';

	/// en: 'Use TimeBuddy right away. Your cities stay on this device until you sign in.'
	String get continueAsGuestHint => 'Use TimeBuddy right away. Your cities stay on this device until you sign in.';

	/// en: 'You're not signed in'
	String get guestTitle => 'You\'re not signed in';

	/// en: 'Your cities and settings live only on this device. Sign in and they follow you to your phone and back.'
	String get guestBody => 'Your cities and settings live only on this device. Sign in and they follow you to your phone and back.';

	/// en: 'Sign in to save'
	String get signInToSave => 'Sign in to save';
}

// Path: profile
class Translations$profile$en {
	Translations$profile$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Account'
	String get title => 'Account';

	/// en: 'Signed in as'
	String get signedInAs => 'Signed in as';

	/// en: 'Everything is synced'
	String get syncStatusIdle => 'Everything is synced';

	/// en: 'Syncing...'
	String get syncStatusSyncing => 'Syncing...';

	/// en: 'Offline. Your changes are saved on this device.'
	String get syncStatusOffline => 'Offline. Your changes are saved on this device.';

	/// en: 'Sync didn't work. Your changes are safe on this device.'
	String get syncStatusError => 'Sync didn\'t work. Your changes are safe on this device.';

	/// en: 'Sync now'
	String get syncNow => 'Sync now';

	/// en: 'Last synced ${time}'
	String lastSynced({required Object time}) => 'Last synced ${time}';

	/// en: 'Not synced yet'
	String get neverSynced => 'Not synced yet';

	/// en: 'Your board was updated from another device.'
	String get boardUpdatedFromAnotherDevice => 'Your board was updated from another device.';

	/// en: 'Your settings were updated from another device.'
	String get preferencesUpdatedFromAnotherDevice => 'Your settings were updated from another device.';
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

	/// en: 'System'
	String get languageSystem => 'System';

	/// en: 'Português'
	String get languagePortuguese => 'Português';

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

	/// en: 'Your board and preferences, and the way out.'
	String get accountRowHint => 'Your board and preferences, and the way out.';
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

// Path: nav
class Translations$nav$en {
	Translations$nav$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Grid'
	String get grid => 'Grid';

	/// en: 'Clocks'
	String get clocks => 'Clocks';

	/// en: 'Converter'
	String get converter => 'Converter';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Account'
	String get profile => 'Account';
}

// Path: grid
class Translations$grid$en {
	Translations$grid$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Time grid'
	String get title => 'Time grid';

	/// en: 'Today'
	String get today => 'Today';

	/// en: 'No cities yet'
	String get emptyTitle => 'No cities yet';

	/// en: 'Add a city and its hours line up next to yours, hour by hour.'
	String get emptyMessage => 'Add a city and its hours line up next to yours, hour by hour.';

	/// en: 'Add your first city'
	String get emptyCta => 'Add your first city';

	/// en: 'Home'
	String get homeBadge => 'Home';

	/// en: 'Same time as home'
	String get sameTime => 'Same time as home';

	/// en: 'Daylight saving'
	String get dstOn => 'Daylight saving';

	/// en: 'The clocks change during this hour'
	String get dstTransitionHere => 'The clocks change during this hour';

	/// en: 'Why this day looks odd'
	String get dstExplainTitle => 'Why this day looks odd';

	/// en: 'This zone moves its clocks on this day, so the day is 23 or 25 hours long. One hour is skipped or repeated, and every hour after it shifts.'
	String get dstExplainBody => 'This zone moves its clocks on this day, so the day is 23 or 25 hours long. One hour is skipped or repeated, and every hour after it shifts.';

	/// en: 'Time zone unavailable'
	String get unresolvedRow => 'Time zone unavailable';

	/// en: 'We could not resolve your home time zone, so the grid is lined up to UTC. Pick your home city to fix it.'
	String get homeZoneBrokenBanner => 'We could not resolve your home time zone, so the grid is lined up to UTC. Pick your home city to fix it.';

	/// en: 'Tap an hour in the ruler to read that moment in every city.'
	String get cursorHint => 'Tap an hour in the ruler to read that moment in every city.';
}

// Path: worldClock
class Translations$worldClock$en {
	Translations$worldClock$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'World clock'
	String get title => 'World clock';

	/// en: 'Same time'
	String get sameTime => 'Same time';

	/// en: 'Tomorrow'
	String get tomorrow => 'Tomorrow';

	/// en: 'Yesterday'
	String get yesterday => 'Yesterday';

	/// en: 'Daylight saving is on'
	String get dstActive => 'Daylight saving is on';

	/// en: 'The clocks change here on ${date}'
	String nextTransition({required Object date}) => 'The clocks change here on ${date}';

	/// en: 'Only your clock so far'
	String get emptyTitle => 'Only your clock so far';

	/// en: 'Add a city and its clock ticks right below yours.'
	String get emptyMessage => 'Add a city and its clock ticks right below yours.';

	/// en: 'Add a city'
	String get emptyCta => 'Add a city';

	/// en: 'Time zone id'
	String get detailZoneId => 'Time zone id';

	/// en: 'Offset from UTC'
	String get detailOffsetUtc => 'Offset from UTC';

	/// en: 'Offset from home'
	String get detailOffsetHome => 'Offset from home';

	/// en: 'Remove from board'
	String get actionRemove => 'Remove from board';

	/// en: 'Open in the grid'
	String get actionOpenInGrid => 'Open in the grid';
}

// Path: converter
class Translations$converter$en {
	Translations$converter$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Time converter'
	String get title => 'Time converter';

	/// en: 'Source city'
	String get sourceLabel => 'Source city';

	/// en: 'Date'
	String get dateLabel => 'Date';

	/// en: 'Time'
	String get timeLabel => 'Time';

	/// en: 'Everywhere else'
	String get resultTitle => 'Everywhere else';

	/// en: '${requested} does not exist on this date, so we are showing ${shown}.'
	String shiftedForwardNotice({required Object requested, required Object shown}) => '${requested} does not exist on this date, so we are showing ${shown}.';

	/// en: 'The clocks go back in ${zone} on this date, so this time happens twice.'
	String ambiguousNotice({required Object zone}) => 'The clocks go back in ${zone} on this date, so this time happens twice.';

	/// en: 'First occurrence'
	String get ambiguousFirst => 'First occurrence';

	/// en: 'Second occurrence'
	String get ambiguousSecond => 'Second occurrence';

	/// en: 'Back to now'
	String get resetToNow => 'Back to now';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Copied to the clipboard'
	String get copied => 'Copied to the clipboard';

	/// en: 'We only convert up to ${years} years from today. Past that, the rules are still guesses.'
	String outOfRange({required Object years}) => 'We only convert up to ${years} years from today. Past that, the rules are still guesses.';

	/// en: 'Add another city to see this moment somewhere else.'
	String get needMoreCities => 'Add another city to see this moment somewhere else.';
}

// Path: locations
class Translations$locations$en {
	Translations$locations$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add a city'
	String get addTitle => 'Add a city';

	/// en: 'Search a city, country or time zone'
	String get searchHint => 'Search a city, country or time zone';

	/// en: 'No city matches that. Try the country, or a time zone id like America/Sao_Paulo.'
	String get searchNoResults => 'No city matches that. Try the country, or a time zone id like America/Sao_Paulo.';

	/// en: '${city} already covers this time zone.'
	String duplicateZone({required Object city}) => '${city} already covers this time zone.';

	/// en: 'Your board holds up to ${max} cities. Remove one to add another.'
	String boardFull({required Object max}) => 'Your board holds up to ${max} cities. Remove one to add another.';

	/// en: '${city} removed'
	String removed({required Object city}) => '${city} removed';

	/// en: 'Undo'
	String get undo => 'Undo';

	/// en: 'This time zone is no longer available.'
	String get unresolvedZone => 'This time zone is no longer available.';

	/// en: 'Replace time zone'
	String get replaceZone => 'Replace time zone';

	/// en: 'Pick your home city'
	String get pickHomeTitle => 'Pick your home city';

	/// en: 'We could not detect your time zone, so every difference is measured from UTC. Choose your home city to fix it.'
	String get pickHomeMessage => 'We could not detect your time zone, so every difference is measured from UTC. Choose your home city to fix it.';

	/// en: 'Set as home'
	String get setAsHome => 'Set as home';

	/// en: 'Home'
	String get homeLabel => 'Home';

	/// en: '${count} of ${max} cities'
	String countLabel({required Object count, required Object max}) => '${count} of ${max} cities';
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
			'common.retry' => 'Try again',
			'common.cancel' => 'Cancel',
			'common.save' => 'Save',
			'common.close' => 'Close',
			'common.loading' => 'Loading...',
			'common.errorTitle' => 'Something went wrong',
			'common.errorBody' => 'That didn\'t work. Check your connection and try again.',
			'common.add' => 'Add',
			'common.edit' => 'Edit',
			'common.remove' => 'Remove',
			'common.done' => 'Done',
			'common.search' => 'Search',
			'common.clear' => 'Clear',
			'common.back' => 'Back',
			'common.previousDay' => 'Previous day',
			'common.nextDay' => 'Next day',
			'common.hourInBand' => ({required Object hour, required Object band}) => '${hour}, ${band}',
			'startup.tagline' => 'Every time zone, side by side',
			'startup.stepLoadingData' => 'Loading time zone data',
			'startup.stepCheckingAuth' => 'Checking your account',
			'startup.stepSyncing' => 'Syncing your board',
			'startup.stepReady' => 'Ready',
			'startup.errorTitle' => 'TimeBuddy could not start',
			'startup.errorBody' => 'The time zone data failed to load, so the clocks would be wrong. Try again.',
			'startup.errorRetry' => 'Try again',
			'auth.onboardingTitle1' => 'Every city on one board',
			'auth.onboardingBody1' => 'Put the places you work with side by side and read the same moment in all of them.',
			'auth.onboardingTitle2' => 'Know when to call',
			'auth.onboardingBody2' => 'Working hours are shaded on the grid, so a time that suits everyone is something you see instead of something you calculate.',
			'auth.onboardingTitle3' => 'The same board everywhere',
			'auth.onboardingBody3' => 'Sign in with Google and your cities follow you from the phone to the browser. You can also just start using it.',
			'auth.onboardingSkip' => 'Skip',
			'auth.onboardingNext' => 'Next',
			'auth.onboardingSkipHint' => 'Skip the tour and go straight to signing in.',
			'auth.signInWithGoogle' => 'Sign in with Google',
			'auth.signInFailed' => 'Sign-in didn\'t go through. Try again.',
			'auth.signInStorageBlocked' => 'This browser is blocking the storage the sign-in needs. Allow cross-site cookies for this site, or allow pop-ups, and try again.',
			'auth.signInPopupBlocked' => 'The sign-in window was blocked. Allow pop-ups for this site and press the button again.',
			'auth.signOut' => 'Sign out',
			'auth.signOutConfirm' => 'Sign out?',
			'auth.signOutConfirmBody' => 'Your cities stay in your account. The copy kept on this device is cleared, and you carry on without an account.',
			'auth.signOutFailed' => 'We couldn\'t sign you out. Try again.',
			'auth.deleteAccount' => 'Delete account',
			'auth.deleteAccountConfirm' => 'Delete your account?',
			'auth.deleteAccountWarning' => 'This removes your board, your preferences and your profile from every device. It cannot be undone.',
			'auth.deleteAccountFailed' => 'We couldn\'t delete your account. Try again.',
			'auth.continueAsGuest' => 'Continue without an account',
			'auth.continueAsGuestHint' => 'Use TimeBuddy right away. Your cities stay on this device until you sign in.',
			'auth.guestTitle' => 'You\'re not signed in',
			'auth.guestBody' => 'Your cities and settings live only on this device. Sign in and they follow you to your phone and back.',
			'auth.signInToSave' => 'Sign in to save',
			'profile.title' => 'Account',
			'profile.signedInAs' => 'Signed in as',
			'profile.syncStatusIdle' => 'Everything is synced',
			'profile.syncStatusSyncing' => 'Syncing...',
			'profile.syncStatusOffline' => 'Offline. Your changes are saved on this device.',
			'profile.syncStatusError' => 'Sync didn\'t work. Your changes are safe on this device.',
			'profile.syncNow' => 'Sync now',
			'profile.lastSynced' => ({required Object time}) => 'Last synced ${time}',
			'profile.neverSynced' => 'Not synced yet',
			'profile.boardUpdatedFromAnotherDevice' => 'Your board was updated from another device.',
			'profile.preferencesUpdatedFromAnotherDevice' => 'Your settings were updated from another device.',
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
			'settings.weekStartsOn' => 'Week starts on',
			'settings.weekStartsMonday' => 'Monday',
			'settings.weekStartsSunday' => 'Sunday',
			'settings.workingHoursStart' => 'Starts at',
			'settings.workingHoursEnd' => 'Ends at',
			'settings.workingHoursSummary' => ({required Object start, required Object end}) => '${start} to ${end}',
			'settings.workingHoursPreview' => 'Preview',
			'settings.workingHoursInvalid' => ({required Object min, required Object max}) => 'The window must be between ${min} and ${max} hours long',
			'settings.languageSystem' => 'System',
			'settings.languagePortuguese' => 'Português',
			'settings.languageEnglish' => 'English',
			'settings.notSignedIn' => 'You are not signed in',
			'settings.signOut' => 'Sign out',
			'settings.deleteAccount' => 'Delete account',
			'settings.appVersion' => 'App version',
			'settings.tzDataVersion' => 'Time zone data',
			'settings.licenses' => 'Licenses',
			'settings.accountRowHint' => 'Your board and preferences, and the way out.',
			'bands.good' => 'Good',
			'bands.fair' => 'Borderline',
			'bands.poor' => 'Off hours',
			'bands.night' => 'Night',
			'nav.grid' => 'Grid',
			'nav.clocks' => 'Clocks',
			'nav.converter' => 'Converter',
			'nav.settings' => 'Settings',
			'nav.profile' => 'Account',
			'grid.title' => 'Time grid',
			'grid.today' => 'Today',
			'grid.emptyTitle' => 'No cities yet',
			'grid.emptyMessage' => 'Add a city and its hours line up next to yours, hour by hour.',
			'grid.emptyCta' => 'Add your first city',
			'grid.homeBadge' => 'Home',
			'grid.sameTime' => 'Same time as home',
			'grid.dstOn' => 'Daylight saving',
			'grid.dstTransitionHere' => 'The clocks change during this hour',
			'grid.dstExplainTitle' => 'Why this day looks odd',
			'grid.dstExplainBody' => 'This zone moves its clocks on this day, so the day is 23 or 25 hours long. One hour is skipped or repeated, and every hour after it shifts.',
			'grid.unresolvedRow' => 'Time zone unavailable',
			'grid.homeZoneBrokenBanner' => 'We could not resolve your home time zone, so the grid is lined up to UTC. Pick your home city to fix it.',
			'grid.cursorHint' => 'Tap an hour in the ruler to read that moment in every city.',
			'worldClock.title' => 'World clock',
			'worldClock.sameTime' => 'Same time',
			'worldClock.tomorrow' => 'Tomorrow',
			'worldClock.yesterday' => 'Yesterday',
			'worldClock.dstActive' => 'Daylight saving is on',
			'worldClock.nextTransition' => ({required Object date}) => 'The clocks change here on ${date}',
			'worldClock.emptyTitle' => 'Only your clock so far',
			'worldClock.emptyMessage' => 'Add a city and its clock ticks right below yours.',
			'worldClock.emptyCta' => 'Add a city',
			'worldClock.detailZoneId' => 'Time zone id',
			'worldClock.detailOffsetUtc' => 'Offset from UTC',
			'worldClock.detailOffsetHome' => 'Offset from home',
			'worldClock.actionRemove' => 'Remove from board',
			'worldClock.actionOpenInGrid' => 'Open in the grid',
			'converter.title' => 'Time converter',
			'converter.sourceLabel' => 'Source city',
			'converter.dateLabel' => 'Date',
			'converter.timeLabel' => 'Time',
			'converter.resultTitle' => 'Everywhere else',
			'converter.shiftedForwardNotice' => ({required Object requested, required Object shown}) => '${requested} does not exist on this date, so we are showing ${shown}.',
			'converter.ambiguousNotice' => ({required Object zone}) => 'The clocks go back in ${zone} on this date, so this time happens twice.',
			'converter.ambiguousFirst' => 'First occurrence',
			'converter.ambiguousSecond' => 'Second occurrence',
			'converter.resetToNow' => 'Back to now',
			'converter.copy' => 'Copy',
			'converter.copied' => 'Copied to the clipboard',
			'converter.outOfRange' => ({required Object years}) => 'We only convert up to ${years} years from today. Past that, the rules are still guesses.',
			'converter.needMoreCities' => 'Add another city to see this moment somewhere else.',
			'locations.addTitle' => 'Add a city',
			'locations.searchHint' => 'Search a city, country or time zone',
			'locations.searchNoResults' => 'No city matches that. Try the country, or a time zone id like America/Sao_Paulo.',
			'locations.duplicateZone' => ({required Object city}) => '${city} already covers this time zone.',
			'locations.boardFull' => ({required Object max}) => 'Your board holds up to ${max} cities. Remove one to add another.',
			'locations.removed' => ({required Object city}) => '${city} removed',
			'locations.undo' => 'Undo',
			'locations.unresolvedZone' => 'This time zone is no longer available.',
			'locations.replaceZone' => 'Replace time zone',
			'locations.pickHomeTitle' => 'Pick your home city',
			'locations.pickHomeMessage' => 'We could not detect your time zone, so every difference is measured from UTC. Choose your home city to fix it.',
			'locations.setAsHome' => 'Set as home',
			'locations.homeLabel' => 'Home',
			'locations.countLabel' => ({required Object count, required Object max}) => '${count} of ${max} cities',
			_ => null,
		};
	}
}

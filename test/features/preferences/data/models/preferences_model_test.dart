import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/theme/dark_palettes.dart';
import 'package:timebuddy/app/theme/light_palettes.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/working_hours.dart';
import 'package:timebuddy/features/preferences/data/models/preferences_model.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

import '../../../../harness/factories/preferences_factory.dart';
import '../../../../harness/helpers.dart';

void main() {
  // The parser has no device locale to consult, so its enum fallbacks have to
  // be the same values the provisioning path writes (preferences.md rules 1
  // and 9). Comparing against this rather than against repeated literals keeps
  // the two code paths pinned to each other.
  final provisioned = PreferencesEntity.defaults(
    now: utcDate(2024, 1, 15, 12),
    deviceLocale: const Locale('pt', 'BR'),
  );

  PreferencesModel parse(Map<String, dynamic> json) =>
      PreferencesModel.fromJson(json);

  PreferencesModel roundTrip(PreferencesEntity entity) {
    // Through a real encode/decode, not just toJson/fromJson: a value that is
    // not JSON-encodable would otherwise survive the test and fail on device.
    final encoded = jsonEncode(PreferencesModel.fromEntity(entity).toJson());
    return PreferencesModel.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
  }

  group('toJson', () {
    test('writes the documented field names and encodings', () {
      final model = PreferencesModel.fromEntity(
        aPreferences(
          themeMode: ThemeMode.dark,
          lightPalette: LightPalette.sunsetCoral,
          darkPalette: DarkPalette.royalPurple,
          hourFormat: ClockFormat.h12,
          workingHours: const WorkingHours(startHour: 22, endHour: 6),
          weekStartsOn: WeekStart.sunday,
          showSeconds: true,
          localeTag: 'pt-BR',
          revision: 7,
          updatedAt: utcDate(2024, 3, 10, 6, 30),
        ),
      );

      expect(model.toJson(), <String, dynamic>{
        'themeMode': 'dark',
        'lightPalette': 'sunsetCoral',
        'darkPalette': 'royalPurple',
        'hourFormat': 'h12',
        'workingHours': <String, dynamic>{'start': 22, 'end': 6},
        'weekStartsOn': 'sunday',
        'showSeconds': true,
        // 'locale', not 'localeTag': the field name is the Firestore contract
        // (CLAUDE.md, Firestore Collections), and one shape feeds both writers.
        'locale': 'pt-BR',
        'revision': 7,
        'updatedAt': '2024-03-10T06:30:00.000Z',
      });
    });

    test('writes a null locale as a present null, not a missing key', () {
      // 'follow the device' is a real value (preferences.md rule 3). Dropping
      // the key would make it indistinguishable from a truncated document.
      final json = PreferencesModel.fromEntity(aPreferences()).toJson();

      expect(json.containsKey('locale'), isTrue);
      expect(json['locale'], isNull);
    });

    test('normalises updatedAt to UTC before writing it', () {
      final model = PreferencesModel.fromEntity(
        aPreferences(updatedAt: utcDate(2024, 7, 1, 15)),
      );

      expect(model.toJson()['updatedAt'], endsWith('Z'));
    });
  });

  group('round trip', () {
    test('survives a full encode/decode cycle', () {
      final entity = aPreferences(
        themeMode: ThemeMode.light,
        lightPalette: LightPalette.forestSage,
        darkPalette: DarkPalette.deepOcean,
        hourFormat: ClockFormat.h12,
        workingHours: const WorkingHours(startHour: 22, endHour: 6),
        weekStartsOn: WeekStart.sunday,
        showSeconds: true,
        localeTag: 'en',
        revision: 12,
        updatedAt: utcDate(2024, 11, 3, 5, 45),
      );

      // Compared model to model: Equatable's `==` includes runtimeType, so a
      // PreferencesModel never equals a PreferencesEntity carrying identical
      // fields, however much the two look alike.
      expect(roundTrip(entity), PreferencesModel.fromEntity(entity));
    });

    test('keeps a null locale null across the cycle', () {
      expect(roundTrip(aPreferences()).localeTag, isNull);
    });

    test('fromEntity carries every field across unchanged', () {
      final entity = aPreferences(
        hourFormat: ClockFormat.h12,
        showSeconds: true,
        localeTag: 'pt-BR',
        revision: 5,
      );

      // `props` rather than `==` for the same runtimeType reason as above.
      expect(PreferencesModel.fromEntity(entity).props, entity.props);
    });
  });

  group('degrading parses', () {
    test('an empty document parses to a usable set of defaults', () {
      final parsed = parse(<String, dynamic>{});

      expect(parsed.themeMode, provisioned.themeMode);
      expect(parsed.lightPalette, provisioned.lightPalette);
      expect(parsed.darkPalette, provisioned.darkPalette);
      expect(parsed.workingHours, WorkingHours.defaultHours);
      expect(parsed.showSeconds, isFalse);
      expect(parsed.localeTag, isNull);
      expect(parsed.revision, 0);
    });

    // preferences.md rule 9: a palette dropped in a later release, or a
    // document written by a newer client on the user's other device, must cost
    // one setting rather than the whole settings screen.
    test('an enum value that no longer exists degrades to the default', () {
      final parsed = parse(<String, dynamic>{
        'themeMode': 'sepia',
        'lightPalette': 'neonPink',
        'darkPalette': 'goldRush',
        'hourFormat': 'h13',
        'weekStartsOn': 'caturday',
      });

      expect(parsed.themeMode, provisioned.themeMode);
      expect(parsed.lightPalette, provisioned.lightPalette);
      expect(parsed.darkPalette, provisioned.darkPalette);
      // Not the locale-seeded defaults: seeding happens once, at first launch
      // (rule 2), and a parser reading a stored document is not that moment.
      expect(parsed.hourFormat, ClockFormat.h24);
      expect(parsed.weekStartsOn, WeekStart.monday);
    });

    test('a wrongly typed field degrades instead of throwing', () {
      final parsed = parse(<String, dynamic>{
        'themeMode': 42,
        'locale': 7,
        'showSeconds': 'true',
        'revision': 'four',
      });

      expect(parsed.themeMode, provisioned.themeMode);
      expect(parsed.localeTag, isNull);
      expect(parsed.showSeconds, isFalse);
      expect(parsed.revision, 0);
    });

    test('reads a revision written as a JSON number', () {
      // Firestore hands numbers back as `num`; the local store round-trips
      // them as int. Both sides feed the same parser.
      expect(parse(<String, dynamic>{'revision': 12.0}).revision, 12);
      expect(parse(<String, dynamic>{'revision': 12}).revision, 12);
    });

    // Behaviour change, and a deliberate one: this parser used to accept a
    // stored string verbatim while every sibling model trimmed one, so a
    // padded `" dark "` degraded to the system theme here and would have
    // parsed anywhere else. Both sides now go through `filledStringOrNull`,
    // and the setting the user chose survives a writer that padded it.
    test('a padded enum name is the value, not damage', () {
      final parsed = parse(<String, dynamic>{
        'themeMode': ' dark ',
        'hourFormat': '\th12\n',
        'weekStartsOn': ' sunday',
      });

      expect(parsed.themeMode, ThemeMode.dark);
      expect(parsed.hourFormat, ClockFormat.h12);
      expect(parsed.weekStartsOn, WeekStart.sunday);
    });

    test('a blank locale is no locale', () {
      // Same change seen from the other end: `"   "` is damage, not a BCP-47
      // tag, and a blank tag reaching `Locale` would name no language at all.
      expect(parse(<String, dynamic>{'locale': '   '}).localeTag, isNull);
      expect(parse(<String, dynamic>{'locale': ' pt-BR '}).localeTag, 'pt-BR');
    });

    test('keeps a known enum value', () {
      final parsed = parse(<String, dynamic>{
        'themeMode': 'dark',
        'lightPalette': 'cyanPop',
        'darkPalette': 'pureBlack',
        'hourFormat': 'h12',
        'weekStartsOn': 'sunday',
        'locale': 'pt-BR',
        'showSeconds': true,
      });

      expect(parsed.themeMode, ThemeMode.dark);
      expect(parsed.lightPalette, LightPalette.cyanPop);
      expect(parsed.darkPalette, DarkPalette.pureBlack);
      expect(parsed.hourFormat, ClockFormat.h12);
      expect(parsed.weekStartsOn, WeekStart.sunday);
      expect(parsed.localeTag, 'pt-BR');
      expect(parsed.showSeconds, isTrue);
    });
  });

  group('workingHours', () {
    // preferences.md, Model Serialization: the window is parsed as a unit. A
    // half-adopted window recolours every hour in the grid, and the user never
    // chose it, so the fallback is the whole default pair.
    test('a broken end discards the valid start too', () {
      final parsed = parse(<String, dynamic>{
        'workingHours': <String, dynamic>{'start': 22, 'end': 99},
      });

      expect(parsed.workingHours, WorkingHours.defaultHours);
      // The point of the previous line: 22 paired with the default end would
      // be a 19-hour window nobody asked for.
      expect(parsed.workingHours.startHour, isNot(22));
    });

    final malformedWindows = <String, Object?>{
      'not a map at all': 'nonsense',
      'missing end': <String, dynamic>{'start': 9},
      'missing start': <String, dynamic>{'end': 17},
      'non-numeric bounds': <String, dynamic>{'start': 'nine', 'end': 'five'},
      'start equal to end': <String, dynamic>{'start': 9, 'end': 9},
      'longer than 16 hours': <String, dynamic>{'start': 6, 'end': 23},
      'start out of range': <String, dynamic>{'start': -1, 'end': 5},
      'end out of range': <String, dynamic>{'start': 9, 'end': 25},
    };

    for (final malformed in malformedWindows.entries) {
      test('falls back to the default window: ${malformed.key}', () {
        final parsed = parse(<String, dynamic>{
          'workingHours': malformed.value,
        });

        expect(parsed.workingHours, WorkingHours.defaultHours);
      });
    }

    // preferences.md rule 4: a night shift is a legal window, not a corrupt
    // one, so the fallback must not swallow it.
    test('keeps a window that wraps past midnight', () {
      final parsed = parse(<String, dynamic>{
        'workingHours': <String, dynamic>{'start': 22, 'end': 6},
      });

      expect(
        parsed.workingHours,
        const WorkingHours(startHour: 22, endHour: 6),
      );
    });

    test('keeps the shortest legal window', () {
      final parsed = parse(<String, dynamic>{
        'workingHours': <String, dynamic>{'start': 9, 'end': 10},
      });

      expect(
        parsed.workingHours,
        const WorkingHours(startHour: 9, endHour: 10),
      );
    });

    test('keeps the longest legal window', () {
      final parsed = parse(<String, dynamic>{
        'workingHours': <String, dynamic>{'start': 6, 'end': 22},
      });

      expect(
        parsed.workingHours,
        const WorkingHours(startHour: 6, endHour: 22),
      );
    });
  });

  group('updatedAt', () {
    test('parses an ISO-8601 string', () {
      final parsed = parse(<String, dynamic>{
        'updatedAt': '2024-03-10T06:30:00.000Z',
      });

      expect(parsed.updatedAt, utcDate(2024, 3, 10, 6, 30));
      expect(parsed.updatedAt.isUtc, isTrue);
    });

    test('normalises an offset-bearing ISO string to UTC', () {
      // A document copied from a device that wrote a local offset still has to
      // compare against UTC instants (CLAUDE.md, Time rule 1).
      final parsed = parse(<String, dynamic>{
        'updatedAt': '2024-03-10T03:30:00-03:00',
      });

      expect(parsed.updatedAt, utcDate(2024, 3, 10, 6, 30));
      expect(parsed.updatedAt.isUtc, isTrue);
    });

    test('parses a millisecond epoch int', () {
      final instant = utcDate(2024, 3, 10, 6, 30);

      final parsed = parse(<String, dynamic>{
        'updatedAt': instant.millisecondsSinceEpoch,
      });

      expect(parsed.updatedAt, instant);
      expect(parsed.updatedAt.isUtc, isTrue);
    });

    // sync.md rule 5: updatedAt only ever breaks a revision tie, so an
    // unreadable timestamp has to lose every tie it enters. Falling back to
    // "now" would make the most broken document win them all.
    test('an unreadable timestamp falls back to the epoch', () {
      const unreadable = <Object?>[null, 'yesterday', 42.5];

      for (final raw in unreadable) {
        expect(
          parse(<String, dynamic>{'updatedAt': raw}).updatedAt,
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          reason: 'updatedAt: $raw',
        );
      }
    });
  });
}

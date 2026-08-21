import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/di/injection_container.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/app/widgets/error_view.dart';
import 'package:timebuddy/app/widgets/fab_safe_area.dart';
import 'package:timebuddy/app/widgets/loading_shimmer.dart';
import 'package:timebuddy/app/widgets/timebuddy_large_app_bar.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_field.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_row.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_sheet.dart';
import 'package:timebuddy/app/widgets/timebuddy_picker_sheet_empty.dart';
import 'package:timebuddy/app/widgets/timebuddy_pill_toggle.dart';
import 'package:timebuddy/app/widgets/timebuddy_search_field.dart';
import 'package:timebuddy/app/widgets/timebuddy_section.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/time/clock.dart';
import 'package:timebuddy/core/time/time_formats.dart';
import 'package:timebuddy/core/time/timezone_engine.dart';
import 'package:timebuddy/core/utils/time_formatter.dart';
import 'package:timebuddy/features/locations/domain/entities/city_entity.dart';
import 'package:timebuddy/features/locations/domain/repositories/city_catalog_repository.dart';
import 'package:timebuddy/features/locations/presentation/cubit/board_cubit.dart';
import 'package:timebuddy/features/locations/presentation/cubit/location_search_cubit.dart';
import 'package:timebuddy/features/preferences/presentation/cubit/preferences_cubit.dart';
import 'package:timebuddy/features/time_converter/domain/entities/conversion_result.dart';
import 'package:timebuddy/features/time_converter/domain/usecases/convert_time_usecase.dart';
import 'package:timebuddy/features/time_converter/presentation/cubit/time_converter_cubit.dart';
import 'package:timebuddy/features/time_converter/presentation/widgets/conversion_result_list.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// Placeholder rows while the board resolves. Roughly a phone screen, so the
/// real answer lands without the page jumping (design_system §8).
const int _loadingRowCount = 4;

/// Placeholder rows while the city catalog loads inside the source picker.
const int _pickerLoadingRowCount = 6;

/// Tint behind the disclosure banner, and the size of its glyph.
const double _bannerTintAlpha = 0.12;
const double _bannerIconSize = 20;

/// "It is 15:00 on 12 March in Lisbon. What time is that everywhere else?"
/// (docs/specs/time_converter.md).
///
/// One point-in-time question: unlike the grid it is not anchored to today,
/// and unlike the planner it has no range. Its whole value is being right on
/// dates far from now, where a zone's DST rules differ from today's — which
/// is why every line comes from `ConvertTimeUseCase` resolving the chosen
/// local fields into one instant, and never from an offset carried over from
/// the board.
///
/// It creates its own [TimeConverterCubit] per visit, because it owns no
/// persisted state (CLAUDE.md, Lifecycle).
class TimeConverterPage extends StatelessWidget {
  const TimeConverterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TimeConverterCubit>(
      create: (context) => TimeConverterCubit(
        boardCubit: context.read<BoardCubit>(),
        preferencesCubit: context.read<PreferencesCubit>(),
        convertTime: sl<ConvertTimeUseCase>(),
        engine: sl<TimeZoneEngine>(),
        clock: sl<Clock>(),
      )..start(),
      child: const _ConverterView(),
    );
  }
}

class _ConverterView extends StatelessWidget {
  const _ConverterView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A primary destination, so there is nothing beneath it to go back to.
      appBar: TimeBuddyLargeAppBar(title: t.converter.title, showBack: false),
      body: BlocBuilder<TimeConverterCubit, TimeConverterState>(
        builder: (context, state) => switch (state) {
          // The board, not the conversion: the arithmetic is synchronous and
          // never shows a spinner (spec, State Machine).
          ConverterPreparing() => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: LoadingShimmer(rowCount: _loadingRowCount),
          ),
          ConverterError(:final failure) => ErrorView(
            failure: failure,
            onRetry: () => unawaited(context.read<BoardCubit>().load()),
          ),
          ConverterReady(:final result) => _ConverterBody(result: result),
        },
      ),
    );
  }
}

class _ConverterBody extends StatelessWidget {
  const _ConverterBody({required this.result});

  final ConversionResult result;

  @override
  Widget build(BuildContext context) {
    final hourFormat = _hourFormatOf(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        // The bar floats over this list, so the last city needs room to
        // clear it (design_system §7).
        bottomSafeForBar(context, isSubPage: false),
      ),
      children: [
        _SourceSection(result: result, hourFormat: hourFormat),
        // Rules 4 and 5: a local time that did not map cleanly onto one
        // instant is said out loud, above the answer, every time.
        if (result.isDisclosed) ...[
          const SizedBox(height: AppSpacing.md),
          _DisclosureBanner(result: result, hourFormat: hourFormat),
        ],
        const SizedBox(height: AppSpacing.xl),
        TimeBuddySection(
          label: t.converter.resultTitle,
          // The rows carry their own band-tinted surfaces; a card behind
          // them would be a second surface under every one of them.
          card: false,
          count: result.lines.isEmpty ? null : result.lines.length,
          child: ConversionResultList(
            lines: result.lines,
            hourFormat: hourFormat,
          ),
        ),
      ],
    );
  }
}

/// The question: which city, which date, which time (rule 1).
class _SourceSection extends StatelessWidget {
  const _SourceSection({required this.result, required this.hourFormat});

  final ConversionResult result;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    final input = result.input;
    return TimeBuddySection(
      label: t.converter.sourceLabel,
      trailing: TextButton(
        onPressed: context.read<TimeConverterCubit>().resetToNow,
        child: Text(t.converter.resetToNow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimeBuddyPickerField(
            icon: FontAwesomeIcons.earthAmericas,
            label: t.converter.sourceLabel,
            // Never rendered: the source line always resolves, to a board row
            // or to the stand-in the use case builds. The field still needs
            // one, so it names the same thing the label does.
            placeholder: t.converter.sourceLabel,
            value: result.source.location.label,
            onTap: () => unawaited(_pickSourceZone(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          // Chevrons flank the date, so "the same time tomorrow" is one tap.
          Row(
            children: [
              const _DayStepButton(
                days: -1,
                icon: FontAwesomeIcons.chevronLeft,
              ),
              Expanded(child: _DateField(input: input)),
              const _DayStepButton(
                days: 1,
                icon: FontAwesomeIcons.chevronRight,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _TimeField(input: input, hourFormat: hourFormat),
        ],
      ),
    );
  }
}

/// One calendar day forward or back, and the sentence for the day it refuses.
class _DayStepButton extends StatelessWidget {
  const _DayStepButton({required this.days, required this.icon});

  final int days;
  final FaIconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _step(context),
      icon: AppIcon(icon, color: context.appColors.onBackgroundLight),
    );
  }

  /// Rule 8: stepping past the bound is a no-op with a snackbar, rather than
  /// a chevron that silently does nothing.
  void _step(BuildContext context) {
    if (context.read<TimeConverterCubit>().stepDay(days)) return;
    context.showSnack(
      t.converter.outOfRange(years: ConversionInput.rangeYears),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.input});

  final ConversionInput input;

  /// The chosen date as a **local-flagged** field carrier.
  ///
  /// Material's picker runs its own `DateUtils.dateOnly` arithmetic on every
  /// value it is handed, so a UTC-flagged bound beside a local-flagged
  /// initial date would be off by the device's offset — enough, near either
  /// edge, to refuse a date rule 8 allows. Everything the picker touches is
  /// therefore local-flagged here, and read for its fields only.
  DateTime get _chosenDate => DateTime(input.year, input.month, input.day);

  @override
  Widget build(BuildContext context) {
    return TimeBuddyPickerField(
      icon: FontAwesomeIcons.calendar,
      label: t.converter.dateLabel,
      placeholder: t.converter.dateLabel,
      // The platform's own localized date, rather than an inline DateFormat:
      // the year matters over a twenty-year window, and this is the one
      // formatter that is already localized for the app's locales.
      value: MaterialLocalizations.of(context).formatFullDate(_chosenDate),
      onTap: () => unawaited(_pickDate(context)),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final cubit = context.read<TimeConverterCubit>();
    final picked = await showDatePicker(
      context: context,
      initialDate: _chosenDate,
      // Rule 8's window, enforced by the picker itself so a date outside it
      // cannot be chosen in the first place.
      firstDate: _asPickerDate(cubit.earliestDate),
      lastDate: _asPickerDate(cubit.latestDate),
    );
    if (picked == null) return;
    cubit.setDate(DateTime.utc(picked.year, picked.month, picked.day));
  }

  DateTime _asPickerDate(DateTime bound) =>
      DateTime(bound.year, bound.month, bound.day);
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.input, required this.hourFormat});

  final ConversionInput input;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    return TimeBuddyPickerField(
      icon: FontAwesomeIcons.clock,
      label: t.converter.timeLabel,
      placeholder: t.converter.timeLabel,
      value: formatClock(_inputLocalTime(input), hourFormat),
      onTap: () => unawaited(_pickTime(context)),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final cubit = context.read<TimeConverterCubit>();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: input.hour, minute: input.minute),
      // The dial follows the app's own 12h/24h preference rather than the
      // platform's, which is what the rest of the app renders and the only
      // setting the user has been offered.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          alwaysUse24HourFormat: hourFormat == ClockFormat.h24,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    cubit.setTime(hour: picked.hour, minute: picked.minute);
  }
}

/// Rules 4 and 5: the local time the user typed does not map cleanly onto one
/// instant, and the page says which question it is actually answering.
///
/// Not optional and not a snackbar: it is the difference between answering
/// the question and answering a different one, and it stays until the input
/// changes. On a fall-back date it also carries the toggle between the two
/// legitimate answers, because only the user knows which they meant.
class _DisclosureBanner extends StatelessWidget {
  const _DisclosureBanner({required this.result, required this.hourFormat});

  final ConversionResult result;
  final ClockFormat hourFormat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: _bannerTintAlpha),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(
                  FontAwesomeIcons.circleInfo,
                  size: _bannerIconSize,
                  color: colors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _notice,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: colors.onBackground,
                    ),
                  ),
                ),
              ],
            ),
            if (result.isAmbiguous) ...[
              const SizedBox(height: AppSpacing.md),
              TimeBuddyPillToggle<AmbiguousPick>(
                options: [
                  PillOption(
                    value: AmbiguousPick.first,
                    label: t.converter.ambiguousFirst,
                  ),
                  PillOption(
                    value: AmbiguousPick.second,
                    label: t.converter.ambiguousSecond,
                  ),
                ],
                selected: result.input.ambiguousPick,
                onChanged: context.read<TimeConverterCubit>().setAmbiguousPick,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The ambiguous sentence names the zone; the shifted one names both the
  /// time that does not exist and the one on screen instead of it.
  String get _notice {
    if (result.isAmbiguous) {
      return t.converter.ambiguousNotice(zone: result.source.location.label);
    }
    return t.converter.shiftedForwardNotice(
      requested: formatClock(_inputLocalTime(result.input), hourFormat),
      shown: formatClock(result.source.localTime, hourFormat),
    );
  }
}

/// Opens the source picker and hands what it chose to the cubit.
///
/// The whole catalog rather than the board, because the source may
/// legitimately be a city the user never saved (Edge cases). The catalog name
/// travels with the zone id: a source with no board row has no label of its
/// own, and the picker is the only place one is in hand.
Future<void> _pickSourceZone(BuildContext context) async {
  final cubit = context.read<TimeConverterCubit>();
  final city = await showTimeBuddyPickerSheet<CityEntity>(
    context,
    builder: (_) => const _SourceZoneSheet(),
  );
  if (city == null) return;
  cubit.setSourceZone(city.zoneId, label: city.name);
}

/// The source picker: search the catalog, tap a city, get its zone back.
///
/// It writes nothing. `AddLocationSheet` commits its selection to the board
/// and therefore needs the board cubit handed into the route; this one pops a
/// [CityEntity] and lets the caller decide, which is what keeps choosing a
/// source from adding a city nobody asked to add.
class _SourceZoneSheet extends StatelessWidget {
  const _SourceZoneSheet();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LocationSearchCubit>(
      // Page-scoped: created with the sheet and closed with it (CLAUDE.md,
      // Lifecycle). The catalog behind it is the singleton, so reopening the
      // sheet costs a search, not a parse.
      create: (_) => _searchCubit(),
      child: const _SourceZoneSheetChrome(),
    );
  }

  LocationSearchCubit _searchCubit() {
    final cubit = LocationSearchCubit(repository: sl<CityCatalogRepository>());
    // The sheet has to be useful before anything is typed.
    unawaited(cubit.loadDefaults());
    return cubit;
  }
}

class _SourceZoneSheetChrome extends StatelessWidget {
  const _SourceZoneSheetChrome();

  @override
  Widget build(BuildContext context) {
    return TimeBuddyPickerSheet(
      title: t.converter.sourceLabel,
      header: TimeBuddySearchField(
        hintText: t.locations.searchHint,
        autofocus: true,
        clearTooltip: t.common.clear,
        // Undebounced by design: the field reports keystrokes and the cubit
        // owns the wait.
        onChanged: context.read<LocationSearchCubit>().search,
      ),
      bodyBuilder: (context, scrollController) =>
          BlocBuilder<LocationSearchCubit, LocationSearchState>(
            builder: (context, state) =>
                _body(context, state, scrollController),
          ),
    );
  }

  /// Every state attaches the sheet's own controller to a scroll view, so the
  /// sheet stays draggable while the catalog loads or a query matches nothing
  /// — a body that stops scrolling is a sheet that goes rigid exactly when
  /// the user wants to pull it back down.
  Widget _body(
    BuildContext context,
    LocationSearchState state,
    ScrollController scrollController,
  ) => switch (state) {
    LocationSearchInitial() || LocationSearchLoading() => ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [LoadingShimmer(rowCount: _pickerLoadingRowCount)],
    ),
    // Only the picker reports a broken catalog: the converter itself keeps
    // rendering from the labels the board stored (locations.md, Edge Cases).
    LocationSearchError(:final failure) => ListView(
      controller: scrollController,
      children: [
        ErrorView(
          failure: failure,
          onRetry: () =>
              unawaited(context.read<LocationSearchCubit>().loadDefaults()),
        ),
      ],
    ),
    LocationSearchEmpty() => TimeBuddyPickerSheetEmpty(
      message: t.locations.searchNoResults,
      scrollController: scrollController,
    ),
    LocationSearchResults(:final cities) => ListView.builder(
      controller: scrollController,
      itemCount: cities.length,
      itemBuilder: (context, index) => _CityRow(city: cities[index]),
    ),
  };
}

class _CityRow extends StatelessWidget {
  const _CityRow({required this.city});

  final CityEntity city;

  @override
  Widget build(BuildContext context) {
    return TimeBuddyPickerRow(
      title: city.name,
      subtitle: _subtitle,
      onTap: () => Navigator.of(context).pop(city),
    );
  }

  /// Where the city is, then which clock it keeps. The zone id earns its
  /// place: it is what tells two same-country cities apart, and it is the
  /// string a power user pasted into the field to get here (locations rule
  /// 10).
  String get _subtitle {
    final admin1 = city.admin1;
    final place = admin1 == null
        ? city.countryName
        : '$admin1, ${city.countryName}';
    return '$place · ${city.zoneId}';
  }
}

/// The local time the user typed, as a field carrier for rendering.
///
/// Its epoch value means nothing: only the engine turns these fields into an
/// instant, and it has already done so inside the result.
DateTime _inputLocalTime(ConversionInput input) => DateTime.utc(
  input.year,
  input.month,
  input.day,
  input.hour,
  input.minute,
);

/// Watched rather than read: a 12h/24h switch in settings must repaint every
/// reading on the page.
ClockFormat _hourFormatOf(BuildContext context) =>
    switch (context.watch<PreferencesCubit>().state) {
      PreferencesReady(:final preferences) => preferences.hourFormat,
      // Preferences resolve during startup, before any page mounts.
      PreferencesLoading() => ClockFormat.h24,
    };

import 'package:equatable/equatable.dart';
import 'package:timebuddy/features/preferences/domain/entities/preferences_entity.dart';

/// State of `PreferencesCubit`.
///
/// There is no error state on purpose (preferences.md, State Machine): a
/// storage failure is surfaced passively by the sync layer (sync.md rule 4),
/// and the app always has a usable in-memory document to render from.
sealed class PreferencesState extends Equatable {
  const PreferencesState();

  @override
  List<Object?> get props => const [];
}

/// Before the first read resolves. Only the startup splash sees this.
final class PreferencesLoading extends PreferencesState {
  const PreferencesLoading();
}

final class PreferencesReady extends PreferencesState {
  const PreferencesReady(this.preferences);

  final PreferencesEntity preferences;

  @override
  List<Object?> get props => [preferences];
}

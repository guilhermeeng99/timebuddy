///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsPtBr with BaseTranslations<AppLocale, Translations> implements Translations {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsPtBr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ptBr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <pt-BR>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key);

	late final TranslationsPtBr _root = this; // ignore: unused_field

	@override 
	TranslationsPtBr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsPtBr(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$app$pt_BR app = _Translations$app$pt_BR._(_root);
	@override late final _Translations$common$pt_BR common = _Translations$common$pt_BR._(_root);
	@override late final _Translations$home$pt_BR home = _Translations$home$pt_BR._(_root);
	@override late final _Translations$startup$pt_BR startup = _Translations$startup$pt_BR._(_root);
	@override late final _Translations$settings$pt_BR settings = _Translations$settings$pt_BR._(_root);
	@override late final _Translations$bands$pt_BR bands = _Translations$bands$pt_BR._(_root);
	@override late final _Translations$nav$pt_BR nav = _Translations$nav$pt_BR._(_root);
	@override late final _Translations$grid$pt_BR grid = _Translations$grid$pt_BR._(_root);
	@override late final _Translations$locations$pt_BR locations = _Translations$locations$pt_BR._(_root);
}

// Path: app
class _Translations$app$pt_BR implements Translations$app$en {
	_Translations$app$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get name => 'TimeBuddy';
	@override String get tagline => 'Todos os fusos, lado a lado';
}

// Path: common
class _Translations$common$pt_BR implements Translations$common$en {
	_Translations$common$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get retry => 'Tentar de novo';
	@override String get cancel => 'Cancelar';
	@override String get save => 'Salvar';
	@override String get close => 'Fechar';
	@override String get loading => 'Carregando...';
	@override String get errorTitle => 'Algo deu errado';
	@override String get errorBody => 'Não rolou desta vez. Confira sua conexão e tente de novo.';
	@override String get add => 'Adicionar';
	@override String get edit => 'Editar';
	@override String get remove => 'Remover';
	@override String get done => 'Pronto';
	@override String get search => 'Buscar';
	@override String get clear => 'Limpar';
}

// Path: home
class _Translations$home$pt_BR implements Translations$home$en {
	_Translations$home$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'TimeBuddy';
	@override String get deviceClockLabel => 'Seu dispositivo';
	@override String get settingsAction => 'Configurações';
	@override String get milestoneNotice => 'A grade de comparação chega na próxima etapa. Por enquanto, este é o relógio do seu dispositivo.';
	@override String get deviceZoneUnknownTitle => 'Fuso horário não detectado';
	@override String get deviceZoneUnknownBody => 'Seu dispositivo não informou nenhum, então este relógio está mostrando UTC.';
}

// Path: startup
class _Translations$startup$pt_BR implements Translations$startup$en {
	_Translations$startup$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get tagline => 'Todos os fusos, lado a lado';
	@override String get stepLoadingData => 'Carregando os fusos horários';
	@override String get stepCheckingAuth => 'Conferindo sua conta';
	@override String get stepSyncing => 'Sincronizando seu painel';
	@override String get stepReady => 'Tudo pronto';
	@override String get errorTitle => 'O TimeBuddy não conseguiu iniciar';
	@override String get errorBody => 'A base de fusos horários não carregou, então os relógios sairiam errados. Tente de novo.';
	@override String get errorRetry => 'Tentar de novo';
}

// Path: settings
class _Translations$settings$pt_BR implements Translations$settings$en {
	_Translations$settings$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Configurações';
	@override String get groupAppearance => 'Aparência';
	@override String get groupTime => 'Hora';
	@override String get groupWorkingHours => 'Horário de trabalho';
	@override String get groupLanguage => 'Idioma';
	@override String get groupAccount => 'Conta';
	@override String get groupAbout => 'Sobre';
	@override String get themeMode => 'Tema';
	@override String get themeSystem => 'Do sistema';
	@override String get themeLight => 'Claro';
	@override String get themeDark => 'Escuro';
	@override String get lightPalette => 'Paleta clara';
	@override String get darkPalette => 'Paleta escura';
	@override String get hourFormat => 'Formato de hora';
	@override String get hourFormat12 => '12h';
	@override String get hourFormat24 => '24h';
	@override String get showSeconds => 'Mostrar segundos';
	@override String get showSecondsHint => 'Os relógios passam a atualizar a cada segundo, e não a cada minuto.';
	@override String get weekStartsOn => 'A semana começa em';
	@override String get weekStartsMonday => 'Segunda-feira';
	@override String get weekStartsSunday => 'Domingo';
	@override String get workingHoursStart => 'Começa às';
	@override String get workingHoursEnd => 'Termina às';
	@override String workingHoursSummary({required Object start, required Object end}) => '${start} às ${end}';
	@override String get workingHoursPreview => 'Prévia do dia';
	@override String workingHoursInvalid({required Object min, required Object max}) => 'A janela deve ter entre ${min} e ${max} horas';
	@override String get languageSystem => 'Idioma do sistema';
	@override String get languagePortuguese => 'Português (Brasil)';
	@override String get languageEnglish => 'English';
	@override String get notSignedIn => 'Você ainda não entrou';
	@override String get signOut => 'Sair da conta';
	@override String get deleteAccount => 'Excluir conta';
	@override String get appVersion => 'Versão do app';
	@override String get tzDataVersion => 'Base de fusos horários';
	@override String get licenses => 'Licenças';
}

// Path: bands
class _Translations$bands$pt_BR implements Translations$bands$en {
	_Translations$bands$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get good => 'Bom';
	@override String get fair => 'No limite';
	@override String get poor => 'Fora do expediente';
	@override String get night => 'Madrugada';
}

// Path: nav
class _Translations$nav$pt_BR implements Translations$nav$en {
	_Translations$nav$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get grid => 'Grade';
	@override String get locations => 'Cidades';
	@override String get settings => 'Configurações';
}

// Path: grid
class _Translations$grid$pt_BR implements Translations$grid$en {
	_Translations$grid$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Grade de horários';
	@override String get today => 'Hoje';
	@override String get emptyTitle => 'Nenhuma cidade por aqui';
	@override String get emptyMessage => 'Adicione uma cidade e as horas dela ficam lado a lado com as suas, hora a hora.';
	@override String get emptyCta => 'Adicionar a primeira cidade';
	@override String get homeBadge => 'Base';
	@override String get sameTime => 'Mesmo horário da sua base';
	@override String get dstOn => 'Horário de verão';
	@override String get dstTransitionHere => 'O relógio muda dentro desta hora';
	@override String get dstExplainTitle => 'Por que este dia parece estranho';
	@override String get dstExplainBody => 'Este fuso muda o relógio neste dia, então o dia tem 23 ou 25 horas. Uma hora é pulada ou repetida, e todas as horas seguintes se deslocam.';
	@override String get unresolvedRow => 'Fuso horário indisponível';
	@override String get homeZoneBrokenBanner => 'Não conseguimos identificar o fuso da sua cidade base, então a grade está alinhada pelo UTC. Escolha sua cidade base para corrigir.';
	@override String get rowActionSetHome => 'Definir como base';
	@override String get rowActionRemove => 'Remover do painel';
	@override String get rowActionReplaceZone => 'Trocar o fuso horário';
	@override String get cursorHint => 'Toque ou arraste sobre as horas para ver o mesmo momento em todas as cidades.';
}

// Path: locations
class _Translations$locations$pt_BR implements Translations$locations$en {
	_Translations$locations$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Minhas cidades';
	@override String get emptyTitle => 'Seu painel está vazio';
	@override String get emptyMessage => 'Adicione as cidades com que você trabalha e veja os horários delas lado a lado.';
	@override String get emptyCta => 'Adicionar cidade';
	@override String get addTitle => 'Adicionar cidade';
	@override String get searchHint => 'Busque por cidade, país ou fuso horário';
	@override String get searchNoResults => 'Nenhuma cidade encontrada. Tente pelo país ou por um id de fuso, como America/Sao_Paulo.';
	@override String duplicateZone({required Object city}) => '${city} já cobre esse fuso horário.';
	@override String boardFull({required Object max}) => 'Seu painel comporta até ${max} cidades. Remova uma para adicionar outra.';
	@override String removed({required Object city}) => '${city} foi removida';
	@override String get undo => 'Desfazer';
	@override String get unresolvedZone => 'Este fuso horário não está mais disponível.';
	@override String get replaceZone => 'Trocar o fuso horário';
	@override String get pickHomeTitle => 'Escolha sua cidade base';
	@override String get pickHomeMessage => 'Não detectamos seu fuso horário, então todas as diferenças estão sendo medidas a partir do UTC. Escolha sua cidade base para corrigir.';
	@override String get setAsHome => 'Definir como base';
	@override String get homeLabel => 'Base';
	@override String get reorderHint => 'Toque e segure uma cidade para arrastá-la até a posição.';
	@override String countLabel({required Object count, required Object max}) => '${count} de ${max} cidades';
}

/// The flat map containing all translations for locale <pt-BR>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsPtBr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'app.name' => 'TimeBuddy',
			'app.tagline' => 'Todos os fusos, lado a lado',
			'common.retry' => 'Tentar de novo',
			'common.cancel' => 'Cancelar',
			'common.save' => 'Salvar',
			'common.close' => 'Fechar',
			'common.loading' => 'Carregando...',
			'common.errorTitle' => 'Algo deu errado',
			'common.errorBody' => 'Não rolou desta vez. Confira sua conexão e tente de novo.',
			'common.add' => 'Adicionar',
			'common.edit' => 'Editar',
			'common.remove' => 'Remover',
			'common.done' => 'Pronto',
			'common.search' => 'Buscar',
			'common.clear' => 'Limpar',
			'home.title' => 'TimeBuddy',
			'home.deviceClockLabel' => 'Seu dispositivo',
			'home.settingsAction' => 'Configurações',
			'home.milestoneNotice' => 'A grade de comparação chega na próxima etapa. Por enquanto, este é o relógio do seu dispositivo.',
			'home.deviceZoneUnknownTitle' => 'Fuso horário não detectado',
			'home.deviceZoneUnknownBody' => 'Seu dispositivo não informou nenhum, então este relógio está mostrando UTC.',
			'startup.tagline' => 'Todos os fusos, lado a lado',
			'startup.stepLoadingData' => 'Carregando os fusos horários',
			'startup.stepCheckingAuth' => 'Conferindo sua conta',
			'startup.stepSyncing' => 'Sincronizando seu painel',
			'startup.stepReady' => 'Tudo pronto',
			'startup.errorTitle' => 'O TimeBuddy não conseguiu iniciar',
			'startup.errorBody' => 'A base de fusos horários não carregou, então os relógios sairiam errados. Tente de novo.',
			'startup.errorRetry' => 'Tentar de novo',
			'settings.title' => 'Configurações',
			'settings.groupAppearance' => 'Aparência',
			'settings.groupTime' => 'Hora',
			'settings.groupWorkingHours' => 'Horário de trabalho',
			'settings.groupLanguage' => 'Idioma',
			'settings.groupAccount' => 'Conta',
			'settings.groupAbout' => 'Sobre',
			'settings.themeMode' => 'Tema',
			'settings.themeSystem' => 'Do sistema',
			'settings.themeLight' => 'Claro',
			'settings.themeDark' => 'Escuro',
			'settings.lightPalette' => 'Paleta clara',
			'settings.darkPalette' => 'Paleta escura',
			'settings.hourFormat' => 'Formato de hora',
			'settings.hourFormat12' => '12h',
			'settings.hourFormat24' => '24h',
			'settings.showSeconds' => 'Mostrar segundos',
			'settings.showSecondsHint' => 'Os relógios passam a atualizar a cada segundo, e não a cada minuto.',
			'settings.weekStartsOn' => 'A semana começa em',
			'settings.weekStartsMonday' => 'Segunda-feira',
			'settings.weekStartsSunday' => 'Domingo',
			'settings.workingHoursStart' => 'Começa às',
			'settings.workingHoursEnd' => 'Termina às',
			'settings.workingHoursSummary' => ({required Object start, required Object end}) => '${start} às ${end}',
			'settings.workingHoursPreview' => 'Prévia do dia',
			'settings.workingHoursInvalid' => ({required Object min, required Object max}) => 'A janela deve ter entre ${min} e ${max} horas',
			'settings.languageSystem' => 'Idioma do sistema',
			'settings.languagePortuguese' => 'Português (Brasil)',
			'settings.languageEnglish' => 'English',
			'settings.notSignedIn' => 'Você ainda não entrou',
			'settings.signOut' => 'Sair da conta',
			'settings.deleteAccount' => 'Excluir conta',
			'settings.appVersion' => 'Versão do app',
			'settings.tzDataVersion' => 'Base de fusos horários',
			'settings.licenses' => 'Licenças',
			'bands.good' => 'Bom',
			'bands.fair' => 'No limite',
			'bands.poor' => 'Fora do expediente',
			'bands.night' => 'Madrugada',
			'nav.grid' => 'Grade',
			'nav.locations' => 'Cidades',
			'nav.settings' => 'Configurações',
			'grid.title' => 'Grade de horários',
			'grid.today' => 'Hoje',
			'grid.emptyTitle' => 'Nenhuma cidade por aqui',
			'grid.emptyMessage' => 'Adicione uma cidade e as horas dela ficam lado a lado com as suas, hora a hora.',
			'grid.emptyCta' => 'Adicionar a primeira cidade',
			'grid.homeBadge' => 'Base',
			'grid.sameTime' => 'Mesmo horário da sua base',
			'grid.dstOn' => 'Horário de verão',
			'grid.dstTransitionHere' => 'O relógio muda dentro desta hora',
			'grid.dstExplainTitle' => 'Por que este dia parece estranho',
			'grid.dstExplainBody' => 'Este fuso muda o relógio neste dia, então o dia tem 23 ou 25 horas. Uma hora é pulada ou repetida, e todas as horas seguintes se deslocam.',
			'grid.unresolvedRow' => 'Fuso horário indisponível',
			'grid.homeZoneBrokenBanner' => 'Não conseguimos identificar o fuso da sua cidade base, então a grade está alinhada pelo UTC. Escolha sua cidade base para corrigir.',
			'grid.rowActionSetHome' => 'Definir como base',
			'grid.rowActionRemove' => 'Remover do painel',
			'grid.rowActionReplaceZone' => 'Trocar o fuso horário',
			'grid.cursorHint' => 'Toque ou arraste sobre as horas para ver o mesmo momento em todas as cidades.',
			'locations.title' => 'Minhas cidades',
			'locations.emptyTitle' => 'Seu painel está vazio',
			'locations.emptyMessage' => 'Adicione as cidades com que você trabalha e veja os horários delas lado a lado.',
			'locations.emptyCta' => 'Adicionar cidade',
			'locations.addTitle' => 'Adicionar cidade',
			'locations.searchHint' => 'Busque por cidade, país ou fuso horário',
			'locations.searchNoResults' => 'Nenhuma cidade encontrada. Tente pelo país ou por um id de fuso, como America/Sao_Paulo.',
			'locations.duplicateZone' => ({required Object city}) => '${city} já cobre esse fuso horário.',
			'locations.boardFull' => ({required Object max}) => 'Seu painel comporta até ${max} cidades. Remova uma para adicionar outra.',
			'locations.removed' => ({required Object city}) => '${city} foi removida',
			'locations.undo' => 'Desfazer',
			'locations.unresolvedZone' => 'Este fuso horário não está mais disponível.',
			'locations.replaceZone' => 'Trocar o fuso horário',
			'locations.pickHomeTitle' => 'Escolha sua cidade base',
			'locations.pickHomeMessage' => 'Não detectamos seu fuso horário, então todas as diferenças estão sendo medidas a partir do UTC. Escolha sua cidade base para corrigir.',
			'locations.setAsHome' => 'Definir como base',
			'locations.homeLabel' => 'Base',
			'locations.reorderHint' => 'Toque e segure uma cidade para arrastá-la até a posição.',
			'locations.countLabel' => ({required Object count, required Object max}) => '${count} de ${max} cidades',
			_ => null,
		};
	}
}

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
	@override late final _Translations$auth$pt_BR auth = _Translations$auth$pt_BR._(_root);
	@override late final _Translations$profile$pt_BR profile = _Translations$profile$pt_BR._(_root);
	@override late final _Translations$settings$pt_BR settings = _Translations$settings$pt_BR._(_root);
	@override late final _Translations$bands$pt_BR bands = _Translations$bands$pt_BR._(_root);
	@override late final _Translations$nav$pt_BR nav = _Translations$nav$pt_BR._(_root);
	@override late final _Translations$grid$pt_BR grid = _Translations$grid$pt_BR._(_root);
	@override late final _Translations$worldClock$pt_BR worldClock = _Translations$worldClock$pt_BR._(_root);
	@override late final _Translations$planner$pt_BR planner = _Translations$planner$pt_BR._(_root);
	@override late final _Translations$converter$pt_BR converter = _Translations$converter$pt_BR._(_root);
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

// Path: auth
class _Translations$auth$pt_BR implements Translations$auth$en {
	_Translations$auth$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get onboardingTitle1 => 'Todas as cidades num painel só';
	@override String get onboardingBody1 => 'Coloque lado a lado os lugares com que você trabalha e veja o mesmo momento em todos eles.';
	@override String get onboardingTitle2 => 'Saiba a hora certa de chamar';
	@override String get onboardingBody2 => 'O horário de trabalho fica destacado na grade, então achar um horário bom para todo mundo é questão de olhar, não de calcular.';
	@override String get onboardingTitle3 => 'O mesmo painel em qualquer lugar';
	@override String get onboardingBody3 => 'Entre com o Google e suas cidades vão junto do celular para o navegador.';
	@override String get onboardingSkip => 'Pular';
	@override String get onboardingNext => 'Avançar';
	@override String get onboardingSkipHint => 'Pule a apresentação e vá direto para a entrada.';
	@override String get signInWithGoogle => 'Entrar com o Google';
	@override String get signInFailed => 'Não conseguimos entrar. Tente de novo.';
	@override String get signInCancelled => 'Você cancelou a entrada.';
	@override String get signInStorageBlocked => 'Este navegador está bloqueando o armazenamento necessário para entrar. Libere os cookies de terceiros para este site, ou permita pop-ups, e tente de novo.';
	@override String get signInPopupBlocked => 'A janela de entrada foi bloqueada. Permita pop-ups para este site e tente entrar de novo.';
	@override String get signOut => 'Sair da conta';
	@override String get signOutConfirm => 'Sair da conta?';
	@override String get signOutConfirmBody => 'Suas cidades continuam na sua conta. A cópia guardada neste aparelho é apagada até você entrar de novo.';
	@override String get signOutFailed => 'Não conseguimos sair da conta. Tente de novo.';
	@override String get deleteAccount => 'Excluir conta';
	@override String get deleteAccountConfirm => 'Excluir sua conta?';
	@override String get deleteAccountWarning => 'Isso apaga seu painel, suas preferências e seu perfil de todos os aparelhos. Não dá para desfazer.';
	@override String get deleteAccountFailed => 'Não conseguimos excluir sua conta. Tente de novo.';
}

// Path: profile
class _Translations$profile$pt_BR implements Translations$profile$en {
	_Translations$profile$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Conta';
	@override String get signedInAs => 'Você entrou como';
	@override String get syncStatusIdle => 'Tudo sincronizado';
	@override String get syncStatusSyncing => 'Sincronizando...';
	@override String get syncStatusOffline => 'Sem conexão. Suas mudanças ficam salvas neste aparelho.';
	@override String get syncStatusError => 'A sincronização não rolou. Suas mudanças estão salvas neste aparelho.';
	@override String get syncNow => 'Sincronizar agora';
	@override String lastSynced({required Object time}) => 'Última sincronização ${time}';
	@override String get neverSynced => 'Ainda não sincronizou';
	@override String get boardUpdatedFromAnotherDevice => 'Seu painel foi atualizado em outro aparelho.';
	@override String get preferencesUpdatedFromAnotherDevice => 'Suas configurações foram atualizadas em outro aparelho.';
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
	@override String get clocks => 'Relógios';
	@override String get converter => 'Conversor';
	@override String get locations => 'Cidades';
	@override String get settings => 'Configurações';
	@override String get profile => 'Conta';
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

// Path: worldClock
class _Translations$worldClock$pt_BR implements Translations$worldClock$en {
	_Translations$worldClock$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Relógio mundial';
	@override String get sameTime => 'Mesmo horário';
	@override String get tomorrow => 'Amanhã';
	@override String get yesterday => 'Ontem';
	@override String get dstActive => 'Horário de verão em vigor';
	@override String nextTransition({required Object date}) => 'O relógio daqui muda em ${date}';
	@override String get emptyTitle => 'Por enquanto, só o seu relógio';
	@override String get emptyMessage => 'Adicione uma cidade e o relógio dela passa a correr logo abaixo do seu.';
	@override String get emptyCta => 'Adicionar cidade';
	@override String get detailZoneId => 'Id do fuso horário';
	@override String get detailOffsetUtc => 'Diferença para o UTC';
	@override String get detailOffsetHome => 'Diferença para a sua base';
	@override String get actionSetHome => 'Definir como base';
	@override String get actionRemove => 'Remover do painel';
	@override String get actionOpenInGrid => 'Abrir na grade';
}

// Path: planner
class _Translations$planner$pt_BR implements Translations$planner$en {
	_Translations$planner$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get modeCompare => 'Comparar';
	@override String get modePlan => 'Planejar';
	@override String get selectHint => 'Arraste sobre as horas para escolher uma janela, e o horário local de cada cidade aparece abaixo.';
	@override String durationLabel({required Object duration}) => 'Dura ${duration}';
	@override String get verdictGood => 'Funciona bem';
	@override String get verdictFair => 'Dá, mas no limite';
	@override String get verdictPoor => 'Horário ruim aqui';
	@override String get suggestionTitle => 'Uma janela melhor';
	@override String get suggestionApply => 'Usar esta janela';
	@override String get noSuggestion => 'Não há janela melhor hoje: em qualquer horário alguém fica de fora.';
	@override String get copyCompact => 'Resumido';
	@override String get copyVerbose => 'Detalhado';
	@override String get copied => 'Copiado para a área de transferência';
	@override String get crossesDst => 'O relógio muda dentro desta janela, então ela não dura o que as colunas sugerem.';
	@override String get dayTomorrow => 'Amanhã';
	@override String get dayYesterday => 'Ontem';
	@override String get summaryTitle => 'Sua reunião';
}

// Path: converter
class _Translations$converter$pt_BR implements Translations$converter$en {
	_Translations$converter$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Conversor de horários';
	@override String get sourceLabel => 'Cidade de origem';
	@override String get dateLabel => 'Data';
	@override String get timeLabel => 'Hora';
	@override String get resultTitle => 'Nas outras cidades';
	@override String shiftedForwardNotice({required Object requested, required Object shown}) => '${requested} não existe nesta data, então estamos mostrando ${shown}.';
	@override String ambiguousNotice({required Object zone}) => 'O relógio atrasa em ${zone} nesta data, então esse horário acontece duas vezes.';
	@override String get ambiguousFirst => 'Primeira ocorrência';
	@override String get ambiguousSecond => 'Segunda ocorrência';
	@override String get resetToNow => 'Voltar para agora';
	@override String get copy => 'Copiar';
	@override String get copied => 'Copiado para a área de transferência';
	@override String outOfRange({required Object years}) => 'Só convertemos até ${years} anos a partir de hoje. Depois disso, as regras ainda são um palpite.';
	@override String get needMoreCities => 'Adicione outra cidade para ver este momento em outro lugar.';
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
			'auth.onboardingTitle1' => 'Todas as cidades num painel só',
			'auth.onboardingBody1' => 'Coloque lado a lado os lugares com que você trabalha e veja o mesmo momento em todos eles.',
			'auth.onboardingTitle2' => 'Saiba a hora certa de chamar',
			'auth.onboardingBody2' => 'O horário de trabalho fica destacado na grade, então achar um horário bom para todo mundo é questão de olhar, não de calcular.',
			'auth.onboardingTitle3' => 'O mesmo painel em qualquer lugar',
			'auth.onboardingBody3' => 'Entre com o Google e suas cidades vão junto do celular para o navegador.',
			'auth.onboardingSkip' => 'Pular',
			'auth.onboardingNext' => 'Avançar',
			'auth.onboardingSkipHint' => 'Pule a apresentação e vá direto para a entrada.',
			'auth.signInWithGoogle' => 'Entrar com o Google',
			'auth.signInFailed' => 'Não conseguimos entrar. Tente de novo.',
			'auth.signInCancelled' => 'Você cancelou a entrada.',
			'auth.signInStorageBlocked' => 'Este navegador está bloqueando o armazenamento necessário para entrar. Libere os cookies de terceiros para este site, ou permita pop-ups, e tente de novo.',
			'auth.signInPopupBlocked' => 'A janela de entrada foi bloqueada. Permita pop-ups para este site e tente entrar de novo.',
			'auth.signOut' => 'Sair da conta',
			'auth.signOutConfirm' => 'Sair da conta?',
			'auth.signOutConfirmBody' => 'Suas cidades continuam na sua conta. A cópia guardada neste aparelho é apagada até você entrar de novo.',
			'auth.signOutFailed' => 'Não conseguimos sair da conta. Tente de novo.',
			'auth.deleteAccount' => 'Excluir conta',
			'auth.deleteAccountConfirm' => 'Excluir sua conta?',
			'auth.deleteAccountWarning' => 'Isso apaga seu painel, suas preferências e seu perfil de todos os aparelhos. Não dá para desfazer.',
			'auth.deleteAccountFailed' => 'Não conseguimos excluir sua conta. Tente de novo.',
			'profile.title' => 'Conta',
			'profile.signedInAs' => 'Você entrou como',
			'profile.syncStatusIdle' => 'Tudo sincronizado',
			'profile.syncStatusSyncing' => 'Sincronizando...',
			'profile.syncStatusOffline' => 'Sem conexão. Suas mudanças ficam salvas neste aparelho.',
			'profile.syncStatusError' => 'A sincronização não rolou. Suas mudanças estão salvas neste aparelho.',
			'profile.syncNow' => 'Sincronizar agora',
			'profile.lastSynced' => ({required Object time}) => 'Última sincronização ${time}',
			'profile.neverSynced' => 'Ainda não sincronizou',
			'profile.boardUpdatedFromAnotherDevice' => 'Seu painel foi atualizado em outro aparelho.',
			'profile.preferencesUpdatedFromAnotherDevice' => 'Suas configurações foram atualizadas em outro aparelho.',
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
			'nav.clocks' => 'Relógios',
			'nav.converter' => 'Conversor',
			'nav.locations' => 'Cidades',
			'nav.settings' => 'Configurações',
			'nav.profile' => 'Conta',
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
			'worldClock.title' => 'Relógio mundial',
			'worldClock.sameTime' => 'Mesmo horário',
			'worldClock.tomorrow' => 'Amanhã',
			'worldClock.yesterday' => 'Ontem',
			'worldClock.dstActive' => 'Horário de verão em vigor',
			'worldClock.nextTransition' => ({required Object date}) => 'O relógio daqui muda em ${date}',
			'worldClock.emptyTitle' => 'Por enquanto, só o seu relógio',
			'worldClock.emptyMessage' => 'Adicione uma cidade e o relógio dela passa a correr logo abaixo do seu.',
			'worldClock.emptyCta' => 'Adicionar cidade',
			'worldClock.detailZoneId' => 'Id do fuso horário',
			'worldClock.detailOffsetUtc' => 'Diferença para o UTC',
			'worldClock.detailOffsetHome' => 'Diferença para a sua base',
			'worldClock.actionSetHome' => 'Definir como base',
			'worldClock.actionRemove' => 'Remover do painel',
			'worldClock.actionOpenInGrid' => 'Abrir na grade',
			'planner.modeCompare' => 'Comparar',
			'planner.modePlan' => 'Planejar',
			'planner.selectHint' => 'Arraste sobre as horas para escolher uma janela, e o horário local de cada cidade aparece abaixo.',
			'planner.durationLabel' => ({required Object duration}) => 'Dura ${duration}',
			'planner.verdictGood' => 'Funciona bem',
			'planner.verdictFair' => 'Dá, mas no limite',
			'planner.verdictPoor' => 'Horário ruim aqui',
			'planner.suggestionTitle' => 'Uma janela melhor',
			'planner.suggestionApply' => 'Usar esta janela',
			'planner.noSuggestion' => 'Não há janela melhor hoje: em qualquer horário alguém fica de fora.',
			'planner.copyCompact' => 'Resumido',
			'planner.copyVerbose' => 'Detalhado',
			'planner.copied' => 'Copiado para a área de transferência',
			'planner.crossesDst' => 'O relógio muda dentro desta janela, então ela não dura o que as colunas sugerem.',
			'planner.dayTomorrow' => 'Amanhã',
			'planner.dayYesterday' => 'Ontem',
			'planner.summaryTitle' => 'Sua reunião',
			'converter.title' => 'Conversor de horários',
			'converter.sourceLabel' => 'Cidade de origem',
			'converter.dateLabel' => 'Data',
			'converter.timeLabel' => 'Hora',
			'converter.resultTitle' => 'Nas outras cidades',
			'converter.shiftedForwardNotice' => ({required Object requested, required Object shown}) => '${requested} não existe nesta data, então estamos mostrando ${shown}.',
			'converter.ambiguousNotice' => ({required Object zone}) => 'O relógio atrasa em ${zone} nesta data, então esse horário acontece duas vezes.',
			'converter.ambiguousFirst' => 'Primeira ocorrência',
			'converter.ambiguousSecond' => 'Segunda ocorrência',
			'converter.resetToNow' => 'Voltar para agora',
			'converter.copy' => 'Copiar',
			'converter.copied' => 'Copiado para a área de transferência',
			'converter.outOfRange' => ({required Object years}) => 'Só convertemos até ${years} anos a partir de hoje. Depois disso, as regras ainda são um palpite.',
			'converter.needMoreCities' => 'Adicione outra cidade para ver este momento em outro lugar.',
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

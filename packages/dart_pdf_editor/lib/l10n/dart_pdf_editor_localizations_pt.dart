// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class DartPdfEditorLocalizationsPt extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get add => 'Adicionar';

  @override
  String get annotCaret => 'Marca de inserção';

  @override
  String get annotCircle => 'Círculo';

  @override
  String get annotFileAttachment => 'Anexo de arquivo';

  @override
  String get annotFreeText => 'Caixa de texto';

  @override
  String get annotHighlight => 'Destaque';

  @override
  String get annotInk => 'Traço à mão livre';

  @override
  String get annotLine => 'Linha';

  @override
  String get annotLink => 'Link';

  @override
  String get annotPolygon => 'Polígono';

  @override
  String get annotPolyline => 'Polilinha';

  @override
  String get annotRedact => 'Tarja';

  @override
  String get annotSquare => 'Quadrado';

  @override
  String get annotSquiggly => 'Ondulado';

  @override
  String get annotStamp => 'Carimbo';

  @override
  String get annotStrikeOut => 'Tachado';

  @override
  String get annotText => 'Nota';

  @override
  String get annotUnderline => 'Sublinhado';

  @override
  String get annotWidget => 'Campo de formulário';

  @override
  String get apply => 'Aplicar';

  @override
  String get bookmarkAdd => 'Adicionar marcador';

  @override
  String get bookmarkAddChild => 'Adicionar submarcador';

  @override
  String get bookmarkCollapse => 'Recolher';

  @override
  String get bookmarkDelete => 'Excluir marcador';

  @override
  String get bookmarkEdit => 'Editar marcador';

  @override
  String get bookmarkEmpty => 'Nenhum marcador';

  @override
  String get bookmarkExpand => 'Expandir';

  @override
  String get bookmarkExpandedByDefault => 'Expandido por padrão';

  @override
  String get bookmarkNoDestination => 'Sem destino';

  @override
  String get bookmarkPageFieldLabel => 'Página';

  @override
  String bookmarkPageLabel(int number) {
    return 'Página $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Marcadores';

  @override
  String get bookmarkTitleLabel => 'Título';

  @override
  String get bookmarkUntitled => 'Sem título';

  @override
  String get cancel => 'Cancelar';

  @override
  String get clear => 'Limpar';

  @override
  String get close => 'Fechar';

  @override
  String get colorApplyingChanges => 'Aplicando alterações de cor…';

  @override
  String get colorColorFormat => 'Formato de cor';

  @override
  String get colorColorTitle => 'Cor';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cores selecionadas',
      one: '$count cor selecionada',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Cores do documento';

  @override
  String get colorFillColors => 'Cores de preenchimento';

  @override
  String get colorFind => 'Localizar';

  @override
  String get colorInDocument => 'No documento';

  @override
  String get colorNoColorsFound => 'Nenhuma cor encontrada ainda';

  @override
  String get colorNoPageContentColors =>
      'Nenhuma cor de conteúdo de página encontrada';

  @override
  String get colorPalette => 'Paleta';

  @override
  String get colorPickColor => 'Selecionar cor';

  @override
  String get colorProcessingTitle => 'Processamento de cores';

  @override
  String get colorRecent => 'Recentes';

  @override
  String get colorReplace => 'Substituir';

  @override
  String get colorReplaceWithTransparent => 'Substituir por transparente';

  @override
  String get colorScanning => 'Analisando…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Analisando $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Páginas selecionadas ($count)';
  }

  @override
  String get colorStrokeColors => 'Cores de traço';

  @override
  String get colorTolerance => 'Tolerância';

  @override
  String get colorTransparent => 'Transparente';

  @override
  String get colorWholeDocument => 'Documento inteiro';

  @override
  String get compareAfter => 'Depois';

  @override
  String get compareBefore => 'Antes';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alterações',
      one: '1 alteração',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alterações',
      one: '1 alteração',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(vazio)';

  @override
  String get compareNextChange => 'Próxima alteração';

  @override
  String get compareNoChanges => 'Nenhuma alteração';

  @override
  String get compareNoDifferences =>
      'Nenhuma diferença entre os dois documentos';

  @override
  String get compareOverlay => 'Sobreposição';

  @override
  String comparePageHeader(int page) {
    return 'Página $page';
  }

  @override
  String get comparePreviousChange => 'Alteração anterior';

  @override
  String get compareSideBySide => 'Lado a lado';

  @override
  String get copy => 'Copiar';

  @override
  String get cut => 'Recortar';

  @override
  String get delete => 'Excluir';

  @override
  String get done => 'Concluído';

  @override
  String get edit => 'Editar';

  @override
  String get editorViewAuthorNameTitle => 'Nome do autor';

  @override
  String get lineStyleDashDot => 'Traço-ponto';

  @override
  String get lineStyleDashed => 'Tracejado';

  @override
  String get lineStyleDotted => 'Pontilhado';

  @override
  String get lineStyleSolid => 'Sólido';

  @override
  String get measCalibrate => 'Calibrar';

  @override
  String get measCalibrateScale => 'Calibrar escala';

  @override
  String get measDepthLabel => 'Profundidade: ';

  @override
  String get measKindAngle => 'Ângulo';

  @override
  String get measKindArc => 'Arco';

  @override
  String get measKindArea => 'Área';

  @override
  String get measKindCount => 'Contagem';

  @override
  String get measKindLength => 'Comprimento';

  @override
  String get measKindNetArea => 'Área líquida';

  @override
  String get measKindPerimeter => 'Perímetro';

  @override
  String get measKindSlope => 'Inclinação';

  @override
  String get measKindVolume => 'Volume';

  @override
  String get measLineRepresents => 'A linha que você desenhou representa:';

  @override
  String get measMeasure => 'Medir';

  @override
  String get measSetScale => 'Definir escala de medição';

  @override
  String get measSetScaleButton => 'Definir escala';

  @override
  String get measVolumeDepth => 'Profundidade do volume';

  @override
  String get menuAddNode => 'Adicionar nó';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aplicar anotações às páginas',
      one: 'Aplicar anotação às páginas',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Aplicar às páginas…';

  @override
  String get menuBringToFront => 'Trazer para a frente';

  @override
  String get menuCheck => 'Marcar';

  @override
  String get menuChooseValue => 'Escolher valor…';

  @override
  String get menuClearCheck => 'Desmarcar';

  @override
  String get menuConvertToCheckBox => 'Converter em caixa de seleção';

  @override
  String get menuConvertToImageButton => 'Converter em botão de imagem';

  @override
  String get menuConvertToTextField => 'Converter em campo de texto';

  @override
  String get menuDeleteField => 'Excluir campo';

  @override
  String get menuEditValue => 'Editar valor…';

  @override
  String get menuFieldName => 'Nome do campo';

  @override
  String get menuFieldValue => 'Valor do campo';

  @override
  String get menuFlattenForm => 'Achatar formulário';

  @override
  String get menuLock => 'Bloquear';

  @override
  String get menuUnlock => 'Desbloquear';

  @override
  String get menuRecolour => 'Recolorir…';

  @override
  String get menuRemoveNode => 'Remover nó';

  @override
  String get menuSaveToStamps => 'Salvar nos carimbos';

  @override
  String get menuSetAsDefaultStyle => 'Definir como estilo padrão';

  @override
  String get menuRename => 'Renomear…';

  @override
  String get menuSelectOption => 'Selecionar opção';

  @override
  String get menuSendToBack => 'Enviar para trás';

  @override
  String get menuSetImage => 'Definir imagem…';

  @override
  String get menuTextStyle => 'Estilo de texto…';

  @override
  String get none => 'Nenhum';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Cor';

  @override
  String get overlayEditText => 'Editar texto';

  @override
  String get overlayFont => 'Fonte';

  @override
  String get overlayLarger => 'Maior';

  @override
  String get overlayMore => 'Mais';

  @override
  String get overlayNote => 'Nota';

  @override
  String get overlaySmaller => 'Menor';

  @override
  String get overlayStampText => 'Texto do carimbo';

  @override
  String get linkDialogTitle => 'Adicionar link';

  @override
  String get linkKindWeb => 'Endereço da Web';

  @override
  String get linkKindPage => 'Página no documento';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Número da página';

  @override
  String get toolLink => 'Link';

  @override
  String get overlayUnderline => 'Sublinhado';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Insira páginas entre 1 e $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'A última página não pode ser anterior à primeira.';

  @override
  String get pageRangeFrom => 'De';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Até';

  @override
  String get panelDragToMovePanel => 'Arraste para mover o painel';

  @override
  String get paste => 'Colar';

  @override
  String get propAlign => 'Alinhar';

  @override
  String get propAlignCenter => 'Centralizar';

  @override
  String get propAlignLeft => 'Alinhar à esquerda';

  @override
  String get propAlignRight => 'Alinhar à direita';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anotações',
      one: '$count anotação',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Autor';

  @override
  String get propAutoSize => 'Ajuste automático';

  @override
  String get propBold => 'Negrito';

  @override
  String get propBoldLetter => 'N';

  @override
  String get propBundledFont => 'Fonte incluída';

  @override
  String get propCallout => 'Chamada';

  @override
  String get propCharSpacing => 'Espaçamento entre caracteres';

  @override
  String get propColor => 'Cor';

  @override
  String get propColour => 'Cor';

  @override
  String get propContents => 'Conteúdo';

  @override
  String get propCornerRadius => 'Raio do canto';

  @override
  String get propEditsApplyToAll =>
      'As edições se aplicam a todas as anotações compatíveis';

  @override
  String get propFieldName => 'Nome do campo';

  @override
  String get propFieldTypeCheckBox => 'Caixa de seleção';

  @override
  String get propFieldTypeComboBox => 'Caixa de combinação';

  @override
  String get propFieldTypeImageButton => 'Botão de imagem';

  @override
  String get propFieldTypeListBox => 'Caixa de lista';

  @override
  String get propFieldTypeRadioGroup => 'Grupo de opções';

  @override
  String get propFieldTypeSignature => 'Assinatura';

  @override
  String get propFieldTypeText => 'Campo de texto';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Tipo de campo: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Campo desconhecido';

  @override
  String get propFill => 'Preenchimento';

  @override
  String get propFont => 'Fonte';

  @override
  String get propFontSubsetTooltip =>
      'Esta fonte é um subconjunto - apenas os caracteres já usados no documento podem ser digitados.';

  @override
  String get propFontWidth => 'Largura da fonte';

  @override
  String get propGeometryHeight => 'A';

  @override
  String get propGeometryWidth => 'L';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Itálico';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Caracteres limitados';

  @override
  String get propLineEnd => 'Fim da linha';

  @override
  String get propLineEndingButt => 'Reto';

  @override
  String get propLineEndingCircle => 'Círculo';

  @override
  String get propLineEndingClosedArrow => 'Seta fechada';

  @override
  String get propLineEndingClosedArrowRev => 'Seta fechada (inv.)';

  @override
  String get propLineEndingDiamond => 'Losango';

  @override
  String get propLineEndingOpenArrow => 'Seta aberta';

  @override
  String get propLineEndingOpenArrowRev => 'Seta aberta (inv.)';

  @override
  String get propLineEndingSlash => 'Barra';

  @override
  String get propLineEndingSquare => 'Quadrado';

  @override
  String get propLineSpacing => 'Espaçamento entre linhas';

  @override
  String get propLineStart => 'Início da linha';

  @override
  String get propLineType => 'Tipo de linha';

  @override
  String get propLoadFont => 'Carregar fonte…';

  @override
  String get propLoadFontSubtitle => 'Arquivo TTF ou OTF';

  @override
  String get propMoreColors => 'Mais cores…';

  @override
  String get propMultiline => 'Múltiplas linhas';

  @override
  String get propNoFill => 'Sem preenchimento';

  @override
  String get propNoFontsFound => 'Nenhuma fonte encontrada';

  @override
  String get propNoOutline => 'Sem contorno';

  @override
  String get propOpacity => 'Opacidade';

  @override
  String get propOutline => 'Contorno';

  @override
  String get propPageLabel => 'Página';

  @override
  String propPageNumber(int number) {
    return 'Página $number';
  }

  @override
  String get propPropertiesTitle => 'Propriedades';

  @override
  String get propRecentlyUsed => 'Usadas recentemente';

  @override
  String get propScale => 'Escala';

  @override
  String get propSearchFonts => 'Pesquisar fontes';

  @override
  String get propSectionAllFonts => 'Todas as fontes';

  @override
  String get propSectionAppearance => 'Aparência';

  @override
  String get propSectionContent => 'Conteúdo';

  @override
  String get propSectionFormField => 'Campo de formulário';

  @override
  String get propSectionInThisDocument => 'Neste documento';

  @override
  String get propSectionPositionSize => 'Posição e tamanho (pt)';

  @override
  String get propSectionSelection => 'Seleção';

  @override
  String get propSectionText => 'Texto';

  @override
  String get propSelectAnnotationPrompt =>
      'Selecione uma anotação para ver suas propriedades';

  @override
  String get propSize => 'Tamanho';

  @override
  String get propStandardPdfFont => 'Fonte PDF padrão';

  @override
  String get propStroke => 'Traço';

  @override
  String get propStyle => 'Estilo';

  @override
  String get propSystemFont => 'Fonte do sistema';

  @override
  String get propType => 'Tipo';

  @override
  String get propUnderline => 'Sublinhado';

  @override
  String get propVaries => 'Varia';

  @override
  String get redo => 'Refazer';

  @override
  String get reflowNoContent => 'Nenhum conteúdo extraível';

  @override
  String reflowPageLabel(int number) {
    return 'Página $number';
  }

  @override
  String get reflowSaveOrShare => 'Salvar ou compartilhar';

  @override
  String get reflowViewFigure => 'Ver figura';

  @override
  String get remove => 'Remover';

  @override
  String get rename => 'Renomear';

  @override
  String get reset => 'Redefinir';

  @override
  String get save => 'Salvar';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Página $page';
  }

  @override
  String get sbarCallout => 'Chamada';

  @override
  String get sbarFieldButton => 'Campo de botão';

  @override
  String get sbarFieldChoice => 'Campo de escolha';

  @override
  String get sbarFieldGeneric => 'Campo de formulário';

  @override
  String get sbarFieldSignature => 'Campo de assinatura';

  @override
  String get sbarFieldText => 'Campo de texto';

  @override
  String get sbarStateAccepted => 'Aceito';

  @override
  String get sbarStateCancelled => 'Cancelado';

  @override
  String get sbarStateMarked => 'Marcado';

  @override
  String get sbarStateRejected => 'Rejeitado';

  @override
  String get sbarStateResolved => 'Resolvido';

  @override
  String get sbarStateUnmarked => 'Desmarcado';

  @override
  String get searchAnnotations => 'Pesquisar anotações';

  @override
  String get searchClearSearch => 'Limpar pesquisa';

  @override
  String get searchEmptyHint =>
      'Pesquise no documento para listar todas as ocorrências aqui';

  @override
  String get searchMatchCase => 'Diferenciar maiúsculas de minúsculas';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ocorrências',
      one: '1 ocorrência',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Próxima ocorrência';

  @override
  String searchNoMatches(String query) {
    return 'Nenhuma ocorrência para “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Página $page';
  }

  @override
  String get searchPreviousMatch => 'Ocorrência anterior';

  @override
  String get searchRegex => 'Expressão regular';

  @override
  String get searchReplace => 'Substituir';

  @override
  String get searchReplaceAll => 'Substituir tudo';

  @override
  String get searchReplaceHint => 'Substituir por';

  @override
  String get searchReplaceNotTargetable =>
      'Essa ocorrência não pode ser substituída isoladamente — use Substituir tudo ou edite-a com a ferramenta de conteúdo';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ocorrências substituídas',
      one: '1 ocorrência substituída',
      zero: 'Nada substituído',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => 'Resultados da pesquisa';

  @override
  String get searchWholeWord => 'Palavra inteira';

  @override
  String get shellControls => 'Controles';

  @override
  String get shellDefaultAuthor => 'Autor padrão…';

  @override
  String get shellHighlightFormFields => 'Destacar campos de formulário';

  @override
  String get shellKeyboardShortcutsMenu => 'Atalhos de teclado…';

  @override
  String get shellKeyboardShortcutsTitle => 'Atalhos de teclado';

  @override
  String get shellShortcutsSearchHint => 'Pesquisar atalhos';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Nenhum atalho corresponde a “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Selecionar';

  @override
  String get shellShortcutGroupMarkup => 'Marcação';

  @override
  String get shellShortcutGroupDraw => 'Desenhar';

  @override
  String get shellShortcutGroupShapes => 'Formas';

  @override
  String get shellShortcutGroupInsert => 'Inserir';

  @override
  String get shellShortcutGroupMeasure => 'Medir';

  @override
  String get shellShortcutGroupEdit => 'Editar';

  @override
  String get shellNotSet => 'Não definido';

  @override
  String get shellPageColor => 'Cor da página…';

  @override
  String get shellPageGrid => 'Grade de páginas';

  @override
  String get shellPanelAnnotations => 'Anotações';

  @override
  String get shellPanelBookmarks => 'Marcadores';

  @override
  String get shellPanelPages => 'Páginas';

  @override
  String get shellPanelProperties => 'Propriedades';

  @override
  String get shellPanelSearchResults => 'Resultados da pesquisa';

  @override
  String get shellPanels => 'Painéis';

  @override
  String get shellPressAKey => 'Pressione uma tecla';

  @override
  String get shellPressLetterKeyHint =>
      'Pressione uma tecla de letra ou Delete para limpar.';

  @override
  String get shellReflow => 'Refluxo';

  @override
  String get shellReflowText => 'Refluir texto';

  @override
  String get shellResetZoom => 'Redefinir zoom';

  @override
  String get shellSectionShell => 'Interface';

  @override
  String get shellSectionView => 'Exibição';

  @override
  String get shellSettings => 'Configurações';

  @override
  String get shellShowAnnotations => 'Mostrar anotações';

  @override
  String get shellShowScrollbarChapters =>
      'Mostrar capítulos na barra de rolagem';

  @override
  String get shellTabHere => 'Agrupar em aba aqui';

  @override
  String get shellUnbound => 'Não vinculado';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'por $author';
  }

  @override
  String get sidebarCancelSelection => 'Cancelar seleção';

  @override
  String get sidebarClearSearch => 'Limpar pesquisa';

  @override
  String get sidebarDeleteSelected => 'Excluir selecionadas';

  @override
  String get sidebarDeleteSignature => 'Excluir assinatura';

  @override
  String get sidebarLockAnnotation => 'Bloquear';

  @override
  String get sidebarUnlockAnnotation => 'Desbloquear';

  @override
  String get sidebarMore => 'Mais';

  @override
  String get sidebarNoAnnotations => 'Nenhuma anotação';

  @override
  String get sidebarNoMatchingAnnotations => 'Nenhuma anotação correspondente';

  @override
  String sidebarPageHeader(int number) {
    return 'Página $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Isso remove a assinatura digital do documento. Você pode desfazer.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Isso remove a assinatura digital de \"$name\" do documento. Você pode desfazer.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Remover assinatura?';

  @override
  String get sidebarReopen => 'Reabrir';

  @override
  String get sidebarReply => 'Responder';

  @override
  String get sidebarResolve => 'Resolver';

  @override
  String get sidebarSearchHint => 'Pesquisar anotações';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selecionadas',
      one: '$count selecionada',
    );
    return '$_temp0';
  }

  @override
  String get sidebarSignatureChecking => 'Checking…';

  @override
  String get sidebarSignatureTrusted => 'Valid — trusted';

  @override
  String get sidebarSignatureUnverified => 'Valid — unverified';

  @override
  String get sidebarSignatureInvalid => 'Invalid';

  @override
  String sidebarSignatureSignedBy(String name) {
    return 'Signed by $name';
  }

  @override
  String sidebarSignatureSignedAt(String time) {
    return 'Signed $time';
  }

  @override
  String sidebarSignatureTrustedVia(String authority) {
    return 'Trusted via $authority';
  }

  @override
  String get sidebarSignatureUntrustedDetail =>
      'Signer is not from a trusted authority';

  @override
  String get sidebarSignatureNoAnchors =>
      'No trusted authorities are configured';

  @override
  String get sidebarSignatureModified => 'Document was changed after signing';

  @override
  String get sidebarSignatureRevoked => 'The signer\'s certificate was revoked';

  @override
  String sidebarSignatureTimestamped(String time) {
    return 'Timestamped $time';
  }

  @override
  String sidebarSignatureLevel(String level) {
    return 'PAdES $level';
  }

  @override
  String get sidebarWriteReplyHint => 'Escrever uma resposta…';

  @override
  String get sigTitle => 'Assinatura';

  @override
  String get signIdCreate => 'Criar';

  @override
  String get signIdEmail => 'E-mail (opcional)';

  @override
  String get signIdName => 'Nome';

  @override
  String get signIdNameHint => 'Seu nome, como deve aparecer na assinatura';

  @override
  String get signIdNameRequired => 'Insira um nome';

  @override
  String get signIdOrganization => 'Organização (opcional)';

  @override
  String get signIdSelfSignedInfo =>
      'Isso cria uma identidade autoassinada. As assinaturas aparecerão como \"assinado, validade desconhecida\" no Adobe Acrobat e em outros leitores - o mesmo que ocorre com os próprios IDs autoassinados deles. O selo verde de verificação exige uma CA paga e publicamente confiável.';

  @override
  String get signIdTitle => 'Criar identidade de assinatura';

  @override
  String get stampBox => 'Retângulo';

  @override
  String get stampCircle => 'Círculo';

  @override
  String get stampCustomCaption => 'Carimbo personalizado';

  @override
  String get stampDateFormat => 'Formato de data';

  @override
  String get stampDeleteComponent => 'Excluir componente selecionado';

  @override
  String get stampDeleteStamp => 'Excluir carimbo';

  @override
  String get stampEditStamp => 'Editar carimbo';

  @override
  String get stampExport => 'Exportar…';

  @override
  String get stampFieldDate => 'Data';

  @override
  String get stampFieldDateTime => 'Data e hora';

  @override
  String get stampFieldTime => 'Hora';

  @override
  String get stampFieldUsername => 'Nome de usuário';

  @override
  String get stampFont => 'Fonte';

  @override
  String get stampFontBold => 'Negrito';

  @override
  String get stampFontItalic => 'Itálico';

  @override
  String get stampHeight => 'Altura';

  @override
  String get stampImage => 'Imagem';

  @override
  String get stampImport => 'Importar…';

  @override
  String get stampInsertField => 'Inserir campo';

  @override
  String get stampMoreColors => 'Mais cores…';

  @override
  String get stampNewStamp => 'Novo carimbo…';

  @override
  String get stampNewStampTitle => 'Novo carimbo';

  @override
  String get stampSavedToCollection => 'Salvo nos carimbos';

  @override
  String get stampSelectTextToEdit => 'Selecione um texto para editar';

  @override
  String get stampSelectedText => 'Texto selecionado';

  @override
  String get stampSignature => 'Assinatura';

  @override
  String get stampStamps => 'Carimbos';

  @override
  String get stampText => 'Texto';

  @override
  String get stampTime12Hour => '12 h';

  @override
  String get stampTime24Hour => '24 h';

  @override
  String get stampTimeFormat => 'Formato de hora';

  @override
  String get stampWidth => 'Largura';

  @override
  String get takeoffArea => 'Área';

  @override
  String get takeoffCount => 'Contagem';

  @override
  String get takeoffEmpty => 'Nenhuma medição ainda.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grupos',
      one: '$count grupo',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Comprimento';

  @override
  String get takeoffTitle => 'Levantamento';

  @override
  String get tbAddInkAnnotation => 'Adicionar anotação de traço';

  @override
  String get tbAlign => 'Alinhar';

  @override
  String get tbAlignBottom => 'Alinhar embaixo';

  @override
  String get tbAlignHorizontalCenters => 'Alinhar centros horizontais';

  @override
  String get tbAlignLeft => 'Alinhar à esquerda';

  @override
  String get tbAlignRight => 'Alinhar à direita';

  @override
  String get tbAlignTop => 'Alinhar em cima';

  @override
  String get tbAlignVerticalCenters => 'Alinhar centros verticais';

  @override
  String get tbAnnotationsFlattened => 'Anotações achatadas nas páginas';

  @override
  String get tbApplyRedactionsMessage =>
      'O conteúdo marcado será removido permanentemente do documento. Isso não pode ser desfeito.';

  @override
  String get tbApplyRedactionsTitle => 'Aplicar tarjas?';

  @override
  String get tbApplyRedactionsTooltip => 'Aplicar tarjas (irreversível)';

  @override
  String get tbAutosizeTextBox =>
      'Ajustar caixa de texto automaticamente (Alt+Z)';

  @override
  String get tbAutosizeTextFont => 'Ajustar fonte à caixa de texto';

  @override
  String get tbCalibrateScaleHint =>
      'Desenhe uma linha de comprimento conhecido para calibrar a escala.';

  @override
  String get tbCharSpacing => 'Espaçamento entre caracteres';

  @override
  String get tbCheckBoxOption => 'Caixa de seleção';

  @override
  String get tbCheckMarksOnDocument => 'Marcas de contagem no documento';

  @override
  String get tbCropImage => 'Cortar imagem';

  @override
  String get tbCroppingImage => 'Cortando imagem';

  @override
  String get tbCropApply => 'Aplicar corte';

  @override
  String get tbCropCancel => 'Cancelar corte';

  @override
  String get tbCropReset => 'Redefinir corte';

  @override
  String get tbColorLabel => 'Cor';

  @override
  String get tbColorProcessingTooltip =>
      'Processamento de cores - localizar e substituir cores do conteúdo da página';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cores substituídas',
      one: '1 cor substituída',
      zero: 'Nenhuma cor correspondente encontrada',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Converter em caixa de seleção';

  @override
  String get tbConvertToImageButton => 'Converter em botão de imagem';

  @override
  String get tbConvertToTextField => 'Converter em campo de texto';

  @override
  String get tbCornerRadius => 'Raio do canto';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count anotações',
      one: 'Excluir anotação',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Excluir elemento';

  @override
  String get tbDeleteField => 'Excluir campo';

  @override
  String get tbDiscardDrawing => 'Descartar desenho';

  @override
  String get tbDistributeHorizontally => 'Distribuir horizontalmente';

  @override
  String get tbDistributeVertically => 'Distribuir verticalmente';

  @override
  String get tbDrawNewSignature => 'Desenhar uma nova assinatura…';

  @override
  String get tbEditAnnotationText => 'Editar texto da anotação';

  @override
  String get tbEditTextStyle => 'Editar texto e estilo';

  @override
  String get tbElement => 'Elemento';

  @override
  String get tbEraserSize => 'Tamanho da borracha';

  @override
  String get tbFieldActions => 'Ações do campo';

  @override
  String get tbFieldName => 'Nome do campo';

  @override
  String tbFieldNamed(String name) {
    return 'Campo: $name';
  }

  @override
  String get tbFieldValue => 'Valor do campo';

  @override
  String get tbFill => 'Preenchimento';

  @override
  String get tbFingerDraws => 'O dedo desenha - toque para que role a página';

  @override
  String get tbFingerScrolls =>
      'O dedo rola (a caneta desenha) - toque para que desenhe';

  @override
  String get tbFlattenAnnotationsTooltip => 'Achatar anotações nas páginas';

  @override
  String get tbFlattenForm => 'Achatar formulário';

  @override
  String get tbFlattenFormBakeValues =>
      'Achatar formulário - fixar os valores nas páginas';

  @override
  String get tbFlattenLabel => 'Achatar';

  @override
  String get tbFont => 'Fonte';

  @override
  String get tbFontSize => 'Tamanho da fonte';

  @override
  String get tbFontWidth => 'Largura da fonte';

  @override
  String get tbFormFieldsFlattened =>
      'Campos de formulário achatados nas páginas';

  @override
  String get tbGroupDraw => 'Desenhar';

  @override
  String get tbGroupEdit => 'Editar';

  @override
  String get tbGroupInsert => 'Inserir';

  @override
  String get tbGroupMarkup => 'Marcação';

  @override
  String get tbGroupMeasure => 'Medir';

  @override
  String get tbGroupSelect => 'Selecionar';

  @override
  String get tbGroupShapes => 'Formas';

  @override
  String get tbImageButtonOption => 'Botão de imagem';

  @override
  String get tbLineEnd => 'Fim da linha';

  @override
  String get tbLineSpacing => 'Espaçamento entre linhas';

  @override
  String get tbLineStart => 'Início da linha';

  @override
  String get tbLineType => 'Tipo de linha';

  @override
  String get tbManageStamps => 'Gerenciar carimbos…';

  @override
  String get tbMarkupHighlight => 'Destacar';

  @override
  String get tbMarkupHighlightTip => 'Destacar seleção';

  @override
  String get tbMarkupSquiggly => 'Sublinhado ondulado';

  @override
  String get tbMarkupSquigglyTip => 'Sublinhar seleção com ondulado';

  @override
  String get tbMarkupStrikeOut => 'Tachar';

  @override
  String get tbMarkupStrikeOutTip => 'Tachar seleção';

  @override
  String get tbMarkupUnderline => 'Sublinhar';

  @override
  String get tbMarkupUnderlineTip => 'Sublinhar seleção';

  @override
  String get tbMoreColors => 'Mais cores…';

  @override
  String get tbNameArrow => 'Seta';

  @override
  String get tbNameCallout => 'Chamada';

  @override
  String get tbNameCloudPolygon => 'Polígono em nuvem';

  @override
  String get tbNameCount => 'Contagem';

  @override
  String get tbNameDigitalSignature => 'Assinatura digital';

  @override
  String get tbNameDraw => 'Desenhar';

  @override
  String get tbNameEllipse => 'Elipse';

  @override
  String get tbNameEraser => 'Apagar traços';

  @override
  String get tbNameHand => 'Mão';

  @override
  String get tbNameHighlight => 'Destacar';

  @override
  String get tbNameImage => 'Imagem';

  @override
  String get tbNameLine => 'Linha';

  @override
  String get tbNameMeasureAngle => 'Medir ângulo';

  @override
  String get tbNameMeasureArc => 'Medir comprimento de arco';

  @override
  String get tbNameMeasureArea => 'Medir área';

  @override
  String get tbNameMeasureDistance => 'Medir distância';

  @override
  String get tbNameMeasurePerimeter => 'Medir perímetro';

  @override
  String get tbNameMeasureSlope => 'Medir inclinação (subida/avanço)';

  @override
  String get tbNameMeasureVolume => 'Medir volume (área × profundidade)';

  @override
  String get tbNameNote => 'Nota';

  @override
  String get tbNamePolygon => 'Polígono';

  @override
  String get tbNamePolyline => 'Polilinha';

  @override
  String get tbNameRectangle => 'Retângulo';

  @override
  String get tbNameSelect => 'Selecionar';

  @override
  String get tbNameSignature => 'Assinatura';

  @override
  String get tbNameStamp => 'Carimbo';

  @override
  String get tbNameTextBox => 'Caixa de texto';

  @override
  String get tbNewFieldType =>
      'Novo tipo de campo - arraste em uma página para adicionar um';

  @override
  String get tbNoAnnotationsToFlatten => 'Nenhuma anotação para achatar';

  @override
  String get tbNoCustomStamps => 'Nenhum carimbo personalizado';

  @override
  String get tbNoFormFieldsToFlatten =>
      'Nenhum campo de formulário para achatar';

  @override
  String get tbNoRedactionsToApply => 'Nenhuma tarja para aplicar';

  @override
  String get tbNoteTitle => 'Nota';

  @override
  String get tbOpacity => 'Opacidade';

  @override
  String get tbOutline => 'Contorno';

  @override
  String get tbPatternScale => 'Escala do padrão';

  @override
  String get tbPickColorFromPage => 'Selecionar uma cor da página';

  @override
  String get tbRedactionsApplied => 'Tarjas aplicadas';

  @override
  String get tbRedoShortcut => 'Refazer (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Não foi possível refluir - este não é um parágrafo de coluna única que esta ferramenta possa reajustar. Tente Substituir texto.';

  @override
  String get tbReflowParagraph => 'Refluir parágrafo';

  @override
  String get tbRenameField => 'Renomear campo';

  @override
  String get tbRenameFieldEllipsis => 'Renomear campo…';

  @override
  String get tbReplaceImage => 'Substituir imagem';

  @override
  String get tbReplaceImageFailed => 'Não foi possível substituir a imagem';

  @override
  String get tbReplaceText => 'Substituir texto';

  @override
  String get tbSaveImage => 'Salvar imagem';

  @override
  String get tbSaveShortcut => 'Salvar… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Escala';

  @override
  String get tbSelectTextForMarkup => 'Selecione um texto para usar a marcação';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selecionadas',
      one: 'Seleção',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Definir…';

  @override
  String get tbStamp => 'Carimbo';

  @override
  String get tbStampText => 'Texto do carimbo';

  @override
  String get tbStrokeOpacityFont => 'Traço, opacidade, fonte';

  @override
  String get tbStrokeWidthLabel => 'Largura do traço';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Traço $width';
  }

  @override
  String get tbStyle => 'Estilo';

  @override
  String get tbTakeoffTotals => 'Totais do levantamento';

  @override
  String get tbTextBorder => 'Borda do texto';

  @override
  String get tbTextColour => 'Cor do texto';

  @override
  String get tbTextFieldOption => 'Campo de texto';

  @override
  String get tbTextFill => 'Preenchimento do texto';

  @override
  String get tbTextStyleEllipsis => 'Estilo de texto…';

  @override
  String get tbTextTitle => 'Texto';

  @override
  String get tbTipCallout =>
      'Chamada - arraste do ponto até onde a caixa ficará';

  @override
  String get tbTipContent => 'Editar conteúdo da página';

  @override
  String get tbTipCount => 'Contagem - toque para inserir marcas e contá-las';

  @override
  String get tbTipDigitalSignature =>
      'Assinatura digital - arraste uma caixa para posicionar e assinar';

  @override
  String get tbTipForm =>
      'Campos de formulário - toque para selecionar, toque duas vezes para preencher, arraste para adicionar';

  @override
  String get tbTipHighlightDraw => 'Destaque - desenhe à mão livre';

  @override
  String get tbTipImage =>
      'Imagem - toque para posicionar ou arraste uma caixa';

  @override
  String get tbTipMeasureAngle => 'Medir ângulo - clique em três pontos';

  @override
  String get tbTipMeasureArc =>
      'Medir comprimento de arco - clique em três pontos';

  @override
  String get tbTipRedact => 'Tarjar - arraste uma região e depois aplique';

  @override
  String get tbTipSignature =>
      'Assinatura - toque em uma página para posicioná-la';

  @override
  String get tbTipSnapshot =>
      'Instantâneo - arraste uma região para capturá-la (cole de volta como vetor)';

  @override
  String get tbToolContent => 'Conteúdo';

  @override
  String get tbToolForm => 'Formulário';

  @override
  String get tbToolRedact => 'Tarjar';

  @override
  String get tbToolSnapshot => 'Instantâneo';

  @override
  String get tbTools => 'Ferramentas';

  @override
  String get tbTotals => 'Totais';

  @override
  String get tbTypeTextEachTime => 'Digitar texto a cada vez';

  @override
  String get tbUnderline => 'Sublinhado';

  @override
  String get tbUndoShortcut => 'Desfazer (⌘Z)';

  @override
  String get textStyleFont => 'Fonte';

  @override
  String get textStyleFontSize => 'Tamanho da fonte';

  @override
  String get textStyleKeep => 'manter';

  @override
  String get textStyleStyle => 'Estilo';

  @override
  String get textStyleText => 'Texto';

  @override
  String get textStyleTextFill => 'Preenchimento do texto';

  @override
  String get textStyleTitle => 'Editar texto e estilo';

  @override
  String get thumbAddPage => 'Adicionar página';

  @override
  String get thumbClearSelection => 'Limpar seleção';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copiar $count páginas',
      one: 'Copiar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Copiar páginas selecionadas';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recortar $count páginas',
      one: 'Recortar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Recortar páginas selecionadas';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count páginas',
      one: 'Excluir página',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Excluir páginas selecionadas';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Duplicar $count páginas',
      one: 'Duplicar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Exportar páginas…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exportar $count páginas…',
      one: 'Exportar página…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Exportar páginas selecionadas';

  @override
  String get thumbInsertBlankAfter => 'Inserir página em branco depois';

  @override
  String get thumbInsertBlankBefore => 'Inserir página em branco antes';

  @override
  String get thumbInsertFileFailed => 'Não foi possível inserir esse arquivo.';

  @override
  String get thumbInsertPdf => 'Inserir PDF…';

  @override
  String get thumbPageActions => 'Ações da página';

  @override
  String thumbPageNumber(int number) {
    return 'Página $number';
  }

  @override
  String get thumbPages => 'Páginas';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Colar $count páginas',
      one: 'Colar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Girar 180°';

  @override
  String get thumbRotateLeft => 'Girar à esquerda';

  @override
  String get thumbRotatePageRight => 'Girar página à direita';

  @override
  String get thumbRotateRight => 'Girar à direita';

  @override
  String get thumbRotateSelectedLeft => 'Girar páginas selecionadas à esquerda';

  @override
  String get thumbRotateSelectedRight => 'Girar páginas selecionadas à direita';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selecionadas',
      one: '$count selecionada',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Desfazer';

  @override
  String get viewerEditFontUnsafe =>
      'Esta fonte ou codificação de PDF não pode ser editada com segurança.';

  @override
  String get viewerEditNeedsSinglePage =>
      'A edição exige uma seleção em uma única página.';

  @override
  String get viewerEditNotEditableRun =>
      'Esta seleção não é um único trecho de texto editável do conteúdo da página.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Esta fonte de PDF pode ser redigitada, mas seu estilo não pode ser alterado.';

  @override
  String get viewerEditTextStyle => 'Editar texto e estilo';

  @override
  String get viewerMarkup => 'Marcação';

  @override
  String get viewerMarkupHighlight => 'Destacar';

  @override
  String get viewerMarkupSquiggly => 'Ondulado';

  @override
  String get viewerMarkupStrikeOut => 'Tachar';

  @override
  String get viewerMarkupUnderline => 'Sublinhar';

  @override
  String get viewerSelectAll => 'Selecionar tudo';

  @override
  String get annotationLibraryTitle => 'Biblioteca de anotações';

  @override
  String get annotationLibraryEmpty => 'Nenhuma anotação guardada.';

  @override
  String get annotationLibraryHelp =>
      'Selecione uma anotação compatível e escolha «Guardar na biblioteca de anotações» no respetivo menu. Não é possível guardar ligações nem campos de formulário.';

  @override
  String get annotationLibrarySave => 'Guardar na biblioteca de anotações';

  @override
  String get annotationLibrarySaveTitle => 'Guardar anotação';

  @override
  String get annotationLibraryRenameTitle =>
      'Mudar o nome do item da biblioteca';

  @override
  String get annotationLibrarySearchHint => 'Pesquisar na biblioteca';

  @override
  String get annotationLibraryNoMatches => 'Nenhuma anotação correspondente.';

  @override
  String get annotationLibraryUngrouped => 'Sem grupo';

  @override
  String get annotationLibraryChooseGroup => 'Mover para o grupo';

  @override
  String get annotationLibraryNewGroup => 'Novo grupo…';

  @override
  String get annotationLibraryGroupTitle => 'Novo grupo de anotações';

  @override
  String get annotationLibraryRenameGroupTitle => 'Renomear grupo de anotações';

  @override
  String get annotationLibraryRemoveGroup => 'Remover grupo';

  @override
  String get annotationLibraryPlacementHint =>
      'Clique na página para posicionar. Pressione Escape para cancelar.';

  @override
  String get annotationLibraryCustomStamps => 'Carimbos personalizados…';

  @override
  String get signatureLibraryManage => 'Gerir assinaturas';

  @override
  String get signatureLibraryRenameTitle => 'Mudar o nome da assinatura';

  @override
  String get signatureLibraryEmpty => 'Nenhuma assinatura guardada.';

  @override
  String get splitTitle => 'Dividir PDF…';

  @override
  String get splitHelp =>
      'Introduza intervalos de páginas separados por vírgulas. Cada intervalo cria um PDF separado.';

  @override
  String get splitRanges => 'Intervalos de páginas';

  @override
  String splitInvalidRanges(int count) {
    return 'Use páginas de 1 a $count, separadas por vírgulas. Os intervalos devem ser crescentes.';
  }

  @override
  String get splitConfirm => 'Dividir';

  @override
  String get splitFailed => 'Não foi possível dividir este PDF.';

  @override
  String get guidesSnapHint =>
      'Alinhar bordas e centros das anotações • Mantenha Alt pressionado para ignorar';
}

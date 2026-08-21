// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class DartPdfEditorLocalizationsIt extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get add => 'Aggiungi';

  @override
  String get annotCaret => 'Cursore';

  @override
  String get annotCircle => 'Cerchio';

  @override
  String get annotFileAttachment => 'Allegato';

  @override
  String get annotFreeText => 'Casella di testo';

  @override
  String get annotHighlight => 'Evidenziazione';

  @override
  String get annotInk => 'Inchiostro';

  @override
  String get annotLine => 'Linea';

  @override
  String get annotLink => 'Collegamento';

  @override
  String get annotPolygon => 'Poligono';

  @override
  String get annotPolyline => 'Polilinea';

  @override
  String get annotRedact => 'Oscuramento';

  @override
  String get annotSquare => 'Rettangolo';

  @override
  String get annotSquiggly => 'Ondulato';

  @override
  String get annotStamp => 'Timbro';

  @override
  String get annotStrikeOut => 'Barrato';

  @override
  String get annotText => 'Nota';

  @override
  String get annotUnderline => 'Sottolineatura';

  @override
  String get annotWidget => 'Campo modulo';

  @override
  String get apply => 'Applica';

  @override
  String get bookmarkAdd => 'Aggiungi segnalibro';

  @override
  String get bookmarkAddChild => 'Aggiungi segnalibro secondario';

  @override
  String get bookmarkCollapse => 'Comprimi';

  @override
  String get bookmarkDelete => 'Elimina segnalibro';

  @override
  String get bookmarkEdit => 'Modifica segnalibro';

  @override
  String get bookmarkEmpty => 'Nessun segnalibro';

  @override
  String get bookmarkExpand => 'Espandi';

  @override
  String get bookmarkExpandedByDefault =>
      'Espanso per impostazione predefinita';

  @override
  String get bookmarkNoDestination => 'Nessuna destinazione';

  @override
  String get bookmarkPageFieldLabel => 'Pagina';

  @override
  String bookmarkPageLabel(int number) {
    return 'Pagina $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Segnalibri';

  @override
  String get bookmarkTitleLabel => 'Titolo';

  @override
  String get bookmarkUntitled => 'Senza titolo';

  @override
  String get cancel => 'Annulla';

  @override
  String get clear => 'Cancella';

  @override
  String get close => 'Chiudi';

  @override
  String get colorApplyingChanges => 'Applicazione delle modifiche di colore…';

  @override
  String get colorColorFormat => 'Formato colore';

  @override
  String get colorColorTitle => 'Colore';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count colori selezionati',
      one: '$count colore selezionato',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Colori del documento';

  @override
  String get colorFillColors => 'Colori di riempimento';

  @override
  String get colorFind => 'Trova';

  @override
  String get colorInDocument => 'Nel documento';

  @override
  String get colorNoColorsFound => 'Nessun colore ancora trovato';

  @override
  String get colorNoPageContentColors =>
      'Nessun colore del contenuto della pagina trovato';

  @override
  String get colorPalette => 'Tavolozza';

  @override
  String get colorPickColor => 'Scegli colore';

  @override
  String get colorProcessingTitle => 'Elaborazione colori';

  @override
  String get colorRecent => 'Recenti';

  @override
  String get colorReplace => 'Sostituisci';

  @override
  String get colorReplaceWithTransparent => 'Sostituisci con trasparente';

  @override
  String get colorScanning => 'Scansione…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Scansione $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Pagine selezionate ($count)';
  }

  @override
  String get colorStrokeColors => 'Colori del tratto';

  @override
  String get colorTolerance => 'Tolleranza';

  @override
  String get colorTransparent => 'Trasparente';

  @override
  String get colorWholeDocument => 'Intero documento';

  @override
  String get compareAfter => 'Dopo';

  @override
  String get compareBefore => 'Prima';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifiche',
      one: '1 modifica',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifiche',
      one: '1 modifica',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(vuoto)';

  @override
  String get compareNextChange => 'Modifica successiva';

  @override
  String get compareNoChanges => 'Nessuna modifica';

  @override
  String get compareNoDifferences => 'Nessuna differenza tra i due documenti';

  @override
  String get compareOverlay => 'Sovrapposizione';

  @override
  String comparePageHeader(int page) {
    return 'Pagina $page';
  }

  @override
  String get comparePreviousChange => 'Modifica precedente';

  @override
  String get compareSideBySide => 'Affiancati';

  @override
  String get copy => 'Copia';

  @override
  String get cut => 'Taglia';

  @override
  String get delete => 'Elimina';

  @override
  String get done => 'Fatto';

  @override
  String get edit => 'Modifica';

  @override
  String get editorViewAuthorNameTitle => 'Nome dell\'autore';

  @override
  String get lineStyleDashDot => 'Tratto-punto';

  @override
  String get lineStyleDashed => 'Tratteggiata';

  @override
  String get lineStyleDotted => 'Punteggiata';

  @override
  String get lineStyleSolid => 'Continua';

  @override
  String get measCalibrate => 'Calibra';

  @override
  String get measCalibrateScale => 'Calibra scala';

  @override
  String get measDepthLabel => 'Profondità: ';

  @override
  String get measKindAngle => 'Angolo';

  @override
  String get measKindArc => 'Arco';

  @override
  String get measKindArea => 'Area';

  @override
  String get measKindCount => 'Conteggio';

  @override
  String get measKindLength => 'Lunghezza';

  @override
  String get measKindNetArea => 'Area netta';

  @override
  String get measKindPerimeter => 'Perimetro';

  @override
  String get measKindSlope => 'Pendenza';

  @override
  String get measKindVolume => 'Volume';

  @override
  String get measLineRepresents => 'La linea che hai disegnato rappresenta:';

  @override
  String get measMeasure => 'Misura';

  @override
  String get measSetScale => 'Imposta scala di misurazione';

  @override
  String get measSetScaleButton => 'Imposta scala';

  @override
  String get measVolumeDepth => 'Profondità del volume';

  @override
  String get menuAddNode => 'Aggiungi nodo';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Applica annotazioni alle pagine',
      one: 'Applica annotazione alle pagine',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Applica alle pagine…';

  @override
  String get menuBringToFront => 'Porta in primo piano';

  @override
  String get menuCheck => 'Seleziona';

  @override
  String get menuChooseValue => 'Scegli valore…';

  @override
  String get menuClearCheck => 'Deseleziona';

  @override
  String get menuConvertToCheckBox => 'Converti in casella di controllo';

  @override
  String get menuConvertToImageButton => 'Converti in pulsante immagine';

  @override
  String get menuConvertToTextField => 'Converti in campo di testo';

  @override
  String get menuDeleteField => 'Elimina campo';

  @override
  String get menuEditValue => 'Modifica valore…';

  @override
  String get menuFieldName => 'Nome del campo';

  @override
  String get menuFieldValue => 'Valore del campo';

  @override
  String get menuFlattenForm => 'Rendi definitivo il modulo';

  @override
  String get menuLock => 'Blocca';

  @override
  String get menuUnlock => 'Sblocca';

  @override
  String get menuRecolour => 'Ricolora…';

  @override
  String get menuRemoveNode => 'Rimuovi nodo';

  @override
  String get menuSaveToStamps => 'Salva nei timbri';

  @override
  String get menuSetAsDefaultStyle => 'Imposta come stile predefinito';

  @override
  String get menuRename => 'Rinomina…';

  @override
  String get menuSelectOption => 'Seleziona opzione';

  @override
  String get menuSendToBack => 'Porta in secondo piano';

  @override
  String get menuSetImage => 'Imposta immagine…';

  @override
  String get menuTextStyle => 'Stile del testo…';

  @override
  String get none => 'Nessuno';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Colore';

  @override
  String get overlayEditText => 'Modifica testo';

  @override
  String get overlayFont => 'Carattere';

  @override
  String get overlayLarger => 'Più grande';

  @override
  String get overlayMore => 'Altro';

  @override
  String get overlayNote => 'Nota';

  @override
  String get overlaySmaller => 'Più piccolo';

  @override
  String get overlayStampText => 'Testo del timbro';

  @override
  String get linkDialogTitle => 'Aggiungi link';

  @override
  String get linkKindWeb => 'Indirizzo web';

  @override
  String get linkKindPage => 'Pagina nel documento';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Numero di pagina';

  @override
  String get toolLink => 'Link';

  @override
  String get overlayUnderline => 'Sottolineato';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Inserisci pagine comprese tra 1 e $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'L\'ultima pagina non deve precedere la prima.';

  @override
  String get pageRangeFrom => 'Da';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'A';

  @override
  String get panelDragToMovePanel => 'Trascina per spostare il pannello';

  @override
  String get paste => 'Incolla';

  @override
  String get propAlign => 'Allinea';

  @override
  String get propAlignCenter => 'Allinea al centro';

  @override
  String get propAlignLeft => 'Allinea a sinistra';

  @override
  String get propAlignRight => 'Allinea a destra';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count annotazioni',
      one: '$count annotazione',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Autore';

  @override
  String get propAutoSize => 'Dimensione automatica';

  @override
  String get propBold => 'Grassetto';

  @override
  String get propBoldLetter => 'G';

  @override
  String get propBundledFont => 'Carattere incluso';

  @override
  String get propCallout => 'Didascalia';

  @override
  String get propCharSpacing => 'Spaziatura caratteri';

  @override
  String get propColor => 'Colore';

  @override
  String get propColour => 'Colore';

  @override
  String get propContents => 'Contenuto';

  @override
  String get propCornerRadius => 'Raggio angolo';

  @override
  String get propEditsApplyToAll =>
      'Le modifiche si applicano a tutte le annotazioni compatibili';

  @override
  String get propFieldName => 'Nome del campo';

  @override
  String get propFieldTypeCheckBox => 'Casella di controllo';

  @override
  String get propFieldTypeComboBox => 'Casella combinata';

  @override
  String get propFieldTypeImageButton => 'Pulsante immagine';

  @override
  String get propFieldTypeListBox => 'Casella di riepilogo';

  @override
  String get propFieldTypeRadioGroup => 'Gruppo di opzioni';

  @override
  String get propFieldTypeSignature => 'Firma';

  @override
  String get propFieldTypeText => 'Campo di testo';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Tipo di campo: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Campo sconosciuto';

  @override
  String get propFill => 'Riempimento';

  @override
  String get propFont => 'Carattere';

  @override
  String get propFontSubsetTooltip =>
      'Questo carattere è un subset - possono essere digitati solo i caratteri già usati nel documento.';

  @override
  String get propFontWidth => 'Larghezza carattere';

  @override
  String get propGeometryHeight => 'A';

  @override
  String get propGeometryWidth => 'L';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Corsivo';

  @override
  String get propItalicLetter => 'C';

  @override
  String get propLimitedCharacters => 'Caratteri limitati';

  @override
  String get propLineEnd => 'Fine linea';

  @override
  String get propLineEndingButt => 'Piatta';

  @override
  String get propLineEndingCircle => 'Cerchio';

  @override
  String get propLineEndingClosedArrow => 'Freccia chiusa';

  @override
  String get propLineEndingClosedArrowRev => 'Freccia chiusa (inv.)';

  @override
  String get propLineEndingDiamond => 'Rombo';

  @override
  String get propLineEndingOpenArrow => 'Freccia aperta';

  @override
  String get propLineEndingOpenArrowRev => 'Freccia aperta (inv.)';

  @override
  String get propLineEndingSlash => 'Barra';

  @override
  String get propLineEndingSquare => 'Quadrato';

  @override
  String get propLineSpacing => 'Interlinea';

  @override
  String get propLineStart => 'Inizio linea';

  @override
  String get propLineType => 'Tipo di linea';

  @override
  String get propLoadFont => 'Carica carattere…';

  @override
  String get propLoadFontSubtitle => 'File TTF o OTF';

  @override
  String get propMoreColors => 'Altri colori…';

  @override
  String get propMultiline => 'Multiriga';

  @override
  String get propNoFill => 'Nessun riempimento';

  @override
  String get propNoFontsFound => 'Nessun carattere trovato';

  @override
  String get propNoOutline => 'Nessun contorno';

  @override
  String get propOpacity => 'Opacità';

  @override
  String get propOutline => 'Contorno';

  @override
  String get propPageLabel => 'Pagina';

  @override
  String propPageNumber(int number) {
    return 'Pagina $number';
  }

  @override
  String get propPropertiesTitle => 'Proprietà';

  @override
  String get propRecentlyUsed => 'Usati di recente';

  @override
  String get propScale => 'Scala';

  @override
  String get propSearchFonts => 'Cerca caratteri';

  @override
  String get propSectionAllFonts => 'Tutti i caratteri';

  @override
  String get propSectionAppearance => 'Aspetto';

  @override
  String get propSectionContent => 'Contenuto';

  @override
  String get propSectionFormField => 'Campo modulo';

  @override
  String get propSectionInThisDocument => 'In questo documento';

  @override
  String get propSectionPositionSize => 'Posizione e dimensione (pt)';

  @override
  String get propSectionSelection => 'Selezione';

  @override
  String get propSectionText => 'Testo';

  @override
  String get propSelectAnnotationPrompt =>
      'Seleziona un\'annotazione per vederne le proprietà';

  @override
  String get propSize => 'Dimensione';

  @override
  String get propStandardPdfFont => 'Carattere PDF standard';

  @override
  String get propStroke => 'Tratto';

  @override
  String get propStyle => 'Stile';

  @override
  String get propSystemFont => 'Carattere di sistema';

  @override
  String get propType => 'Tipo';

  @override
  String get propUnderline => 'Sottolineato';

  @override
  String get propVaries => 'Variabile';

  @override
  String get redo => 'Ripeti';

  @override
  String get reflowNoContent => 'Nessun contenuto estraibile';

  @override
  String reflowPageLabel(int number) {
    return 'Pagina $number';
  }

  @override
  String get reflowSaveOrShare => 'Salva o condividi';

  @override
  String get reflowViewFigure => 'Visualizza figura';

  @override
  String get remove => 'Rimuovi';

  @override
  String get rename => 'Rinomina';

  @override
  String get reset => 'Reimposta';

  @override
  String get save => 'Salva';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Pagina $page';
  }

  @override
  String get sbarCallout => 'Didascalia';

  @override
  String get sbarFieldButton => 'Campo pulsante';

  @override
  String get sbarFieldChoice => 'Campo di scelta';

  @override
  String get sbarFieldGeneric => 'Campo modulo';

  @override
  String get sbarFieldSignature => 'Campo firma';

  @override
  String get sbarFieldText => 'Campo di testo';

  @override
  String get sbarStateAccepted => 'Accettato';

  @override
  String get sbarStateCancelled => 'Annullato';

  @override
  String get sbarStateMarked => 'Contrassegnato';

  @override
  String get sbarStateRejected => 'Rifiutato';

  @override
  String get sbarStateResolved => 'Risolto';

  @override
  String get sbarStateUnmarked => 'Non contrassegnato';

  @override
  String get searchAnnotations => 'Cerca annotazioni';

  @override
  String get searchClearSearch => 'Cancella ricerca';

  @override
  String get searchEmptyHint =>
      'Cerca nel documento per elencare qui ogni corrispondenza';

  @override
  String get searchMatchCase => 'Maiuscole/minuscole';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corrispondenze',
      one: '1 corrispondenza',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Corrispondenza successiva';

  @override
  String searchNoMatches(String query) {
    return 'Nessuna corrispondenza per “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Pagina $page';
  }

  @override
  String get searchPreviousMatch => 'Corrispondenza precedente';

  @override
  String get searchRegex => 'Espressione regolare';

  @override
  String get searchReplace => 'Sostituisci';

  @override
  String get searchReplaceAll => 'Sostituisci tutto';

  @override
  String get searchReplaceHint => 'Sostituisci con';

  @override
  String get searchReplaceNotTargetable =>
      'Questa corrispondenza non può essere sostituita da sola: usa «Sostituisci tutto» oppure modificala con lo strumento contenuto';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corrispondenze sostituite',
      one: '1 corrispondenza sostituita',
      zero: 'Nessuna sostituzione',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => 'Risultati della ricerca';

  @override
  String get searchWholeWord => 'Parola intera';

  @override
  String get shellControls => 'Controlli';

  @override
  String get shellDefaultAuthor => 'Autore predefinito…';

  @override
  String get shellHighlightFormFields => 'Evidenzia campi modulo';

  @override
  String get shellKeyboardShortcutsMenu => 'Scorciatoie da tastiera…';

  @override
  String get shellKeyboardShortcutsTitle => 'Scorciatoie da tastiera';

  @override
  String get shellShortcutsSearchHint => 'Cerca scorciatoie';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Nessuna scorciatoia corrisponde a “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Seleziona';

  @override
  String get shellShortcutGroupMarkup => 'Marcatura';

  @override
  String get shellShortcutGroupDraw => 'Disegna';

  @override
  String get shellShortcutGroupShapes => 'Forme';

  @override
  String get shellShortcutGroupInsert => 'Inserisci';

  @override
  String get shellShortcutGroupMeasure => 'Misura';

  @override
  String get shellShortcutGroupEdit => 'Modifica';

  @override
  String get shellNotSet => 'Non impostato';

  @override
  String get shellPageColor => 'Colore pagina…';

  @override
  String get shellPageGrid => 'Griglia pagine';

  @override
  String get shellPanelAnnotations => 'Annotazioni';

  @override
  String get shellPanelBookmarks => 'Segnalibri';

  @override
  String get shellPanelPages => 'Pagine';

  @override
  String get shellPanelProperties => 'Proprietà';

  @override
  String get shellPanelSearchResults => 'Risultati della ricerca';

  @override
  String get shellPanels => 'Pannelli';

  @override
  String get shellPressAKey => 'Premi un tasto';

  @override
  String get shellPressLetterKeyHint =>
      'Premi un tasto lettera, o Canc per cancellare.';

  @override
  String get shellReflow => 'Ridisposizione';

  @override
  String get shellReflowText => 'Ridisponi testo';

  @override
  String get shellResetZoom => 'Reimposta zoom';

  @override
  String get shellSectionShell => 'Interfaccia';

  @override
  String get shellSectionView => 'Vista';

  @override
  String get shellSettings => 'Impostazioni';

  @override
  String get shellShowAnnotations => 'Mostra annotazioni';

  @override
  String get shellShowScrollbarChapters =>
      'Mostra capitoli sulla barra di scorrimento';

  @override
  String get shellTabHere => 'Scheda qui';

  @override
  String get shellUnbound => 'Non assegnato';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'di $author';
  }

  @override
  String get sidebarCancelSelection => 'Annulla selezione';

  @override
  String get sidebarClearSearch => 'Cancella ricerca';

  @override
  String get sidebarDeleteSelected => 'Elimina selezionati';

  @override
  String get sidebarDeleteSignature => 'Elimina firma';

  @override
  String get sidebarLockAnnotation => 'Blocca';

  @override
  String get sidebarUnlockAnnotation => 'Sblocca';

  @override
  String get sidebarMore => 'Altro';

  @override
  String get sidebarNoAnnotations => 'Nessuna annotazione';

  @override
  String get sidebarNoMatchingAnnotations =>
      'Nessuna annotazione corrispondente';

  @override
  String sidebarPageHeader(int number) {
    return 'Pagina $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Questo rimuove la firma digitale dal documento. Puoi annullare l\'operazione.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Questo rimuove la firma digitale di \"$name\" dal documento. Puoi annullare l\'operazione.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Rimuovere la firma?';

  @override
  String get sidebarReopen => 'Riapri';

  @override
  String get sidebarReply => 'Rispondi';

  @override
  String get sidebarResolve => 'Risolvi';

  @override
  String get sidebarSearchHint => 'Cerca annotazioni';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selezionati',
      one: '$count selezionato',
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
  String get sidebarWriteReplyHint => 'Scrivi una risposta…';

  @override
  String get sigTitle => 'Firma';

  @override
  String get signIdCreate => 'Crea';

  @override
  String get signIdEmail => 'Email (facoltativo)';

  @override
  String get signIdName => 'Nome';

  @override
  String get signIdNameHint => 'Il tuo nome, come deve apparire sulla firma';

  @override
  String get signIdNameRequired => 'Inserisci un nome';

  @override
  String get signIdOrganization => 'Organizzazione (facoltativo)';

  @override
  String get signIdSelfSignedInfo =>
      'Questo crea un\'identità autofirmata. Le firme risulteranno come \"firmato, validità sconosciuta\" in Adobe Acrobat e altri lettori - come le loro stesse identità autofirmate. Il segno di spunta verde richiede una CA a pagamento e pubblicamente attendibile.';

  @override
  String get signIdTitle => 'Crea identità di firma';

  @override
  String get stampBox => 'Rettangolo';

  @override
  String get stampCircle => 'Cerchio';

  @override
  String get stampCustomCaption => 'Timbro personalizzato';

  @override
  String get stampDateFormat => 'Formato data';

  @override
  String get stampDeleteComponent => 'Elimina componente selezionato';

  @override
  String get stampDeleteStamp => 'Elimina timbro';

  @override
  String get stampEditStamp => 'Modifica timbro';

  @override
  String get stampExport => 'Esporta…';

  @override
  String get stampFieldDate => 'Data';

  @override
  String get stampFieldDateTime => 'Data e ora';

  @override
  String get stampFieldTime => 'Ora';

  @override
  String get stampFieldUsername => 'Nome utente';

  @override
  String get stampFont => 'Carattere';

  @override
  String get stampFontBold => 'Grassetto';

  @override
  String get stampFontItalic => 'Corsivo';

  @override
  String get stampHeight => 'Altezza';

  @override
  String get stampImage => 'Immagine';

  @override
  String get stampImport => 'Importa…';

  @override
  String get stampInsertField => 'Inserisci campo';

  @override
  String get stampMoreColors => 'Altri colori…';

  @override
  String get stampNewStamp => 'Nuovo timbro…';

  @override
  String get stampNewStampTitle => 'Nuovo timbro';

  @override
  String get stampSavedToCollection => 'Salvato nei timbri';

  @override
  String get stampSelectTextToEdit => 'Seleziona il testo da modificare';

  @override
  String get stampSelectedText => 'Testo selezionato';

  @override
  String get stampSignature => 'Firma';

  @override
  String get stampStamps => 'Timbri';

  @override
  String get stampText => 'Testo';

  @override
  String get stampTime12Hour => '12 ore';

  @override
  String get stampTime24Hour => '24 ore';

  @override
  String get stampTimeFormat => 'Formato ora';

  @override
  String get stampWidth => 'Larghezza';

  @override
  String get takeoffArea => 'Area';

  @override
  String get takeoffCount => 'Conteggio';

  @override
  String get takeoffEmpty => 'Ancora nessuna misurazione.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gruppi',
      one: '$count gruppo',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '$count elemento',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Lunghezza';

  @override
  String get takeoffTitle => 'Computo';

  @override
  String get tbAddInkAnnotation => 'Aggiungi annotazione a inchiostro';

  @override
  String get tbAlign => 'Allinea';

  @override
  String get tbAlignBottom => 'Allinea in basso';

  @override
  String get tbAlignHorizontalCenters => 'Allinea ai centri orizzontali';

  @override
  String get tbAlignLeft => 'Allinea a sinistra';

  @override
  String get tbAlignRight => 'Allinea a destra';

  @override
  String get tbAlignTop => 'Allinea in alto';

  @override
  String get tbAlignVerticalCenters => 'Allinea ai centri verticali';

  @override
  String get tbAnnotationsFlattened => 'Annotazioni integrate nelle pagine';

  @override
  String get tbApplyRedactionsMessage =>
      'Il contenuto contrassegnato verrà rimosso in modo permanente dal documento. Questa operazione non può essere annullata.';

  @override
  String get tbApplyRedactionsTitle => 'Applicare gli oscuramenti?';

  @override
  String get tbApplyRedactionsTooltip => 'Applica oscuramenti (irreversibile)';

  @override
  String get tbAutosizeTextBox => 'Adatta casella di testo (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Disegna una linea di lunghezza nota per calibrare la scala.';

  @override
  String get tbCharSpacing => 'Spaziatura caratteri';

  @override
  String get tbCheckBoxOption => 'Casella di controllo';

  @override
  String get tbCheckMarksOnDocument => 'Segni di spunta sul documento';

  @override
  String get tbCropImage => 'Ritaglia immagine';

  @override
  String get tbCroppingImage => 'Ritaglio immagine in corso';

  @override
  String get tbCropApply => 'Applica ritaglio';

  @override
  String get tbCropCancel => 'Annulla ritaglio';

  @override
  String get tbCropReset => 'Reimposta ritaglio';

  @override
  String get tbColorLabel => 'Colore';

  @override
  String get tbColorProcessingTooltip =>
      'Elaborazione colori - trova e sostituisci i colori del contenuto della pagina';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count colori sostituiti',
      one: '1 colore sostituito',
      zero: 'Nessun colore corrispondente trovato',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Converti in casella di controllo';

  @override
  String get tbConvertToImageButton => 'Converti in pulsante immagine';

  @override
  String get tbConvertToTextField => 'Converti in campo di testo';

  @override
  String get tbCornerRadius => 'Raggio angolo';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Elimina $count annotazioni',
      one: 'Elimina annotazione',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Elimina elemento';

  @override
  String get tbDeleteField => 'Elimina campo';

  @override
  String get tbDiscardDrawing => 'Scarta disegno';

  @override
  String get tbDistributeHorizontally => 'Distribuisci orizzontalmente';

  @override
  String get tbDistributeVertically => 'Distribuisci verticalmente';

  @override
  String get tbDrawNewSignature => 'Disegna una nuova firma…';

  @override
  String get tbEditAnnotationText => 'Modifica testo annotazione';

  @override
  String get tbEditTextStyle => 'Modifica testo e stile';

  @override
  String get tbElement => 'Elemento';

  @override
  String get tbEraserSize => 'Dimensione gomma';

  @override
  String get tbFieldActions => 'Azioni campo';

  @override
  String get tbFieldName => 'Nome del campo';

  @override
  String tbFieldNamed(String name) {
    return 'Campo: $name';
  }

  @override
  String get tbFieldValue => 'Valore del campo';

  @override
  String get tbFill => 'Riempimento';

  @override
  String get tbFingerDraws =>
      'Il dito disegna - tocca per farlo scorrere invece';

  @override
  String get tbFingerScrolls =>
      'Il dito fa scorrere (la penna disegna) - tocca per farlo disegnare';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'Integra le annotazioni nelle pagine';

  @override
  String get tbFlattenForm => 'Rendi definitivo il modulo';

  @override
  String get tbFlattenFormBakeValues =>
      'Rendi definitivo il modulo - integra i valori nelle pagine';

  @override
  String get tbFlattenLabel => 'Integra';

  @override
  String get tbFont => 'Carattere';

  @override
  String get tbFontSize => 'Dimensione carattere';

  @override
  String get tbFontWidth => 'Larghezza carattere';

  @override
  String get tbFormFieldsFlattened => 'Campi modulo integrati nelle pagine';

  @override
  String get tbGroupDraw => 'Disegna';

  @override
  String get tbGroupEdit => 'Modifica';

  @override
  String get tbGroupInsert => 'Inserisci';

  @override
  String get tbGroupMarkup => 'Marcatura';

  @override
  String get tbGroupMeasure => 'Misura';

  @override
  String get tbGroupSelect => 'Seleziona';

  @override
  String get tbGroupShapes => 'Forme';

  @override
  String get tbImageButtonOption => 'Pulsante immagine';

  @override
  String get tbLineEnd => 'Fine linea';

  @override
  String get tbLineSpacing => 'Interlinea';

  @override
  String get tbLineStart => 'Inizio linea';

  @override
  String get tbLineType => 'Tipo di linea';

  @override
  String get tbManageStamps => 'Gestisci timbri…';

  @override
  String get tbMarkupHighlight => 'Evidenzia';

  @override
  String get tbMarkupHighlightTip => 'Evidenzia selezione';

  @override
  String get tbMarkupSquiggly => 'Sottolineatura ondulata';

  @override
  String get tbMarkupSquigglyTip => 'Sottolineatura ondulata della selezione';

  @override
  String get tbMarkupStrikeOut => 'Barra';

  @override
  String get tbMarkupStrikeOutTip => 'Barra la selezione';

  @override
  String get tbMarkupUnderline => 'Sottolinea';

  @override
  String get tbMarkupUnderlineTip => 'Sottolinea la selezione';

  @override
  String get tbMoreColors => 'Altri colori…';

  @override
  String get tbNameArrow => 'Freccia';

  @override
  String get tbNameCallout => 'Didascalia';

  @override
  String get tbNameCloudPolygon => 'Poligono a nuvola';

  @override
  String get tbNameCount => 'Conteggio';

  @override
  String get tbNameDigitalSignature => 'Firma digitale';

  @override
  String get tbNameDraw => 'Disegna';

  @override
  String get tbNameEllipse => 'Ellisse';

  @override
  String get tbNameEraser => 'Cancella tratti a inchiostro';

  @override
  String get tbNameHand => 'Hand';

  @override
  String get tbNameHighlight => 'Evidenzia';

  @override
  String get tbNameImage => 'Immagine';

  @override
  String get tbNameLine => 'Linea';

  @override
  String get tbNameMeasureAngle => 'Misura angolo';

  @override
  String get tbNameMeasureArc => 'Misura lunghezza arco';

  @override
  String get tbNameMeasureArea => 'Misura area';

  @override
  String get tbNameMeasureDistance => 'Misura distanza';

  @override
  String get tbNameMeasurePerimeter => 'Misura perimetro';

  @override
  String get tbNameMeasureSlope => 'Misura pendenza (dislivello/distanza)';

  @override
  String get tbNameMeasureVolume => 'Misura volume (area × profondità)';

  @override
  String get tbNameNote => 'Nota';

  @override
  String get tbNamePolygon => 'Poligono';

  @override
  String get tbNamePolyline => 'Polilinea';

  @override
  String get tbNameRectangle => 'Rettangolo';

  @override
  String get tbNameSelect => 'Seleziona';

  @override
  String get tbNameSignature => 'Firma';

  @override
  String get tbNameStamp => 'Timbro';

  @override
  String get tbNameTextBox => 'Casella di testo';

  @override
  String get tbNewFieldType =>
      'Nuovo tipo di campo - trascina su una pagina per aggiungerne uno';

  @override
  String get tbNoAnnotationsToFlatten => 'Nessuna annotazione da integrare';

  @override
  String get tbNoCustomStamps => 'Nessun timbro personalizzato';

  @override
  String get tbNoFormFieldsToFlatten => 'Nessun campo modulo da integrare';

  @override
  String get tbNoRedactionsToApply => 'Nessun oscuramento da applicare';

  @override
  String get tbNoteTitle => 'Nota';

  @override
  String get tbOpacity => 'Opacità';

  @override
  String get tbOutline => 'Contorno';

  @override
  String get tbPatternScale => 'Scala motivo';

  @override
  String get tbPickColorFromPage => 'Scegli un colore dalla pagina';

  @override
  String get tbRedactionsApplied => 'Oscuramenti applicati';

  @override
  String get tbRedoShortcut => 'Ripeti (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Impossibile ridisporre - non è un paragrafo a colonna singola che questo strumento può riformattare. Prova invece Sostituisci testo.';

  @override
  String get tbReflowParagraph => 'Ridisponi paragrafo';

  @override
  String get tbRenameField => 'Rinomina campo';

  @override
  String get tbRenameFieldEllipsis => 'Rinomina campo…';

  @override
  String get tbReplaceImage => 'Sostituisci immagine';

  @override
  String get tbReplaceImageFailed => 'Impossibile sostituire l\'immagine';

  @override
  String get tbReplaceText => 'Sostituisci testo';

  @override
  String get tbSaveImage => 'Salva immagine';

  @override
  String get tbSaveShortcut => 'Salva… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Scala';

  @override
  String get tbSelectTextForMarkup =>
      'Seleziona il testo per usare la marcatura';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selezionati',
      one: 'Selezione',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Imposta…';

  @override
  String get tbStamp => 'Timbro';

  @override
  String get tbStampText => 'Testo del timbro';

  @override
  String get tbStrokeOpacityFont => 'Tratto, opacità, carattere';

  @override
  String get tbStrokeWidthLabel => 'Spessore tratto';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Tratto $width';
  }

  @override
  String get tbStyle => 'Stile';

  @override
  String get tbTakeoffTotals => 'Totali computo';

  @override
  String get tbTextBorder => 'Bordo del testo';

  @override
  String get tbTextColour => 'Colore del testo';

  @override
  String get tbTextFieldOption => 'Campo di testo';

  @override
  String get tbTextFill => 'Riempimento del testo';

  @override
  String get tbTextStyleEllipsis => 'Stile del testo…';

  @override
  String get tbTextTitle => 'Testo';

  @override
  String get tbTipCallout =>
      'Didascalia - trascina dal punto verso dove va la casella';

  @override
  String get tbTipContent => 'Modifica il contenuto della pagina';

  @override
  String get tbTipCount =>
      'Conteggio - tocca per inserire segni di spunta e contarli';

  @override
  String get tbTipDigitalSignature =>
      'Firma digitale - trascina un riquadro per posizionare e firmare';

  @override
  String get tbTipForm =>
      'Campi modulo - tocca per selezionare, tocca due volte per compilare, trascina per aggiungere';

  @override
  String get tbTipHighlightDraw => 'Evidenzia - disegna a mano libera';

  @override
  String get tbTipImage =>
      'Immagine - tocca per posizionare, o trascina un riquadro';

  @override
  String get tbTipMeasureAngle => 'Misura angolo - clicca tre punti';

  @override
  String get tbTipMeasureArc => 'Misura lunghezza arco - clicca tre punti';

  @override
  String get tbTipRedact => 'Oscura - trascina una regione, poi applica';

  @override
  String get tbTipSignature => 'Firma - tocca una pagina per posizionarla';

  @override
  String get tbTipSnapshot =>
      'Istantanea - trascina una regione per catturarla (incolla come vettoriale)';

  @override
  String get tbToolContent => 'Contenuto';

  @override
  String get tbToolForm => 'Modulo';

  @override
  String get tbToolRedact => 'Oscura';

  @override
  String get tbToolSnapshot => 'Istantanea';

  @override
  String get tbTools => 'Strumenti';

  @override
  String get tbTotals => 'Totali';

  @override
  String get tbTypeTextEachTime => 'Digita il testo ogni volta';

  @override
  String get tbUnderline => 'Sottolinea';

  @override
  String get tbUndoShortcut => 'Annulla (⌘Z)';

  @override
  String get textStyleFont => 'Carattere';

  @override
  String get textStyleFontSize => 'Dimensione carattere';

  @override
  String get textStyleKeep => 'mantieni';

  @override
  String get textStyleStyle => 'Stile';

  @override
  String get textStyleText => 'Testo';

  @override
  String get textStyleTextFill => 'Riempimento del testo';

  @override
  String get textStyleTitle => 'Modifica testo e stile';

  @override
  String get thumbAddPage => 'Aggiungi pagina';

  @override
  String get thumbClearSelection => 'Cancella selezione';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copia $count pagine',
      one: 'Copia pagina',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Copia pagine selezionate';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Taglia $count pagine',
      one: 'Taglia pagina',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Taglia pagine selezionate';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Elimina $count pagine',
      one: 'Elimina pagina',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Elimina pagine selezionate';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Duplica $count pagine',
      one: 'Duplica pagina',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Esporta pagine…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Esporta $count pagine…',
      one: 'Esporta pagina…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Esporta pagine selezionate';

  @override
  String get thumbInsertBlankAfter => 'Inserisci pagina vuota dopo';

  @override
  String get thumbInsertBlankBefore => 'Inserisci pagina vuota prima';

  @override
  String get thumbInsertFileFailed => 'Impossibile inserire quel file.';

  @override
  String get thumbInsertPdf => 'Inserisci PDF…';

  @override
  String get thumbPageActions => 'Azioni pagina';

  @override
  String thumbPageNumber(int number) {
    return 'Pagina $number';
  }

  @override
  String get thumbPages => 'Pagine';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Incolla $count pagine',
      one: 'Incolla pagina',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Ruota di 180°';

  @override
  String get thumbRotateLeft => 'Ruota a sinistra';

  @override
  String get thumbRotatePageRight => 'Ruota pagina a destra';

  @override
  String get thumbRotateRight => 'Ruota a destra';

  @override
  String get thumbRotateSelectedLeft =>
      'Ruota a sinistra le pagine selezionate';

  @override
  String get thumbRotateSelectedRight => 'Ruota a destra le pagine selezionate';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selezionate',
      one: '$count selezionata',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Annulla';

  @override
  String get viewerEditFontUnsafe =>
      'Questo carattere o codifica PDF non può essere modificato in sicurezza.';

  @override
  String get viewerEditNeedsSinglePage =>
      'La modifica richiede una selezione su una sola pagina.';

  @override
  String get viewerEditNotEditableRun =>
      'Questa selezione non è un unico blocco di testo del contenuto della pagina modificabile.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Questo carattere PDF può essere riscritto, ma il suo stile non può essere modificato.';

  @override
  String get viewerEditTextStyle => 'Modifica testo e stile';

  @override
  String get viewerMarkup => 'Marcatura';

  @override
  String get viewerMarkupHighlight => 'Evidenzia';

  @override
  String get viewerMarkupSquiggly => 'Ondulato';

  @override
  String get viewerMarkupStrikeOut => 'Barra';

  @override
  String get viewerMarkupUnderline => 'Sottolinea';

  @override
  String get viewerSelectAll => 'Seleziona tutto';
}

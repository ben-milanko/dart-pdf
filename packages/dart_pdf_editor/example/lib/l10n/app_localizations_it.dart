// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get add => 'Aggiungi';

  @override
  String get apply => 'Applica';

  @override
  String get cancel => 'Annulla';

  @override
  String get clear => 'Cancella';

  @override
  String get close => 'Chiudi';

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
  String exActionJavaScript(String script) {
    return 'JavaScript mostrato all\'app: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Collegamento: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Azione denominata: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Tipo di azione non gestito: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Testo dell\'annotazione copiato';

  @override
  String get exApiKeyHelper => 'Inviato come Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Chiave API / token (facoltativo)';

  @override
  String get exAppMenuTooltip => 'Menu DartPDF';

  @override
  String get exClearRecentFiles => 'Cancella file recenti';

  @override
  String get exCloseTab => 'Chiudi scheda';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Confronto: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Confronta con un altro PDF…';

  @override
  String get exCopiedToClipboard => 'Copiato negli appunti';

  @override
  String get exCopySelectedText => 'Copia il testo selezionato (⌘C)';

  @override
  String get exCopyText => 'Copia testo';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Impossibile aprire $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Impossibile aprire $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Impossibile aprire $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Impossibile aprire $uri\n$error\n\nSul web questo è spesso una restrizione CORS: il server deve inviare Access-Control-Allow-Origin ed esporre gli header Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Impossibile riaprire $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Impossibile riaprire $title - la copia salvata non è più disponibile.';
  }

  @override
  String get exDemoNoteHint =>
      'Digita qui - questa casella di testo fluttua sopra la pagina';

  @override
  String get exDiagnosticsCopied => 'Diagnostica copiata negli appunti';

  @override
  String exDownloaded(String name) {
    return 'Scaricato $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Scaricato $name - incolla di nuovo nel PDF con Ctrl+V';
  }

  @override
  String get exExport => 'Esporta';

  @override
  String exExportFailed(String error) {
    return 'Esportazione non riuscita: $error';
  }

  @override
  String get exExportPageImageMenu => 'Esporta pagina come immagine…';

  @override
  String get exExportPageImageTitle => 'Esporta pagina come immagine';

  @override
  String get exFeatureShowcase => 'Vetrina delle funzionalità';

  @override
  String get exFormat => 'Formato';

  @override
  String get exHide => 'Nascondi';

  @override
  String get exHorizontalLayout => 'Layout pagina orizzontale';

  @override
  String get exHowToSetupOcr => 'Come configurare un server OCR';

  @override
  String get exModelName => 'Nome del modello';

  @override
  String get exNoMessage => 'Nessun messaggio';

  @override
  String get exNoRecentFiles => 'Nessun file recente';

  @override
  String exNotAValidUrl(String url) {
    return 'URL non valido:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'L\'OCR ha aggiunto $count blocchi di testo - il testo della pagina è ora selezionabile',
      one:
          'L\'OCR ha aggiunto 1 blocco di testo - il testo della pagina è ora selezionabile',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Aggiunge un livello di testo selezionabile e ricercabile sulle pagine scansionate usando un modello OCR linguistico-visivo ospitato da te (dots.ocr su vLLM, o qualsiasi endpoint OCR compatibile con OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR non riuscito: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Apri';

  @override
  String get exOpenDocumentBeforeOcr =>
      'Apri un documento prima di eseguire l\'OCR';

  @override
  String get exOpenDocumentFirst => 'Apri prima un documento';

  @override
  String get exOpenFromUrl => 'Apri da un URL…';

  @override
  String get exOpenFromUrlTitle => 'Apri da un URL';

  @override
  String get exOpenInNewTab => 'Apri il PDF in una nuova scheda';

  @override
  String get exOpenInteractiveDemo => 'Apri la demo interattiva';

  @override
  String get exOpenPdf => 'Apri un PDF…';

  @override
  String get exOpenPdfButton => 'Apri un PDF';

  @override
  String get exOpenRecent => 'Apri recenti';

  @override
  String get exOpenUrlDescription =>
      'Trasmette il PDF tramite richieste HTTP Range via PdfHttpByteSource, recuperando solo ciò di cui il parser ha bisogno e ricorrendo a un download completo quando il server non supporta le richieste range.';

  @override
  String get exOpeningDocument => 'Apertura del documento';

  @override
  String get exOpeningPdf => 'Apertura del PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Apertura di $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL del PDF';

  @override
  String get exPerformanceAuto => 'Prestazioni: Auto';

  @override
  String get exPreparing => 'Preparazione…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor su pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Riconoscimento della pagina $current di $count…';
  }

  @override
  String get exResolution => 'Risoluzione';

  @override
  String get exRunOcr => 'Esegui OCR';

  @override
  String get exSaveAs => 'Salva con nome…';

  @override
  String exSaveFailed(String error) {
    return 'Salvataggio non riuscito: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Salvato $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Salvato $name - incolla di nuovo nel PDF con ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Salvato in $path';
  }

  @override
  String get exScrollIndicatorDemo =>
      'Demo dell\'API dell\'indicatore di scorrimento';

  @override
  String get exServiceEndpoint => 'Endpoint del servizio';

  @override
  String get exShow => 'Mostra';

  @override
  String get exSingleWorker => 'Worker singolo';

  @override
  String get exSupplyFeedback => 'Invia feedback…';

  @override
  String get exSwitchToEdit => 'Passa alla modalità di modifica';

  @override
  String get exSwitchToReadOnly => 'Passa a sola lettura';

  @override
  String get exThemeDark => 'Tema: scuro - passa a sistema';

  @override
  String get exThemeLight => 'Tema: chiaro - passa a scuro';

  @override
  String get exThemeSystem => 'Tema: sistema - passa a chiaro';

  @override
  String get exTryDemo => 'Prova la demo interattiva';

  @override
  String get exWelcomeScreen => 'Schermata di benvenuto';

  @override
  String get exUntitled => 'Senza titolo';

  @override
  String get exVerticalLayout => 'Layout pagina verticale';

  @override
  String get exViewSource => 'Visualizza il codice sorgente su GitHub';

  @override
  String get exWorkerAuto => 'Auto';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Prestazioni: $count worker',
      one: 'Prestazioni: worker singolo',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count worker';
  }

  @override
  String get feedbackAttachDiagnostics => 'Allega questa diagnostica al report';

  @override
  String get feedbackClearLog => 'Cancella log';

  @override
  String get feedbackCopyDiagnostics => 'Copia diagnostica';

  @override
  String get feedbackDiagnosticsNotice =>
      'Il modulo di feedback si apre nel tuo browser. La diagnostica qui sotto è raccolta solo su questo dispositivo ed è allegata per aiutare a riprodurre il problema. Esaminala prima - non includere nulla che preferiresti mantenere privato.';

  @override
  String get feedbackOpenForm => 'Apri il modulo di feedback';

  @override
  String get feedbackTitle => 'Invia feedback';

  @override
  String get none => 'Nessuno';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Incolla';

  @override
  String get redo => 'Ripeti';

  @override
  String get remove => 'Rimuovi';

  @override
  String get rename => 'Rinomina';

  @override
  String get reset => 'Reimposta';

  @override
  String get save => 'Salva';

  @override
  String get scrollDemoNextPage => 'Pagina successiva';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Pagina $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Pagina precedente';

  @override
  String get scrollDemoSwitchHorizontal => 'Passa al layout orizzontale';

  @override
  String get scrollDemoSwitchVertical => 'Passa al layout verticale';

  @override
  String get scrollDemoTitle => 'API dell\'indicatore di scorrimento';

  @override
  String get undo => 'Annulla';

  @override
  String get exFileTypePdf => 'Documenti PDF';

  @override
  String get exFileTypeImages => 'Immagini';

  @override
  String get exFileTypeFonts => 'Caratteri';
}

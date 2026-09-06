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
  String get appSigAddLogo => 'Aggiungi logo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Tutte le $pageCount pagine';
  }

  @override
  String get appSigAppearance => 'Aspetto';

  @override
  String get appSigAppearanceDescription =>
      'La firma viene disegnata dove l\'hai posizionata. Il nome del firmatario e i dettagli sono sempre mostrati; puoi aggiungere un segno disegnato a mano e un logo di sfondo.';

  @override
  String appSigApplyTo(String label) {
    return 'Applica a: $label';
  }

  @override
  String get appSigApplyToPages => 'Applica alle pagine…';

  @override
  String get appSigChooseCertificate => 'Scegli file del certificato…';

  @override
  String get appSigChooseKeyDescription =>
      'Scegli la tua chiave privata (RSA, PEM o DER) e il relativo file del certificato. La chiave è usata solo per firmare e non viene mai salvata.';

  @override
  String get appSigChoosePngOrJpeg => 'Scegli un\'immagine PNG o JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Scegli chiave privata…';

  @override
  String get appSigContactInfo => 'Informazioni di contatto';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Impossibile acquisire la firma.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Impossibile leggere il certificato: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Impossibile leggere la chiave: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Crea una firma su questo dispositivo';

  @override
  String appSigDate(String date) {
    return 'Data: $date';
  }

  @override
  String get appSigDigitallySign => 'Firma digitalmente';

  @override
  String get appSigDrawSignature => 'Disegna firma…';

  @override
  String get appSigFieldHelper =>
      'Lascia vuoto per creare un nuovo campo firma.';

  @override
  String get appSigFieldLabel => 'Campo firma esistente (facoltativo)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificati',
      one: '1 certificato',
    );
    return '$_temp0 · valido da $validFrom a $validUntil';
  }

  @override
  String get appSigIntro =>
      'Una firma digitale dimostra che hai firmato questo documento e che non è stato modificato da allora. Scegli come vuoi firmare.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Impossibile leggere la chiave o il certificato selezionati.';

  @override
  String get appSigKeylessDescription =>
      'Il più semplice. Confermiamo la tua identità via email e firmiamo per te, con una marca temporale attendibile. Nulla da installare o configurare.';

  @override
  String get appSigKeylessIdentity => 'Identità senza chiave';

  @override
  String get appSigKeylessSignInExpired =>
      'L\'accesso senza chiave è scaduto. Accedi di nuovo.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Accesso senza chiave non riuscito: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Senza chiave · con marca temporale · validità sconosciuta';

  @override
  String get appSigKeylessWebNote =>
      'Accedere con la tua email è il modo più semplice — è disponibile nelle app desktop e mobile di DartPDF. Per motivi di sicurezza non può funzionare in un browser web.';

  @override
  String get appSigLocation => 'Luogo';

  @override
  String get appSigLogoAdded => 'Logo aggiunto ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Pagine $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Anteprima - il riquadro firmato potrebbe differire leggermente.';

  @override
  String get appSigReason => 'Motivo';

  @override
  String appSigReasonLine(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Aggiornamento accesso…';

  @override
  String get appSigRemoveLogo => 'Rimuovi logo';

  @override
  String get appSigRemoveSignature => 'Rimuovi firma';

  @override
  String get appSigSelfSignedDescription =>
      'Nessun accesso o file necessario. Ideale per uso personale — viene salvato su questo dispositivo per la prossima volta. Alcuni lettori PDF la mostreranno come \"firmato, validità sconosciuta\", il che è normale per una firma creata da te.';

  @override
  String get appSigSelfSignedIdentity => 'Identità autofirmata';

  @override
  String get appSigSelfSignedSubtitle => 'Autofirmata · validità sconosciuta';

  @override
  String get appSigShowSignatureOnPages => 'Mostra la firma sulle pagine';

  @override
  String get appSigSign => 'Firma';

  @override
  String get appSigSignInWithEmail => 'Accedi con la tua email';

  @override
  String get appSigSignatureAdded => 'Firma aggiunta ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Firmato digitalmente da $signerName';
  }

  @override
  String get appSigSigner => 'Firmatario';

  @override
  String get appSigSigningYouIn => 'Accesso in corso…';

  @override
  String get appSigThisPageOnly => 'Solo questa pagina';

  @override
  String get appSigUseOwnCertificate => 'Usa il tuo certificato';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Per un certificato di firma della tua organizzazione';

  @override
  String get appSigX509Signer => 'Firmatario X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Aprire questi $count PDF in una nuova scheda, o inserire le loro pagine in \"$title\"?',
      one:
          'Aprire questo PDF in una nuova scheda, o inserire le sue pagine in \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aggiungi PDF rilasciati',
      one: 'Aggiungi PDF rilasciato',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Testo dell\'annotazione copiato';

  @override
  String get editorAppMenuTooltip => 'Menu DartPDF';

  @override
  String get editorCancelOcr => 'Annulla OCR';

  @override
  String get editorClearRecentFiles => 'Cancella file recenti';

  @override
  String get editorCloseAll => 'Chiudi tutto';

  @override
  String get editorCloseOthers => 'Chiudi le altre';

  @override
  String get editorCloseTab => 'Chiudi scheda';

  @override
  String get editorCloseTabsToRight => 'Chiudi le schede a destra';

  @override
  String get editorCompareFailedTitle => 'Confronto non riuscito';

  @override
  String editorCompareTitle(String title) {
    return 'Confronto: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Copiato negli appunti';

  @override
  String get editorCopySelectedTextTooltip => 'Copia il testo selezionato (⌘C)';

  @override
  String get editorCopyText => 'Copia testo';

  @override
  String editorCouldNotExport(String title) {
    return 'Impossibile esportare $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Impossibile importare i timbri: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Impossibile inserire i PDF rilasciati',
      one: 'Impossibile inserire il PDF rilasciato',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Impossibile aprire $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder =>
      'Impossibile aprire la cartella contenitore';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Impossibile aprire il secondo file\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Impossibile aprire il file selezionato\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Impossibile aprire $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Impossibile stampare $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Impossibile riaprire $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Impossibile firmare digitalmente: $error';
  }

  @override
  String get editorDiscard => 'Scarta';

  @override
  String get editorDiscardChangesTitle => 'Scartare le modifiche?';

  @override
  String get editorDocumentSigned => 'Documento firmato digitalmente';

  @override
  String get editorDownload => 'Scarica';

  @override
  String get editorDropToOpen => 'Rilascia il PDF per aprirlo';

  @override
  String get editorDropToOpenOrInsert =>
      'Rilascia il PDF per aprirlo o inserirlo';

  @override
  String get editorInsertPages => 'Inserisci pagine';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Inseriti $count; impossibile leggere $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF inseriti in $title',
      one: 'Pagine inserite in $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Collegamento non valido: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Questo documento ha tentato di eseguire JavaScript (ignorato)';

  @override
  String get editorLoadingFullDocument => 'Caricamento del documento completo';

  @override
  String get editorMenuCompareWith => 'Confronta con…';

  @override
  String get editorMenuDigitallySign => 'Firma digitalmente…';

  @override
  String get editorMenuDigitallySigning => 'Firma digitale in corso…';

  @override
  String get editorMenuExportImage => 'Esporta pagina come immagine…';

  @override
  String get editorMenuNewDocument => 'Nuovo documento…';

  @override
  String get editorMenuNewWindow => 'Nuova finestra';

  @override
  String get editorMoveToNewWindow => 'Sposta in una nuova finestra';

  @override
  String get editorUnableToOpenNewWindow =>
      'Impossibile aprire una nuova finestra';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Apri un PDF…';

  @override
  String get editorMenuPrint => 'Stampa…';

  @override
  String get editorMenuSaveAs => 'Salva con nome…';

  @override
  String get editorMenuScanDocument => 'Scansiona in un nuovo documento…';

  @override
  String get editorMenuInsertDocument => 'Inserisci documento…';

  @override
  String get editorMenuInsertScan => 'Inserisci scansione…';

  @override
  String get editorScanFailed => 'Impossibile scansionare il documento.';

  @override
  String get editorInsertedScan => 'Pagine scansionate inserite.';

  @override
  String get editorMenuSettings => 'Impostazioni';

  @override
  String get editorMenuSectionFile => 'File';

  @override
  String get editorMenuSectionDocument => 'Questo documento';

  @override
  String get editorMenuSectionApp => 'App';

  @override
  String get editorMenuReadOnly => 'Sola lettura';

  @override
  String get editorMenuSearchActions => 'Cerca azioni…';

  @override
  String get paletteHint => 'Cerca azioni, strumenti e pannelli';

  @override
  String get paletteNoMatch => 'Nessun comando corrispondente';

  @override
  String get paletteKeyHints => '↑↓ sposta · ⏎ esegui · esc chiudi';

  @override
  String paletteCount(int count) {
    return '$count comandi';
  }

  @override
  String paletteCountFiltered(int count, int total) {
    return '$count di $total';
  }

  @override
  String get paletteSourceMenu => 'Menu';

  @override
  String get paletteSourcePanel => 'Pannello';

  @override
  String get paletteSourceView => 'Vista';

  @override
  String get paletteSourceFile => 'File';

  @override
  String paletteSourceTool(String group) {
    return 'Strumento $group';
  }

  @override
  String get paletteNeedsDocument => 'Richiede un documento aperto';

  @override
  String editorNamedAction(String name) {
    return 'Azione denominata: $name';
  }

  @override
  String get editorNoRecentFiles => 'Nessun file recente';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr =>
      'Apri un documento prima di eseguire l\'OCR';

  @override
  String get editorOpenFailedTitle => 'Apertura non riuscita';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Apri in nuove schede',
      one: 'Apri in una nuova scheda',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Apri il PDF in una nuova scheda';

  @override
  String get editorOpenRecent => 'Apri recenti';

  @override
  String get editorViewAllRecentFiles => 'Visualizza tutti i file recenti…';

  @override
  String get editorOpenTabs => 'Schede aperte';

  @override
  String get editorOpeningDocumentSemantic => 'Apertura del documento';

  @override
  String get editorOpeningPdf => 'Apertura del PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Apertura di $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Pagina $number';
  }

  @override
  String get editorPreviewComparison => 'Confronto';

  @override
  String get editorPreviewCouldNotOpen => 'Impossibile aprire';

  @override
  String get editorPreviewOpening => 'Apertura';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Modifiche non salvate recuperate in $count documenti dall\'ultima sessione.',
      one: 'Modifiche non salvate recuperate dall\'ultima sessione.',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'Firma rimossa';

  @override
  String get editorSnapshotCopied => 'Istantanea copiata negli appunti';

  @override
  String get editorSnapshotCopyFailed =>
      'Impossibile copiare l\'istantanea negli appunti';

  @override
  String get editorTabs => 'Schede';

  @override
  String editorTabsOpenCount(int count) {
    return '$count aperte';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documenti hanno modifiche non salvate.',
      one: 'Un documento ha modifiche non salvate.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Azione non supportata: $type';
  }

  @override
  String get editorUntitled => 'Senza titolo';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version è disponibile.';
  }

  @override
  String get editorUpdateLater => 'Più tardi';

  @override
  String get updateInstallNow => 'Aggiorna ora';

  @override
  String get updateDownloadingTitle => 'Download dell’aggiornamento';

  @override
  String get updatePreparing => 'Preparazione…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Download… $percent%';
  }

  @override
  String get updateRestarting => 'Riavvio per completare l’aggiornamento…';

  @override
  String get updateHandedOff =>
      'Aggiornamento scaricato. Apertura del programma di installazione…';

  @override
  String updateFailed(String error) {
    return 'Aggiornamento non riuscito: $error';
  }

  @override
  String get editorViewAllTabs => 'Visualizza tutte le schede';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Esporta';

  @override
  String get imgExportFormat => 'Formato';

  @override
  String get imgExportResolution => 'Risoluzione';

  @override
  String get imgExportTitle => 'Esporta pagina come immagine';

  @override
  String get newDocCreate => 'Crea';

  @override
  String get newDocLandscape => 'Orizzontale';

  @override
  String get newDocOrientation => 'Orientamento';

  @override
  String get newDocPageSize => 'Dimensione pagina';

  @override
  String get newDocPortrait => 'Verticale';

  @override
  String get newDocTitle => 'Nuovo documento';

  @override
  String get none => 'Nessuno';

  @override
  String get ocrAlreadyRunning =>
      'L\'OCR è già in esecuzione - attendi che finisca o annullalo';

  @override
  String get ocrBrowserInitFailed =>
      'Inizializzazione dell\'OCR del browser non riuscita';

  @override
  String get ocrCancelled => 'OCR annullato';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR annullato dopo $count blocchi di testo',
      one: 'OCR annullato dopo 1 blocco di testo',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Scarica';

  @override
  String ocrDownloadFailed(String error) {
    return 'Impossibile scaricare il modello OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'L\'aggiunta di un livello di testo selezionabile richiede il modello OCR sul dispositivo$size. Viene scaricato una sola volta e poi funziona offline.\n\nModello: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Scaricare il modello OCR?';

  @override
  String ocrFailed(String error) {
    return 'OCR non riuscito: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'L\'OCR sul dispositivo non è disponibile su questa piattaforma';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'L\'OCR ha aggiunto $count blocchi di testo - il testo della pagina è ora selezionabile',
      one:
          'L\'OCR ha aggiunto 1 blocco di testo - il testo della pagina è ora selezionabile',
      zero: 'L\'OCR non ha trovato testo su queste pagine',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'L\'OCR web scarica un modello linguistico-visivo Florence-2 e lo esegue localmente con WebGPU/WASM tramite Transformers.js. Le pagine PDF rimangono in questo browser; solo i file del modello vengono recuperati al primo utilizzo.';

  @override
  String get ocrWebPromptTitle => 'Eseguire l\'OCR con IA in questo browser?';

  @override
  String get ocrWebStart => 'Avvia OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Incolla';

  @override
  String get printDlgPreparing => 'Preparazione…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Rendering della pagina $rendered di $total…';
  }

  @override
  String get printDlgTitle => 'Stampa';

  @override
  String get printPreviewAll => 'Tutte';

  @override
  String get printPreviewCurrent => 'Corrente';

  @override
  String get printPreviewFrom => 'Da';

  @override
  String get printPreviewNextPage => 'Pagina successiva';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Pagina $page di $total';
  }

  @override
  String get printPreviewPreviousPage => 'Pagina precedente';

  @override
  String get printPreviewPrint => 'Stampa';

  @override
  String get printPreviewRange => 'Intervallo';

  @override
  String printPreviewRangeError(int total) {
    return 'Inserisci un intervallo di pagine tra 1 e $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Pagine da stampare: $count';
  }

  @override
  String get printPreviewTitle => 'Anteprima di stampa';

  @override
  String get printPreviewTo => 'A';

  @override
  String get printPreviewUnavailable => 'Anteprima non disponibile';

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
  String get settingsAbout => 'Informazioni';

  @override
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsCheckNow => 'Controlla ora';

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsLanguageSystem => 'Predefinita del sistema';

  @override
  String get settingsCheckingForUpdates => 'Ricerca di aggiornamenti…';

  @override
  String get settingsCouldNotOpenDownload => 'Impossibile aprire il download';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Impossibile aprire le impostazioni di sistema';

  @override
  String get settingsDeveloperTools => 'Strumenti per sviluppatori';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Metriche, log, modalità di rendering (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Scarica $version';
  }

  @override
  String get settingsOpenSettings => 'Apri Impostazioni';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count memorizzati',
      one: '1 memorizzato',
      zero: 'Nessun file recente',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'File recenti';

  @override
  String get settingsSetUpAsDefault =>
      'Configura come applicazione predefinita';

  @override
  String get settingsSystem => 'Sistema';

  @override
  String get settingsThemeDark => 'Scuro';

  @override
  String get settingsThemeLight => 'Chiaro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String settingsUpToDate(String version) {
    return 'Hai la versione più recente ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'La versione $version è disponibile (hai la $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Impossibile verificare gli aggiornamenti. Riprova più tardi.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Hai $name $version.';
  }

  @override
  String get settingsNightlyUpdates => 'Aggiornamenti nightly';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'Ricevi notifiche automatiche per le build di test Windows non firmate da main.';

  @override
  String get settingsUpdates => 'Aggiornamenti';

  @override
  String get settingsViewSource => 'Visualizza il codice sorgente su GitHub';

  @override
  String get undo => 'Annulla';

  @override
  String get welcomeOpenPdf => 'Apri un PDF';

  @override
  String get welcomePickAgainToReopen => 'Riseleziona per riaprire';

  @override
  String get welcomeRecent => 'Recenti';

  @override
  String get welcomeSearchRecentFiles => 'Cerca nei file recenti';

  @override
  String get welcomeNoMatchingRecentFiles =>
      'Nessun file recente corrisponde alla ricerca';

  @override
  String get welcomeRemoveFromRecent => 'Rimuovi dai recenti';

  @override
  String get welcomeTapToReopen => 'Tocca per riaprire';

  @override
  String get welcomeViewAsGrid => 'Vista a griglia';

  @override
  String get welcomeViewAsList => 'Vista elenco';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Installa l\'app web, poi scegliela per i file PDF.',
        'windows':
            'Apri le impostazioni delle app predefinite di Windows per i PDF.',
        'macos': 'Segui i passaggi \"Apri sempre con\" del Finder.',
        'linux':
            'Usa le impostazioni delle applicazioni predefinite del tuo desktop.',
        'android': 'Scegli DartPDF quando apri un PDF, poi tocca Sempre.',
        'ios': 'Usa Condividi o Apri in da File per inviare i PDF qui.',
        'other': 'Configura il gestore di file PDF del tuo sistema.',
      },
    );
    return '$_temp0';
  }

  @override
  String settingsDefaultAppInstructions(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web':
            'Installa prima DartPDF dal tuo browser. Poi usa le impostazioni del gestore di file del browser o del sistema operativo per associare i file PDF all\'app installata.',
        'windows':
            'Le Impostazioni di Windows si apriranno su App predefinite. Cerca \".pdf\" o \"PDF\", scegli l\'app PDF attuale, poi seleziona DartPDF.',
        'macos':
            'Nel Finder, seleziona un PDF qualsiasi, scegli File > Ottieni informazioni, espandi \"Apri con\", scegli DartPDF, poi clicca \"Modifica tutti…\".',
        'linux':
            'Apri le impostazioni del desktop per le Applicazioni predefinite, oppure fai clic destro su un PDF in File, scegli Proprietà, e imposta DartPDF come predefinita per i documenti PDF.',
        'android':
            'Apri un PDF da File o Download, scegli DartPDF nel selettore di app, poi seleziona Sempre. Se un\'altra app apre già i PDF, cancella prima le impostazioni predefinite di quell\'app nelle Impostazioni di Android.',
        'ios':
            'iOS non fornisce un editor PDF predefinito globale. Usa File > Condividi, oppure tieni premuto un PDF e scegli Condividi/Apri in, poi seleziona DartPDF.',
        'other':
            'Usa le impostazioni di sistema per i gestori di file per associare i documenti PDF a DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Download del modello OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Download del modello $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Completamento OCR…';

  @override
  String get fileTypePdf => 'Documenti PDF';

  @override
  String get fileTypeImages => 'Immagini';

  @override
  String get fileTypeStampBundle => 'Timbri DartPDF';

  @override
  String get appSigKeyFileType => 'Chiavi private RSA';

  @override
  String get appSigCertificateFileType => 'Certificati X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Seleziona almeno un certificato X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Il certificato $index non è un X.509 valido.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'La chiave privata non corrisponde a nessun certificato RSA selezionato.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Le chiavi private crittografate non sono supportate. Scegli una chiave RSA PKCS#1 o PKCS#8 non crittografata.';

  @override
  String get appSigErrorKeyNotRsa =>
      'La chiave privata non è una chiave RSA PKCS#1 o PKCS#8 non crittografata.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Nessun certificato X.509 trovato.';

  @override
  String get imageSourceTakePhoto => 'Scatta foto';

  @override
  String get imageSourceChooseFile => 'Scegli file';

  @override
  String get imageSourceCameraFailed => 'Impossibile scattare la foto';

  @override
  String get settingsCachedDocuments => 'Documenti nella cache';

  @override
  String settingsCacheUsage(String used, String limit) {
    return '$used MiB utilizzati su $limit MiB';
  }

  @override
  String settingsCacheExplanation(String limit) {
    return 'I file oltre $limit MiB non vengono memorizzati nella cache. La pulizia conserva i recenti, i documenti aperti e le modifiche non salvate; per riaprire i file nella cache dovrai selezionarli di nuovo.';
  }

  @override
  String get settingsClearCachedDocuments => 'Svuota la cache dei documenti';

  @override
  String get settingsCacheUnavailable =>
      'Dimensione della cache non disponibile';

  @override
  String get settingsCacheClearFailed =>
      'Impossibile svuotare la cache dei documenti. Riprova.';

  @override
  String get printOptionsPrinter => 'Stampante';

  @override
  String get printOptionsNativePrinter =>
      'Scegli la stampante, il vassoio carta, il colore, la stampa fronte-retro e le proprietà del dispositivo nella successiva finestra di stampa del sistema. Mantieni la scala al 100% e il numero di copie a 1 per usare l’impaginazione mostrata qui.';

  @override
  String get printOptionsPages => 'Pagine';

  @override
  String get printOptionsSelected => 'Selezionate';

  @override
  String get printOptionsPageRange => 'Pagine (ad esempio, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Aggiungi file…';

  @override
  String get printOptionsAddFailed =>
      'Impossibile aggiungere i file selezionati.';

  @override
  String get printOptionsGetWindow => 'Seleziona area';

  @override
  String get printOptionsClearWindow => 'Azzera area';

  @override
  String get printOptionsWindowHint =>
      'Traccia un rettangolo su questa pagina originale per scegliere l’area da stampare.';

  @override
  String get printOptionsPaper => 'Carta';

  @override
  String get printOptionsPaperSize => 'Formato carta';

  @override
  String get printOptionsPageSize => 'Usa il formato pagina del documento';

  @override
  String get printOptionsOrientation => 'Orientamento';

  @override
  String get printOptionsAuto => 'Automatico';

  @override
  String get printOptionsPortrait => 'Verticale';

  @override
  String get printOptionsLandscape => 'Orizzontale';

  @override
  String get printOptionsCopies => 'Copie';

  @override
  String get printOptionsCollate => 'Fascicola';

  @override
  String get printOptionsReverse => 'Inverti l’ordine delle pagine';

  @override
  String get printOptionsLayout => 'Impaginazione';

  @override
  String get printOptionsScaling => 'Ridimensionamento pagina';

  @override
  String get printOptionsScaleNone => 'Nessuno (dimensioni effettive)';

  @override
  String get printOptionsFitPaper => 'Adatta alla carta';

  @override
  String get printOptionsReducePaper => 'Riduci al formato carta';

  @override
  String get printOptionsFitMargins => 'Adatta entro i margini';

  @override
  String get printOptionsReduceMargins => 'Riduci entro i margini';

  @override
  String get printOptionsCustomScale => 'Scala personalizzata';

  @override
  String get printOptionsMultiple => 'Più pagine per foglio';

  @override
  String get printOptionsScalePercent => 'Scala (%)';

  @override
  String get printOptionsMargin => 'Margini (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Pagine per foglio';

  @override
  String get printOptionsPageOrder => 'Ordine delle pagine';

  @override
  String get printOptionsHorizontal => 'Orizzontale';

  @override
  String get printOptionsHorizontalReverse => 'Orizzontale inverso';

  @override
  String get printOptionsVertical => 'Verticale';

  @override
  String get printOptionsVerticalReverse => 'Verticale inverso';

  @override
  String get printOptionsBorder => 'Stampa i bordi delle pagine';

  @override
  String get printOptionsRotation => 'Rotazione (senso orario)';

  @override
  String get printOptionsNoRotation => 'Nessuna';

  @override
  String get printOptionsCenter => 'Centra sulla carta';

  @override
  String get printOptionsOffsetX => 'Spostamento a destra (pt)';

  @override
  String get printOptionsOffsetY => 'Spostamento in basso (pt)';

  @override
  String get printOptionsContents => 'Contenuto da stampare';

  @override
  String get printOptionsDocumentAndMarkups => 'Documento e annotazioni';

  @override
  String get printOptionsDocumentOnly => 'Solo documento';

  @override
  String get printOptionsMarkupsOnly => 'Solo annotazioni';

  @override
  String get printOptionsDimPage => 'Attenua il contenuto della pagina';

  @override
  String get printOptionsDimMarkups => 'Attenua le annotazioni';

  @override
  String get printOptionsHyperlinks =>
      'Stampa i collegamenti ipertestuali visibili';

  @override
  String get printOptionsDefaults => 'Predefiniti';

  @override
  String get printOptionsInvalidNumber =>
      'Inserisci numeri validi prima di stampare.';

  @override
  String get printOptionsInvalidValue => 'Valore non valido';

  @override
  String get printOptionsMarginGuide =>
      'Le linee rosse indicano i margini e non vengono stampate.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Area: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Originale: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Foglio: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Foglio $sheet di $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Impossibile preparare questa impaginazione. Controlla il formato carta, i margini e la scala.';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get add => 'Hinzufügen';

  @override
  String get appSigAddLogo => 'Logo hinzufügen…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Alle $pageCount Seiten';
  }

  @override
  String get appSigAppearance => 'Darstellung';

  @override
  String get appSigAppearanceDescription =>
      'Die Signatur wird dort gezeichnet, wo Sie sie platziert haben. Name und Details des Unterzeichners werden immer angezeigt; Sie können eine handgezeichnete Markierung und einen Logo-Hintergrund hinzufügen.';

  @override
  String appSigApplyTo(String label) {
    return 'Anwenden auf: $label';
  }

  @override
  String get appSigApplyToPages => 'Auf Seiten anwenden…';

  @override
  String get appSigChooseCertificate => 'Zertifikatsdatei auswählen…';

  @override
  String get appSigChooseKeyDescription =>
      'Wählen Sie Ihren privaten Schlüssel (RSA, PEM oder DER) und dessen Zertifikatsdatei. Der Schlüssel wird nur zum Signieren verwendet und niemals gespeichert.';

  @override
  String get appSigChoosePngOrJpeg => 'Wählen Sie ein PNG- oder JPEG-Bild.';

  @override
  String get appSigChoosePrivateKey => 'Privaten Schlüssel auswählen…';

  @override
  String get appSigContactInfo => 'Kontaktinformationen';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Die Unterschrift konnte nicht erfasst werden.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Das Zertifikat konnte nicht gelesen werden: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Der Schlüssel konnte nicht gelesen werden: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Eine Signatur auf diesem Gerät erstellen';

  @override
  String appSigDate(String date) {
    return 'Datum: $date';
  }

  @override
  String get appSigDigitallySign => 'Digital signieren';

  @override
  String get appSigDrawSignature => 'Unterschrift zeichnen…';

  @override
  String get appSigFieldHelper =>
      'Leer lassen, um ein neues Signaturfeld zu erstellen.';

  @override
  String get appSigFieldLabel => 'Vorhandenes Signaturfeld (optional)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zertifikate',
      one: '1 Zertifikat',
    );
    return '$_temp0 · gültig von $validFrom bis $validUntil';
  }

  @override
  String get appSigIntro =>
      'Eine digitale Signatur beweist, dass Sie dieses Dokument signiert haben und dass es seitdem nicht verändert wurde. Wählen Sie, wie Sie signieren möchten.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Der ausgewählte Schlüssel oder das Zertifikat konnte nicht gelesen werden.';

  @override
  String get appSigKeylessDescription =>
      'Am einfachsten. Wir bestätigen Ihre Identität per E-Mail und signieren für Sie, mit einem vertrauenswürdigen Zeitstempel. Nichts zu installieren oder einzurichten.';

  @override
  String get appSigKeylessIdentity => 'Schlüssellose Identität';

  @override
  String get appSigKeylessSignInExpired =>
      'Ihre schlüssellose Anmeldung ist abgelaufen. Bitte melden Sie sich erneut an.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Schlüssellose Anmeldung fehlgeschlagen: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Schlüssellos · mit Zeitstempel · Gültigkeit unbekannt';

  @override
  String get appSigKeylessWebNote =>
      'Die Anmeldung mit Ihrer E-Mail ist der einfachste Weg — sie ist in den DartPDF-Desktop- und -Mobil-Apps verfügbar. Aus Sicherheitsgründen kann sie nicht in einem Webbrowser ausgeführt werden.';

  @override
  String get appSigLocation => 'Ort';

  @override
  String get appSigLogoAdded => 'Logo hinzugefügt ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Seiten $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Vorschau - das signierte Feld kann leicht abweichen.';

  @override
  String get appSigReason => 'Grund';

  @override
  String appSigReasonLine(String reason) {
    return 'Grund: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Anmeldung wird aktualisiert…';

  @override
  String get appSigRemoveLogo => 'Logo entfernen';

  @override
  String get appSigRemoveSignature => 'Signatur entfernen';

  @override
  String get appSigSelfSignedDescription =>
      'Keine Anmeldung oder Dateien erforderlich. Am besten für den persönlichen Gebrauch — sie wird für das nächste Mal auf diesem Gerät gespeichert. Einige PDF-Reader zeigen sie als \"signiert, Gültigkeit unbekannt\" an, was für eine selbst erstellte Signatur normal ist.';

  @override
  String get appSigSelfSignedIdentity => 'Selbstsignierte Identität';

  @override
  String get appSigSelfSignedSubtitle =>
      'Selbstsigniert · Gültigkeit unbekannt';

  @override
  String get appSigShowSignatureOnPages => 'Signatur auf Seiten anzeigen';

  @override
  String get appSigSign => 'Signieren';

  @override
  String get appSigSignInWithEmail => 'Mit Ihrer E-Mail anmelden';

  @override
  String get appSigSignatureAdded => 'Signatur hinzugefügt ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Digital signiert von $signerName';
  }

  @override
  String get appSigSigner => 'Unterzeichner';

  @override
  String get appSigSigningYouIn => 'Sie werden angemeldet…';

  @override
  String get appSigThisPageOnly => 'Nur diese Seite';

  @override
  String get appSigUseOwnCertificate => 'Eigenes Zertifikat verwenden';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Für ein Signaturzertifikat Ihrer Organisation';

  @override
  String get appSigX509Signer => 'X.509-Unterzeichner';

  @override
  String get apply => 'Anwenden';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get clear => 'Leeren';

  @override
  String get close => 'Schließen';

  @override
  String get copy => 'Kopieren';

  @override
  String get cut => 'Ausschneiden';

  @override
  String get delete => 'Löschen';

  @override
  String get done => 'Fertig';

  @override
  String get edit => 'Bearbeiten';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Diese $count PDFs in einem neuen Tab öffnen oder ihre Seiten in \"$title\" einfügen?',
      one:
          'Dieses PDF in einem neuen Tab öffnen oder seine Seiten in \"$title\" einfügen?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abgelegte PDFs hinzufügen',
      one: 'Abgelegtes PDF hinzufügen',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Anmerkungstext kopiert';

  @override
  String get editorAppMenuTooltip => 'DartPDF-Menü';

  @override
  String get editorCancelOcr => 'OCR abbrechen';

  @override
  String get editorClearRecentFiles => 'Zuletzt verwendete Dateien löschen';

  @override
  String get editorCloseAll => 'Alle schließen';

  @override
  String get editorCloseOthers => 'Andere schließen';

  @override
  String get editorCloseTab => 'Tab schließen';

  @override
  String get editorCloseTabsToRight => 'Tabs rechts schließen';

  @override
  String get editorCompareFailedTitle => 'Vergleich fehlgeschlagen';

  @override
  String editorCompareTitle(String title) {
    return 'Vergleichen: $title';
  }

  @override
  String get editorCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get editorCopySelectedTextTooltip => 'Ausgewählten Text kopieren (⌘C)';

  @override
  String get editorCopyText => 'Text kopieren';

  @override
  String editorCouldNotExport(String title) {
    return '$title konnte nicht exportiert werden';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Stempel konnten nicht importiert werden: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Die abgelegten PDFs konnten nicht eingefügt werden',
      one: 'Das abgelegte PDF konnte nicht eingefügt werden',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return '$title konnte nicht geöffnet werden\n$error';
  }

  @override
  String get editorCouldNotOpenFolder =>
      'Der übergeordnete Ordner konnte nicht geöffnet werden';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Die zweite Datei konnte nicht geöffnet werden\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Die ausgewählte Datei konnte nicht geöffnet werden\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return '$url konnte nicht geöffnet werden';
  }

  @override
  String editorCouldNotPrint(String title) {
    return '$title konnte nicht gedruckt werden';
  }

  @override
  String editorCouldNotReopen(String title) {
    return '$title konnte nicht erneut geöffnet werden';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Digitale Signatur nicht möglich: $error';
  }

  @override
  String get editorDiscard => 'Verwerfen';

  @override
  String get editorDiscardChangesTitle => 'Änderungen verwerfen?';

  @override
  String get editorDocumentSigned => 'Dokument digital signiert';

  @override
  String get editorDownload => 'Herunterladen';

  @override
  String get editorDropToOpen => 'PDF ablegen zum Öffnen';

  @override
  String get editorDropToOpenOrInsert => 'PDF ablegen zum Öffnen oder Einfügen';

  @override
  String get editorInsertPages => 'Seiten einfügen';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '$count eingefügt; $files konnten nicht gelesen werden';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDFs in $title eingefügt',
      one: 'Seiten in $title eingefügt',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Ungültiger Link: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Dieses Dokument hat versucht, JavaScript auszuführen (ignoriert)';

  @override
  String get editorLoadingFullDocument => 'Vollständiges Dokument wird geladen';

  @override
  String get editorMenuCompareWith => 'Vergleichen mit…';

  @override
  String get editorMenuDigitallySign => 'Digital signieren…';

  @override
  String get editorMenuDigitallySigning => 'Wird digital signiert…';

  @override
  String get editorMenuExportImage => 'Seite als Bild exportieren…';

  @override
  String get editorMenuNewDocument => 'Neues Dokument…';

  @override
  String get editorMenuNewWindow => 'Neues Fenster';

  @override
  String get editorMoveToNewWindow => 'In neues Fenster verschieben';

  @override
  String get editorUnableToOpenNewWindow =>
      'Neues Fenster konnte nicht geöffnet werden';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'PDF öffnen…';

  @override
  String get editorMenuPrint => 'Drucken…';

  @override
  String get editorMenuSaveAs => 'Speichern unter…';

  @override
  String get editorMenuScanDocument => 'In neues Dokument scannen…';

  @override
  String get editorMenuInsertDocument => 'Dokument einfügen…';

  @override
  String get editorMenuInsertScan => 'Scan einfügen…';

  @override
  String get editorScanFailed => 'Dokument konnte nicht gescannt werden.';

  @override
  String get editorInsertedScan => 'Gescannte Seiten eingefügt.';

  @override
  String get editorMenuSettings => 'Einstellungen';

  @override
  String get editorMenuSectionFile => 'Datei';

  @override
  String get editorMenuSectionDocument => 'Dieses Dokument';

  @override
  String get editorMenuSectionApp => 'App';

  @override
  String get editorMenuReadOnly => 'Schreibgeschützt';

  @override
  String get editorMenuSearchActions => 'Aktionen suchen…';

  @override
  String get paletteHint => 'Aktionen, Werkzeuge und Bereiche suchen';

  @override
  String get paletteNoMatch => 'Kein Befehl gefunden';

  @override
  String get paletteKeyHints => '↑↓ Auswahl · ⏎ Ausführen · Esc Schließen';

  @override
  String paletteCount(int count) {
    return '$count Befehle';
  }

  @override
  String paletteCountFiltered(int count, int total) {
    return '$count von $total';
  }

  @override
  String get paletteSourceMenu => 'Menü';

  @override
  String get paletteSourcePanel => 'Bereich';

  @override
  String get paletteSourceView => 'Ansicht';

  @override
  String get paletteSourceFile => 'Datei';

  @override
  String paletteSourceTool(String group) {
    return 'Werkzeug „$group“';
  }

  @override
  String get paletteNeedsDocument => 'Erfordert ein geöffnetes Dokument';

  @override
  String editorNamedAction(String name) {
    return 'Benannte Aktion: $name';
  }

  @override
  String get editorNoRecentFiles => 'Keine zuletzt verwendeten Dateien';

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
      'Öffnen Sie ein Dokument, bevor Sie OCR ausführen';

  @override
  String get editorOpenFailedTitle => 'Öffnen fehlgeschlagen';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In neuen Tabs öffnen',
      one: 'In neuem Tab öffnen',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'PDF in einem neuen Tab öffnen';

  @override
  String get editorOpenRecent => 'Zuletzt geöffnet';

  @override
  String get editorViewAllRecentFiles =>
      'Alle zuletzt verwendeten Dateien anzeigen…';

  @override
  String get editorOpenTabs => 'Offene Tabs';

  @override
  String get editorOpeningDocumentSemantic => 'Dokument wird geöffnet';

  @override
  String get editorOpeningPdf => 'PDF wird geöffnet…';

  @override
  String editorOpeningTitle(String title) {
    return '$title wird geöffnet…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Seite $number';
  }

  @override
  String get editorPreviewComparison => 'Vergleich';

  @override
  String get editorPreviewCouldNotOpen => 'Konnte nicht geöffnet werden';

  @override
  String get editorPreviewOpening => 'Wird geöffnet';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Nicht gespeicherte Änderungen in $count Dokumenten aus der letzten Sitzung wiederhergestellt.',
      one:
          'Nicht gespeicherte Änderungen aus der letzten Sitzung wiederhergestellt.',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'Signatur entfernt';

  @override
  String get editorSnapshotCopied =>
      'Schnappschuss in die Zwischenablage kopiert';

  @override
  String get editorSnapshotCopyFailed =>
      'Schnappschuss konnte nicht in die Zwischenablage kopiert werden';

  @override
  String get editorTabs => 'Tabs';

  @override
  String editorTabsOpenCount(int count) {
    return '$count offen';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dokumente haben nicht gespeicherte Änderungen.',
      one: 'Ein Dokument hat nicht gespeicherte Änderungen.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Nicht unterstützte Aktion: $type';
  }

  @override
  String get editorUntitled => 'Ohne Titel';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version ist verfügbar.';
  }

  @override
  String get editorUpdateLater => 'Später';

  @override
  String get updateInstallNow => 'Jetzt aktualisieren';

  @override
  String get updateDownloadingTitle => 'Update wird heruntergeladen';

  @override
  String get updatePreparing => 'Wird vorbereitet…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Wird heruntergeladen… $percent%';
  }

  @override
  String get updateRestarting => 'Neustart, um das Update abzuschließen…';

  @override
  String get updateHandedOff =>
      'Update heruntergeladen. Installationsprogramm wird geöffnet…';

  @override
  String updateFailed(String error) {
    return 'Update fehlgeschlagen: $error';
  }

  @override
  String get editorViewAllTabs => 'Alle Tabs anzeigen';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Exportieren';

  @override
  String get imgExportFormat => 'Format';

  @override
  String get imgExportResolution => 'Auflösung';

  @override
  String get imgExportTitle => 'Seite als Bild exportieren';

  @override
  String get newDocCreate => 'Erstellen';

  @override
  String get newDocLandscape => 'Querformat';

  @override
  String get newDocOrientation => 'Ausrichtung';

  @override
  String get newDocPageSize => 'Seitengröße';

  @override
  String get newDocPortrait => 'Hochformat';

  @override
  String get newDocTitle => 'Neues Dokument';

  @override
  String get none => 'Keine';

  @override
  String get ocrAlreadyRunning =>
      'OCR läuft bereits - warten Sie, bis es fertig ist, oder brechen Sie es ab';

  @override
  String get ocrBrowserInitFailed =>
      'Browser-OCR konnte nicht initialisiert werden';

  @override
  String get ocrCancelled => 'OCR abgebrochen';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR nach $count Textabschnitten abgebrochen',
      one: 'OCR nach 1 Textabschnitt abgebrochen',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Herunterladen';

  @override
  String ocrDownloadFailed(String error) {
    return 'Das OCR-Modell konnte nicht heruntergeladen werden: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Zum Hinzufügen einer auswählbaren Textebene wird das On-Device-OCR-Modell$size benötigt. Es wird einmal heruntergeladen und läuft danach offline.\n\nModell: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'OCR-Modell herunterladen?';

  @override
  String ocrFailed(String error) {
    return 'OCR fehlgeschlagen: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'On-Device-OCR ist auf dieser Plattform nicht verfügbar';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR hat $count Textabschnitte hinzugefügt - der Seitentext ist jetzt auswählbar',
      one:
          'OCR hat 1 Textabschnitt hinzugefügt - der Seitentext ist jetzt auswählbar',
      zero: 'OCR hat auf diesen Seiten keinen Text gefunden',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Web-OCR lädt ein Florence-2-Vision-Language-Modell herunter und führt es lokal mit WebGPU/WASM über Transformers.js aus. Die PDF-Seiten bleiben in diesem Browser; nur die Modelldateien werden bei der ersten Verwendung abgerufen.';

  @override
  String get ocrWebPromptTitle => 'KI-OCR in diesem Browser ausführen?';

  @override
  String get ocrWebStart => 'OCR starten';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Einfügen';

  @override
  String get printDlgPreparing => 'Wird vorbereitet…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Seite $rendered von $total wird gerendert…';
  }

  @override
  String get printDlgTitle => 'Wird gedruckt';

  @override
  String get printPreviewAll => 'Alle';

  @override
  String get printPreviewCurrent => 'Aktuell';

  @override
  String get printPreviewFrom => 'Von';

  @override
  String get printPreviewNextPage => 'Nächste Seite';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Seite $page von $total';
  }

  @override
  String get printPreviewPreviousPage => 'Vorherige Seite';

  @override
  String get printPreviewPrint => 'Drucken';

  @override
  String get printPreviewRange => 'Bereich';

  @override
  String printPreviewRangeError(int total) {
    return 'Geben Sie einen Seitenbereich zwischen 1 und $total ein.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Zu druckende Seiten: $count';
  }

  @override
  String get printPreviewTitle => 'Druckvorschau';

  @override
  String get printPreviewTo => 'Bis';

  @override
  String get printPreviewUnavailable => 'Vorschau nicht verfügbar';

  @override
  String get redo => 'Wiederholen';

  @override
  String get remove => 'Entfernen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get save => 'Speichern';

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsCheckNow => 'Jetzt prüfen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageSystem => 'Systemstandard';

  @override
  String get settingsCheckingForUpdates => 'Nach Updates wird gesucht…';

  @override
  String get settingsCouldNotOpenDownload =>
      'Der Download konnte nicht geöffnet werden';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Die Systemeinstellungen konnten nicht geöffnet werden';

  @override
  String get settingsDeveloperTools => 'Entwicklerwerkzeuge';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Metriken, Protokolle, Rendermodi (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '$version herunterladen';
  }

  @override
  String get settingsOpenSettings => 'Einstellungen öffnen';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gemerkt',
      one: '1 gemerkt',
      zero: 'Keine zuletzt verwendeten Dateien',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Zuletzt verwendete Dateien';

  @override
  String get settingsSetUpAsDefault => 'Als Standardanwendung einrichten';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String settingsUpToDate(String version) {
    return 'Sie verwenden die neueste Version ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Version $version ist verfügbar (Sie haben $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Nach Updates konnte nicht gesucht werden. Versuchen Sie es später erneut.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Sie haben $name $version.';
  }

  @override
  String get settingsNightlyUpdates => 'Nightly-Updates';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'Automatische Update-Benachrichtigungen für unsignierte Windows-Testbuilds aus main erhalten.';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsViewSource => 'Quellcode auf GitHub anzeigen';

  @override
  String get undo => 'Rückgängig';

  @override
  String get welcomeOpenPdf => 'PDF öffnen';

  @override
  String get welcomePickAgainToReopen => 'Erneut auswählen zum Wiederöffnen';

  @override
  String get welcomeRecent => 'Zuletzt verwendet';

  @override
  String get welcomeSearchRecentFiles =>
      'Zuletzt verwendete Dateien durchsuchen';

  @override
  String get welcomeNoMatchingRecentFiles =>
      'Keine zuletzt verwendeten Dateien entsprechen der Suche';

  @override
  String get welcomeRemoveFromRecent => 'Aus zuletzt verwendet entfernen';

  @override
  String get welcomeTapToReopen => 'Zum erneuten Öffnen tippen';

  @override
  String get welcomeViewAsGrid => 'Rasteransicht';

  @override
  String get welcomeViewAsList => 'Listenansicht';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web':
            'Installieren Sie die Web-App und wählen Sie sie dann für PDF-Dateien aus.',
        'windows':
            'Öffnen Sie die Windows-Standard-App-Einstellungen für PDFs.',
        'macos': 'Folgen Sie den „Immer öffnen mit“-Schritten im Finder.',
        'linux':
            'Verwenden Sie die Einstellungen für Standardanwendungen Ihres Desktops.',
        'android':
            'Wählen Sie DartPDF beim Öffnen eines PDFs und tippen Sie dann auf Immer.',
        'ios':
            'Verwenden Sie Teilen oder Öffnen in in der Dateien-App, um PDFs hierher zu senden.',
        'other': 'Konfigurieren Sie den PDF-Dateihandler Ihres Systems.',
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
            'Installieren Sie DartPDF zuerst über Ihren Browser. Verwenden Sie dann die Dateihandler-Einstellungen des Browsers oder Betriebssystems, um PDF-Dateien mit der installierten App zu verknüpfen.',
        'windows':
            'Die Windows-Einstellungen öffnen sich unter Standard-Apps. Suchen Sie nach „.pdf“ oder „PDF“, wählen Sie die aktuelle PDF-App und dann DartPDF.',
        'macos':
            'Wählen Sie im Finder ein beliebiges PDF, wählen Sie Ablage > Informationen, erweitern Sie „Öffnen mit“, wählen Sie DartPDF und klicken Sie dann auf „Alle ändern…“.',
        'linux':
            'Öffnen Sie Ihre Desktop-Einstellungen für Standardanwendungen oder klicken Sie mit der rechten Maustaste auf ein PDF in Dateien, wählen Sie Eigenschaften und legen Sie DartPDF als Standard für PDF-Dokumente fest.',
        'android':
            'Öffnen Sie ein PDF aus Dateien oder Downloads, wählen Sie DartPDF in der App-Auswahl und dann Immer. Wenn bereits eine andere App PDFs öffnet, löschen Sie zuerst deren Standardeinstellungen in den Android-Einstellungen.',
        'ios':
            'iOS bietet keinen globalen Standard-PDF-Editor. Verwenden Sie Dateien > Teilen oder drücken Sie lange auf ein PDF und wählen Sie Teilen/Öffnen in, dann DartPDF.',
        'other':
            'Verwenden Sie die Systemeinstellungen für Dateihandler, um PDF-Dokumente mit DartPDF zu verknüpfen.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'OCR-Modell wird heruntergeladen…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Modell wird heruntergeladen $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'OCR wird abgeschlossen…';

  @override
  String get fileTypePdf => 'PDF-Dokumente';

  @override
  String get fileTypeImages => 'Bilder';

  @override
  String get fileTypeStampBundle => 'DartPDF-Stempel';

  @override
  String get appSigKeyFileType => 'Private RSA-Schlüssel';

  @override
  String get appSigCertificateFileType => 'X.509-Zertifikate';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Wählen Sie mindestens ein X.509-Zertifikat aus.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Zertifikat $index ist kein gültiges X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'Der private Schlüssel passt zu keinem ausgewählten RSA-Zertifikat.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Verschlüsselte private Schlüssel werden nicht unterstützt. Wählen Sie einen unverschlüsselten RSA-PKCS#1- oder PKCS#8-Schlüssel.';

  @override
  String get appSigErrorKeyNotRsa =>
      'Der private Schlüssel ist kein unverschlüsselter RSA-PKCS#1- oder PKCS#8-Schlüssel.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Es wurden keine X.509-Zertifikate gefunden.';

  @override
  String get imageSourceTakePhoto => 'Foto aufnehmen';

  @override
  String get imageSourceChooseFile => 'Datei auswählen';

  @override
  String get imageSourceCameraFailed => 'Foto konnte nicht aufgenommen werden';

  @override
  String get settingsCachedDocuments => 'Zwischengespeicherte Dokumente';

  @override
  String settingsCacheUsage(String used, String limit) {
    return '$used MiB von $limit MiB belegt';
  }

  @override
  String settingsCacheExplanation(String limit) {
    return 'Dateien über $limit MiB werden nicht zwischengespeichert. Beim Leeren bleiben die Liste zuletzt geöffneter Dateien, offene Dokumente und ungespeicherte Änderungen erhalten; zwischengespeicherte Dateien müssen zum Öffnen erneut ausgewählt werden.';
  }

  @override
  String get settingsClearCachedDocuments =>
      'Zwischengespeicherte Dokumente löschen';

  @override
  String get settingsCacheUnavailable => 'Cache-Größe nicht verfügbar';

  @override
  String get settingsCacheClearFailed =>
      'Zwischengespeicherte Dokumente konnten nicht gelöscht werden. Erneut versuchen.';

  @override
  String get printOptionsPrinter => 'Drucker';

  @override
  String get printOptionsNativePrinter =>
      'Wählen Sie im anschließenden Systemdruckdialog den Drucker, das Papierfach, Farbe, beidseitigen Druck und die Geräteeigenschaften. Lassen Sie die Skalierung bei 100 % und die Kopienanzahl bei 1, um das hier angezeigte Layout zu verwenden.';

  @override
  String get printOptionsPages => 'Seiten';

  @override
  String get printOptionsSelected => 'Ausgewählt';

  @override
  String get printOptionsPageRange => 'Seiten (zum Beispiel 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Dateien hinzufügen…';

  @override
  String get printOptionsAddFailed =>
      'Die ausgewählten Dateien konnten nicht hinzugefügt werden.';

  @override
  String get printOptionsGetWindow => 'Bereich auswählen';

  @override
  String get printOptionsClearWindow => 'Bereich aufheben';

  @override
  String get printOptionsWindowHint =>
      'Ziehen Sie auf dieser Originalseite ein Rechteck auf, um den Druckbereich auszuwählen.';

  @override
  String get printOptionsPaper => 'Papier';

  @override
  String get printOptionsPaperSize => 'Papierformat';

  @override
  String get printOptionsPageSize => 'Seitenformat des Dokuments verwenden';

  @override
  String get printOptionsOrientation => 'Ausrichtung';

  @override
  String get printOptionsAuto => 'Automatisch';

  @override
  String get printOptionsPortrait => 'Hochformat';

  @override
  String get printOptionsLandscape => 'Querformat';

  @override
  String get printOptionsCopies => 'Kopien';

  @override
  String get printOptionsCollate => 'Sortieren';

  @override
  String get printOptionsReverse => 'Umgekehrte Seitenreihenfolge';

  @override
  String get printOptionsLayout => 'Seitenlayout';

  @override
  String get printOptionsScaling => 'Seitenskalierung';

  @override
  String get printOptionsScaleNone => 'Keine (tatsächliche Größe)';

  @override
  String get printOptionsFitPaper => 'An Papier anpassen';

  @override
  String get printOptionsReducePaper => 'Auf Papiergröße verkleinern';

  @override
  String get printOptionsFitMargins => 'An Seitenränder anpassen';

  @override
  String get printOptionsReduceMargins => 'Auf Seitenränder verkleinern';

  @override
  String get printOptionsCustomScale => 'Benutzerdefinierte Skalierung';

  @override
  String get printOptionsMultiple => 'Mehrere Seiten pro Blatt';

  @override
  String get printOptionsScalePercent => 'Skalierung (%)';

  @override
  String get printOptionsMargin => 'Seitenränder (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Seiten pro Blatt';

  @override
  String get printOptionsPageOrder => 'Seitenreihenfolge';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal umgekehrt';

  @override
  String get printOptionsVertical => 'Vertikal';

  @override
  String get printOptionsVerticalReverse => 'Vertikal umgekehrt';

  @override
  String get printOptionsBorder => 'Seitenrahmen drucken';

  @override
  String get printOptionsRotation => 'Drehung (im Uhrzeigersinn)';

  @override
  String get printOptionsNoRotation => 'Keine';

  @override
  String get printOptionsCenter => 'Auf Papier zentrieren';

  @override
  String get printOptionsOffsetX => 'Versatz nach rechts (pt)';

  @override
  String get printOptionsOffsetY => 'Versatz nach unten (pt)';

  @override
  String get printOptionsContents => 'Druckinhalt';

  @override
  String get printOptionsDocumentAndMarkups => 'Dokument und Anmerkungen';

  @override
  String get printOptionsDocumentOnly => 'Nur Dokument';

  @override
  String get printOptionsMarkupsOnly => 'Nur Anmerkungen';

  @override
  String get printOptionsDimPage => 'Seiteninhalt abschwächen';

  @override
  String get printOptionsDimMarkups => 'Anmerkungen abschwächen';

  @override
  String get printOptionsHyperlinks => 'Sichtbare Hyperlinks drucken';

  @override
  String get printOptionsDefaults => 'Standardwerte';

  @override
  String get printOptionsInvalidNumber =>
      'Geben Sie vor dem Drucken gültige Zahlen ein.';

  @override
  String get printOptionsInvalidValue => 'Ungültiger Wert';

  @override
  String get printOptionsMarginGuide =>
      'Die roten Linien zeigen die Seitenränder an und werden nicht gedruckt.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Bereich: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Original: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Blatt: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Blatt $sheet von $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Dieses Layout konnte nicht erstellt werden. Prüfen Sie Papierformat, Seitenränder und Skalierung.';
}

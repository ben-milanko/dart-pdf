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
  String exActionJavaScript(String script) {
    return 'Der App angezeigtes JavaScript: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Link: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Benannte Aktion: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Nicht behandelter Aktionstyp: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Anmerkungstext kopiert';

  @override
  String get exApiKeyHelper => 'Gesendet als Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'API-Schlüssel / Token (optional)';

  @override
  String get exAppMenuTooltip => 'DartPDF-Menü';

  @override
  String get exClearRecentFiles => 'Zuletzt verwendete Dateien löschen';

  @override
  String get exCloseTab => 'Tab schließen';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Vergleichen: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Mit einem anderen PDF vergleichen…';

  @override
  String get exCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get exCopySelectedText => 'Ausgewählten Text kopieren (⌘C)';

  @override
  String get exCopyText => 'Text kopieren';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return '$name konnte nicht geöffnet werden\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return '$path konnte nicht geöffnet werden\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return '$url konnte nicht geöffnet werden';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return '$uri konnte nicht geöffnet werden\n$error\n\nIm Web ist dies oft eine CORS-Einschränkung: Der Server muss Access-Control-Allow-Origin senden und die Range-Header freigeben.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return '$title konnte nicht erneut geöffnet werden\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return '$title konnte nicht erneut geöffnet werden - die gespeicherte Kopie ist nicht mehr verfügbar.';
  }

  @override
  String get exDemoNoteHint =>
      'Hier tippen - dieses Textfeld schwebt über der Seite';

  @override
  String get exDiagnosticsCopied =>
      'Diagnosedaten in die Zwischenablage kopiert';

  @override
  String exDownloaded(String name) {
    return '$name heruntergeladen';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '$name heruntergeladen - mit Strg+V wieder in das PDF einfügen';
  }

  @override
  String get exExport => 'Exportieren';

  @override
  String exExportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get exExportPageImageMenu => 'Seite als Bild exportieren…';

  @override
  String get exExportPageImageTitle => 'Seite als Bild exportieren';

  @override
  String get exFeatureShowcase => 'Funktionsübersicht';

  @override
  String get exFormat => 'Format';

  @override
  String get exHide => 'Ausblenden';

  @override
  String get exHorizontalLayout => 'Horizontales Seitenlayout';

  @override
  String get exHowToSetupOcr => 'So richten Sie einen OCR-Server ein';

  @override
  String get exModelName => 'Modellname';

  @override
  String get exNoMessage => 'Keine Nachricht';

  @override
  String get exNoRecentFiles => 'Keine zuletzt verwendeten Dateien';

  @override
  String exNotAValidUrl(String url) {
    return 'Keine gültige URL:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR hat $count Textabschnitte hinzugefügt - der Seitentext ist jetzt auswählbar',
      one:
          'OCR hat 1 Textabschnitt hinzugefügt - der Seitentext ist jetzt auswählbar',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Fügt gescannten Seiten eine auswählbare, durchsuchbare Textebene hinzu, mithilfe eines Vision-Language-OCR-Modells, das Sie selbst hosten (dots.ocr auf vLLM oder ein beliebiger OpenAI-kompatibler OCR-Endpunkt).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR fehlgeschlagen: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Öffnen';

  @override
  String get exOpenDocumentBeforeOcr =>
      'Öffnen Sie ein Dokument, bevor Sie OCR ausführen';

  @override
  String get exOpenDocumentFirst => 'Öffnen Sie zuerst ein Dokument';

  @override
  String get exOpenFromUrl => 'Von einer URL öffnen…';

  @override
  String get exOpenFromUrlTitle => 'Von einer URL öffnen';

  @override
  String get exOpenInNewTab => 'PDF in einem neuen Tab öffnen';

  @override
  String get exOpenInteractiveDemo => 'Interaktive Demo öffnen';

  @override
  String get exOpenPdf => 'PDF öffnen…';

  @override
  String get exOpenPdfButton => 'PDF öffnen';

  @override
  String get exOpenRecent => 'Zuletzt geöffnet';

  @override
  String get exRecentFiles => 'Zuletzt verwendete Dateien';

  @override
  String get exViewAllRecentFiles =>
      'Alle zuletzt verwendeten Dateien anzeigen…';

  @override
  String get exSearchRecentFiles => 'Zuletzt verwendete Dateien durchsuchen';

  @override
  String get exNoMatchingRecentFiles =>
      'Keine zuletzt verwendeten Dateien entsprechen der Suche';

  @override
  String get exGridView => 'Rasteransicht';

  @override
  String get exListView => 'Listenansicht';

  @override
  String get exOpenUrlDescription =>
      'Streamt das PDF über HTTP-Range-Anfragen mittels PdfHttpByteSource und ruft nur das ab, was der Parser benötigt; fällt auf einen vollständigen Download zurück, wenn der Server keine Range-Unterstützung bietet.';

  @override
  String get exOpeningDocument => 'Dokument wird geöffnet';

  @override
  String get exOpeningPdf => 'PDF wird geöffnet…';

  @override
  String exOpeningTitle(String title) {
    return '$title wird geöffnet…';
  }

  @override
  String get exPdfUrlLabel => 'PDF-URL';

  @override
  String get exPerformanceAuto => 'Leistung: Automatisch';

  @override
  String get exPreparing => 'Wird vorbereitet…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor auf pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Seite $current von $count wird erkannt…';
  }

  @override
  String get exResolution => 'Auflösung';

  @override
  String get exRunOcr => 'OCR ausführen';

  @override
  String get exSaveAs => 'Speichern unter…';

  @override
  String exSaveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String exSavedName(String name) {
    return '$name gespeichert';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '$name gespeichert - mit ⌘V wieder in das PDF einfügen';
  }

  @override
  String exSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Scroll-Indikator-API-Demo';

  @override
  String get exServiceEndpoint => 'Dienstendpunkt';

  @override
  String get exShow => 'Anzeigen';

  @override
  String get exSingleWorker => 'Einzelner Worker';

  @override
  String get exSupplyFeedback => 'Feedback geben…';

  @override
  String get exSwitchToEdit => 'In den Bearbeitungsmodus wechseln';

  @override
  String get exSwitchToReadOnly => 'In den schreibgeschützten Modus wechseln';

  @override
  String get exThemeDark => 'Design: dunkel - zu System wechseln';

  @override
  String get exThemeLight => 'Design: hell - zu dunkel wechseln';

  @override
  String get exThemeSystem => 'Design: System - zu hell wechseln';

  @override
  String get exTryDemo => 'Interaktive Demo ausprobieren';

  @override
  String get exUntitled => 'Ohne Titel';

  @override
  String get exVerticalLayout => 'Vertikales Seitenlayout';

  @override
  String get exViewSource => 'Quellcode auf GitHub anzeigen';

  @override
  String get exWorkerAuto => 'Automatisch';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Leistung: $count Worker',
      one: 'Leistung: einzelner Worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count Worker';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Diese Diagnosedaten dem Bericht anhängen';

  @override
  String get feedbackClearLog => 'Protokoll leeren';

  @override
  String get feedbackCopyDiagnostics => 'Diagnosedaten kopieren';

  @override
  String get feedbackDiagnosticsNotice =>
      'Das Feedback-Formular öffnet sich in Ihrem Browser. Die untenstehenden Diagnosedaten werden nur auf diesem Gerät erfasst und angehängt, um das Problem nachzuvollziehen. Überprüfen Sie sie zuerst - fügen Sie nichts hinzu, das Sie lieber privat halten möchten.';

  @override
  String get feedbackOpenForm => 'Feedback-Formular öffnen';

  @override
  String get feedbackTitle => 'Feedback senden';

  @override
  String get none => 'Keine';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Einfügen';

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
  String get scrollDemoNextPage => 'Nächste Seite';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Seite $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Vorherige Seite';

  @override
  String get scrollDemoSwitchHorizontal => 'Zu horizontalem Layout wechseln';

  @override
  String get scrollDemoSwitchVertical => 'Zu vertikalem Layout wechseln';

  @override
  String get scrollDemoTitle => 'Scroll-Indikator-API';

  @override
  String get undo => 'Rückgängig';

  @override
  String get exFileTypePdf => 'PDF-Dokumente';

  @override
  String get exFileTypeImages => 'Bilder';

  @override
  String get exFileTypeFonts => 'Schriftarten';
}

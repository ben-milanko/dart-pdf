// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get add => 'Toevoegen';

  @override
  String get apply => 'Toepassen';

  @override
  String get cancel => 'Annuleren';

  @override
  String get clear => 'Wissen';

  @override
  String get close => 'Sluiten';

  @override
  String get copy => 'Kopiëren';

  @override
  String get cut => 'Knippen';

  @override
  String get delete => 'Verwijderen';

  @override
  String get done => 'Klaar';

  @override
  String get edit => 'Bewerken';

  @override
  String exActionJavaScript(String script) {
    return 'JavaScript weergegeven aan de app: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Koppeling: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Benoemde actie: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Niet-afgehandeld actietype: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Annotatietekst gekopieerd';

  @override
  String get exApiKeyHelper => 'Verzonden als Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'API-sleutel / token (optioneel)';

  @override
  String get exAppMenuTooltip => 'DartPDF-menu';

  @override
  String get exClearRecentFiles => 'Recente bestanden wissen';

  @override
  String get exCloseTab => 'Tabblad sluiten';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Vergelijken: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Vergelijken met een andere PDF…';

  @override
  String get exCopiedToClipboard => 'Gekopieerd naar klembord';

  @override
  String get exCopySelectedText => 'Geselecteerde tekst kopiëren (⌘C)';

  @override
  String get exCopyText => 'Tekst kopiëren';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Kan $name niet openen\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Kan $path niet openen\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Kan $url niet openen';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Kan $uri niet openen\n$error\n\nOp het web is dit vaak een CORS-beperking: de server moet Access-Control-Allow-Origin verzenden en de Range-headers beschikbaar maken.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Kan $title niet opnieuw openen\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Kan $title niet opnieuw openen - de opgeslagen kopie is niet meer beschikbaar.';
  }

  @override
  String get exDemoNoteHint => 'Typ hier - dit tekstvak zweeft boven de pagina';

  @override
  String get exDiagnosticsCopied =>
      'Diagnostische gegevens naar klembord gekopieerd';

  @override
  String exDownloaded(String name) {
    return '$name gedownload';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '$name gedownload - plak terug in de PDF met Ctrl+V';
  }

  @override
  String get exExport => 'Exporteren';

  @override
  String exExportFailed(String error) {
    return 'Exporteren mislukt: $error';
  }

  @override
  String get exExportPageImageMenu => 'Pagina als afbeelding exporteren…';

  @override
  String get exExportPageImageTitle => 'Pagina als afbeelding exporteren';

  @override
  String get exFeatureShowcase => 'Functiepresentatie';

  @override
  String get exFormat => 'Indeling';

  @override
  String get exHide => 'Verbergen';

  @override
  String get exHorizontalLayout => 'Horizontale pagina-indeling';

  @override
  String get exHowToSetupOcr => 'Een OCR-server instellen';

  @override
  String get exModelName => 'Modelnaam';

  @override
  String get exNoMessage => 'Geen bericht';

  @override
  String get exNoRecentFiles => 'Geen recente bestanden';

  @override
  String exNotAValidUrl(String url) {
    return 'Geen geldige URL:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR heeft $count tekstsegmenten toegevoegd - de paginatekst is nu selecteerbaar',
      one:
          'OCR heeft 1 tekstsegment toegevoegd - de paginatekst is nu selecteerbaar',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Voegt een selecteerbare, doorzoekbare tekstlaag toe over gescande pagina\'s met behulp van een visie-taal-OCR-model dat u zelf host (dots.ocr op vLLM, of een OpenAI-compatibel OCR-eindpunt).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR mislukt: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Openen';

  @override
  String get exOpenDocumentBeforeOcr =>
      'Open een document voordat u OCR uitvoert';

  @override
  String get exOpenDocumentFirst => 'Open eerst een document';

  @override
  String get exOpenFromUrl => 'Openen vanaf een URL…';

  @override
  String get exOpenFromUrlTitle => 'Openen vanaf een URL';

  @override
  String get exOpenInNewTab => 'PDF openen in een nieuw tabblad';

  @override
  String get exOpenInteractiveDemo => 'De interactieve demo openen';

  @override
  String get exOpenPdf => 'Een PDF openen…';

  @override
  String get exOpenPdfButton => 'Een PDF openen';

  @override
  String get exOpenRecent => 'Recent openen';

  @override
  String get exOpenUrlDescription =>
      'Streamt de PDF via HTTP Range-verzoeken met PdfHttpByteSource, waarbij alleen wordt opgehaald wat de parser nodig heeft en teruggevallen wordt op een volledige download wanneer de server geen range-ondersteuning heeft.';

  @override
  String get exOpeningDocument => 'Document openen';

  @override
  String get exOpeningPdf => 'PDF openen…';

  @override
  String exOpeningTitle(String title) {
    return '$title openen…';
  }

  @override
  String get exPdfUrlLabel => 'PDF-URL';

  @override
  String get exPerformanceAuto => 'Prestaties: Automatisch';

  @override
  String get exPreparing => 'Voorbereiden…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor op pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Pagina $current van $count herkennen…';
  }

  @override
  String get exResolution => 'Resolutie';

  @override
  String get exRunOcr => 'OCR uitvoeren';

  @override
  String get exSaveAs => 'Opslaan als…';

  @override
  String exSaveFailed(String error) {
    return 'Opslaan mislukt: $error';
  }

  @override
  String exSavedName(String name) {
    return '$name opgeslagen';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '$name opgeslagen - plak terug in de PDF met ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Opgeslagen naar $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Scroll-indicator-API-demo';

  @override
  String get exServiceEndpoint => 'Service-eindpunt';

  @override
  String get exShow => 'Tonen';

  @override
  String get exSingleWorker => 'Enkele worker';

  @override
  String get exSupplyFeedback => 'Feedback geven…';

  @override
  String get exSwitchToEdit => 'Overschakelen naar bewerkmodus';

  @override
  String get exSwitchToReadOnly => 'Overschakelen naar alleen-lezen';

  @override
  String get exThemeDark => 'Thema: donker - overschakelen naar systeem';

  @override
  String get exThemeLight => 'Thema: licht - overschakelen naar donker';

  @override
  String get exThemeSystem => 'Thema: systeem - overschakelen naar licht';

  @override
  String get exTryDemo => 'Probeer de interactieve demo';

  @override
  String get exUntitled => 'Naamloos';

  @override
  String get exVerticalLayout => 'Verticale pagina-indeling';

  @override
  String get exViewSource => 'Broncode bekijken op GitHub';

  @override
  String get exWorkerAuto => 'Automatisch';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Prestaties: $count workers',
      one: 'Prestaties: enkele worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count workers';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Deze diagnostische gegevens aan het rapport toevoegen';

  @override
  String get feedbackClearLog => 'Logboek wissen';

  @override
  String get feedbackCopyDiagnostics => 'Diagnostische gegevens kopiëren';

  @override
  String get feedbackDiagnosticsNotice =>
      'Het feedbackformulier opent in uw browser. De onderstaande diagnostische gegevens worden alleen op dit apparaat verzameld en toegevoegd om het probleem te helpen reproduceren. Bekijk ze eerst - neem niets op wat u liever privé houdt.';

  @override
  String get feedbackOpenForm => 'Feedbackformulier openen';

  @override
  String get feedbackTitle => 'Feedback verzenden';

  @override
  String get none => 'Geen';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Plakken';

  @override
  String get redo => 'Opnieuw';

  @override
  String get remove => 'Verwijderen';

  @override
  String get rename => 'Naam wijzigen';

  @override
  String get reset => 'Herstellen';

  @override
  String get save => 'Opslaan';

  @override
  String get scrollDemoNextPage => 'Volgende pagina';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Pagina $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Vorige pagina';

  @override
  String get scrollDemoSwitchHorizontal =>
      'Overschakelen naar horizontale indeling';

  @override
  String get scrollDemoSwitchVertical =>
      'Overschakelen naar verticale indeling';

  @override
  String get scrollDemoTitle => 'Scroll-indicator-API';

  @override
  String get undo => 'Ongedaan maken';

  @override
  String get exFileTypePdf => 'PDF-documenten';

  @override
  String get exFileTypeImages => 'Afbeeldingen';

  @override
  String get exFileTypeFonts => 'Lettertypen';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - deel $part.pdf';
  }
}

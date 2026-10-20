// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class DartPdfPrintingLocalizationsDe extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get cancel => 'Abbrechen';

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
  String get printPreviewUnavailable => 'Vorschau nicht verfügbar';

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

  @override
  String get printOptionsChoosePrinter => 'Drucker auswählen';

  @override
  String get printOptionsNoPrinters =>
      'Es sind keine Drucker installiert. Fügen Sie in den Windows-Einstellungen einen Drucker hinzu und versuchen Sie es erneut.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'Der gespeicherte Drucker „$printer“ ist nicht verfügbar. Wählen Sie einen Drucker aus, um fortzufahren.';
  }

  @override
  String get printOptionsPrinterError =>
      'Die Druckereinstellungen konnten nicht geladen werden. Prüfen Sie die Druckerverbindung und versuchen Sie es erneut.';

  @override
  String get printOptionsRetry => 'Erneut versuchen';

  @override
  String get printOptionsColor => 'Farbe';

  @override
  String get printOptionsGrayscale => 'Schwarzweiß';

  @override
  String get printOptionsDuplex => 'Beidseitiger Druck';

  @override
  String get printOptionsSimplex => 'Einseitig';

  @override
  String get printOptionsLongEdge => 'An langer Kante wenden';

  @override
  String get printOptionsShortEdge => 'An kurzer Kante wenden';

  @override
  String get printOptionsTray => 'Papierfach';

  @override
  String get printOptionsDefaultTray => 'Druckerstandard';

  @override
  String get printOptionsProperties => 'Druckereigenschaften…';

  @override
  String get printOptionsDirectPrinter =>
      '„Drucken“ sendet diesen Auftrag direkt an den ausgewählten Drucker.';

  @override
  String get printOptionsPropertiesError =>
      'Die Druckereigenschaften konnten nicht geöffnet werden.';

  @override
  String get printOptionsLoadingPrinters => 'Drucker werden geladen…';
}

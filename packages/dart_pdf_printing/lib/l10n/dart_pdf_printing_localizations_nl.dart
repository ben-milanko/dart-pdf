// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class DartPdfPrintingLocalizationsNl extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get cancel => 'Annuleren';

  @override
  String get printDlgPreparing => 'Voorbereiden…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Pagina $rendered van $total renderen…';
  }

  @override
  String get printDlgTitle => 'Afdrukken';

  @override
  String get printPreviewAll => 'Alle';

  @override
  String get printPreviewCurrent => 'Huidige';

  @override
  String get printPreviewNextPage => 'Volgende pagina';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Pagina $page van $total';
  }

  @override
  String get printPreviewPreviousPage => 'Vorige pagina';

  @override
  String get printPreviewPrint => 'Afdrukken';

  @override
  String get printPreviewRange => 'Bereik';

  @override
  String printPreviewRangeError(int total) {
    return 'Voer een paginabereik tussen 1 en $total in.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Af te drukken pagina\'s: $count';
  }

  @override
  String get printPreviewTitle => 'Afdrukvoorbeeld';

  @override
  String get printPreviewUnavailable => 'Voorbeeld niet beschikbaar';

  @override
  String get printOptionsPrinter => 'Printer';

  @override
  String get printOptionsNativePrinter =>
      'Kies hierna de printer, papierlade, kleur, dubbelzijdig afdrukken en apparaateigenschappen in het afdrukvenster van het systeem. Laat de schaal op 100% en het aantal exemplaren op 1 staan om de indeling uit dit voorbeeld te gebruiken.';

  @override
  String get printOptionsPages => 'Pagina\'s';

  @override
  String get printOptionsSelected => 'Geselecteerd';

  @override
  String get printOptionsPageRange => 'Pagina\'s (bijvoorbeeld 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Bestanden toevoegen…';

  @override
  String get printOptionsAddFailed =>
      'De geselecteerde bestanden konden niet worden toegevoegd.';

  @override
  String get printOptionsGetWindow => 'Gebied kiezen';

  @override
  String get printOptionsClearWindow => 'Gebied wissen';

  @override
  String get printOptionsWindowHint =>
      'Sleep een rechthoek op deze bronpagina om het afdrukgebied te kiezen.';

  @override
  String get printOptionsPaper => 'Papier';

  @override
  String get printOptionsPaperSize => 'Papierformaat';

  @override
  String get printOptionsPageSize => 'Paginaformaat van document gebruiken';

  @override
  String get printOptionsOrientation => 'Afdrukstand';

  @override
  String get printOptionsAuto => 'Automatisch';

  @override
  String get printOptionsPortrait => 'Staand';

  @override
  String get printOptionsLandscape => 'Liggend';

  @override
  String get printOptionsCopies => 'Exemplaren';

  @override
  String get printOptionsCollate => 'Sorteren';

  @override
  String get printOptionsReverse => 'Paginavolgorde omkeren';

  @override
  String get printOptionsLayout => 'Pagina-indeling';

  @override
  String get printOptionsScaling => 'Paginaschaal';

  @override
  String get printOptionsScaleNone => 'Geen (ware grootte)';

  @override
  String get printOptionsFitPaper => 'Aanpassen aan papier';

  @override
  String get printOptionsReducePaper => 'Verkleinen tot papierformaat';

  @override
  String get printOptionsFitMargins => 'Aanpassen aan marges';

  @override
  String get printOptionsReduceMargins => 'Verkleinen tot binnen marges';

  @override
  String get printOptionsCustomScale => 'Aangepaste schaal';

  @override
  String get printOptionsMultiple => 'Meerdere pagina\'s per vel';

  @override
  String get printOptionsScalePercent => 'Schaal (%)';

  @override
  String get printOptionsMargin => 'Marges (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Pagina\'s per vel';

  @override
  String get printOptionsPageOrder => 'Paginavolgorde';

  @override
  String get printOptionsHorizontal => 'Horizontaal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontaal omgekeerd';

  @override
  String get printOptionsVertical => 'Verticaal';

  @override
  String get printOptionsVerticalReverse => 'Verticaal omgekeerd';

  @override
  String get printOptionsBorder => 'Paginaranden afdrukken';

  @override
  String get printOptionsRotation => 'Rotatie (met de klok mee)';

  @override
  String get printOptionsNoRotation => 'Geen';

  @override
  String get printOptionsCenter => 'Centreren op papier';

  @override
  String get printOptionsOffsetX => 'Verschuiving naar rechts (pt)';

  @override
  String get printOptionsOffsetY => 'Verschuiving naar beneden (pt)';

  @override
  String get printOptionsContents => 'Af te drukken inhoud';

  @override
  String get printOptionsDocumentAndMarkups => 'Document en annotaties';

  @override
  String get printOptionsDocumentOnly => 'Alleen document';

  @override
  String get printOptionsMarkupsOnly => 'Alleen annotaties';

  @override
  String get printOptionsDimPage => 'Pagina-inhoud lichter afdrukken';

  @override
  String get printOptionsDimMarkups => 'Annotaties lichter afdrukken';

  @override
  String get printOptionsHyperlinks => 'Zichtbare hyperlinks afdrukken';

  @override
  String get printOptionsDefaults => 'Standaardinstellingen';

  @override
  String get printOptionsInvalidNumber =>
      'Voer geldige getallen in voordat u afdrukt.';

  @override
  String get printOptionsInvalidValue => 'Ongeldige waarde';

  @override
  String get printOptionsMarginGuide =>
      'Rode lijnen geven de marges aan en worden niet afgedrukt.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Gebied: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Bron: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Vel: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Vel $sheet van $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Deze indeling kon niet worden voorbereid. Controleer het papierformaat, de marges en de schaal.';

  @override
  String get printOptionsChoosePrinter => 'Een printer kiezen';

  @override
  String get printOptionsNoPrinters =>
      'Er zijn geen printers geïnstalleerd. Voeg een printer toe in Windows-instellingen en probeer het opnieuw.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'De opgeslagen printer “$printer” is niet beschikbaar. Kies een printer om door te gaan.';
  }

  @override
  String get printOptionsPrinterError =>
      'De printerinstellingen konden niet worden geladen. Controleer de printerverbinding en probeer het opnieuw.';

  @override
  String get printOptionsRetry => 'Opnieuw proberen';

  @override
  String get printOptionsColor => 'Kleur';

  @override
  String get printOptionsGrayscale => 'Zwart-wit';

  @override
  String get printOptionsDuplex => 'Dubbelzijdig afdrukken';

  @override
  String get printOptionsSimplex => 'Enkelzijdig';

  @override
  String get printOptionsLongEdge => 'Omslaan over lange zijde';

  @override
  String get printOptionsShortEdge => 'Omslaan over korte zijde';

  @override
  String get printOptionsTray => 'Papierlade';

  @override
  String get printOptionsDefaultTray => 'Printerstandaard';

  @override
  String get printOptionsProperties => 'Printereigenschappen…';

  @override
  String get printOptionsDirectPrinter =>
      'Afdrukken stuurt deze taak rechtstreeks naar de geselecteerde printer.';

  @override
  String get printOptionsPropertiesError =>
      'De printereigenschappen konden niet worden geopend.';

  @override
  String get printOptionsLoadingPrinters => 'Printers laden…';
}

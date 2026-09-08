// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class DartPdfPrintingLocalizationsIt extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get cancel => 'Annulla';

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
  String get printPreviewUnavailable => 'Anteprima non disponibile';

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

  @override
  String get printOptionsChoosePrinter => 'Scegli una stampante';

  @override
  String get printOptionsNoPrinters =>
      'Nessuna stampante installata. Aggiungi una stampante nelle Impostazioni di Windows, quindi riprova.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'La stampante salvata «$printer» non è disponibile. Scegli una stampante per continuare.';
  }

  @override
  String get printOptionsPrinterError =>
      'Impossibile caricare le impostazioni della stampante. Controlla il collegamento della stampante e riprova.';

  @override
  String get printOptionsRetry => 'Riprova';

  @override
  String get printOptionsColor => 'Colore';

  @override
  String get printOptionsGrayscale => 'Bianco e nero';

  @override
  String get printOptionsDuplex => 'Stampa fronte/retro';

  @override
  String get printOptionsSimplex => 'Solo fronte';

  @override
  String get printOptionsLongEdge => 'Capovolgi sul lato lungo';

  @override
  String get printOptionsShortEdge => 'Capovolgi sul lato corto';

  @override
  String get printOptionsTray => 'Vassoio carta';

  @override
  String get printOptionsDefaultTray => 'Predefinito della stampante';

  @override
  String get printOptionsProperties => 'Proprietà stampante…';

  @override
  String get printOptionsDirectPrinter =>
      'Stampa invia questo lavoro direttamente alla stampante selezionata.';

  @override
  String get printOptionsPropertiesError =>
      'Impossibile aprire le proprietà della stampante.';

  @override
  String get printOptionsLoadingPrinters => 'Caricamento delle stampanti…';
}

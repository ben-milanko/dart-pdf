// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class DartPdfPrintingLocalizationsPl extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get cancel => 'Anuluj';

  @override
  String get printDlgPreparing => 'Przygotowywanie…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Renderowanie strony $rendered z $total…';
  }

  @override
  String get printDlgTitle => 'Drukowanie';

  @override
  String get printPreviewAll => 'Wszystkie';

  @override
  String get printPreviewCurrent => 'Bieżąca';

  @override
  String get printPreviewNextPage => 'Następna strona';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Strona $page z $total';
  }

  @override
  String get printPreviewPreviousPage => 'Poprzednia strona';

  @override
  String get printPreviewPrint => 'Drukuj';

  @override
  String get printPreviewRange => 'Zakres';

  @override
  String printPreviewRangeError(int total) {
    return 'Podaj zakres stron od 1 do $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Strony do wydruku: $count';
  }

  @override
  String get printPreviewTitle => 'Podgląd wydruku';

  @override
  String get printPreviewUnavailable => 'Podgląd niedostępny';

  @override
  String get printOptionsPrinter => 'Drukarka';

  @override
  String get printOptionsNativePrinter =>
      'W następnym, systemowym oknie drukowania wybierz drukarkę, podajnik papieru, kolor, druk dwustronny i właściwości urządzenia. Pozostaw skalę 100% i liczbę kopii 1, aby użyć widocznego tutaj układu.';

  @override
  String get printOptionsPages => 'Strony';

  @override
  String get printOptionsSelected => 'Zaznaczone';

  @override
  String get printOptionsPageRange => 'Strony (na przykład 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Dodaj pliki…';

  @override
  String get printOptionsAddFailed => 'Nie udało się dodać wybranych plików.';

  @override
  String get printOptionsGetWindow => 'Wybierz obszar';

  @override
  String get printOptionsClearWindow => 'Wyczyść obszar';

  @override
  String get printOptionsWindowHint =>
      'Przeciągnij prostokąt na tej stronie źródłowej, aby wybrać obszar do wydrukowania.';

  @override
  String get printOptionsPaper => 'Papier';

  @override
  String get printOptionsPaperSize => 'Rozmiar papieru';

  @override
  String get printOptionsPageSize => 'Użyj rozmiaru strony dokumentu';

  @override
  String get printOptionsOrientation => 'Orientacja';

  @override
  String get printOptionsAuto => 'Automatyczna';

  @override
  String get printOptionsPortrait => 'Pionowa';

  @override
  String get printOptionsLandscape => 'Pozioma';

  @override
  String get printOptionsCopies => 'Kopie';

  @override
  String get printOptionsCollate => 'Sortuj kopie';

  @override
  String get printOptionsReverse => 'Odwróć kolejność stron';

  @override
  String get printOptionsLayout => 'Układ strony';

  @override
  String get printOptionsScaling => 'Skalowanie strony';

  @override
  String get printOptionsScaleNone => 'Brak (rozmiar rzeczywisty)';

  @override
  String get printOptionsFitPaper => 'Dopasuj do papieru';

  @override
  String get printOptionsReducePaper => 'Zmniejsz do rozmiaru papieru';

  @override
  String get printOptionsFitMargins => 'Dopasuj do marginesów';

  @override
  String get printOptionsReduceMargins => 'Zmniejsz do marginesów';

  @override
  String get printOptionsCustomScale => 'Skala niestandardowa';

  @override
  String get printOptionsMultiple => 'Wiele stron na arkuszu';

  @override
  String get printOptionsScalePercent => 'Skala (%)';

  @override
  String get printOptionsMargin => 'Marginesy (pkt)';

  @override
  String get printOptionsPagesPerSheet => 'Strony na arkuszu';

  @override
  String get printOptionsPageOrder => 'Kolejność stron';

  @override
  String get printOptionsHorizontal => 'Poziomo';

  @override
  String get printOptionsHorizontalReverse => 'Poziomo, od końca';

  @override
  String get printOptionsVertical => 'Pionowo';

  @override
  String get printOptionsVerticalReverse => 'Pionowo, od końca';

  @override
  String get printOptionsBorder => 'Drukuj obramowania stron';

  @override
  String get printOptionsRotation =>
      'Obrót (zgodnie z ruchem wskazówek zegara)';

  @override
  String get printOptionsNoRotation => 'Brak';

  @override
  String get printOptionsCenter => 'Wyśrodkuj na papierze';

  @override
  String get printOptionsOffsetX => 'Przesunięcie w prawo (pkt)';

  @override
  String get printOptionsOffsetY => 'Przesunięcie w dół (pkt)';

  @override
  String get printOptionsContents => 'Zawartość wydruku';

  @override
  String get printOptionsDocumentAndMarkups => 'Dokument i adnotacje';

  @override
  String get printOptionsDocumentOnly => 'Tylko dokument';

  @override
  String get printOptionsMarkupsOnly => 'Tylko adnotacje';

  @override
  String get printOptionsDimPage => 'Rozjaśnij zawartość strony';

  @override
  String get printOptionsDimMarkups => 'Rozjaśnij adnotacje';

  @override
  String get printOptionsHyperlinks => 'Drukuj widoczne hiperłącza';

  @override
  String get printOptionsDefaults => 'Ustawienia domyślne';

  @override
  String get printOptionsInvalidNumber =>
      'Przed drukowaniem wprowadź prawidłowe liczby.';

  @override
  String get printOptionsInvalidValue => 'Nieprawidłowa wartość';

  @override
  String get printOptionsMarginGuide =>
      'Czerwone linie wskazują marginesy i nie są drukowane.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Obszar: $width × $height pkt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Źródło: $width × $height pkt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Arkusz: $width × $height pkt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Arkusz $sheet z $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Nie udało się przygotować tego układu. Sprawdź rozmiar papieru, marginesy i skalę.';

  @override
  String get printOptionsChoosePrinter => 'Wybierz drukarkę';

  @override
  String get printOptionsNoPrinters =>
      'Nie ma zainstalowanych drukarek. Dodaj drukarkę w Ustawieniach systemu Windows i spróbuj ponownie.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'Zapisana drukarka „$printer” jest niedostępna. Wybierz drukarkę, aby kontynuować.';
  }

  @override
  String get printOptionsPrinterError =>
      'Nie udało się wczytać ustawień drukarki. Sprawdź połączenie z drukarką i spróbuj ponownie.';

  @override
  String get printOptionsRetry => 'Ponów próbę';

  @override
  String get printOptionsColor => 'Kolor';

  @override
  String get printOptionsGrayscale => 'Czarno-białe';

  @override
  String get printOptionsDuplex => 'Druk dwustronny';

  @override
  String get printOptionsSimplex => 'Jednostronnie';

  @override
  String get printOptionsLongEdge => 'Odwracaj przy długiej krawędzi';

  @override
  String get printOptionsShortEdge => 'Odwracaj przy krótkiej krawędzi';

  @override
  String get printOptionsTray => 'Podajnik papieru';

  @override
  String get printOptionsDefaultTray => 'Domyślne ustawienie drukarki';

  @override
  String get printOptionsProperties => 'Właściwości drukarki…';

  @override
  String get printOptionsDirectPrinter =>
      'Drukuj wysyła to zadanie bezpośrednio do wybranej drukarki.';

  @override
  String get printOptionsPropertiesError =>
      'Nie udało się otworzyć właściwości drukarki.';

  @override
  String get printOptionsLoadingPrinters => 'Wczytywanie drukarek…';
}

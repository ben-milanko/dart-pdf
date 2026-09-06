// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get add => 'Dodaj';

  @override
  String get apply => 'Zastosuj';

  @override
  String get cancel => 'Anuluj';

  @override
  String get clear => 'Wyczyść';

  @override
  String get close => 'Zamknij';

  @override
  String get copy => 'Kopiuj';

  @override
  String get cut => 'Wytnij';

  @override
  String get delete => 'Usuń';

  @override
  String get done => 'Gotowe';

  @override
  String get edit => 'Edytuj';

  @override
  String exActionJavaScript(String script) {
    return 'JavaScript udostępniony aplikacji: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Łącze: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Akcja nazwana: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Nieobsługiwany typ akcji: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Skopiowano tekst adnotacji';

  @override
  String get exApiKeyHelper => 'Wysyłane jako Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Klucz API / token (opcjonalnie)';

  @override
  String get exAppMenuTooltip => 'Menu DartPDF';

  @override
  String get exClearRecentFiles => 'Wyczyść ostatnie pliki';

  @override
  String get exCloseTab => 'Zamknij kartę';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Porównaj: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Porównaj z innym plikiem PDF…';

  @override
  String get exCopiedToClipboard => 'Skopiowano do schowka';

  @override
  String get exCopySelectedText => 'Kopiuj zaznaczony tekst (⌘C)';

  @override
  String get exCopyText => 'Kopiuj tekst';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Nie udało się otworzyć $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Nie udało się otworzyć $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Nie udało się otworzyć $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Nie udało się otworzyć $uri\n$error\n\nW internecie jest to często ograniczenie CORS: serwer musi wysyłać nagłówek Access-Control-Allow-Origin i udostępniać nagłówki Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Nie udało się ponownie otworzyć $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Nie udało się ponownie otworzyć $title - jego zapisana kopia nie jest już dostępna.';
  }

  @override
  String get exDemoNoteHint =>
      'Pisz tutaj - to pole tekstowe unosi się nad stroną';

  @override
  String get exDiagnosticsCopied => 'Skopiowano diagnostykę do schowka';

  @override
  String exDownloaded(String name) {
    return 'Pobrano $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Pobrano $name - wklej z powrotem do PDF za pomocą Ctrl+V';
  }

  @override
  String get exExport => 'Eksportuj';

  @override
  String exExportFailed(String error) {
    return 'Eksport nie powiódł się: $error';
  }

  @override
  String get exExportPageImageMenu => 'Eksportuj stronę jako obraz…';

  @override
  String get exExportPageImageTitle => 'Eksportuj stronę jako obraz';

  @override
  String get exFeatureShowcase => 'Prezentacja funkcji';

  @override
  String get exFormat => 'Format';

  @override
  String get exHide => 'Ukryj';

  @override
  String get exHorizontalLayout => 'Poziomy układ stron';

  @override
  String get exHowToSetupOcr => 'Jak skonfigurować serwer OCR';

  @override
  String get exModelName => 'Nazwa modelu';

  @override
  String get exNoMessage => 'Brak wiadomości';

  @override
  String get exNoRecentFiles => 'Brak ostatnich plików';

  @override
  String exNotAValidUrl(String url) {
    return 'Nieprawidłowy adres URL:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR dodał $count fragmentów tekstu - tekst strony jest teraz zaznaczalny',
      many:
          'OCR dodał $count fragmentów tekstu - tekst strony jest teraz zaznaczalny',
      few:
          'OCR dodał $count fragmenty tekstu - tekst strony jest teraz zaznaczalny',
      one: 'OCR dodał 1 fragment tekstu - tekst strony jest teraz zaznaczalny',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Dodaje zaznaczalną, przeszukiwalną warstwę tekstu nad zeskanowanymi stronami przy użyciu hostowanego przez Ciebie modelu OCR językowo-wizyjnego (dots.ocr na vLLM lub dowolny punkt końcowy OCR zgodny z OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR nie powiódł się: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Otwórz';

  @override
  String get exOpenDocumentBeforeOcr =>
      'Otwórz dokument przed uruchomieniem OCR';

  @override
  String get exOpenDocumentFirst => 'Najpierw otwórz dokument';

  @override
  String get exOpenFromUrl => 'Otwórz z adresu URL…';

  @override
  String get exOpenFromUrlTitle => 'Otwórz z adresu URL';

  @override
  String get exOpenInNewTab => 'Otwórz PDF w nowej karcie';

  @override
  String get exOpenInteractiveDemo => 'Otwórz interaktywne demo';

  @override
  String get exOpenPdf => 'Otwórz plik PDF…';

  @override
  String get exOpenPdfButton => 'Otwórz plik PDF';

  @override
  String get exOpenRecent => 'Otwórz ostatnie';

  @override
  String get exOpenUrlDescription =>
      'Przesyła strumieniowo PDF za pomocą żądań HTTP Range przez PdfHttpByteSource, pobierając tylko to, czego potrzebuje parser, i przechodząc do pełnego pobierania, gdy serwer nie obsługuje żądań zakresu.';

  @override
  String get exOpeningDocument => 'Otwieranie dokumentu';

  @override
  String get exOpeningPdf => 'Otwieranie pliku PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Otwieranie $title…';
  }

  @override
  String get exPdfUrlLabel => 'Adres URL pliku PDF';

  @override
  String get exPerformanceAuto => 'Wydajność: Automatyczna';

  @override
  String get exPreparing => 'Przygotowywanie…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor na pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Rozpoznawanie strony $current z $count…';
  }

  @override
  String get exResolution => 'Rozdzielczość';

  @override
  String get exRunOcr => 'Uruchom OCR';

  @override
  String get exSaveAs => 'Zapisz jako…';

  @override
  String exSaveFailed(String error) {
    return 'Zapisywanie nie powiodło się: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Zapisano $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Zapisano $name - wklej z powrotem do PDF za pomocą ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Zapisano w $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Demo API wskaźnika przewijania';

  @override
  String get exServiceEndpoint => 'Punkt końcowy usługi';

  @override
  String get exShow => 'Pokaż';

  @override
  String get exSingleWorker => 'Pojedynczy wątek roboczy';

  @override
  String get exSupplyFeedback => 'Prześlij opinię…';

  @override
  String get exSwitchToEdit => 'Przełącz na tryb edycji';

  @override
  String get exSwitchToReadOnly => 'Przełącz na tryb tylko do odczytu';

  @override
  String get exThemeDark => 'Motyw: ciemny - przełącz na systemowy';

  @override
  String get exThemeLight => 'Motyw: jasny - przełącz na ciemny';

  @override
  String get exThemeSystem => 'Motyw: systemowy - przełącz na jasny';

  @override
  String get exTryDemo => 'Wypróbuj interaktywne demo';

  @override
  String get exUntitled => 'Bez tytułu';

  @override
  String get exVerticalLayout => 'Pionowy układ stron';

  @override
  String get exViewSource => 'Zobacz kod źródłowy na GitHub';

  @override
  String get exWorkerAuto => 'Automatycznie';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wydajność: $count wątków roboczych',
      many: 'Wydajność: $count wątków roboczych',
      few: 'Wydajność: $count wątki robocze',
      one: 'Wydajność: pojedynczy wątek roboczy',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count wątków roboczych';
  }

  @override
  String get feedbackAttachDiagnostics => 'Dołącz tę diagnostykę do zgłoszenia';

  @override
  String get feedbackClearLog => 'Wyczyść dziennik';

  @override
  String get feedbackCopyDiagnostics => 'Kopiuj diagnostykę';

  @override
  String get feedbackDiagnosticsNotice =>
      'Formularz opinii otwiera się w przeglądarce. Poniższa diagnostyka jest zbierana tylko na tym urządzeniu i dołączana, aby pomóc odtworzyć problem. Najpierw ją przejrzyj - nie dołączaj niczego, co wolisz zachować dla siebie.';

  @override
  String get feedbackOpenForm => 'Otwórz formularz opinii';

  @override
  String get feedbackTitle => 'Wyślij opinię';

  @override
  String get none => 'Brak';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Wklej';

  @override
  String get redo => 'Ponów';

  @override
  String get remove => 'Usuń';

  @override
  String get rename => 'Zmień nazwę';

  @override
  String get reset => 'Resetuj';

  @override
  String get save => 'Zapisz';

  @override
  String get scrollDemoNextPage => 'Następna strona';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Strona $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Poprzednia strona';

  @override
  String get scrollDemoSwitchHorizontal => 'Przełącz na układ poziomy';

  @override
  String get scrollDemoSwitchVertical => 'Przełącz na układ pionowy';

  @override
  String get scrollDemoTitle => 'API wskaźnika przewijania';

  @override
  String get undo => 'Cofnij';

  @override
  String get exFileTypePdf => 'Dokumenty PDF';

  @override
  String get exFileTypeImages => 'Obrazy';

  @override
  String get exFileTypeFonts => 'Czcionki';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - część $part.pdf';
  }
}

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
  String get appSigAddLogo => 'Dodaj logo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Wszystkie strony ($pageCount)';
  }

  @override
  String get appSigAppearance => 'Wygląd';

  @override
  String get appSigAppearanceDescription =>
      'Podpis jest rysowany w miejscu, w którym go umieszczono. Imię i dane podpisującego są zawsze widoczne; możesz dodać odręczny znak i tło z logo.';

  @override
  String appSigApplyTo(String label) {
    return 'Zastosuj do: $label';
  }

  @override
  String get appSigApplyToPages => 'Zastosuj do stron…';

  @override
  String get appSigChooseCertificate => 'Wybierz plik certyfikatu…';

  @override
  String get appSigChooseKeyDescription =>
      'Wybierz swój klucz prywatny (RSA, PEM lub DER) i jego plik certyfikatu. Klucz jest używany wyłącznie do podpisania i nigdy nie jest zapisywany.';

  @override
  String get appSigChoosePngOrJpeg => 'Wybierz obraz PNG lub JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Wybierz klucz prywatny…';

  @override
  String get appSigContactInfo => 'Dane kontaktowe';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Nie udało się przechwycić podpisu.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Nie udało się odczytać certyfikatu: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Nie udało się odczytać klucza: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Utwórz podpis na tym urządzeniu';

  @override
  String appSigDate(String date) {
    return 'Data: $date';
  }

  @override
  String get appSigDigitallySign => 'Podpisz cyfrowo';

  @override
  String get appSigDrawSignature => 'Narysuj podpis…';

  @override
  String get appSigFieldHelper =>
      'Pozostaw puste, aby utworzyć nowe pole podpisu.';

  @override
  String get appSigFieldLabel => 'Istniejące pole podpisu (opcjonalnie)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certyfikatu',
      many: '$count certyfikatów',
      few: '$count certyfikaty',
      one: '1 certyfikat',
    );
    return '$_temp0 · ważny od $validFrom do $validUntil';
  }

  @override
  String get appSigIntro =>
      'Podpis cyfrowy potwierdza, że podpisałeś ten dokument i że nie został on od tego czasu zmieniony. Wybierz sposób podpisywania.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Nie udało się odczytać wybranego klucza lub certyfikatu.';

  @override
  String get appSigKeylessDescription =>
      'Najłatwiejsze. Potwierdzamy Twoją tożsamość przez e-mail i podpisujemy za Ciebie, z zaufanym znacznikiem czasu. Nic do instalowania ani konfigurowania.';

  @override
  String get appSigKeylessIdentity => 'Tożsamość bez klucza';

  @override
  String get appSigKeylessSignInExpired =>
      'Twoje logowanie bez klucza wygasło. Zaloguj się ponownie.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Logowanie bez klucza nie powiodło się: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Bez klucza · ze znacznikiem czasu · ważność nieznana';

  @override
  String get appSigKeylessWebNote =>
      'Logowanie przez e-mail to najłatwiejszy sposób - jest dostępne w aplikacjach DartPDF na komputery i urządzenia mobilne. Ze względów bezpieczeństwa nie może działać w przeglądarce internetowej.';

  @override
  String get appSigLocation => 'Lokalizacja';

  @override
  String get appSigLogoAdded => 'Dodano logo ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Strony $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Podgląd - podpisane pole może się nieznacznie różnić.';

  @override
  String get appSigReason => 'Powód';

  @override
  String appSigReasonLine(String reason) {
    return 'Powód: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Odświeżanie logowania…';

  @override
  String get appSigRemoveLogo => 'Usuń logo';

  @override
  String get appSigRemoveSignature => 'Usuń podpis';

  @override
  String get appSigSelfSignedDescription =>
      'Nie wymaga logowania ani plików. Najlepsze do użytku osobistego - zostanie zapisane na tym urządzeniu na następny raz. Niektóre czytniki PDF pokażą je jako „podpisano, ważność nieznana”, co jest normalne dla podpisu tworzonego samodzielnie.';

  @override
  String get appSigSelfSignedIdentity => 'Tożsamość samopodpisana';

  @override
  String get appSigSelfSignedSubtitle => 'Samopodpisana · ważność nieznana';

  @override
  String get appSigShowSignatureOnPages => 'Pokaż podpis na stronach';

  @override
  String get appSigSign => 'Podpisz';

  @override
  String get appSigSignInWithEmail => 'Zaloguj się przez e-mail';

  @override
  String get appSigSignatureAdded => 'Dodano podpis ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Podpisano cyfrowo przez $signerName';
  }

  @override
  String get appSigSigner => 'Podpisujący';

  @override
  String get appSigSigningYouIn => 'Logowanie…';

  @override
  String get appSigThisPageOnly => 'Tylko ta strona';

  @override
  String get appSigUseOwnCertificate => 'Użyj własnego certyfikatu';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Do certyfikatu podpisu z Twojej organizacji';

  @override
  String get appSigX509Signer => 'Podpisujący X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Otworzyć te $count plików PDF w nowych kartach, czy wstawić ich strony do „$title”?',
      many:
          'Otworzyć te $count plików PDF w nowych kartach, czy wstawić ich strony do „$title”?',
      few:
          'Otworzyć te $count pliki PDF w nowych kartach, czy wstawić ich strony do „$title”?',
      one:
          'Otworzyć ten plik PDF w nowej karcie, czy wstawić jego strony do „$title”?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dodaj upuszczone pliki PDF',
      many: 'Dodaj upuszczone pliki PDF',
      few: 'Dodaj upuszczone pliki PDF',
      one: 'Dodaj upuszczony plik PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Skopiowano tekst adnotacji';

  @override
  String get editorAppMenuTooltip => 'Menu DartPDF';

  @override
  String get editorCancelOcr => 'Anuluj OCR';

  @override
  String get editorClearRecentFiles => 'Wyczyść ostatnie pliki';

  @override
  String get editorCloseAll => 'Zamknij wszystkie';

  @override
  String get editorCloseOthers => 'Zamknij pozostałe';

  @override
  String get editorCloseTab => 'Zamknij kartę';

  @override
  String get editorCloseTabsToRight => 'Zamknij karty po prawej';

  @override
  String get editorCompareFailedTitle => 'Porównanie nie powiodło się';

  @override
  String editorCompareTitle(String title) {
    return 'Porównaj: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Skopiowano do schowka';

  @override
  String get editorCopySelectedTextTooltip => 'Kopiuj zaznaczony tekst (⌘C)';

  @override
  String get editorCopyText => 'Kopiuj tekst';

  @override
  String editorCouldNotExport(String title) {
    return 'Nie udało się wyeksportować $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Nie udało się zaimportować stempli: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nie udało się wstawić upuszczonych plików PDF',
      many: 'Nie udało się wstawić upuszczonych plików PDF',
      few: 'Nie udało się wstawić upuszczonych plików PDF',
      one: 'Nie udało się wstawić upuszczonego pliku PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Nie udało się otworzyć $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder =>
      'Nie udało się otworzyć folderu zawierającego';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Nie udało się otworzyć drugiego pliku\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Nie udało się otworzyć wybranego pliku\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Nie udało się otworzyć $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Nie udało się wydrukować $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Nie udało się ponownie otworzyć $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Nie udało się podpisać cyfrowo: $error';
  }

  @override
  String get editorDiscard => 'Odrzuć';

  @override
  String get editorDiscardChangesTitle => 'Odrzucić zmiany?';

  @override
  String get editorDocumentSigned => 'Dokument podpisany cyfrowo';

  @override
  String get editorDownload => 'Pobierz';

  @override
  String get editorDropToOpen => 'Upuść PDF, aby otworzyć';

  @override
  String get editorDropToOpenOrInsert => 'Upuść PDF, aby otworzyć lub wstawić';

  @override
  String get editorInsertPages => 'Wstaw strony';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Wstawiono $count; nie udało się odczytać $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wstawiono $count plików PDF do $title',
      many: 'Wstawiono $count plików PDF do $title',
      few: 'Wstawiono $count pliki PDF do $title',
      one: 'Wstawiono strony do $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Nieprawidłowe łącze: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Ten dokument próbował uruchomić kod JavaScript (zignorowano)';

  @override
  String get editorLoadingFullDocument => 'Ładowanie pełnego dokumentu';

  @override
  String get editorMenuCompareWith => 'Porównaj z…';

  @override
  String get editorMenuDigitallySign => 'Podpisz cyfrowo…';

  @override
  String get editorMenuDigitallySigning => 'Podpisywanie cyfrowe…';

  @override
  String get editorMenuExportImage => 'Eksportuj stronę jako obraz…';

  @override
  String get editorMenuNewDocument => 'Nowy dokument…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Otwórz plik PDF…';

  @override
  String get editorMenuPrint => 'Drukuj…';

  @override
  String get editorMenuSaveAs => 'Zapisz jako…';

  @override
  String get editorMenuSettings => 'Ustawienia';

  @override
  String get editorMenuSwitchToEdit => 'Przełącz na tryb edycji';

  @override
  String get editorMenuSwitchToReadOnly => 'Przełącz na tryb tylko do odczytu';

  @override
  String editorNamedAction(String name) {
    return 'Akcja nazwana: $name';
  }

  @override
  String get editorNoRecentFiles => 'Brak ostatnich plików';

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
      'Otwórz dokument przed uruchomieniem OCR';

  @override
  String get editorOpenFailedTitle => 'Otwieranie nie powiodło się';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Otwórz w nowych kartach',
      many: 'Otwórz w nowych kartach',
      few: 'Otwórz w nowych kartach',
      one: 'Otwórz w nowej karcie',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Otwórz PDF w nowej karcie';

  @override
  String get editorOpenRecent => 'Otwórz ostatnie';

  @override
  String get editorOpenTabs => 'Otwarte karty';

  @override
  String get editorOpeningDocumentSemantic => 'Otwieranie dokumentu';

  @override
  String get editorOpeningPdf => 'Otwieranie pliku PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Otwieranie $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Strona $number';
  }

  @override
  String get editorPreviewComparison => 'Porównanie';

  @override
  String get editorPreviewCouldNotOpen => 'Nie udało się otworzyć';

  @override
  String get editorPreviewOpening => 'Otwieranie';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'Usunięto podpis';

  @override
  String get editorSnapshotCopied => 'Skopiowano migawkę do schowka';

  @override
  String get editorSnapshotCopyFailed =>
      'Nie udało się skopiować migawki do schowka';

  @override
  String get editorTabs => 'Karty';

  @override
  String editorTabsOpenCount(int count) {
    return 'Otwarte: $count';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dokumentów ma niezapisane zmiany.',
      many: '$count dokumentów ma niezapisane zmiany.',
      few: '$count dokumenty mają niezapisane zmiany.',
      one: 'Dokument ma niezapisane zmiany.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Nieobsługiwana akcja: $type';
  }

  @override
  String get editorUntitled => 'Bez tytułu';

  @override
  String editorUpdateAvailable(String version) {
    return 'Dostępna jest wersja DartPDF $version.';
  }

  @override
  String get editorUpdateLater => 'Później';

  @override
  String get updateInstallNow => 'Aktualizuj teraz';

  @override
  String get updateDownloadingTitle => 'Pobieranie aktualizacji';

  @override
  String get updatePreparing => 'Przygotowywanie…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Pobieranie… $percent%';
  }

  @override
  String get updateRestarting =>
      'Ponowne uruchamianie, aby dokończyć aktualizację…';

  @override
  String get updateHandedOff => 'Pobrano aktualizację. Otwieranie instalatora…';

  @override
  String updateFailed(String error) {
    return 'Aktualizacja nie powiodła się: $error';
  }

  @override
  String get editorViewAllTabs => 'Wyświetl wszystkie karty';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Eksportuj';

  @override
  String get imgExportFormat => 'Format';

  @override
  String get imgExportResolution => 'Rozdzielczość';

  @override
  String get imgExportTitle => 'Eksportuj stronę jako obraz';

  @override
  String get newDocCreate => 'Utwórz';

  @override
  String get newDocLandscape => 'Poziomo';

  @override
  String get newDocOrientation => 'Orientacja';

  @override
  String get newDocPageSize => 'Rozmiar strony';

  @override
  String get newDocPortrait => 'Pionowo';

  @override
  String get newDocTitle => 'Nowy dokument';

  @override
  String get none => 'Brak';

  @override
  String get ocrAlreadyRunning =>
      'OCR jest już uruchomiony - poczekaj na zakończenie lub anuluj';

  @override
  String get ocrBrowserInitFailed =>
      'Nie udało się zainicjować OCR w przeglądarce';

  @override
  String get ocrCancelled => 'Anulowano OCR';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Anulowano OCR po $count fragmentach tekstu',
      many: 'Anulowano OCR po $count fragmentach tekstu',
      few: 'Anulowano OCR po $count fragmentach tekstu',
      one: 'Anulowano OCR po 1 fragmencie tekstu',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Pobierz';

  @override
  String ocrDownloadFailed(String error) {
    return 'Nie udało się pobrać modelu OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Dodanie zaznaczalnej warstwy tekstu wymaga modelu OCR działającego na urządzeniu$size. Pobiera się raz, a następnie działa offline.\n\nModel: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Pobrać model OCR?';

  @override
  String ocrFailed(String error) {
    return 'OCR nie powiódł się: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'OCR na urządzeniu nie jest dostępny na tej platformie';

  @override
  String ocrResult(int count) {
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
      zero: 'OCR nie znalazł tekstu na tych stronach',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'OCR w przeglądarce pobiera model językowo-wizyjny Florence-2 i uruchamia go lokalnie za pomocą WebGPU/WASM przez Transformers.js. Strony PDF pozostają w tej przeglądarce; przy pierwszym użyciu pobierane są tylko pliki modelu.';

  @override
  String get ocrWebPromptTitle => 'Uruchomić OCR AI w tej przeglądarce?';

  @override
  String get ocrWebStart => 'Uruchom OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Wklej';

  @override
  String get printDlgPreparing => 'Przygotowywanie…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Renderowanie strony $rendered z $total…';
  }

  @override
  String get printDlgTitle => 'Drukowanie';

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
  String get settingsAbout => 'O programie';

  @override
  String get settingsAppearance => 'Wygląd';

  @override
  String get settingsCheckNow => 'Sprawdź teraz';

  @override
  String get settingsLanguage => 'Język';

  @override
  String get settingsLanguageSystem => 'Domyślny systemowy';

  @override
  String get settingsCheckingForUpdates => 'Sprawdzanie aktualizacji…';

  @override
  String get settingsCouldNotOpenDownload =>
      'Nie udało się otworzyć pobierania';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Nie udało się otworzyć ustawień systemowych';

  @override
  String get settingsDeveloperTools => 'Narzędzia programisty';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Metryki, dzienniki, tryby renderowania (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Pobierz $version';
  }

  @override
  String get settingsOpenSettings => 'Otwórz Ustawienia';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zapamiętanych',
      many: '$count zapamiętanych',
      few: '$count zapamiętane',
      one: '1 zapamiętany',
      zero: 'Brak ostatnich plików',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Ostatnie pliki';

  @override
  String get settingsSetUpAsDefault => 'Ustaw jako aplikację domyślną';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsThemeDark => 'Ciemny';

  @override
  String get settingsThemeLight => 'Jasny';

  @override
  String get settingsThemeSystem => 'Systemowy';

  @override
  String get settingsTitle => 'Ustawienia';

  @override
  String settingsUpToDate(String version) {
    return 'Masz najnowszą wersję ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Dostępna jest wersja $version (masz $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Nie udało się sprawdzić aktualizacji. Spróbuj ponownie później.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Masz $name $version.';
  }

  @override
  String get settingsUpdates => 'Aktualizacje';

  @override
  String get settingsViewSource => 'Zobacz kod źródłowy na GitHub';

  @override
  String get undo => 'Cofnij';

  @override
  String get welcomeOpenPdf => 'Otwórz plik PDF';

  @override
  String get welcomePickAgainToReopen => 'Wybierz ponownie, aby otworzyć';

  @override
  String get welcomeRecent => 'Ostatnie';

  @override
  String get welcomeRemoveFromRecent => 'Usuń z ostatnich';

  @override
  String get welcomeTapToReopen => 'Dotknij, aby otworzyć ponownie';

  @override
  String get welcomeViewAsGrid => 'Widok siatki';

  @override
  String get welcomeViewAsList => 'Widok listy';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web':
            'Zainstaluj aplikację internetową, a następnie wybierz ją dla plików PDF.',
        'windows':
            'Otwórz ustawienia aplikacji domyślnych systemu Windows dla plików PDF.',
        'macos': 'Wykonaj kroki „Zawsze otwieraj za pomocą” w Finderze.',
        'linux': 'Użyj ustawień aplikacji domyślnych swojego pulpitu.',
        'android':
            'Wybierz DartPDF podczas otwierania pliku PDF, a następnie dotknij Zawsze.',
        'ios':
            'Użyj opcji Udostępnij lub Otwórz w z aplikacji Pliki, aby wysłać tu pliki PDF.',
        'other': 'Skonfiguruj obsługę plików PDF w swoim systemie.',
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
            'Najpierw zainstaluj DartPDF z przeglądarki. Następnie użyj ustawień obsługi plików w przeglądarce lub systemie operacyjnym, aby powiązać pliki PDF z zainstalowaną aplikacją.',
        'windows':
            'Otworzą się Ustawienia systemu Windows w sekcji Aplikacje domyślne. Wyszukaj „.pdf” lub „PDF”, wybierz bieżącą aplikację PDF, a następnie wybierz DartPDF.',
        'macos':
            'W Finderze zaznacz dowolny plik PDF, wybierz Plik > Informacje, rozwiń sekcję „Otwórz za pomocą”, wybierz DartPDF, a następnie kliknij „Zmień wszystkie…”.',
        'linux':
            'Otwórz ustawienia pulpitu dotyczące aplikacji domyślnych lub kliknij plik PDF prawym przyciskiem myszy w Plikach, wybierz Właściwości i ustaw DartPDF jako domyślną aplikację dla dokumentów PDF.',
        'android':
            'Otwórz plik PDF z aplikacji Pliki lub Pobrane, wybierz DartPDF w oknie wyboru aplikacji, a następnie wybierz Zawsze. Jeśli inna aplikacja już otwiera pliki PDF, najpierw wyczyść jej ustawienia domyślne w Ustawieniach systemu Android.',
        'ios':
            'System iOS nie zapewnia globalnego domyślnego edytora PDF. Użyj Pliki > Udostępnij lub przytrzymaj plik PDF i wybierz Udostępnij/Otwórz w, a następnie wybierz DartPDF.',
        'other':
            'Użyj ustawień systemowych obsługi plików, aby powiązać dokumenty PDF z DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Pobieranie modelu OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Pobieranie modelu $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Kończenie OCR…';

  @override
  String get fileTypePdf => 'Dokumenty PDF';

  @override
  String get fileTypeImages => 'Obrazy';

  @override
  String get fileTypeStampBundle => 'Stemple DartPDF';

  @override
  String get appSigKeyFileType => 'Klucze prywatne RSA';

  @override
  String get appSigCertificateFileType => 'Certyfikaty X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Wybierz co najmniej jeden certyfikat X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Certyfikat $index nie jest prawidłowym X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'Klucz prywatny nie pasuje do żadnego wybranego certyfikatu RSA.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Zaszyfrowane klucze prywatne nie są obsługiwane. Wybierz niezaszyfrowany klucz RSA PKCS#1 lub PKCS#8.';

  @override
  String get appSigErrorKeyNotRsa =>
      'Klucz prywatny nie jest niezaszyfrowanym kluczem RSA PKCS#1 lub PKCS#8.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Nie znaleziono certyfikatów X.509.';

  @override
  String get imageSourceTakePhoto => 'Zrób zdjęcie';

  @override
  String get imageSourceChooseFile => 'Wybierz plik';

  @override
  String get imageSourceCameraFailed => 'Nie udało się zrobić zdjęcia';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class DartPdfEditorLocalizationsPl extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get add => 'Dodaj';

  @override
  String get annotCaret => 'Znak wstawiania';

  @override
  String get annotCircle => 'Okrąg';

  @override
  String get annotFileAttachment => 'Załącznik';

  @override
  String get annotFreeText => 'Pole tekstowe';

  @override
  String get annotHighlight => 'Podświetlenie';

  @override
  String get annotInk => 'Rysunek odręczny';

  @override
  String get annotLine => 'Linia';

  @override
  String get annotLink => 'Łącze';

  @override
  String get annotPolygon => 'Wielokąt';

  @override
  String get annotPolyline => 'Łamana';

  @override
  String get annotRedact => 'Wymazanie';

  @override
  String get annotSquare => 'Prostokąt';

  @override
  String get annotSquiggly => 'Falisty';

  @override
  String get annotStamp => 'Stempel';

  @override
  String get annotStrikeOut => 'Przekreślenie';

  @override
  String get annotText => 'Notatka';

  @override
  String get annotUnderline => 'Podkreślenie';

  @override
  String get annotWidget => 'Pole formularza';

  @override
  String get apply => 'Zastosuj';

  @override
  String get bookmarkAdd => 'Dodaj zakładkę';

  @override
  String get bookmarkAddChild => 'Dodaj zakładkę podrzędną';

  @override
  String get bookmarkCollapse => 'Zwiń';

  @override
  String get bookmarkDelete => 'Usuń zakładkę';

  @override
  String get bookmarkEdit => 'Edytuj zakładkę';

  @override
  String get bookmarkEmpty => 'Brak zakładek';

  @override
  String get bookmarkExpand => 'Rozwiń';

  @override
  String get bookmarkExpandedByDefault => 'Domyślnie rozwinięta';

  @override
  String get bookmarkNoDestination => 'Brak miejsca docelowego';

  @override
  String get bookmarkPageFieldLabel => 'Strona';

  @override
  String bookmarkPageLabel(int number) {
    return 'Strona $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Zakładki';

  @override
  String get bookmarkTitleLabel => 'Tytuł';

  @override
  String get bookmarkUntitled => 'Bez tytułu';

  @override
  String get cancel => 'Anuluj';

  @override
  String get clear => 'Wyczyść';

  @override
  String get close => 'Zamknij';

  @override
  String get colorApplyingChanges => 'Stosowanie zmian kolorów…';

  @override
  String get colorColorFormat => 'Format koloru';

  @override
  String get colorColorTitle => 'Kolor';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wybrano $count kolorów',
      many: 'Wybrano $count kolorów',
      few: 'Wybrano $count kolory',
      one: 'Wybrano $count kolor',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Kolory dokumentu';

  @override
  String get colorFillColors => 'Kolory wypełnienia';

  @override
  String get colorFind => 'Znajdź';

  @override
  String get colorInDocument => 'W dokumencie';

  @override
  String get colorNoColorsFound => 'Nie znaleziono jeszcze kolorów';

  @override
  String get colorNoPageContentColors =>
      'Nie znaleziono kolorów w treści strony';

  @override
  String get colorPalette => 'Paleta';

  @override
  String get colorPickColor => 'Wybierz kolor';

  @override
  String get colorProcessingTitle => 'Przetwarzanie kolorów';

  @override
  String get colorRecent => 'Ostatnie';

  @override
  String get colorReplace => 'Zamień';

  @override
  String get colorReplaceWithTransparent => 'Zamień na przezroczysty';

  @override
  String get colorScanning => 'Skanowanie…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Skanowanie $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Wybrane strony ($count)';
  }

  @override
  String get colorStrokeColors => 'Kolory obrysu';

  @override
  String get colorTolerance => 'Tolerancja';

  @override
  String get colorTransparent => 'Przezroczysty';

  @override
  String get colorWholeDocument => 'Cały dokument';

  @override
  String get compareAfter => 'Po';

  @override
  String get compareBefore => 'Przed';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zmiany',
      many: '$count zmian',
      few: '$count zmiany',
      one: '1 zmiana',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zmiany',
      many: '$count zmian',
      few: '$count zmiany',
      one: '1 zmiana',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(puste)';

  @override
  String get compareNextChange => 'Następna zmiana';

  @override
  String get compareNoChanges => 'Brak zmian';

  @override
  String get compareNoDifferences => 'Brak różnic między dwoma dokumentami';

  @override
  String get compareOverlay => 'Nakładka';

  @override
  String comparePageHeader(int page) {
    return 'Strona $page';
  }

  @override
  String get comparePreviousChange => 'Poprzednia zmiana';

  @override
  String get compareSideBySide => 'Obok siebie';

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
  String get editorViewAuthorNameTitle => 'Imię autora';

  @override
  String get lineStyleDashDot => 'Kreska-kropka';

  @override
  String get lineStyleDashed => 'Kreskowana';

  @override
  String get lineStyleDotted => 'Kropkowana';

  @override
  String get lineStyleSolid => 'Ciągła';

  @override
  String get measCalibrate => 'Kalibruj';

  @override
  String get measCalibrateScale => 'Kalibruj skalę';

  @override
  String get measDepthLabel => 'Głębokość: ';

  @override
  String get measKindAngle => 'Kąt';

  @override
  String get measKindArc => 'Łuk';

  @override
  String get measKindArea => 'Powierzchnia';

  @override
  String get measKindCount => 'Liczba';

  @override
  String get measKindLength => 'Długość';

  @override
  String get measKindNetArea => 'Powierzchnia netto';

  @override
  String get measKindPerimeter => 'Obwód';

  @override
  String get measKindSlope => 'Nachylenie';

  @override
  String get measKindVolume => 'Objętość';

  @override
  String get measLineRepresents => 'Narysowana linia reprezentuje:';

  @override
  String get measMeasure => 'Zmierz';

  @override
  String get measSetScale => 'Ustaw skalę pomiaru';

  @override
  String get measSetScaleButton => 'Ustaw skalę';

  @override
  String get measVolumeDepth => 'Głębokość objętości';

  @override
  String get menuAddNode => 'Dodaj węzeł';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zastosuj adnotacje do stron',
      one: 'Zastosuj adnotację do stron',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Zastosuj do stron…';

  @override
  String get menuBringToFront => 'Przenieś na wierzch';

  @override
  String get menuCheck => 'Zaznacz';

  @override
  String get menuChooseValue => 'Wybierz wartość…';

  @override
  String get menuClearCheck => 'Usuń zaznaczenie';

  @override
  String get menuConvertToCheckBox => 'Zmień na pole wyboru';

  @override
  String get menuConvertToImageButton => 'Zmień na przycisk graficzny';

  @override
  String get menuConvertToTextField => 'Zmień na pole tekstowe';

  @override
  String get menuDeleteField => 'Usuń pole';

  @override
  String get menuEditValue => 'Edytuj wartość…';

  @override
  String get menuFieldName => 'Nazwa pola';

  @override
  String get menuFieldValue => 'Wartość pola';

  @override
  String get menuFlattenForm => 'Spłaszcz formularz';

  @override
  String get menuRecolour => 'Zmień kolor…';

  @override
  String get menuRemoveNode => 'Usuń węzeł';

  @override
  String get menuSetAsDefaultStyle => 'Ustaw jako styl domyślny';

  @override
  String get menuRename => 'Zmień nazwę…';

  @override
  String get menuSelectOption => 'Wybierz opcję';

  @override
  String get menuSendToBack => 'Przenieś na spód';

  @override
  String get menuSetImage => 'Ustaw obraz…';

  @override
  String get menuTextStyle => 'Styl tekstu…';

  @override
  String get none => 'Brak';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Kolor';

  @override
  String get overlayEditText => 'Edytuj tekst';

  @override
  String get overlayFont => 'Czcionka';

  @override
  String get overlayLarger => 'Większy';

  @override
  String get overlayMore => 'Więcej';

  @override
  String get overlayNote => 'Notatka';

  @override
  String get overlaySmaller => 'Mniejszy';

  @override
  String get overlayStampText => 'Tekst stempla';

  @override
  String get overlayUnderline => 'Podkreślenie';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Wprowadź strony od 1 do $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'Ostatnia strona nie może być przed pierwszą.';

  @override
  String get pageRangeFrom => 'Od';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count strony',
      many: '$count stron',
      few: '$count strony',
      one: '1 strona',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Do';

  @override
  String get panelDragToMovePanel => 'Przeciągnij, aby przenieść panel';

  @override
  String get paste => 'Wklej';

  @override
  String get propAlign => 'Wyrównanie';

  @override
  String get propAlignCenter => 'Wyśrodkuj';

  @override
  String get propAlignLeft => 'Wyrównaj do lewej';

  @override
  String get propAlignRight => 'Wyrównaj do prawej';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count adnotacji',
      many: '$count adnotacji',
      few: '$count adnotacje',
      one: '$count adnotacja',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Autor';

  @override
  String get propAutoSize => 'Automatyczny rozmiar';

  @override
  String get propBold => 'Pogrubienie';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'Dołączona czcionka';

  @override
  String get propCallout => 'Objaśnienie';

  @override
  String get propCharSpacing => 'Odstęp znaków';

  @override
  String get propColor => 'Kolor';

  @override
  String get propColour => 'Kolor';

  @override
  String get propContents => 'Zawartość';

  @override
  String get propEditsApplyToAll =>
      'Zmiany dotyczą wszystkich zgodnych adnotacji';

  @override
  String get propFieldName => 'Nazwa pola';

  @override
  String get propFieldTypeCheckBox => 'Pole wyboru';

  @override
  String get propFieldTypeComboBox => 'Pole kombi';

  @override
  String get propFieldTypeImageButton => 'Przycisk graficzny';

  @override
  String get propFieldTypeListBox => 'Lista';

  @override
  String get propFieldTypeRadioGroup => 'Grupa przycisków opcji';

  @override
  String get propFieldTypeSignature => 'Podpis';

  @override
  String get propFieldTypeText => 'Pole tekstowe';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Typ pola: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Nieznane pole';

  @override
  String get propFill => 'Wypełnienie';

  @override
  String get propFont => 'Czcionka';

  @override
  String get propFontSubsetTooltip =>
      'Ta czcionka jest podzbiorem - można wpisać tylko znaki już użyte w dokumencie.';

  @override
  String get propFontWidth => 'Szerokość czcionki';

  @override
  String get propGeometryHeight => 'Wys.';

  @override
  String get propGeometryWidth => 'Szer.';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Kursywa';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Ograniczony zestaw znaków';

  @override
  String get propLineEnd => 'Koniec linii';

  @override
  String get propLineEndingButt => 'Płaskie';

  @override
  String get propLineEndingCircle => 'Okrąg';

  @override
  String get propLineEndingClosedArrow => 'Zamknięta strzałka';

  @override
  String get propLineEndingClosedArrowRev => 'Zamknięta strzałka (odwr.)';

  @override
  String get propLineEndingDiamond => 'Romb';

  @override
  String get propLineEndingOpenArrow => 'Otwarta strzałka';

  @override
  String get propLineEndingOpenArrowRev => 'Otwarta strzałka (odwr.)';

  @override
  String get propLineEndingSlash => 'Ukośnik';

  @override
  String get propLineEndingSquare => 'Kwadrat';

  @override
  String get propLineSpacing => 'Interlinia';

  @override
  String get propLineStart => 'Początek linii';

  @override
  String get propLineType => 'Typ linii';

  @override
  String get propLoadFont => 'Wczytaj czcionkę…';

  @override
  String get propLoadFontSubtitle => 'Plik TTF lub OTF';

  @override
  String get propMoreColors => 'Więcej kolorów…';

  @override
  String get propMultiline => 'Wielowierszowy';

  @override
  String get propNoFill => 'Bez wypełnienia';

  @override
  String get propNoFontsFound => 'Nie znaleziono czcionek';

  @override
  String get propNoOutline => 'Bez obrysu';

  @override
  String get propOpacity => 'Krycie';

  @override
  String get propOutline => 'Obrys';

  @override
  String get propPageLabel => 'Strona';

  @override
  String propPageNumber(int number) {
    return 'Strona $number';
  }

  @override
  String get propPropertiesTitle => 'Właściwości';

  @override
  String get propRecentlyUsed => 'Ostatnio używane';

  @override
  String get propScale => 'Skala';

  @override
  String get propSearchFonts => 'Szukaj czcionek';

  @override
  String get propSectionAllFonts => 'Wszystkie czcionki';

  @override
  String get propSectionAppearance => 'Wygląd';

  @override
  String get propSectionContent => 'Zawartość';

  @override
  String get propSectionFormField => 'Pole formularza';

  @override
  String get propSectionInThisDocument => 'W tym dokumencie';

  @override
  String get propSectionPositionSize => 'Pozycja i rozmiar (pt)';

  @override
  String get propSectionSelection => 'Zaznaczenie';

  @override
  String get propSectionText => 'Tekst';

  @override
  String get propSelectAnnotationPrompt =>
      'Wybierz adnotację, aby zobaczyć jej właściwości';

  @override
  String get propSize => 'Rozmiar';

  @override
  String get propStandardPdfFont => 'Standardowa czcionka PDF';

  @override
  String get propStroke => 'Obrys';

  @override
  String get propStyle => 'Styl';

  @override
  String get propSystemFont => 'Czcionka systemowa';

  @override
  String get propType => 'Typ';

  @override
  String get propUnderline => 'Podkreślenie';

  @override
  String get propVaries => 'Różne';

  @override
  String get redo => 'Ponów';

  @override
  String get reflowNoContent => 'Brak treści do wyodrębnienia';

  @override
  String reflowPageLabel(int number) {
    return 'Strona $number';
  }

  @override
  String get reflowSaveOrShare => 'Zapisz lub udostępnij';

  @override
  String get reflowViewFigure => 'Wyświetl ilustrację';

  @override
  String get remove => 'Usuń';

  @override
  String get rename => 'Zmień nazwę';

  @override
  String get reset => 'Resetuj';

  @override
  String get save => 'Zapisz';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Strona $page';
  }

  @override
  String get sbarCallout => 'Objaśnienie';

  @override
  String get sbarFieldButton => 'Pole przycisku';

  @override
  String get sbarFieldChoice => 'Pole wyboru z listy';

  @override
  String get sbarFieldGeneric => 'Pole formularza';

  @override
  String get sbarFieldSignature => 'Pole podpisu';

  @override
  String get sbarFieldText => 'Pole tekstowe';

  @override
  String get sbarStateAccepted => 'Zaakceptowano';

  @override
  String get sbarStateCancelled => 'Anulowano';

  @override
  String get sbarStateMarked => 'Oznaczono';

  @override
  String get sbarStateRejected => 'Odrzucono';

  @override
  String get sbarStateResolved => 'Rozwiązano';

  @override
  String get sbarStateUnmarked => 'Nieoznaczono';

  @override
  String get searchClearSearch => 'Wyczyść wyszukiwanie';

  @override
  String get searchEmptyHint =>
      'Wyszukaj w dokumencie, aby wyświetlić tu wszystkie dopasowania';

  @override
  String get searchMatchCase => 'Uwzględnij wielkość liter';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dopasowania',
      many: '$count dopasowań',
      few: '$count dopasowania',
      one: '1 dopasowanie',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Następne dopasowanie';

  @override
  String searchNoMatches(String query) {
    return 'Brak dopasowań dla „$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Strona $page';
  }

  @override
  String get searchPreviousMatch => 'Poprzednie dopasowanie';

  @override
  String get searchRegex => 'Wyrażenie regularne';

  @override
  String get searchResultsTitle => 'Wyniki wyszukiwania';

  @override
  String get searchWholeWord => 'Całe słowo';

  @override
  String get shellControls => 'Sterowanie';

  @override
  String get shellDefaultAuthor => 'Domyślny autor…';

  @override
  String get shellHighlightFormFields => 'Podświetl pola formularza';

  @override
  String get shellKeyboardShortcutsMenu => 'Skróty klawiszowe…';

  @override
  String get shellKeyboardShortcutsTitle => 'Skróty klawiszowe';

  @override
  String get shellShortcutsSearchHint => 'Szukaj skrótów';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Żaden skrót nie pasuje do „$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Zaznaczanie';

  @override
  String get shellShortcutGroupMarkup => 'Oznaczenia';

  @override
  String get shellShortcutGroupDraw => 'Rysowanie';

  @override
  String get shellShortcutGroupShapes => 'Kształty';

  @override
  String get shellShortcutGroupInsert => 'Wstawianie';

  @override
  String get shellShortcutGroupMeasure => 'Pomiary';

  @override
  String get shellShortcutGroupEdit => 'Edycja';

  @override
  String get shellNotSet => 'Nie ustawiono';

  @override
  String get shellPageColor => 'Kolor strony…';

  @override
  String get shellPageGrid => 'Siatka stron';

  @override
  String get shellPanelAnnotations => 'Adnotacje';

  @override
  String get shellPanelBookmarks => 'Zakładki';

  @override
  String get shellPanelPages => 'Strony';

  @override
  String get shellPanelProperties => 'Właściwości';

  @override
  String get shellPanelSearchResults => 'Wyniki wyszukiwania';

  @override
  String get shellPanels => 'Panele';

  @override
  String get shellPressAKey => 'Naciśnij klawisz';

  @override
  String get shellPressLetterKeyHint =>
      'Naciśnij klawisz litery lub Delete, aby wyczyścić.';

  @override
  String get shellReflow => 'Przepływ';

  @override
  String get shellReflowText => 'Przepływ tekstu';

  @override
  String get shellResetZoom => 'Resetuj powiększenie';

  @override
  String get shellSectionShell => 'Powłoka';

  @override
  String get shellSectionView => 'Widok';

  @override
  String get shellSettings => 'Ustawienia';

  @override
  String get shellShowAnnotations => 'Pokaż adnotacje';

  @override
  String get shellTabHere => 'Dodaj jako kartę';

  @override
  String get shellUnbound => 'Nieprzypisane';

  @override
  String get shellZoom => 'Powiększenie';

  @override
  String sidebarByAuthor(String author) {
    return 'przez $author';
  }

  @override
  String get sidebarCancelSelection => 'Anuluj zaznaczenie';

  @override
  String get sidebarClearSearch => 'Wyczyść wyszukiwanie';

  @override
  String get sidebarDeleteSelected => 'Usuń zaznaczone';

  @override
  String get sidebarDeleteSignature => 'Usuń podpis';

  @override
  String get sidebarMore => 'Więcej';

  @override
  String get sidebarNoAnnotations => 'Brak adnotacji';

  @override
  String get sidebarNoMatchingAnnotations => 'Brak pasujących adnotacji';

  @override
  String sidebarPageHeader(int number) {
    return 'Strona $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Spowoduje to usunięcie podpisu cyfrowego z dokumentu. Możesz to cofnąć.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Spowoduje to usunięcie podpisu cyfrowego „$name” z dokumentu. Możesz to cofnąć.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Usunąć podpis?';

  @override
  String get sidebarReopen => 'Otwórz ponownie';

  @override
  String get sidebarReply => 'Odpowiedz';

  @override
  String get sidebarResolve => 'Rozwiąż';

  @override
  String get sidebarSearchHint => 'Szukaj adnotacji';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wybrano $count',
      many: 'Wybrano $count',
      few: 'Wybrano $count',
      one: 'Wybrano $count',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'Napisz odpowiedź…';

  @override
  String get sigTitle => 'Podpis';

  @override
  String get signIdCreate => 'Utwórz';

  @override
  String get signIdEmail => 'E-mail (opcjonalnie)';

  @override
  String get signIdName => 'Imię';

  @override
  String get signIdNameHint => 'Twoje imię, tak jak ma się pojawić na podpisie';

  @override
  String get signIdNameRequired => 'Wprowadź imię';

  @override
  String get signIdOrganization => 'Organizacja (opcjonalnie)';

  @override
  String get signIdSelfSignedInfo =>
      'Tworzy to tożsamość podpisaną samodzielnie. Podpisy będą odczytywane jako „podpisano, ważność nieznana” w programie Adobe Acrobat i innych czytnikach - tak samo jak ich własne tożsamości samopodpisane. Zielony znacznik wymaga płatnego, publicznie zaufanego urzędu certyfikacji (CA).';

  @override
  String get signIdTitle => 'Utwórz tożsamość podpisu';

  @override
  String get stampBox => 'Prostokąt';

  @override
  String get stampCircle => 'Okrąg';

  @override
  String get stampCustomCaption => 'Niestandardowy stempel';

  @override
  String get stampDateFormat => 'Format daty';

  @override
  String get stampDeleteComponent => 'Usuń wybrany element';

  @override
  String get stampDeleteStamp => 'Usuń stempel';

  @override
  String get stampEditStamp => 'Edytuj stempel';

  @override
  String get stampExport => 'Eksportuj…';

  @override
  String get stampFieldDate => 'Data';

  @override
  String get stampFieldDateTime => 'Data i godzina';

  @override
  String get stampFieldTime => 'Godzina';

  @override
  String get stampFieldUsername => 'Nazwa użytkownika';

  @override
  String get stampFont => 'Czcionka';

  @override
  String get stampFontBold => 'Pogrubienie';

  @override
  String get stampFontItalic => 'Kursywa';

  @override
  String get stampHeight => 'Wysokość';

  @override
  String get stampImage => 'Obraz';

  @override
  String get stampImport => 'Importuj…';

  @override
  String get stampInsertField => 'Wstaw pole';

  @override
  String get stampMoreColors => 'Więcej kolorów…';

  @override
  String get stampNewStamp => 'Nowy stempel…';

  @override
  String get stampNewStampTitle => 'Nowy stempel';

  @override
  String get stampSelectTextToEdit => 'Wybierz tekst do edycji';

  @override
  String get stampSelectedText => 'Wybrany tekst';

  @override
  String get stampSignature => 'Podpis';

  @override
  String get stampStamps => 'Stemple';

  @override
  String get stampText => 'Tekst';

  @override
  String get stampTime12Hour => '12 godz.';

  @override
  String get stampTime24Hour => '24 godz.';

  @override
  String get stampTimeFormat => 'Format godziny';

  @override
  String get stampWidth => 'Szerokość';

  @override
  String get takeoffArea => 'Powierzchnia';

  @override
  String get takeoffCount => 'Liczba';

  @override
  String get takeoffEmpty => 'Brak pomiarów.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grupy',
      many: '$count grup',
      few: '$count grupy',
      one: '$count grupa',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementy',
      many: '$count elementów',
      few: '$count elementy',
      one: '$count element',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Długość';

  @override
  String get takeoffTitle => 'Przedmiar';

  @override
  String get tbAddInkAnnotation => 'Dodaj adnotację odręczną';

  @override
  String get tbAlign => 'Wyrównanie';

  @override
  String get tbAlignBottom => 'Wyrównaj do dołu';

  @override
  String get tbAlignHorizontalCenters => 'Wyrównaj środki w poziomie';

  @override
  String get tbAlignLeft => 'Wyrównaj do lewej';

  @override
  String get tbAlignRight => 'Wyrównaj do prawej';

  @override
  String get tbAlignTop => 'Wyrównaj do góry';

  @override
  String get tbAlignVerticalCenters => 'Wyrównaj środki w pionie';

  @override
  String get tbAnnotationsFlattened => 'Adnotacje spłaszczone do stron';

  @override
  String get tbApplyRedactionsMessage =>
      'Oznaczona treść zostanie trwale usunięta z dokumentu. Tej operacji nie można cofnąć.';

  @override
  String get tbApplyRedactionsTitle => 'Zastosować wymazania?';

  @override
  String get tbApplyRedactionsTooltip => 'Zastosuj wymazania (nieodwracalne)';

  @override
  String get tbAutosizeTextBox =>
      'Automatyczny rozmiar pola tekstowego (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Narysuj linię o znanej długości, aby skalibrować skalę.';

  @override
  String get tbCharSpacing => 'Odstęp znaków';

  @override
  String get tbCheckBoxOption => 'Pole wyboru';

  @override
  String get tbCheckMarksOnDocument => 'Znaczniki na dokumencie';

  @override
  String get tbColorLabel => 'Kolor';

  @override
  String get tbColorProcessingTooltip =>
      'Przetwarzanie kolorów - znajdź i zamień kolory treści strony';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zamieniono $count kolorów',
      many: 'Zamieniono $count kolorów',
      few: 'Zamieniono $count kolory',
      one: 'Zamieniono 1 kolor',
      zero: 'Nie znaleziono pasujących kolorów',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Zmień na pole wyboru';

  @override
  String get tbConvertToImageButton => 'Zmień na przycisk graficzny';

  @override
  String get tbConvertToTextField => 'Zmień na pole tekstowe';

  @override
  String get tbCornerRadius => 'Promień narożnika';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Usuń $count adnotacji',
      many: 'Usuń $count adnotacji',
      few: 'Usuń $count adnotacje',
      one: 'Usuń adnotację',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Usuń element';

  @override
  String get tbDeleteField => 'Usuń pole';

  @override
  String get tbDiscardDrawing => 'Odrzuć rysunek';

  @override
  String get tbDistributeHorizontally => 'Rozłóż w poziomie';

  @override
  String get tbDistributeVertically => 'Rozłóż w pionie';

  @override
  String get tbDrawNewSignature => 'Narysuj nowy podpis…';

  @override
  String get tbEditAnnotationText => 'Edytuj tekst adnotacji';

  @override
  String get tbEditTextStyle => 'Edytuj tekst i styl';

  @override
  String get tbElement => 'Element';

  @override
  String get tbEraserSize => 'Rozmiar gumki';

  @override
  String get tbFieldActions => 'Akcje pola';

  @override
  String get tbFieldName => 'Nazwa pola';

  @override
  String tbFieldNamed(String name) {
    return 'Pole: $name';
  }

  @override
  String get tbFieldValue => 'Wartość pola';

  @override
  String get tbFill => 'Wypełnienie';

  @override
  String get tbFingerDraws => 'Palec rysuje - dotknij, aby przewijać';

  @override
  String get tbFingerScrolls =>
      'Palec przewija (pióro rysuje) - dotknij, aby rysować';

  @override
  String get tbFlattenAnnotationsTooltip => 'Spłaszcz adnotacje do stron';

  @override
  String get tbFlattenForm => 'Spłaszcz formularz';

  @override
  String get tbFlattenFormBakeValues =>
      'Spłaszcz formularz - utrwal wartości na stronach';

  @override
  String get tbFlattenLabel => 'Spłaszcz';

  @override
  String get tbFont => 'Czcionka';

  @override
  String get tbFontSize => 'Rozmiar czcionki';

  @override
  String get tbFontWidth => 'Szerokość czcionki';

  @override
  String get tbFormFieldsFlattened => 'Pola formularza spłaszczone do stron';

  @override
  String get tbGroupDraw => 'Rysowanie';

  @override
  String get tbGroupEdit => 'Edycja';

  @override
  String get tbGroupInsert => 'Wstawianie';

  @override
  String get tbGroupMarkup => 'Oznaczenia';

  @override
  String get tbGroupMeasure => 'Pomiary';

  @override
  String get tbGroupSelect => 'Zaznaczanie';

  @override
  String get tbGroupShapes => 'Kształty';

  @override
  String get tbImageButtonOption => 'Przycisk graficzny';

  @override
  String get tbLineEnd => 'Koniec linii';

  @override
  String get tbLineSpacing => 'Interlinia';

  @override
  String get tbLineStart => 'Początek linii';

  @override
  String get tbLineType => 'Typ linii';

  @override
  String get tbManageStamps => 'Zarządzaj stemplami…';

  @override
  String get tbMarkupHighlight => 'Podświetlenie';

  @override
  String get tbMarkupHighlightTip => 'Podświetl zaznaczenie';

  @override
  String get tbMarkupSquiggly => 'Faliste podkreślenie';

  @override
  String get tbMarkupSquigglyTip => 'Faliste podkreślenie zaznaczenia';

  @override
  String get tbMarkupStrikeOut => 'Przekreślenie';

  @override
  String get tbMarkupStrikeOutTip => 'Przekreśl zaznaczenie';

  @override
  String get tbMarkupUnderline => 'Podkreślenie';

  @override
  String get tbMarkupUnderlineTip => 'Podkreśl zaznaczenie';

  @override
  String get tbMoreColors => 'Więcej kolorów…';

  @override
  String get tbNameArrow => 'Strzałka';

  @override
  String get tbNameCallout => 'Objaśnienie';

  @override
  String get tbNameCloudPolygon => 'Wielokąt chmurkowy';

  @override
  String get tbNameCount => 'Zliczanie';

  @override
  String get tbNameDigitalSignature => 'Podpis cyfrowy';

  @override
  String get tbNameDraw => 'Rysowanie';

  @override
  String get tbNameEllipse => 'Elipsa';

  @override
  String get tbNameEraser => 'Wymaż linie odręczne';

  @override
  String get tbNameHighlight => 'Zakreślacz';

  @override
  String get tbNameImage => 'Obraz';

  @override
  String get tbNameLine => 'Linia';

  @override
  String get tbNameMeasureAngle => 'Zmierz kąt';

  @override
  String get tbNameMeasureArc => 'Zmierz długość łuku';

  @override
  String get tbNameMeasureArea => 'Zmierz powierzchnię';

  @override
  String get tbNameMeasureDistance => 'Zmierz odległość';

  @override
  String get tbNameMeasurePerimeter => 'Zmierz obwód';

  @override
  String get tbNameMeasureSlope => 'Zmierz nachylenie (wznios/bieg)';

  @override
  String get tbNameMeasureVolume =>
      'Zmierz objętość (powierzchnia × głębokość)';

  @override
  String get tbNameNote => 'Notatka';

  @override
  String get tbNamePolygon => 'Wielokąt';

  @override
  String get tbNamePolyline => 'Łamana';

  @override
  String get tbNameRectangle => 'Prostokąt';

  @override
  String get tbNameSelect => 'Zaznaczanie';

  @override
  String get tbNameSignature => 'Podpis';

  @override
  String get tbNameStamp => 'Stempel';

  @override
  String get tbNameTextBox => 'Pole tekstowe';

  @override
  String get tbNewFieldType =>
      'Nowy typ pola - przeciągnij na stronie, aby dodać';

  @override
  String get tbNoAnnotationsToFlatten => 'Brak adnotacji do spłaszczenia';

  @override
  String get tbNoCustomStamps => 'Brak niestandardowych stempli';

  @override
  String get tbNoFormFieldsToFlatten => 'Brak pól formularza do spłaszczenia';

  @override
  String get tbNoRedactionsToApply => 'Brak wymazań do zastosowania';

  @override
  String get tbNoteTitle => 'Notatka';

  @override
  String get tbOpacity => 'Krycie';

  @override
  String get tbOutline => 'Obrys';

  @override
  String get tbPatternScale => 'Skala wzoru';

  @override
  String get tbPickColorFromPage => 'Pobierz kolor ze strony';

  @override
  String get tbRedactionsApplied => 'Zastosowano wymazania';

  @override
  String get tbRedoShortcut => 'Ponów (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Nie można przepłynąć - to nie jest jednokolumnowy akapit, który to narzędzie potrafi ponownie zawinąć. Spróbuj zamiast tego Zamień tekst.';

  @override
  String get tbReflowParagraph => 'Przepływ akapitu';

  @override
  String get tbRenameField => 'Zmień nazwę pola';

  @override
  String get tbRenameFieldEllipsis => 'Zmień nazwę pola…';

  @override
  String get tbReplaceImage => 'Zamień obraz';

  @override
  String get tbReplaceImageFailed => 'Nie można zamienić obrazu';

  @override
  String get tbReplaceText => 'Zamień tekst';

  @override
  String get tbSaveImage => 'Zapisz obraz';

  @override
  String get tbSaveShortcut => 'Zapisz… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Skala';

  @override
  String get tbSelectTextForMarkup => 'Zaznacz tekst, aby użyć oznaczeń';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wybrano $count',
      many: 'Wybrano $count',
      few: 'Wybrano $count',
      one: 'Zaznaczenie',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Ustaw…';

  @override
  String get tbStamp => 'Stempel';

  @override
  String get tbStampText => 'Tekst stempla';

  @override
  String get tbStrokeOpacityFont => 'Obrys, krycie, czcionka';

  @override
  String get tbStrokeWidthLabel => 'Grubość obrysu';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Obrys $width';
  }

  @override
  String get tbStyle => 'Styl';

  @override
  String get tbTakeoffTotals => 'Sumy przedmiaru';

  @override
  String get tbTextBorder => 'Obramowanie tekstu';

  @override
  String get tbTextColour => 'Kolor tekstu';

  @override
  String get tbTextFieldOption => 'Pole tekstowe';

  @override
  String get tbTextFill => 'Wypełnienie tekstu';

  @override
  String get tbTextStyleEllipsis => 'Styl tekstu…';

  @override
  String get tbTextTitle => 'Tekst';

  @override
  String get tbTipCallout =>
      'Objaśnienie - przeciągnij od punktu do miejsca pola';

  @override
  String get tbTipContent => 'Edytuj treść strony';

  @override
  String get tbTipCount =>
      'Zliczanie - dotknij, aby stawiać znaczniki i je zliczać';

  @override
  String get tbTipDigitalSignature =>
      'Podpis cyfrowy - przeciągnij pole, aby umieścić i podpisać';

  @override
  String get tbTipForm =>
      'Pola formularza - dotknij, aby zaznaczyć, dotknij dwukrotnie, aby wypełnić, przeciągnij, aby dodać';

  @override
  String get tbTipHighlightDraw => 'Zakreślacz - rysuj odręcznie';

  @override
  String get tbTipImage =>
      'Obraz - dotknij, aby umieścić, lub przeciągnij pole';

  @override
  String get tbTipMeasureAngle => 'Zmierz kąt - kliknij trzy punkty';

  @override
  String get tbTipMeasureArc => 'Zmierz długość łuku - kliknij trzy punkty';

  @override
  String get tbTipRedact => 'Wymaż - przeciągnij obszar, a następnie zastosuj';

  @override
  String get tbTipSignature => 'Podpis - dotknij strony, aby go umieścić';

  @override
  String get tbTipSnapshot =>
      'Migawka - przeciągnij obszar, aby go przechwycić (wklej jako wektor)';

  @override
  String get tbToolContent => 'Treść';

  @override
  String get tbToolForm => 'Formularz';

  @override
  String get tbToolRedact => 'Wymaż';

  @override
  String get tbToolSnapshot => 'Migawka';

  @override
  String get tbTools => 'Narzędzia';

  @override
  String get tbTotals => 'Sumy';

  @override
  String get tbTypeTextEachTime => 'Wpisuj tekst za każdym razem';

  @override
  String get tbUnderline => 'Podkreślenie';

  @override
  String get tbUndoShortcut => 'Cofnij (⌘Z)';

  @override
  String get textStyleFont => 'Czcionka';

  @override
  String get textStyleFontSize => 'Rozmiar czcionki';

  @override
  String get textStyleKeep => 'zachowaj';

  @override
  String get textStyleStyle => 'Styl';

  @override
  String get textStyleText => 'Tekst';

  @override
  String get textStyleTextFill => 'Wypełnienie tekstu';

  @override
  String get textStyleTitle => 'Edytuj tekst i styl';

  @override
  String get thumbAddPage => 'Dodaj stronę';

  @override
  String get thumbClearSelection => 'Wyczyść zaznaczenie';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kopiuj $count strony',
      many: 'Kopiuj $count stron',
      few: 'Kopiuj $count strony',
      one: 'Kopiuj stronę',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Kopiuj wybrane strony';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wytnij $count strony',
      many: 'Wytnij $count stron',
      few: 'Wytnij $count strony',
      one: 'Wytnij stronę',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Wytnij wybrane strony';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Usuń $count strony',
      many: 'Usuń $count stron',
      few: 'Usuń $count strony',
      one: 'Usuń stronę',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Usuń wybrane strony';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Duplikuj $count strony',
      many: 'Duplikuj $count stron',
      few: 'Duplikuj $count strony',
      one: 'Duplikuj stronę',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Eksportuj strony…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eksportuj $count strony…',
      many: 'Eksportuj $count stron…',
      few: 'Eksportuj $count strony…',
      one: 'Eksportuj stronę…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Eksportuj wybrane strony';

  @override
  String get thumbInsertBlankAfter => 'Wstaw pustą stronę po';

  @override
  String get thumbInsertBlankBefore => 'Wstaw pustą stronę przed';

  @override
  String get thumbInsertFileFailed => 'Nie można wstawić tego pliku.';

  @override
  String get thumbInsertPdf => 'Wstaw PDF…';

  @override
  String get thumbPageActions => 'Akcje strony';

  @override
  String thumbPageNumber(int number) {
    return 'Strona $number';
  }

  @override
  String get thumbPages => 'Strony';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wklej $count strony',
      many: 'Wklej $count stron',
      few: 'Wklej $count strony',
      one: 'Wklej stronę',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Obróć o 180°';

  @override
  String get thumbRotateLeft => 'Obróć w lewo';

  @override
  String get thumbRotatePageRight => 'Obróć stronę w prawo';

  @override
  String get thumbRotateRight => 'Obróć w prawo';

  @override
  String get thumbRotateSelectedLeft => 'Obróć wybrane strony w lewo';

  @override
  String get thumbRotateSelectedRight => 'Obróć wybrane strony w prawo';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wybrano $count',
      many: 'Wybrano $count',
      few: 'Wybrano $count',
      one: 'Wybrano $count',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Cofnij';

  @override
  String get viewerEditFontUnsafe =>
      'Tej czcionki lub kodowania PDF nie można bezpiecznie edytować.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Edycja wymaga zaznaczenia na jednej stronie.';

  @override
  String get viewerEditNotEditableRun =>
      'To zaznaczenie nie jest jednym edytowalnym fragmentem tekstu treści strony.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Tę czcionkę PDF można ponownie wpisać, ale nie można zmienić jej stylu.';

  @override
  String get viewerEditTextStyle => 'Edytuj tekst i styl';

  @override
  String get viewerMarkup => 'Oznaczenia';

  @override
  String get viewerMarkupHighlight => 'Podświetlenie';

  @override
  String get viewerMarkupSquiggly => 'Faliste';

  @override
  String get viewerMarkupStrikeOut => 'Przekreślenie';

  @override
  String get viewerMarkupUnderline => 'Podkreślenie';

  @override
  String get viewerSelectAll => 'Zaznacz wszystko';
}

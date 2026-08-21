// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class DartPdfEditorLocalizationsDe extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get add => 'Hinzufügen';

  @override
  String get annotCaret => 'Einfügemarke';

  @override
  String get annotCircle => 'Kreis';

  @override
  String get annotFileAttachment => 'Dateianhang';

  @override
  String get annotFreeText => 'Textfeld';

  @override
  String get annotHighlight => 'Hervorhebung';

  @override
  String get annotInk => 'Freihand';

  @override
  String get annotLine => 'Linie';

  @override
  String get annotLink => 'Link';

  @override
  String get annotPolygon => 'Polygon';

  @override
  String get annotPolyline => 'Linienzug';

  @override
  String get annotRedact => 'Schwärzung';

  @override
  String get annotSquare => 'Rechteck';

  @override
  String get annotSquiggly => 'Wellenlinie';

  @override
  String get annotStamp => 'Stempel';

  @override
  String get annotStrikeOut => 'Durchstreichung';

  @override
  String get annotText => 'Notiz';

  @override
  String get annotUnderline => 'Unterstreichung';

  @override
  String get annotWidget => 'Formularfeld';

  @override
  String get apply => 'Anwenden';

  @override
  String get bookmarkAdd => 'Lesezeichen hinzufügen';

  @override
  String get bookmarkAddChild => 'Untergeordnetes Lesezeichen hinzufügen';

  @override
  String get bookmarkCollapse => 'Einklappen';

  @override
  String get bookmarkDelete => 'Lesezeichen löschen';

  @override
  String get bookmarkEdit => 'Lesezeichen bearbeiten';

  @override
  String get bookmarkEmpty => 'Keine Lesezeichen';

  @override
  String get bookmarkExpand => 'Ausklappen';

  @override
  String get bookmarkExpandedByDefault => 'Standardmäßig ausgeklappt';

  @override
  String get bookmarkNoDestination => 'Kein Ziel';

  @override
  String get bookmarkPageFieldLabel => 'Seite';

  @override
  String bookmarkPageLabel(int number) {
    return 'Seite $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Lesezeichen';

  @override
  String get bookmarkTitleLabel => 'Titel';

  @override
  String get bookmarkUntitled => 'Ohne Titel';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get clear => 'Leeren';

  @override
  String get close => 'Schließen';

  @override
  String get colorApplyingChanges => 'Farbänderungen werden angewendet…';

  @override
  String get colorColorFormat => 'Farbformat';

  @override
  String get colorColorTitle => 'Farbe';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Farben ausgewählt',
      one: '$count Farbe ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Dokumentfarben';

  @override
  String get colorFillColors => 'Füllfarben';

  @override
  String get colorFind => 'Suchen';

  @override
  String get colorInDocument => 'Im Dokument';

  @override
  String get colorNoColorsFound => 'Noch keine Farben gefunden';

  @override
  String get colorNoPageContentColors => 'Keine Seiteninhaltsfarben gefunden';

  @override
  String get colorPalette => 'Palette';

  @override
  String get colorPickColor => 'Farbe auswählen';

  @override
  String get colorProcessingTitle => 'Farbverarbeitung';

  @override
  String get colorRecent => 'Zuletzt verwendet';

  @override
  String get colorReplace => 'Ersetzen';

  @override
  String get colorReplaceWithTransparent => 'Durch Transparenz ersetzen';

  @override
  String get colorScanning => 'Wird durchsucht…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Wird durchsucht $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Ausgewählte Seiten ($count)';
  }

  @override
  String get colorStrokeColors => 'Konturfarben';

  @override
  String get colorTolerance => 'Toleranz';

  @override
  String get colorTransparent => 'Transparent';

  @override
  String get colorWholeDocument => 'Gesamtes Dokument';

  @override
  String get compareAfter => 'Nachher';

  @override
  String get compareBefore => 'Vorher';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen',
      one: '1 Änderung',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen',
      one: '1 Änderung',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(leer)';

  @override
  String get compareNextChange => 'Nächste Änderung';

  @override
  String get compareNoChanges => 'Keine Änderungen';

  @override
  String get compareNoDifferences =>
      'Keine Unterschiede zwischen den beiden Dokumenten';

  @override
  String get compareOverlay => 'Überlagerung';

  @override
  String comparePageHeader(int page) {
    return 'Seite $page';
  }

  @override
  String get comparePreviousChange => 'Vorherige Änderung';

  @override
  String get compareSideBySide => 'Nebeneinander';

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
  String get editorViewAuthorNameTitle => 'Name des Autors';

  @override
  String get lineStyleDashDot => 'Strich-Punkt';

  @override
  String get lineStyleDashed => 'Gestrichelt';

  @override
  String get lineStyleDotted => 'Gepunktet';

  @override
  String get lineStyleSolid => 'Durchgezogen';

  @override
  String get measCalibrate => 'Kalibrieren';

  @override
  String get measCalibrateScale => 'Maßstab kalibrieren';

  @override
  String get measDepthLabel => 'Tiefe: ';

  @override
  String get measKindAngle => 'Winkel';

  @override
  String get measKindArc => 'Bogen';

  @override
  String get measKindArea => 'Fläche';

  @override
  String get measKindCount => 'Anzahl';

  @override
  String get measKindLength => 'Länge';

  @override
  String get measKindNetArea => 'Nettofläche';

  @override
  String get measKindPerimeter => 'Umfang';

  @override
  String get measKindSlope => 'Gefälle';

  @override
  String get measKindVolume => 'Volumen';

  @override
  String get measLineRepresents => 'Die gezeichnete Linie entspricht:';

  @override
  String get measMeasure => 'Messen';

  @override
  String get measSetScale => 'Messmaßstab festlegen';

  @override
  String get measSetScaleButton => 'Maßstab festlegen';

  @override
  String get measVolumeDepth => 'Volumentiefe';

  @override
  String get menuAddNode => 'Knoten hinzufügen';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Anmerkungen auf Seiten anwenden',
      one: 'Anmerkung auf Seiten anwenden',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Auf Seiten anwenden…';

  @override
  String get menuBringToFront => 'In den Vordergrund';

  @override
  String get menuCheck => 'Aktivieren';

  @override
  String get menuChooseValue => 'Wert auswählen…';

  @override
  String get menuClearCheck => 'Deaktivieren';

  @override
  String get menuConvertToCheckBox => 'In Kontrollkästchen umwandeln';

  @override
  String get menuConvertToImageButton => 'In Bildschaltfläche umwandeln';

  @override
  String get menuConvertToTextField => 'In Textfeld umwandeln';

  @override
  String get menuDeleteField => 'Feld löschen';

  @override
  String get menuEditValue => 'Wert bearbeiten…';

  @override
  String get menuFieldName => 'Feldname';

  @override
  String get menuFieldValue => 'Feldwert';

  @override
  String get menuFlattenForm => 'Formular reduzieren';

  @override
  String get menuLock => 'Sperren';

  @override
  String get menuUnlock => 'Entsperren';

  @override
  String get menuRecolour => 'Umfärben…';

  @override
  String get menuRemoveNode => 'Knoten entfernen';

  @override
  String get menuSaveToStamps => 'In Stempeln speichern';

  @override
  String get menuSetAsDefaultStyle => 'Als Standardstil festlegen';

  @override
  String get menuRename => 'Umbenennen…';

  @override
  String get menuSelectOption => 'Option auswählen';

  @override
  String get menuSendToBack => 'In den Hintergrund';

  @override
  String get menuSetImage => 'Bild festlegen…';

  @override
  String get menuTextStyle => 'Textstil…';

  @override
  String get none => 'Keine';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Farbe';

  @override
  String get overlayEditText => 'Text bearbeiten';

  @override
  String get overlayFont => 'Schriftart';

  @override
  String get overlayLarger => 'Größer';

  @override
  String get overlayMore => 'Mehr';

  @override
  String get overlayNote => 'Notiz';

  @override
  String get overlaySmaller => 'Kleiner';

  @override
  String get overlayStampText => 'Stempeltext';

  @override
  String get linkDialogTitle => 'Link hinzufügen';

  @override
  String get linkKindWeb => 'Webadresse';

  @override
  String get linkKindPage => 'Seite im Dokument';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Seitenzahl';

  @override
  String get toolLink => 'Link';

  @override
  String get overlayUnderline => 'Unterstreichen';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Geben Sie Seiten zwischen 1 und $count ein.';
  }

  @override
  String get pageRangeErrorOrder =>
      'Die letzte Seite darf nicht vor der ersten liegen.';

  @override
  String get pageRangeFrom => 'Von';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '1 Seite',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Bis';

  @override
  String get panelDragToMovePanel => 'Zum Verschieben des Panels ziehen';

  @override
  String get paste => 'Einfügen';

  @override
  String get propAlign => 'Ausrichten';

  @override
  String get propAlignCenter => 'Zentriert ausrichten';

  @override
  String get propAlignLeft => 'Linksbündig ausrichten';

  @override
  String get propAlignRight => 'Rechtsbündig ausrichten';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anmerkungen',
      one: '$count Anmerkung',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Autor';

  @override
  String get propAutoSize => 'Automatische Größe';

  @override
  String get propBold => 'Fett';

  @override
  String get propBoldLetter => 'F';

  @override
  String get propBundledFont => 'Mitgelieferte Schriftart';

  @override
  String get propCallout => 'Sprechblase';

  @override
  String get propCharSpacing => 'Zeichenabstand';

  @override
  String get propColor => 'Farbe';

  @override
  String get propColour => 'Farbe';

  @override
  String get propContents => 'Inhalt';

  @override
  String get propCornerRadius => 'Eckenradius';

  @override
  String get propEditsApplyToAll =>
      'Änderungen gelten für alle kompatiblen Anmerkungen';

  @override
  String get propFieldName => 'Feldname';

  @override
  String get propFieldTypeCheckBox => 'Kontrollkästchen';

  @override
  String get propFieldTypeComboBox => 'Kombinationsfeld';

  @override
  String get propFieldTypeImageButton => 'Bildschaltfläche';

  @override
  String get propFieldTypeListBox => 'Listenfeld';

  @override
  String get propFieldTypeRadioGroup => 'Optionsfeldgruppe';

  @override
  String get propFieldTypeSignature => 'Signatur';

  @override
  String get propFieldTypeText => 'Textfeld';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Feldtyp: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Unbekanntes Feld';

  @override
  String get propFill => 'Füllung';

  @override
  String get propFont => 'Schriftart';

  @override
  String get propFontSubsetTooltip =>
      'Diese Schriftart ist als Teilsatz eingebettet - es können nur die bereits im Dokument verwendeten Zeichen eingegeben werden.';

  @override
  String get propFontWidth => 'Schriftbreite';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'B';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Kursiv';

  @override
  String get propItalicLetter => 'K';

  @override
  String get propLimitedCharacters => 'Eingeschränkter Zeichensatz';

  @override
  String get propLineEnd => 'Linienende';

  @override
  String get propLineEndingButt => 'Stumpf';

  @override
  String get propLineEndingCircle => 'Kreis';

  @override
  String get propLineEndingClosedArrow => 'Geschlossener Pfeil';

  @override
  String get propLineEndingClosedArrowRev => 'Geschlossener Pfeil (umgek.)';

  @override
  String get propLineEndingDiamond => 'Raute';

  @override
  String get propLineEndingOpenArrow => 'Offener Pfeil';

  @override
  String get propLineEndingOpenArrowRev => 'Offener Pfeil (umgek.)';

  @override
  String get propLineEndingSlash => 'Schrägstrich';

  @override
  String get propLineEndingSquare => 'Quadrat';

  @override
  String get propLineSpacing => 'Zeilenabstand';

  @override
  String get propLineStart => 'Linienanfang';

  @override
  String get propLineType => 'Linientyp';

  @override
  String get propLoadFont => 'Schriftart laden…';

  @override
  String get propLoadFontSubtitle => 'TTF- oder OTF-Datei';

  @override
  String get propMoreColors => 'Weitere Farben…';

  @override
  String get propMultiline => 'Mehrzeilig';

  @override
  String get propNoFill => 'Keine Füllung';

  @override
  String get propNoFontsFound => 'Keine Schriftarten gefunden';

  @override
  String get propNoOutline => 'Keine Kontur';

  @override
  String get propOpacity => 'Deckkraft';

  @override
  String get propOutline => 'Kontur';

  @override
  String get propPageLabel => 'Seite';

  @override
  String propPageNumber(int number) {
    return 'Seite $number';
  }

  @override
  String get propPropertiesTitle => 'Eigenschaften';

  @override
  String get propRecentlyUsed => 'Zuletzt verwendet';

  @override
  String get propScale => 'Skalierung';

  @override
  String get propSearchFonts => 'Schriftarten suchen';

  @override
  String get propSectionAllFonts => 'Alle Schriftarten';

  @override
  String get propSectionAppearance => 'Darstellung';

  @override
  String get propSectionContent => 'Inhalt';

  @override
  String get propSectionFormField => 'Formularfeld';

  @override
  String get propSectionInThisDocument => 'In diesem Dokument';

  @override
  String get propSectionPositionSize => 'Position & Größe (pt)';

  @override
  String get propSectionSelection => 'Auswahl';

  @override
  String get propSectionText => 'Text';

  @override
  String get propSelectAnnotationPrompt =>
      'Wählen Sie eine Anmerkung, um ihre Eigenschaften zu sehen';

  @override
  String get propSize => 'Größe';

  @override
  String get propStandardPdfFont => 'Standard-PDF-Schriftart';

  @override
  String get propStroke => 'Konturbreite';

  @override
  String get propStyle => 'Stil';

  @override
  String get propSystemFont => 'Systemschriftart';

  @override
  String get propType => 'Typ';

  @override
  String get propUnderline => 'Unterstreichung';

  @override
  String get propVaries => 'Unterschiedlich';

  @override
  String get redo => 'Wiederholen';

  @override
  String get reflowNoContent => 'Kein extrahierbarer Inhalt';

  @override
  String reflowPageLabel(int number) {
    return 'Seite $number';
  }

  @override
  String get reflowSaveOrShare => 'Speichern oder teilen';

  @override
  String get reflowViewFigure => 'Abbildung anzeigen';

  @override
  String get remove => 'Entfernen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get save => 'Speichern';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Seite $page';
  }

  @override
  String get sbarCallout => 'Sprechblase';

  @override
  String get sbarFieldButton => 'Schaltflächenfeld';

  @override
  String get sbarFieldChoice => 'Auswahlfeld';

  @override
  String get sbarFieldGeneric => 'Formularfeld';

  @override
  String get sbarFieldSignature => 'Signaturfeld';

  @override
  String get sbarFieldText => 'Textfeld';

  @override
  String get sbarStateAccepted => 'Akzeptiert';

  @override
  String get sbarStateCancelled => 'Abgebrochen';

  @override
  String get sbarStateMarked => 'Markiert';

  @override
  String get sbarStateRejected => 'Abgelehnt';

  @override
  String get sbarStateResolved => 'Gelöst';

  @override
  String get sbarStateUnmarked => 'Nicht markiert';

  @override
  String get searchAnnotations => 'Anmerkungen durchsuchen';

  @override
  String get searchClearSearch => 'Suche leeren';

  @override
  String get searchEmptyHint =>
      'Durchsuchen Sie das Dokument, um hier alle Treffer aufzulisten';

  @override
  String get searchMatchCase => 'Groß-/Kleinschreibung beachten';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer',
      one: '1 Treffer',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Nächster Treffer';

  @override
  String searchNoMatches(String query) {
    return 'Keine Treffer für „$query“';
  }

  @override
  String searchPageHeader(int page) {
    return 'Seite $page';
  }

  @override
  String get searchPreviousMatch => 'Vorheriger Treffer';

  @override
  String get searchRegex => 'Regulärer Ausdruck';

  @override
  String get searchReplace => 'Ersetzen';

  @override
  String get searchReplaceAll => 'Alle ersetzen';

  @override
  String get searchReplaceHint => 'Ersetzen durch';

  @override
  String get searchReplaceNotTargetable =>
      'Dieser Treffer kann nicht einzeln ersetzt werden – verwenden Sie „Alle ersetzen“ oder bearbeiten Sie ihn mit dem Inhaltswerkzeug';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer ersetzt',
      one: '1 Treffer ersetzt',
      zero: 'Nichts ersetzt',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => 'Suchergebnisse';

  @override
  String get searchWholeWord => 'Ganzes Wort';

  @override
  String get shellControls => 'Steuerung';

  @override
  String get shellDefaultAuthor => 'Standardautor…';

  @override
  String get shellHighlightFormFields => 'Formularfelder hervorheben';

  @override
  String get shellKeyboardShortcutsMenu => 'Tastenkürzel…';

  @override
  String get shellKeyboardShortcutsTitle => 'Tastenkürzel';

  @override
  String get shellShortcutsSearchHint => 'Kürzel suchen';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Keine Kürzel passen zu „$query“';
  }

  @override
  String get shellShortcutGroupSelect => 'Auswählen';

  @override
  String get shellShortcutGroupMarkup => 'Markierung';

  @override
  String get shellShortcutGroupDraw => 'Zeichnen';

  @override
  String get shellShortcutGroupShapes => 'Formen';

  @override
  String get shellShortcutGroupInsert => 'Einfügen';

  @override
  String get shellShortcutGroupMeasure => 'Messen';

  @override
  String get shellShortcutGroupEdit => 'Bearbeiten';

  @override
  String get shellNotSet => 'Nicht festgelegt';

  @override
  String get shellPageColor => 'Seitenfarbe…';

  @override
  String get shellPageGrid => 'Seitenraster';

  @override
  String get shellPanelAnnotations => 'Anmerkungen';

  @override
  String get shellPanelBookmarks => 'Lesezeichen';

  @override
  String get shellPanelPages => 'Seiten';

  @override
  String get shellPanelProperties => 'Eigenschaften';

  @override
  String get shellPanelSearchResults => 'Suchergebnisse';

  @override
  String get shellPanels => 'Panels';

  @override
  String get shellPressAKey => 'Taste drücken';

  @override
  String get shellPressLetterKeyHint =>
      'Drücken Sie eine Buchstabentaste oder Entf zum Löschen.';

  @override
  String get shellReflow => 'Umbruch';

  @override
  String get shellReflowText => 'Text umbrechen';

  @override
  String get shellResetZoom => 'Zoom zurücksetzen';

  @override
  String get shellSectionShell => 'Rahmen';

  @override
  String get shellSectionView => 'Ansicht';

  @override
  String get shellSettings => 'Einstellungen';

  @override
  String get shellShowAnnotations => 'Anmerkungen anzeigen';

  @override
  String get shellShowScrollbarChapters =>
      'Kapitel auf der Bildlaufleiste anzeigen';

  @override
  String get shellTabHere => 'Hier als Tab';

  @override
  String get shellUnbound => 'Nicht zugewiesen';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'von $author';
  }

  @override
  String get sidebarCancelSelection => 'Auswahl abbrechen';

  @override
  String get sidebarClearSearch => 'Suche leeren';

  @override
  String get sidebarDeleteSelected => 'Ausgewählte löschen';

  @override
  String get sidebarDeleteSignature => 'Signatur löschen';

  @override
  String get sidebarLockAnnotation => 'Sperren';

  @override
  String get sidebarUnlockAnnotation => 'Entsperren';

  @override
  String get sidebarMore => 'Mehr';

  @override
  String get sidebarNoAnnotations => 'Keine Anmerkungen';

  @override
  String get sidebarNoMatchingAnnotations => 'Keine passenden Anmerkungen';

  @override
  String sidebarPageHeader(int number) {
    return 'Seite $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Dadurch wird die digitale Signatur aus dem Dokument entfernt. Sie können dies rückgängig machen.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Dadurch wird die digitale Signatur von \"$name\" aus dem Dokument entfernt. Sie können dies rückgängig machen.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Signatur entfernen?';

  @override
  String get sidebarReopen => 'Erneut öffnen';

  @override
  String get sidebarReply => 'Antworten';

  @override
  String get sidebarResolve => 'Auflösen';

  @override
  String get sidebarSearchHint => 'Anmerkungen suchen';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählt',
      one: '$count ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get sidebarSignatureChecking => 'Checking…';

  @override
  String get sidebarSignatureTrusted => 'Valid — trusted';

  @override
  String get sidebarSignatureUnverified => 'Valid — unverified';

  @override
  String get sidebarSignatureInvalid => 'Invalid';

  @override
  String sidebarSignatureSignedBy(String name) {
    return 'Signed by $name';
  }

  @override
  String sidebarSignatureSignedAt(String time) {
    return 'Signed $time';
  }

  @override
  String sidebarSignatureTrustedVia(String authority) {
    return 'Trusted via $authority';
  }

  @override
  String get sidebarSignatureUntrustedDetail =>
      'Signer is not from a trusted authority';

  @override
  String get sidebarSignatureNoAnchors =>
      'No trusted authorities are configured';

  @override
  String get sidebarSignatureModified => 'Document was changed after signing';

  @override
  String get sidebarSignatureRevoked => 'The signer\'s certificate was revoked';

  @override
  String sidebarSignatureTimestamped(String time) {
    return 'Timestamped $time';
  }

  @override
  String sidebarSignatureLevel(String level) {
    return 'PAdES $level';
  }

  @override
  String get sidebarWriteReplyHint => 'Antwort schreiben…';

  @override
  String get sigTitle => 'Unterschrift';

  @override
  String get signIdCreate => 'Erstellen';

  @override
  String get signIdEmail => 'E-Mail (optional)';

  @override
  String get signIdName => 'Name';

  @override
  String get signIdNameHint =>
      'Ihr Name, wie er auf der Signatur erscheinen soll';

  @override
  String get signIdNameRequired => 'Namen eingeben';

  @override
  String get signIdOrganization => 'Organisation (optional)';

  @override
  String get signIdSelfSignedInfo =>
      'Dadurch wird eine selbstsignierte Identität erstellt. Signaturen werden in Adobe Acrobat und anderen Readern als \"signiert, Gültigkeit unbekannt\" angezeigt - genauso wie deren eigene selbstsignierte IDs. Das grüne Häkchen erfordert eine kostenpflichtige, öffentlich vertrauenswürdige CA.';

  @override
  String get signIdTitle => 'Signaturidentität erstellen';

  @override
  String get stampBox => 'Rechteck';

  @override
  String get stampCircle => 'Kreis';

  @override
  String get stampCustomCaption => 'Eigener Stempel';

  @override
  String get stampDateFormat => 'Datumsformat';

  @override
  String get stampDeleteComponent => 'Ausgewählte Komponente löschen';

  @override
  String get stampDeleteStamp => 'Stempel löschen';

  @override
  String get stampEditStamp => 'Stempel bearbeiten';

  @override
  String get stampExport => 'Exportieren…';

  @override
  String get stampFieldDate => 'Datum';

  @override
  String get stampFieldDateTime => 'Datum & Uhrzeit';

  @override
  String get stampFieldTime => 'Uhrzeit';

  @override
  String get stampFieldUsername => 'Benutzername';

  @override
  String get stampFont => 'Schriftart';

  @override
  String get stampFontBold => 'Fett';

  @override
  String get stampFontItalic => 'Kursiv';

  @override
  String get stampHeight => 'Höhe';

  @override
  String get stampImage => 'Bild';

  @override
  String get stampImport => 'Importieren…';

  @override
  String get stampInsertField => 'Feld einfügen';

  @override
  String get stampMoreColors => 'Weitere Farben…';

  @override
  String get stampNewStamp => 'Neuer Stempel…';

  @override
  String get stampNewStampTitle => 'Neuer Stempel';

  @override
  String get stampSavedToCollection => 'In Stempeln gespeichert';

  @override
  String get stampSelectTextToEdit => 'Text zum Bearbeiten auswählen';

  @override
  String get stampSelectedText => 'Ausgewählter Text';

  @override
  String get stampSignature => 'Unterschrift';

  @override
  String get stampStamps => 'Stempel';

  @override
  String get stampText => 'Text';

  @override
  String get stampTime12Hour => '12 Std';

  @override
  String get stampTime24Hour => '24 Std';

  @override
  String get stampTimeFormat => 'Zeitformat';

  @override
  String get stampWidth => 'Breite';

  @override
  String get takeoffArea => 'Fläche';

  @override
  String get takeoffCount => 'Anzahl';

  @override
  String get takeoffEmpty => 'Noch keine Messungen.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gruppen',
      one: '$count Gruppe',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente',
      one: '$count Element',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Länge';

  @override
  String get takeoffTitle => 'Aufmaß';

  @override
  String get tbAddInkAnnotation => 'Freihandanmerkung hinzufügen';

  @override
  String get tbAlign => 'Ausrichten';

  @override
  String get tbAlignBottom => 'Unten ausrichten';

  @override
  String get tbAlignHorizontalCenters => 'An horizontalen Mitten ausrichten';

  @override
  String get tbAlignLeft => 'Links ausrichten';

  @override
  String get tbAlignRight => 'Rechts ausrichten';

  @override
  String get tbAlignTop => 'Oben ausrichten';

  @override
  String get tbAlignVerticalCenters => 'An vertikalen Mitten ausrichten';

  @override
  String get tbAnnotationsFlattened => 'Anmerkungen in die Seiten reduziert';

  @override
  String get tbApplyRedactionsMessage =>
      'Der markierte Inhalt wird dauerhaft aus dem Dokument entfernt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get tbApplyRedactionsTitle => 'Schwärzungen anwenden?';

  @override
  String get tbApplyRedactionsTooltip =>
      'Schwärzungen anwenden (unwiderruflich)';

  @override
  String get tbAutosizeTextBox => 'Textfeld automatisch anpassen (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Zeichnen Sie eine Linie bekannter Länge, um den Maßstab zu kalibrieren.';

  @override
  String get tbCharSpacing => 'Zeichenabstand';

  @override
  String get tbCheckBoxOption => 'Kontrollkästchen';

  @override
  String get tbCheckMarksOnDocument => 'Häkchen auf dem Dokument';

  @override
  String get tbCropImage => 'Bild zuschneiden';

  @override
  String get tbCroppingImage => 'Bild wird zugeschnitten';

  @override
  String get tbCropApply => 'Zuschnitt anwenden';

  @override
  String get tbCropCancel => 'Zuschnitt abbrechen';

  @override
  String get tbCropReset => 'Zuschnitt zurücksetzen';

  @override
  String get tbColorLabel => 'Farbe';

  @override
  String get tbColorProcessingTooltip =>
      'Farbverarbeitung - Seiteninhaltsfarben suchen und ersetzen';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Farben ersetzt',
      one: '1 Farbe ersetzt',
      zero: 'Keine passenden Farben gefunden',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'In Kontrollkästchen umwandeln';

  @override
  String get tbConvertToImageButton => 'In Bildschaltfläche umwandeln';

  @override
  String get tbConvertToTextField => 'In Textfeld umwandeln';

  @override
  String get tbCornerRadius => 'Eckenradius';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anmerkungen löschen',
      one: 'Anmerkung löschen',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Element löschen';

  @override
  String get tbDeleteField => 'Feld löschen';

  @override
  String get tbDiscardDrawing => 'Zeichnung verwerfen';

  @override
  String get tbDistributeHorizontally => 'Horizontal verteilen';

  @override
  String get tbDistributeVertically => 'Vertikal verteilen';

  @override
  String get tbDrawNewSignature => 'Neue Unterschrift zeichnen…';

  @override
  String get tbEditAnnotationText => 'Anmerkungstext bearbeiten';

  @override
  String get tbEditTextStyle => 'Text & Stil bearbeiten';

  @override
  String get tbElement => 'Element';

  @override
  String get tbEraserSize => 'Radiergummigröße';

  @override
  String get tbFieldActions => 'Feldaktionen';

  @override
  String get tbFieldName => 'Feldname';

  @override
  String tbFieldNamed(String name) {
    return 'Feld: $name';
  }

  @override
  String get tbFieldValue => 'Feldwert';

  @override
  String get tbFill => 'Füllung';

  @override
  String get tbFingerDraws =>
      'Finger zeichnet - tippen, damit stattdessen gescrollt wird';

  @override
  String get tbFingerScrolls =>
      'Finger scrollt (Stift zeichnet) - tippen, damit gezeichnet wird';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'Anmerkungen in die Seiten reduzieren';

  @override
  String get tbFlattenForm => 'Formular reduzieren';

  @override
  String get tbFlattenFormBakeValues =>
      'Formular reduzieren - Werte fest in die Seiten übernehmen';

  @override
  String get tbFlattenLabel => 'Reduzieren';

  @override
  String get tbFont => 'Schriftart';

  @override
  String get tbFontSize => 'Schriftgröße';

  @override
  String get tbFontWidth => 'Schriftbreite';

  @override
  String get tbFormFieldsFlattened => 'Formularfelder in die Seiten reduziert';

  @override
  String get tbGroupDraw => 'Zeichnen';

  @override
  String get tbGroupEdit => 'Bearbeiten';

  @override
  String get tbGroupInsert => 'Einfügen';

  @override
  String get tbGroupMarkup => 'Markierung';

  @override
  String get tbGroupMeasure => 'Messen';

  @override
  String get tbGroupSelect => 'Auswählen';

  @override
  String get tbGroupShapes => 'Formen';

  @override
  String get tbImageButtonOption => 'Bildschaltfläche';

  @override
  String get tbLineEnd => 'Linienende';

  @override
  String get tbLineSpacing => 'Zeilenabstand';

  @override
  String get tbLineStart => 'Linienanfang';

  @override
  String get tbLineType => 'Linientyp';

  @override
  String get tbManageStamps => 'Stempel verwalten…';

  @override
  String get tbMarkupHighlight => 'Hervorheben';

  @override
  String get tbMarkupHighlightTip => 'Auswahl hervorheben';

  @override
  String get tbMarkupSquiggly => 'Wellenunterstreichung';

  @override
  String get tbMarkupSquigglyTip => 'Auswahl mit Wellenlinie unterstreichen';

  @override
  String get tbMarkupStrikeOut => 'Durchstreichen';

  @override
  String get tbMarkupStrikeOutTip => 'Auswahl durchstreichen';

  @override
  String get tbMarkupUnderline => 'Unterstreichen';

  @override
  String get tbMarkupUnderlineTip => 'Auswahl unterstreichen';

  @override
  String get tbMoreColors => 'Weitere Farben…';

  @override
  String get tbNameArrow => 'Pfeil';

  @override
  String get tbNameCallout => 'Sprechblase';

  @override
  String get tbNameCloudPolygon => 'Wolkenpolygon';

  @override
  String get tbNameCount => 'Zählen';

  @override
  String get tbNameDigitalSignature => 'Digitale Signatur';

  @override
  String get tbNameDraw => 'Zeichnen';

  @override
  String get tbNameEllipse => 'Ellipse';

  @override
  String get tbNameEraser => 'Freihandstriche löschen';

  @override
  String get tbNameHand => 'Hand';

  @override
  String get tbNameHighlight => 'Hervorheben';

  @override
  String get tbNameImage => 'Bild';

  @override
  String get tbNameLine => 'Linie';

  @override
  String get tbNameMeasureAngle => 'Winkel messen';

  @override
  String get tbNameMeasureArc => 'Bogenlänge messen';

  @override
  String get tbNameMeasureArea => 'Fläche messen';

  @override
  String get tbNameMeasureDistance => 'Abstand messen';

  @override
  String get tbNameMeasurePerimeter => 'Umfang messen';

  @override
  String get tbNameMeasureSlope => 'Gefälle messen (Steigung/Strecke)';

  @override
  String get tbNameMeasureVolume => 'Volumen messen (Fläche × Tiefe)';

  @override
  String get tbNameNote => 'Notiz';

  @override
  String get tbNamePolygon => 'Polygon';

  @override
  String get tbNamePolyline => 'Linienzug';

  @override
  String get tbNameRectangle => 'Rechteck';

  @override
  String get tbNameSelect => 'Auswählen';

  @override
  String get tbNameSignature => 'Unterschrift';

  @override
  String get tbNameStamp => 'Stempel';

  @override
  String get tbNameTextBox => 'Textfeld';

  @override
  String get tbNewFieldType =>
      'Neuer Feldtyp - auf eine Seite ziehen, um eines hinzuzufügen';

  @override
  String get tbNoAnnotationsToFlatten => 'Keine Anmerkungen zum Reduzieren';

  @override
  String get tbNoCustomStamps => 'Keine eigenen Stempel';

  @override
  String get tbNoFormFieldsToFlatten => 'Keine Formularfelder zum Reduzieren';

  @override
  String get tbNoRedactionsToApply => 'Keine Schwärzungen zum Anwenden';

  @override
  String get tbNoteTitle => 'Notiz';

  @override
  String get tbOpacity => 'Deckkraft';

  @override
  String get tbOutline => 'Kontur';

  @override
  String get tbPatternScale => 'Musterskalierung';

  @override
  String get tbPickColorFromPage => 'Eine Farbe von der Seite aufnehmen';

  @override
  String get tbRedactionsApplied => 'Schwärzungen angewendet';

  @override
  String get tbRedoShortcut => 'Wiederholen (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Umbruch nicht möglich - dies ist kein einspaltiger Absatz, den dieses Werkzeug neu umbrechen kann. Verwenden Sie stattdessen Text ersetzen.';

  @override
  String get tbReflowParagraph => 'Absatz umbrechen';

  @override
  String get tbRenameField => 'Feld umbenennen';

  @override
  String get tbRenameFieldEllipsis => 'Feld umbenennen…';

  @override
  String get tbReplaceImage => 'Bild ersetzen';

  @override
  String get tbReplaceImageFailed => 'Bild konnte nicht ersetzt werden';

  @override
  String get tbReplaceText => 'Text ersetzen';

  @override
  String get tbSaveImage => 'Bild speichern';

  @override
  String get tbSaveShortcut => 'Speichern… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Maßstab';

  @override
  String get tbSelectTextForMarkup =>
      'Text auswählen, um Markierung zu verwenden';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählt',
      one: 'Auswahl',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Festlegen…';

  @override
  String get tbStamp => 'Stempel';

  @override
  String get tbStampText => 'Stempeltext';

  @override
  String get tbStrokeOpacityFont => 'Kontur, Deckkraft, Schriftart';

  @override
  String get tbStrokeWidthLabel => 'Konturbreite';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Kontur $width';
  }

  @override
  String get tbStyle => 'Stil';

  @override
  String get tbTakeoffTotals => 'Aufmaß-Summen';

  @override
  String get tbTextBorder => 'Textrahmen';

  @override
  String get tbTextColour => 'Textfarbe';

  @override
  String get tbTextFieldOption => 'Textfeld';

  @override
  String get tbTextFill => 'Textfüllung';

  @override
  String get tbTextStyleEllipsis => 'Textstil…';

  @override
  String get tbTextTitle => 'Text';

  @override
  String get tbTipCallout =>
      'Sprechblase - vom Punkt zur gewünschten Position des Feldes ziehen';

  @override
  String get tbTipContent => 'Seiteninhalt bearbeiten';

  @override
  String get tbTipCount =>
      'Zählen - tippen, um Häkchen zu setzen und zu zählen';

  @override
  String get tbTipDigitalSignature =>
      'Digitale Signatur - ein Feld ziehen, um zu platzieren und zu signieren';

  @override
  String get tbTipForm =>
      'Formularfelder - tippen zum Auswählen, doppeltippen zum Ausfüllen, ziehen zum Hinzufügen';

  @override
  String get tbTipHighlightDraw => 'Hervorheben - freihändig zeichnen';

  @override
  String get tbTipImage =>
      'Bild - tippen zum Platzieren oder ein Feld aufziehen';

  @override
  String get tbTipMeasureAngle => 'Winkel messen - drei Punkte anklicken';

  @override
  String get tbTipMeasureArc => 'Bogenlänge messen - drei Punkte anklicken';

  @override
  String get tbTipRedact =>
      'Schwärzen - einen Bereich ziehen und dann anwenden';

  @override
  String get tbTipSignature =>
      'Unterschrift - eine Seite antippen, um sie zu platzieren';

  @override
  String get tbTipSnapshot =>
      'Schnappschuss - einen Bereich ziehen, um ihn zu erfassen (als Vektor wieder einfügen)';

  @override
  String get tbToolContent => 'Inhalt';

  @override
  String get tbToolForm => 'Formular';

  @override
  String get tbToolRedact => 'Schwärzen';

  @override
  String get tbToolSnapshot => 'Schnappschuss';

  @override
  String get tbTools => 'Werkzeuge';

  @override
  String get tbTotals => 'Summen';

  @override
  String get tbTypeTextEachTime => 'Text jedes Mal eingeben';

  @override
  String get tbUnderline => 'Unterstreichen';

  @override
  String get tbUndoShortcut => 'Rückgängig (⌘Z)';

  @override
  String get textStyleFont => 'Schriftart';

  @override
  String get textStyleFontSize => 'Schriftgröße';

  @override
  String get textStyleKeep => 'beibehalten';

  @override
  String get textStyleStyle => 'Stil';

  @override
  String get textStyleText => 'Text';

  @override
  String get textStyleTextFill => 'Textfüllung';

  @override
  String get textStyleTitle => 'Text & Stil bearbeiten';

  @override
  String get thumbAddPage => 'Seite hinzufügen';

  @override
  String get thumbClearSelection => 'Auswahl aufheben';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten kopieren',
      one: 'Seite kopieren',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Ausgewählte Seiten kopieren';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten ausschneiden',
      one: 'Seite ausschneiden',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Ausgewählte Seiten ausschneiden';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten löschen',
      one: 'Seite löschen',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Ausgewählte Seiten löschen';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten duplizieren',
      one: 'Seite duplizieren',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Seiten exportieren…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten exportieren…',
      one: 'Seite exportieren…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Ausgewählte Seiten exportieren';

  @override
  String get thumbInsertBlankAfter => 'Leere Seite danach einfügen';

  @override
  String get thumbInsertBlankBefore => 'Leere Seite davor einfügen';

  @override
  String get thumbInsertFileFailed =>
      'Diese Datei konnte nicht eingefügt werden.';

  @override
  String get thumbInsertPdf => 'PDF einfügen…';

  @override
  String get thumbPageActions => 'Seitenaktionen';

  @override
  String thumbPageNumber(int number) {
    return 'Seite $number';
  }

  @override
  String get thumbPages => 'Seiten';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten einfügen',
      one: 'Seite einfügen',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Um 180° drehen';

  @override
  String get thumbRotateLeft => 'Nach links drehen';

  @override
  String get thumbRotatePageRight => 'Seite nach rechts drehen';

  @override
  String get thumbRotateRight => 'Nach rechts drehen';

  @override
  String get thumbRotateSelectedLeft => 'Ausgewählte Seiten nach links drehen';

  @override
  String get thumbRotateSelectedRight =>
      'Ausgewählte Seiten nach rechts drehen';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählt',
      one: '$count ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Rückgängig';

  @override
  String get viewerEditFontUnsafe =>
      'Diese PDF-Schriftart oder -Kodierung kann nicht sicher bearbeitet werden.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Zum Bearbeiten ist eine Auswahl auf einer Seite erforderlich.';

  @override
  String get viewerEditNotEditableRun =>
      'Diese Auswahl ist kein einzelner bearbeitbarer Textlauf im Seiteninhalt.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Diese PDF-Schriftart kann neu eingegeben werden, aber ihr Stil kann nicht geändert werden.';

  @override
  String get viewerEditTextStyle => 'Text & Stil bearbeiten';

  @override
  String get viewerMarkup => 'Markierung';

  @override
  String get viewerMarkupHighlight => 'Hervorheben';

  @override
  String get viewerMarkupSquiggly => 'Wellenlinie';

  @override
  String get viewerMarkupStrikeOut => 'Durchstreichen';

  @override
  String get viewerMarkupUnderline => 'Unterstreichen';

  @override
  String get viewerSelectAll => 'Alles auswählen';
}

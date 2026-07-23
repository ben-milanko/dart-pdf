// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class DartPdfEditorLocalizationsNl extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get add => 'Toevoegen';

  @override
  String get annotCaret => 'Invoegteken';

  @override
  String get annotCircle => 'Cirkel';

  @override
  String get annotFileAttachment => 'Bijlage';

  @override
  String get annotFreeText => 'Tekstvak';

  @override
  String get annotHighlight => 'Markering';

  @override
  String get annotInk => 'Inkt';

  @override
  String get annotLine => 'Lijn';

  @override
  String get annotLink => 'Koppeling';

  @override
  String get annotPolygon => 'Veelhoek';

  @override
  String get annotPolyline => 'Polylijn';

  @override
  String get annotRedact => 'Redactie';

  @override
  String get annotSquare => 'Vierkant';

  @override
  String get annotSquiggly => 'Golflijn';

  @override
  String get annotStamp => 'Stempel';

  @override
  String get annotStrikeOut => 'Doorhalen';

  @override
  String get annotText => 'Notitie';

  @override
  String get annotUnderline => 'Onderstreping';

  @override
  String get annotWidget => 'Formulierveld';

  @override
  String get apply => 'Toepassen';

  @override
  String get bookmarkAdd => 'Bladwijzer toevoegen';

  @override
  String get bookmarkAddChild => 'Onderliggende bladwijzer toevoegen';

  @override
  String get bookmarkCollapse => 'Samenvouwen';

  @override
  String get bookmarkDelete => 'Bladwijzer verwijderen';

  @override
  String get bookmarkEdit => 'Bladwijzer bewerken';

  @override
  String get bookmarkEmpty => 'Geen bladwijzers';

  @override
  String get bookmarkExpand => 'Uitvouwen';

  @override
  String get bookmarkExpandedByDefault => 'Standaard uitgevouwen';

  @override
  String get bookmarkNoDestination => 'Geen bestemming';

  @override
  String get bookmarkPageFieldLabel => 'Pagina';

  @override
  String bookmarkPageLabel(int number) {
    return 'Pagina $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Bladwijzers';

  @override
  String get bookmarkTitleLabel => 'Titel';

  @override
  String get bookmarkUntitled => 'Naamloos';

  @override
  String get cancel => 'Annuleren';

  @override
  String get clear => 'Wissen';

  @override
  String get close => 'Sluiten';

  @override
  String get colorApplyingChanges => 'Kleurwijzigingen toepassen…';

  @override
  String get colorColorFormat => 'Kleurindeling';

  @override
  String get colorColorTitle => 'Kleur';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kleuren geselecteerd',
      one: '$count kleur geselecteerd',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Documentkleuren';

  @override
  String get colorFillColors => 'Vulkleuren';

  @override
  String get colorFind => 'Zoeken';

  @override
  String get colorInDocument => 'In document';

  @override
  String get colorNoColorsFound => 'Nog geen kleuren gevonden';

  @override
  String get colorNoPageContentColors => 'Geen pagina-inhoudkleuren gevonden';

  @override
  String get colorPalette => 'Palet';

  @override
  String get colorPickColor => 'Kleur kiezen';

  @override
  String get colorProcessingTitle => 'Kleurverwerking';

  @override
  String get colorRecent => 'Recent';

  @override
  String get colorReplace => 'Vervangen';

  @override
  String get colorReplaceWithTransparent => 'Vervangen door transparant';

  @override
  String get colorScanning => 'Scannen…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Scannen $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Geselecteerde pagina\'s ($count)';
  }

  @override
  String get colorStrokeColors => 'Lijnkleuren';

  @override
  String get colorTolerance => 'Tolerantie';

  @override
  String get colorTransparent => 'Transparant';

  @override
  String get colorWholeDocument => 'Hele document';

  @override
  String get compareAfter => 'Na';

  @override
  String get compareBefore => 'Voor';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wijzigingen',
      one: '1 wijziging',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wijzigingen',
      one: '1 wijziging',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(leeg)';

  @override
  String get compareNextChange => 'Volgende wijziging';

  @override
  String get compareNoChanges => 'Geen wijzigingen';

  @override
  String get compareNoDifferences =>
      'Geen verschillen tussen de twee documenten';

  @override
  String get compareOverlay => 'Overlay';

  @override
  String comparePageHeader(int page) {
    return 'Pagina $page';
  }

  @override
  String get comparePreviousChange => 'Vorige wijziging';

  @override
  String get compareSideBySide => 'Naast elkaar';

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
  String get editorViewAuthorNameTitle => 'Auteursnaam';

  @override
  String get lineStyleDashDot => 'Streep-punt';

  @override
  String get lineStyleDashed => 'Gestreept';

  @override
  String get lineStyleDotted => 'Gestippeld';

  @override
  String get lineStyleSolid => 'Doorlopend';

  @override
  String get measCalibrate => 'Kalibreren';

  @override
  String get measCalibrateScale => 'Schaal kalibreren';

  @override
  String get measDepthLabel => 'Diepte: ';

  @override
  String get measKindAngle => 'Hoek';

  @override
  String get measKindArc => 'Boog';

  @override
  String get measKindArea => 'Oppervlakte';

  @override
  String get measKindCount => 'Aantal';

  @override
  String get measKindLength => 'Lengte';

  @override
  String get measKindNetArea => 'Netto-oppervlakte';

  @override
  String get measKindPerimeter => 'Omtrek';

  @override
  String get measKindSlope => 'Helling';

  @override
  String get measKindVolume => 'Volume';

  @override
  String get measLineRepresents => 'De lijn die u tekende vertegenwoordigt:';

  @override
  String get measMeasure => 'Meten';

  @override
  String get measSetScale => 'Meetschaal instellen';

  @override
  String get measSetScaleButton => 'Schaal instellen';

  @override
  String get measVolumeDepth => 'Volumediepte';

  @override
  String get menuAddNode => 'Knooppunt toevoegen';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Annotaties op pagina\'s toepassen',
      one: 'Annotatie op pagina\'s toepassen',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Toepassen op pagina\'s…';

  @override
  String get menuBringToFront => 'Naar voorgrond';

  @override
  String get menuCheck => 'Aanvinken';

  @override
  String get menuChooseValue => 'Waarde kiezen…';

  @override
  String get menuClearCheck => 'Vinkje wissen';

  @override
  String get menuConvertToCheckBox => 'Omzetten naar selectievakje';

  @override
  String get menuConvertToImageButton => 'Omzetten naar afbeeldingsknop';

  @override
  String get menuConvertToTextField => 'Omzetten naar tekstveld';

  @override
  String get menuDeleteField => 'Veld verwijderen';

  @override
  String get menuEditValue => 'Waarde bewerken…';

  @override
  String get menuFieldName => 'Veldnaam';

  @override
  String get menuFieldValue => 'Veldwaarde';

  @override
  String get menuFlattenForm => 'Formulier afvlakken';

  @override
  String get menuLock => 'Vergrendelen';

  @override
  String get menuUnlock => 'Ontgrendelen';

  @override
  String get menuRecolour => 'Herkleuren…';

  @override
  String get menuRemoveNode => 'Knooppunt verwijderen';

  @override
  String get menuSetAsDefaultStyle => 'Als standaardstijl instellen';

  @override
  String get menuRename => 'Naam wijzigen…';

  @override
  String get menuSelectOption => 'Optie selecteren';

  @override
  String get menuSendToBack => 'Naar achtergrond';

  @override
  String get menuSetImage => 'Afbeelding instellen…';

  @override
  String get menuTextStyle => 'Tekststijl…';

  @override
  String get none => 'Geen';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Kleur';

  @override
  String get overlayEditText => 'Tekst bewerken';

  @override
  String get overlayFont => 'Lettertype';

  @override
  String get overlayLarger => 'Groter';

  @override
  String get overlayMore => 'Meer';

  @override
  String get overlayNote => 'Notitie';

  @override
  String get overlaySmaller => 'Kleiner';

  @override
  String get overlayStampText => 'Stempeltekst';

  @override
  String get overlayUnderline => 'Onderstrepen';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Voer pagina\'s in tussen 1 en $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'De laatste pagina mag niet vóór de eerste liggen.';

  @override
  String get pageRangeFrom => 'Van';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagina\'s',
      one: '1 pagina',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Tot';

  @override
  String get panelDragToMovePanel => 'Sleep om paneel te verplaatsen';

  @override
  String get paste => 'Plakken';

  @override
  String get propAlign => 'Uitlijnen';

  @override
  String get propAlignCenter => 'Centreren';

  @override
  String get propAlignLeft => 'Links uitlijnen';

  @override
  String get propAlignRight => 'Rechts uitlijnen';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count annotaties',
      one: '$count annotatie',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Auteur';

  @override
  String get propAutoSize => 'Automatisch aanpassen';

  @override
  String get propBold => 'Vet';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'Meegeleverd lettertype';

  @override
  String get propCallout => 'Bijschrift';

  @override
  String get propCharSpacing => 'Tekenafstand';

  @override
  String get propColor => 'Kleur';

  @override
  String get propColour => 'Kleur';

  @override
  String get propContents => 'Inhoud';

  @override
  String get propEditsApplyToAll =>
      'Bewerkingen gelden voor alle compatibele annotaties';

  @override
  String get propFieldName => 'Veldnaam';

  @override
  String get propFieldTypeCheckBox => 'Selectievakje';

  @override
  String get propFieldTypeComboBox => 'Vervolgkeuzelijst';

  @override
  String get propFieldTypeImageButton => 'Afbeeldingsknop';

  @override
  String get propFieldTypeListBox => 'Keuzelijst';

  @override
  String get propFieldTypeRadioGroup => 'Keuzerondjesgroep';

  @override
  String get propFieldTypeSignature => 'Handtekening';

  @override
  String get propFieldTypeText => 'Tekstveld';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Veldtype: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Onbekend veld';

  @override
  String get propFill => 'Vulling';

  @override
  String get propFont => 'Lettertype';

  @override
  String get propFontSubsetTooltip =>
      'Dit lettertype is een subset - alleen de tekens die al in het document worden gebruikt, kunnen worden getypt.';

  @override
  String get propFontWidth => 'Letterbreedte';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'B';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Cursief';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Beperkte tekens';

  @override
  String get propLineEnd => 'Lijneinde';

  @override
  String get propLineEndingButt => 'Plat';

  @override
  String get propLineEndingCircle => 'Cirkel';

  @override
  String get propLineEndingClosedArrow => 'Gesloten pijl';

  @override
  String get propLineEndingClosedArrowRev => 'Gesloten pijl (omg.)';

  @override
  String get propLineEndingDiamond => 'Ruit';

  @override
  String get propLineEndingOpenArrow => 'Open pijl';

  @override
  String get propLineEndingOpenArrowRev => 'Open pijl (omg.)';

  @override
  String get propLineEndingSlash => 'Schuine streep';

  @override
  String get propLineEndingSquare => 'Vierkant';

  @override
  String get propLineSpacing => 'Regelafstand';

  @override
  String get propLineStart => 'Lijnbegin';

  @override
  String get propLineType => 'Lijntype';

  @override
  String get propLoadFont => 'Lettertype laden…';

  @override
  String get propLoadFontSubtitle => 'TTF- of OTF-bestand';

  @override
  String get propMoreColors => 'Meer kleuren…';

  @override
  String get propMultiline => 'Meerdere regels';

  @override
  String get propNoFill => 'Geen vulling';

  @override
  String get propNoFontsFound => 'Geen lettertypen gevonden';

  @override
  String get propNoOutline => 'Geen omtrek';

  @override
  String get propOpacity => 'Dekking';

  @override
  String get propOutline => 'Omtrek';

  @override
  String get propPageLabel => 'Pagina';

  @override
  String propPageNumber(int number) {
    return 'Pagina $number';
  }

  @override
  String get propPropertiesTitle => 'Eigenschappen';

  @override
  String get propRecentlyUsed => 'Onlangs gebruikt';

  @override
  String get propScale => 'Schaal';

  @override
  String get propSearchFonts => 'Lettertypen zoeken';

  @override
  String get propSectionAllFonts => 'Alle lettertypen';

  @override
  String get propSectionAppearance => 'Weergave';

  @override
  String get propSectionContent => 'Inhoud';

  @override
  String get propSectionFormField => 'Formulierveld';

  @override
  String get propSectionInThisDocument => 'In dit document';

  @override
  String get propSectionPositionSize => 'Positie & grootte (pt)';

  @override
  String get propSectionSelection => 'Selectie';

  @override
  String get propSectionText => 'Tekst';

  @override
  String get propSelectAnnotationPrompt =>
      'Selecteer een annotatie om de eigenschappen te zien';

  @override
  String get propSize => 'Grootte';

  @override
  String get propStandardPdfFont => 'Standaard-PDF-lettertype';

  @override
  String get propStroke => 'Lijn';

  @override
  String get propStyle => 'Stijl';

  @override
  String get propSystemFont => 'Systeemlettertype';

  @override
  String get propType => 'Type';

  @override
  String get propUnderline => 'Onderstrepen';

  @override
  String get propVaries => 'Verschilt';

  @override
  String get redo => 'Opnieuw';

  @override
  String get reflowNoContent => 'Geen extraheerbare inhoud';

  @override
  String reflowPageLabel(int number) {
    return 'Pagina $number';
  }

  @override
  String get reflowSaveOrShare => 'Opslaan of delen';

  @override
  String get reflowViewFigure => 'Afbeelding weergeven';

  @override
  String get remove => 'Verwijderen';

  @override
  String get rename => 'Naam wijzigen';

  @override
  String get reset => 'Herstellen';

  @override
  String get save => 'Opslaan';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Pagina $page';
  }

  @override
  String get sbarCallout => 'Bijschrift';

  @override
  String get sbarFieldButton => 'Knopveld';

  @override
  String get sbarFieldChoice => 'Keuzeveld';

  @override
  String get sbarFieldGeneric => 'Formulierveld';

  @override
  String get sbarFieldSignature => 'Handtekeningveld';

  @override
  String get sbarFieldText => 'Tekstveld';

  @override
  String get sbarStateAccepted => 'Geaccepteerd';

  @override
  String get sbarStateCancelled => 'Geannuleerd';

  @override
  String get sbarStateMarked => 'Gemarkeerd';

  @override
  String get sbarStateRejected => 'Afgewezen';

  @override
  String get sbarStateResolved => 'Opgelost';

  @override
  String get sbarStateUnmarked => 'Niet gemarkeerd';

  @override
  String get searchAnnotations => 'Annotaties doorzoeken';

  @override
  String get searchClearSearch => 'Zoekopdracht wissen';

  @override
  String get searchEmptyHint =>
      'Doorzoek het document om hier alle overeenkomsten te zien';

  @override
  String get searchMatchCase => 'Hoofdlettergevoelig';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overeenkomsten',
      one: '1 overeenkomst',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Volgende overeenkomst';

  @override
  String searchNoMatches(String query) {
    return 'Geen overeenkomsten voor “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Pagina $page';
  }

  @override
  String get searchPreviousMatch => 'Vorige overeenkomst';

  @override
  String get searchRegex => 'Reguliere expressie';

  @override
  String get searchResultsTitle => 'Zoekresultaten';

  @override
  String get searchWholeWord => 'Heel woord';

  @override
  String get shellControls => 'Bediening';

  @override
  String get shellDefaultAuthor => 'Standaardauteur…';

  @override
  String get shellHighlightFormFields => 'Formuliervelden markeren';

  @override
  String get shellKeyboardShortcutsMenu => 'Sneltoetsen…';

  @override
  String get shellKeyboardShortcutsTitle => 'Sneltoetsen';

  @override
  String get shellShortcutsSearchHint => 'Sneltoetsen zoeken';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Geen sneltoetsen komen overeen met “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Selecteren';

  @override
  String get shellShortcutGroupMarkup => 'Opmaak';

  @override
  String get shellShortcutGroupDraw => 'Tekenen';

  @override
  String get shellShortcutGroupShapes => 'Vormen';

  @override
  String get shellShortcutGroupInsert => 'Invoegen';

  @override
  String get shellShortcutGroupMeasure => 'Meten';

  @override
  String get shellShortcutGroupEdit => 'Bewerken';

  @override
  String get shellNotSet => 'Niet ingesteld';

  @override
  String get shellPageColor => 'Paginakleur…';

  @override
  String get shellPageGrid => 'Paginaraster';

  @override
  String get shellPanelAnnotations => 'Annotaties';

  @override
  String get shellPanelBookmarks => 'Bladwijzers';

  @override
  String get shellPanelPages => 'Pagina\'s';

  @override
  String get shellPanelProperties => 'Eigenschappen';

  @override
  String get shellPanelSearchResults => 'Zoekresultaten';

  @override
  String get shellPanels => 'Panelen';

  @override
  String get shellPressAKey => 'Druk op een toets';

  @override
  String get shellPressLetterKeyHint =>
      'Druk op een lettertoets of Delete om te wissen.';

  @override
  String get shellReflow => 'Herschikken';

  @override
  String get shellReflowText => 'Tekst herschikken';

  @override
  String get shellResetZoom => 'Zoom herstellen';

  @override
  String get shellSectionShell => 'Shell';

  @override
  String get shellSectionView => 'Weergave';

  @override
  String get shellSettings => 'Instellingen';

  @override
  String get shellShowAnnotations => 'Annotaties tonen';

  @override
  String get shellTabHere => 'Tabblad hier';

  @override
  String get shellUnbound => 'Niet toegewezen';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'door $author';
  }

  @override
  String get sidebarCancelSelection => 'Selectie annuleren';

  @override
  String get sidebarClearSearch => 'Zoekopdracht wissen';

  @override
  String get sidebarDeleteSelected => 'Geselecteerde verwijderen';

  @override
  String get sidebarDeleteSignature => 'Handtekening verwijderen';

  @override
  String get sidebarLockAnnotation => 'Vergrendelen';

  @override
  String get sidebarUnlockAnnotation => 'Ontgrendelen';

  @override
  String get sidebarMore => 'Meer';

  @override
  String get sidebarNoAnnotations => 'Geen annotaties';

  @override
  String get sidebarNoMatchingAnnotations => 'Geen overeenkomende annotaties';

  @override
  String sidebarPageHeader(int number) {
    return 'Pagina $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Hiermee wordt de digitale handtekening uit het document verwijderd. U kunt dit ongedaan maken.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Hiermee wordt de digitale handtekening van \"$name\" uit het document verwijderd. U kunt dit ongedaan maken.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Handtekening verwijderen?';

  @override
  String get sidebarReopen => 'Opnieuw openen';

  @override
  String get sidebarReply => 'Beantwoorden';

  @override
  String get sidebarResolve => 'Oplossen';

  @override
  String get sidebarSearchHint => 'Annotaties zoeken';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geselecteerd',
      one: '$count geselecteerd',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'Schrijf een antwoord…';

  @override
  String get sigTitle => 'Handtekening';

  @override
  String get signIdCreate => 'Aanmaken';

  @override
  String get signIdEmail => 'E-mail (optioneel)';

  @override
  String get signIdName => 'Naam';

  @override
  String get signIdNameHint =>
      'Uw naam, zoals die op de handtekening moet verschijnen';

  @override
  String get signIdNameRequired => 'Voer een naam in';

  @override
  String get signIdOrganization => 'Organisatie (optioneel)';

  @override
  String get signIdSelfSignedInfo =>
      'Hiermee maakt u een zelfondertekende identiteit. Handtekeningen worden weergegeven als \"ondertekend, geldigheid onbekend\" in Adobe Acrobat en andere lezers - hetzelfde als hun eigen zelfondertekende ID\'s. Het groene vinkje vereist een betaalde, openbaar vertrouwde CA.';

  @override
  String get signIdTitle => 'Ondertekeningsidentiteit aanmaken';

  @override
  String get stampBox => 'Vak';

  @override
  String get stampCircle => 'Cirkel';

  @override
  String get stampCustomCaption => 'Aangepaste stempel';

  @override
  String get stampDateFormat => 'Datumnotatie';

  @override
  String get stampDeleteComponent => 'Geselecteerd onderdeel verwijderen';

  @override
  String get stampDeleteStamp => 'Stempel verwijderen';

  @override
  String get stampEditStamp => 'Stempel bewerken';

  @override
  String get stampExport => 'Exporteren…';

  @override
  String get stampFieldDate => 'Datum';

  @override
  String get stampFieldDateTime => 'Datum & tijd';

  @override
  String get stampFieldTime => 'Tijd';

  @override
  String get stampFieldUsername => 'Gebruikersnaam';

  @override
  String get stampFont => 'Lettertype';

  @override
  String get stampFontBold => 'Vet';

  @override
  String get stampFontItalic => 'Cursief';

  @override
  String get stampHeight => 'Hoogte';

  @override
  String get stampImage => 'Afbeelding';

  @override
  String get stampImport => 'Importeren…';

  @override
  String get stampInsertField => 'Veld invoegen';

  @override
  String get stampMoreColors => 'Meer kleuren…';

  @override
  String get stampNewStamp => 'Nieuwe stempel…';

  @override
  String get stampNewStampTitle => 'Nieuwe stempel';

  @override
  String get stampSelectTextToEdit => 'Selecteer tekst om te bewerken';

  @override
  String get stampSelectedText => 'Geselecteerde tekst';

  @override
  String get stampSignature => 'Handtekening';

  @override
  String get stampStamps => 'Stempels';

  @override
  String get stampText => 'Tekst';

  @override
  String get stampTime12Hour => '12 uur';

  @override
  String get stampTime24Hour => '24 uur';

  @override
  String get stampTimeFormat => 'Tijdnotatie';

  @override
  String get stampWidth => 'Breedte';

  @override
  String get takeoffArea => 'Oppervlakte';

  @override
  String get takeoffCount => 'Aantal';

  @override
  String get takeoffEmpty => 'Nog geen metingen.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groepen',
      one: '$count groep',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Lengte';

  @override
  String get takeoffTitle => 'Hoeveelheden';

  @override
  String get tbAddInkAnnotation => 'Inktannotatie toevoegen';

  @override
  String get tbAlign => 'Uitlijnen';

  @override
  String get tbAlignBottom => 'Onder uitlijnen';

  @override
  String get tbAlignHorizontalCenters => 'Horizontale middens uitlijnen';

  @override
  String get tbAlignLeft => 'Links uitlijnen';

  @override
  String get tbAlignRight => 'Rechts uitlijnen';

  @override
  String get tbAlignTop => 'Boven uitlijnen';

  @override
  String get tbAlignVerticalCenters => 'Verticale middens uitlijnen';

  @override
  String get tbAnnotationsFlattened => 'Annotaties in de pagina\'s afgevlakt';

  @override
  String get tbApplyRedactionsMessage =>
      'De gemarkeerde inhoud wordt permanent uit het document verwijderd. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get tbApplyRedactionsTitle => 'Redacties toepassen?';

  @override
  String get tbApplyRedactionsTooltip => 'Redacties toepassen (onomkeerbaar)';

  @override
  String get tbAutosizeTextBox => 'Tekstvak automatisch aanpassen (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Teken een lijn met bekende lengte om de schaal te kalibreren.';

  @override
  String get tbCharSpacing => 'Tekenafstand';

  @override
  String get tbCheckBoxOption => 'Selectievakje';

  @override
  String get tbCheckMarksOnDocument => 'Vinkjes op het document';

  @override
  String get tbCropImage => 'Afbeelding bijsnijden';

  @override
  String get tbCroppingImage => 'Bezig met bijsnijden';

  @override
  String get tbCropApply => 'Bijsnijden toepassen';

  @override
  String get tbCropCancel => 'Bijsnijden annuleren';

  @override
  String get tbCropReset => 'Bijsnijden herstellen';

  @override
  String get tbColorLabel => 'Kleur';

  @override
  String get tbColorProcessingTooltip =>
      'Kleurverwerking - pagina-inhoudkleuren zoeken en vervangen';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kleuren vervangen',
      one: '1 kleur vervangen',
      zero: 'Geen overeenkomende kleuren gevonden',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Omzetten naar selectievakje';

  @override
  String get tbConvertToImageButton => 'Omzetten naar afbeeldingsknop';

  @override
  String get tbConvertToTextField => 'Omzetten naar tekstveld';

  @override
  String get tbCornerRadius => 'Hoekradius';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count annotaties verwijderen',
      one: 'Annotatie verwijderen',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Element verwijderen';

  @override
  String get tbDeleteField => 'Veld verwijderen';

  @override
  String get tbDiscardDrawing => 'Tekening verwijderen';

  @override
  String get tbDistributeHorizontally => 'Horizontaal verdelen';

  @override
  String get tbDistributeVertically => 'Verticaal verdelen';

  @override
  String get tbDrawNewSignature => 'Nieuwe handtekening tekenen…';

  @override
  String get tbEditAnnotationText => 'Annotatietekst bewerken';

  @override
  String get tbEditTextStyle => 'Tekst & stijl bewerken';

  @override
  String get tbElement => 'Element';

  @override
  String get tbEraserSize => 'Gumgrootte';

  @override
  String get tbFieldActions => 'Veldacties';

  @override
  String get tbFieldName => 'Veldnaam';

  @override
  String tbFieldNamed(String name) {
    return 'Veld: $name';
  }

  @override
  String get tbFieldValue => 'Veldwaarde';

  @override
  String get tbFill => 'Vulling';

  @override
  String get tbFingerDraws =>
      'Vinger tekent - tik zodat deze in plaats daarvan scrolt';

  @override
  String get tbFingerScrolls =>
      'Vinger scrolt (pen tekent) - tik zodat deze tekent';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'Annotaties in de pagina\'s afvlakken';

  @override
  String get tbFlattenForm => 'Formulier afvlakken';

  @override
  String get tbFlattenFormBakeValues =>
      'Formulier afvlakken - waarden in de pagina\'s vastleggen';

  @override
  String get tbFlattenLabel => 'Afvlakken';

  @override
  String get tbFont => 'Lettertype';

  @override
  String get tbFontSize => 'Tekengrootte';

  @override
  String get tbFontWidth => 'Letterbreedte';

  @override
  String get tbFormFieldsFlattened =>
      'Formuliervelden in de pagina\'s afgevlakt';

  @override
  String get tbGroupDraw => 'Tekenen';

  @override
  String get tbGroupEdit => 'Bewerken';

  @override
  String get tbGroupInsert => 'Invoegen';

  @override
  String get tbGroupMarkup => 'Opmaak';

  @override
  String get tbGroupMeasure => 'Meten';

  @override
  String get tbGroupSelect => 'Selecteren';

  @override
  String get tbGroupShapes => 'Vormen';

  @override
  String get tbImageButtonOption => 'Afbeeldingsknop';

  @override
  String get tbLineEnd => 'Lijneinde';

  @override
  String get tbLineSpacing => 'Regelafstand';

  @override
  String get tbLineStart => 'Lijnbegin';

  @override
  String get tbLineType => 'Lijntype';

  @override
  String get tbManageStamps => 'Stempels beheren…';

  @override
  String get tbMarkupHighlight => 'Markeren';

  @override
  String get tbMarkupHighlightTip => 'Selectie markeren';

  @override
  String get tbMarkupSquiggly => 'Golvend onderstrepen';

  @override
  String get tbMarkupSquigglyTip => 'Selectie golvend onderstrepen';

  @override
  String get tbMarkupStrikeOut => 'Doorhalen';

  @override
  String get tbMarkupStrikeOutTip => 'Selectie doorhalen';

  @override
  String get tbMarkupUnderline => 'Onderstrepen';

  @override
  String get tbMarkupUnderlineTip => 'Selectie onderstrepen';

  @override
  String get tbMoreColors => 'Meer kleuren…';

  @override
  String get tbNameArrow => 'Pijl';

  @override
  String get tbNameCallout => 'Bijschrift';

  @override
  String get tbNameCloudPolygon => 'Wolkveelhoek';

  @override
  String get tbNameCount => 'Aantal';

  @override
  String get tbNameDigitalSignature => 'Digitale handtekening';

  @override
  String get tbNameDraw => 'Tekenen';

  @override
  String get tbNameEllipse => 'Ellips';

  @override
  String get tbNameEraser => 'Inktstreken wissen';

  @override
  String get tbNameHighlight => 'Markeren';

  @override
  String get tbNameImage => 'Afbeelding';

  @override
  String get tbNameLine => 'Lijn';

  @override
  String get tbNameMeasureAngle => 'Hoek meten';

  @override
  String get tbNameMeasureArc => 'Booglengte meten';

  @override
  String get tbNameMeasureArea => 'Oppervlakte meten';

  @override
  String get tbNameMeasureDistance => 'Afstand meten';

  @override
  String get tbNameMeasurePerimeter => 'Omtrek meten';

  @override
  String get tbNameMeasureSlope => 'Helling meten (stijging/loop)';

  @override
  String get tbNameMeasureVolume => 'Volume meten (oppervlakte × diepte)';

  @override
  String get tbNameNote => 'Notitie';

  @override
  String get tbNamePolygon => 'Veelhoek';

  @override
  String get tbNamePolyline => 'Polylijn';

  @override
  String get tbNameRectangle => 'Rechthoek';

  @override
  String get tbNameSelect => 'Selecteren';

  @override
  String get tbNameSignature => 'Handtekening';

  @override
  String get tbNameStamp => 'Stempel';

  @override
  String get tbNameTextBox => 'Tekstvak';

  @override
  String get tbNewFieldType =>
      'Nieuw veldtype - sleep op een pagina om er een toe te voegen';

  @override
  String get tbNoAnnotationsToFlatten => 'Geen annotaties om af te vlakken';

  @override
  String get tbNoCustomStamps => 'Geen aangepaste stempels';

  @override
  String get tbNoFormFieldsToFlatten => 'Geen formuliervelden om af te vlakken';

  @override
  String get tbNoRedactionsToApply => 'Geen redacties om toe te passen';

  @override
  String get tbNoteTitle => 'Notitie';

  @override
  String get tbOpacity => 'Dekking';

  @override
  String get tbOutline => 'Omtrek';

  @override
  String get tbPatternScale => 'Patroonschaal';

  @override
  String get tbPickColorFromPage => 'Een kleur van de pagina kiezen';

  @override
  String get tbRedactionsApplied => 'Redacties toegepast';

  @override
  String get tbRedoShortcut => 'Opnieuw (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Kan niet herschikken - dit is geen enkelkoloms alinea die deze tool opnieuw kan afbreken. Probeer in plaats daarvan Tekst vervangen.';

  @override
  String get tbReflowParagraph => 'Alinea herschikken';

  @override
  String get tbRenameField => 'Veldnaam wijzigen';

  @override
  String get tbRenameFieldEllipsis => 'Veldnaam wijzigen…';

  @override
  String get tbReplaceImage => 'Afbeelding vervangen';

  @override
  String get tbReplaceImageFailed => 'Kan afbeelding niet vervangen';

  @override
  String get tbReplaceText => 'Tekst vervangen';

  @override
  String get tbSaveImage => 'Afbeelding opslaan';

  @override
  String get tbSaveShortcut => 'Opslaan… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Schaal';

  @override
  String get tbSelectTextForMarkup => 'Selecteer tekst om opmaak te gebruiken';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geselecteerd',
      one: 'Selectie',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Instellen…';

  @override
  String get tbStamp => 'Stempel';

  @override
  String get tbStampText => 'Stempeltekst';

  @override
  String get tbStrokeOpacityFont => 'Lijn, dekking, lettertype';

  @override
  String get tbStrokeWidthLabel => 'Lijndikte';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Lijn $width';
  }

  @override
  String get tbStyle => 'Stijl';

  @override
  String get tbTakeoffTotals => 'Hoeveelheidstotalen';

  @override
  String get tbTextBorder => 'Tekstrand';

  @override
  String get tbTextColour => 'Tekstkleur';

  @override
  String get tbTextFieldOption => 'Tekstveld';

  @override
  String get tbTextFill => 'Tekstvulling';

  @override
  String get tbTextStyleEllipsis => 'Tekststijl…';

  @override
  String get tbTextTitle => 'Tekst';

  @override
  String get tbTipCallout =>
      'Bijschrift - sleep van het punt naar waar het vak komt';

  @override
  String get tbTipContent => 'Pagina-inhoud bewerken';

  @override
  String get tbTipCount => 'Aantal - tik om vinkjes te plaatsen en te tellen';

  @override
  String get tbTipDigitalSignature =>
      'Digitale handtekening - sleep een vak om te plaatsen en te ondertekenen';

  @override
  String get tbTipForm =>
      'Formuliervelden - tik om te selecteren, dubbeltik om in te vullen, sleep om toe te voegen';

  @override
  String get tbTipHighlightDraw => 'Markeren - teken uit de vrije hand';

  @override
  String get tbTipImage => 'Afbeelding - tik om te plaatsen of sleep een vak';

  @override
  String get tbTipMeasureAngle => 'Hoek meten - klik drie punten';

  @override
  String get tbTipMeasureArc => 'Booglengte meten - klik drie punten';

  @override
  String get tbTipRedact => 'Redigeren - sleep een gebied en pas toe';

  @override
  String get tbTipSignature =>
      'Handtekening - tik op een pagina om te plaatsen';

  @override
  String get tbTipSnapshot =>
      'Momentopname - sleep een gebied om het vast te leggen (plak terug als vector)';

  @override
  String get tbToolContent => 'Inhoud';

  @override
  String get tbToolForm => 'Formulier';

  @override
  String get tbToolRedact => 'Redigeren';

  @override
  String get tbToolSnapshot => 'Momentopname';

  @override
  String get tbTools => 'Gereedschappen';

  @override
  String get tbTotals => 'Totalen';

  @override
  String get tbTypeTextEachTime => 'Elke keer tekst typen';

  @override
  String get tbUnderline => 'Onderstrepen';

  @override
  String get tbUndoShortcut => 'Ongedaan maken (⌘Z)';

  @override
  String get textStyleFont => 'Lettertype';

  @override
  String get textStyleFontSize => 'Tekengrootte';

  @override
  String get textStyleKeep => 'behouden';

  @override
  String get textStyleStyle => 'Stijl';

  @override
  String get textStyleText => 'Tekst';

  @override
  String get textStyleTextFill => 'Tekstvulling';

  @override
  String get textStyleTitle => 'Tekst & stijl bewerken';

  @override
  String get thumbAddPage => 'Pagina toevoegen';

  @override
  String get thumbClearSelection => 'Selectie wissen';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagina\'s kopiëren',
      one: 'Pagina kopiëren',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Geselecteerde pagina\'s kopiëren';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagina\'s knippen',
      one: 'Pagina knippen',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Geselecteerde pagina\'s knippen';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagina\'s verwijderen',
      one: 'Pagina verwijderen',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Geselecteerde pagina\'s verwijderen';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagina\'s dupliceren',
      one: 'Pagina dupliceren',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Pagina\'s exporteren…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagina\'s exporteren…',
      one: 'Pagina exporteren…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Geselecteerde pagina\'s exporteren';

  @override
  String get thumbInsertBlankAfter => 'Lege pagina hierna invoegen';

  @override
  String get thumbInsertBlankBefore => 'Lege pagina hiervoor invoegen';

  @override
  String get thumbInsertFileFailed => 'Kan dat bestand niet invoegen.';

  @override
  String get thumbInsertPdf => 'PDF invoegen…';

  @override
  String get thumbPageActions => 'Pagina-acties';

  @override
  String thumbPageNumber(int number) {
    return 'Pagina $number';
  }

  @override
  String get thumbPages => 'Pagina\'s';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagina\'s plakken',
      one: 'Pagina plakken',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => '180° draaien';

  @override
  String get thumbRotateLeft => 'Linksom draaien';

  @override
  String get thumbRotatePageRight => 'Pagina rechtsom draaien';

  @override
  String get thumbRotateRight => 'Rechtsom draaien';

  @override
  String get thumbRotateSelectedLeft =>
      'Geselecteerde pagina\'s linksom draaien';

  @override
  String get thumbRotateSelectedRight =>
      'Geselecteerde pagina\'s rechtsom draaien';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geselecteerd',
      one: '$count geselecteerd',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Ongedaan maken';

  @override
  String get viewerEditFontUnsafe =>
      'Dit PDF-lettertype of deze codering kan niet veilig worden bewerkt.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Bewerken vereist een selectie op één pagina.';

  @override
  String get viewerEditNotEditableRun =>
      'Deze selectie is geen enkele bewerkbare pagina-inhoudtekstrun.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Dit PDF-lettertype kan opnieuw worden getypt, maar de stijl kan niet worden gewijzigd.';

  @override
  String get viewerEditTextStyle => 'Tekst & stijl bewerken';

  @override
  String get viewerMarkup => 'Opmaak';

  @override
  String get viewerMarkupHighlight => 'Markeren';

  @override
  String get viewerMarkupSquiggly => 'Golvend';

  @override
  String get viewerMarkupStrikeOut => 'Doorhalen';

  @override
  String get viewerMarkupUnderline => 'Onderstrepen';

  @override
  String get viewerSelectAll => 'Alles selecteren';
}

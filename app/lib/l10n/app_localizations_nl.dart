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
  String get appSigAddLogo => 'Logo toevoegen…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Alle $pageCount pagina\'s';
  }

  @override
  String get appSigAppearance => 'Weergave';

  @override
  String get appSigAppearanceDescription =>
      'De handtekening wordt getekend waar u deze hebt geplaatst. De naam en gegevens van de ondertekenaar worden altijd getoond; u kunt een handgetekende markering en een logo-achtergrond toevoegen.';

  @override
  String appSigApplyTo(String label) {
    return 'Toepassen op: $label';
  }

  @override
  String get appSigApplyToPages => 'Toepassen op pagina\'s…';

  @override
  String get appSigChooseCertificate => 'Certificaatbestand kiezen…';

  @override
  String get appSigChooseKeyDescription =>
      'Kies uw privésleutel (RSA, PEM of DER) en het bijbehorende certificaatbestand. De sleutel wordt alleen gebruikt om te ondertekenen en wordt nooit opgeslagen.';

  @override
  String get appSigChoosePngOrJpeg => 'Kies een PNG- of JPEG-afbeelding.';

  @override
  String get appSigChoosePrivateKey => 'Privésleutel kiezen…';

  @override
  String get appSigContactInfo => 'Contactgegevens';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Kan de handtekening niet vastleggen.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Kan het certificaat niet lezen: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Kan de sleutel niet lezen: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Een handtekening op dit apparaat maken';

  @override
  String appSigDate(String date) {
    return 'Datum: $date';
  }

  @override
  String get appSigDigitallySign => 'Digitaal ondertekenen';

  @override
  String get appSigDrawSignature => 'Handtekening tekenen…';

  @override
  String get appSigFieldHelper =>
      'Laat leeg om een nieuw handtekeningveld te maken.';

  @override
  String get appSigFieldLabel => 'Bestaand handtekeningveld (optioneel)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificaten',
      one: '1 certificaat',
    );
    return '$_temp0 · geldig $validFrom tot $validUntil';
  }

  @override
  String get appSigIntro =>
      'Een digitale handtekening bewijst dat u dit document hebt ondertekend en dat het sindsdien niet is gewijzigd. Kies hoe u wilt ondertekenen.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'De geselecteerde sleutel of het certificaat kon niet worden gelezen.';

  @override
  String get appSigKeylessDescription =>
      'Het eenvoudigst. We bevestigen dat u het bent via e-mail en ondertekenen voor u, met een vertrouwde tijdstempel. Niets te installeren of in te stellen.';

  @override
  String get appSigKeylessIdentity => 'Sleutelloze identiteit';

  @override
  String get appSigKeylessSignInExpired =>
      'Uw sleutelloze aanmelding is verlopen. Meld u opnieuw aan.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Sleutelloze aanmelding mislukt: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Sleutelloos · met tijdstempel · geldigheid onbekend';

  @override
  String get appSigKeylessWebNote =>
      'Aanmelden met uw e-mail is de eenvoudigste manier — dit is beschikbaar in de DartPDF-desktop- en mobiele apps. Om veiligheidsredenen kan het niet in een webbrowser worden uitgevoerd.';

  @override
  String get appSigLocation => 'Locatie';

  @override
  String get appSigLogoAdded => 'Logo toegevoegd ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Pagina\'s $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Voorbeeld - het ondertekende vak kan iets afwijken.';

  @override
  String get appSigReason => 'Reden';

  @override
  String appSigReasonLine(String reason) {
    return 'Reden: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Aanmelding vernieuwen…';

  @override
  String get appSigRemoveLogo => 'Logo verwijderen';

  @override
  String get appSigRemoveSignature => 'Handtekening verwijderen';

  @override
  String get appSigSelfSignedDescription =>
      'Geen aanmelding of bestanden nodig. Het beste voor persoonlijk gebruik — het wordt op dit apparaat opgeslagen voor de volgende keer. Sommige PDF-lezers tonen het als \"ondertekend, geldigheid onbekend\", wat normaal is voor een handtekening die u zelf maakt.';

  @override
  String get appSigSelfSignedIdentity => 'Zelfondertekende identiteit';

  @override
  String get appSigSelfSignedSubtitle =>
      'Zelfondertekend · geldigheid onbekend';

  @override
  String get appSigShowSignatureOnPages => 'De handtekening op pagina\'s tonen';

  @override
  String get appSigSign => 'Ondertekenen';

  @override
  String get appSigSignInWithEmail => 'Aanmelden met uw e-mail';

  @override
  String get appSigSignatureAdded => 'Handtekening toegevoegd ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Digitaal ondertekend door $signerName';
  }

  @override
  String get appSigSigner => 'Ondertekenaar';

  @override
  String get appSigSigningYouIn => 'U wordt aangemeld…';

  @override
  String get appSigThisPageOnly => 'Alleen deze pagina';

  @override
  String get appSigUseOwnCertificate => 'Uw eigen certificaat gebruiken';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Voor een ondertekeningscertificaat van uw organisatie';

  @override
  String get appSigX509Signer => 'X.509-ondertekenaar';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Deze $count PDF\'s in een nieuw tabblad openen of hun pagina\'s invoegen in \"$title\"?',
      one:
          'Deze PDF in een nieuw tabblad openen of de pagina\'s ervan invoegen in \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Neergezette PDF\'s toevoegen',
      one: 'Neergezette PDF toevoegen',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Annotatietekst gekopieerd';

  @override
  String get editorAppMenuTooltip => 'DartPDF-menu';

  @override
  String get editorCancelOcr => 'OCR annuleren';

  @override
  String get editorClearRecentFiles => 'Recente bestanden wissen';

  @override
  String get editorCloseAll => 'Alles sluiten';

  @override
  String get editorCloseOthers => 'Overige sluiten';

  @override
  String get editorCloseTab => 'Tabblad sluiten';

  @override
  String get editorCloseTabsToRight => 'Tabbladen rechts sluiten';

  @override
  String get editorCompareFailedTitle => 'Vergelijken mislukt';

  @override
  String editorCompareTitle(String title) {
    return 'Vergelijken: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Gekopieerd naar klembord';

  @override
  String get editorCopySelectedTextTooltip =>
      'Geselecteerde tekst kopiëren (⌘C)';

  @override
  String get editorCopyText => 'Tekst kopiëren';

  @override
  String editorCouldNotExport(String title) {
    return 'Kan $title niet exporteren';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Kan stempels niet importeren: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kan de neergezette PDF\'s niet invoegen',
      one: 'Kan de neergezette PDF niet invoegen',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Kan $title niet openen\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'Kan bovenliggende map niet openen';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Kan het tweede bestand niet openen\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Kan het geselecteerde bestand niet openen\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Kan $url niet openen';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Kan $title niet afdrukken';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Kan $title niet opnieuw openen';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Kan niet digitaal ondertekenen: $error';
  }

  @override
  String get editorDiscard => 'Verwerpen';

  @override
  String get editorDiscardChangesTitle => 'Wijzigingen verwerpen?';

  @override
  String get editorDocumentSigned => 'Document digitaal ondertekend';

  @override
  String get editorDownload => 'Downloaden';

  @override
  String get editorDropToOpen => 'Zet PDF neer om te openen';

  @override
  String get editorDropToOpenOrInsert =>
      'Zet PDF neer om te openen of in te voegen';

  @override
  String get editorInsertPages => 'Pagina\'s invoegen';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '$count ingevoegd; kan $files niet lezen';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF\'s ingevoegd in $title',
      one: 'Pagina\'s ingevoegd in $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Ongeldige koppeling: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Dit document probeerde JavaScript uit te voeren (genegeerd)';

  @override
  String get editorLoadingFullDocument => 'Volledig document laden';

  @override
  String get editorMenuCompareWith => 'Vergelijken met…';

  @override
  String get editorMenuDigitallySign => 'Digitaal ondertekenen…';

  @override
  String get editorMenuDigitallySigning => 'Digitaal ondertekenen…';

  @override
  String get editorMenuExportImage => 'Pagina als afbeelding exporteren…';

  @override
  String get editorMenuNewDocument => 'Nieuw document…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Een PDF openen…';

  @override
  String get editorMenuPrint => 'Afdrukken…';

  @override
  String get editorMenuSaveAs => 'Opslaan als…';

  @override
  String get editorMenuScanDocument => 'Scannen naar nieuw document…';

  @override
  String get editorMenuInsertScan => 'Scan invoegen…';

  @override
  String get editorScanFailed => 'Kan het document niet scannen.';

  @override
  String get editorInsertedScan => 'Gescande pagina\'s ingevoegd.';

  @override
  String get editorMenuSettings => 'Instellingen';

  @override
  String get editorMenuSwitchToEdit => 'Overschakelen naar bewerkmodus';

  @override
  String get editorMenuSwitchToReadOnly => 'Overschakelen naar alleen-lezen';

  @override
  String editorNamedAction(String name) {
    return 'Benoemde actie: $name';
  }

  @override
  String get editorNoRecentFiles => 'Geen recente bestanden';

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
      'Open een document voordat u OCR uitvoert';

  @override
  String get editorOpenFailedTitle => 'Openen mislukt';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Openen in nieuwe tabbladen',
      one: 'Openen in nieuw tabblad',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'PDF openen in een nieuw tabblad';

  @override
  String get editorOpenRecent => 'Recent openen';

  @override
  String get editorOpenTabs => 'Open tabbladen';

  @override
  String get editorOpeningDocumentSemantic => 'Document openen';

  @override
  String get editorOpeningPdf => 'PDF openen…';

  @override
  String editorOpeningTitle(String title) {
    return '$title openen…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Pagina $number';
  }

  @override
  String get editorPreviewComparison => 'Vergelijking';

  @override
  String get editorPreviewCouldNotOpen => 'Kan niet openen';

  @override
  String get editorPreviewOpening => 'Openen';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'Handtekening verwijderd';

  @override
  String get editorSnapshotCopied => 'Momentopname naar klembord gekopieerd';

  @override
  String get editorSnapshotCopyFailed =>
      'Kan momentopname niet naar klembord kopiëren';

  @override
  String get editorTabs => 'Tabbladen';

  @override
  String editorTabsOpenCount(int count) {
    return '$count open';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documenten hebben niet-opgeslagen wijzigingen.',
      one: 'Een document heeft niet-opgeslagen wijzigingen.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Niet-ondersteunde actie: $type';
  }

  @override
  String get editorUntitled => 'Naamloos';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version is beschikbaar.';
  }

  @override
  String get editorUpdateLater => 'Later';

  @override
  String get updateInstallNow => 'Nu bijwerken';

  @override
  String get updateDownloadingTitle => 'Update downloaden';

  @override
  String get updatePreparing => 'Voorbereiden…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloaden… $percent%';
  }

  @override
  String get updateRestarting => 'Opnieuw opstarten om de update te voltooien…';

  @override
  String get updateHandedOff =>
      'Update gedownload. Installatieprogramma wordt geopend…';

  @override
  String updateFailed(String error) {
    return 'Bijwerken mislukt: $error';
  }

  @override
  String get editorViewAllTabs => 'Alle tabbladen weergeven';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Exporteren';

  @override
  String get imgExportFormat => 'Indeling';

  @override
  String get imgExportResolution => 'Resolutie';

  @override
  String get imgExportTitle => 'Pagina als afbeelding exporteren';

  @override
  String get newDocCreate => 'Aanmaken';

  @override
  String get newDocLandscape => 'Liggend';

  @override
  String get newDocOrientation => 'Oriëntatie';

  @override
  String get newDocPageSize => 'Paginaformaat';

  @override
  String get newDocPortrait => 'Staand';

  @override
  String get newDocTitle => 'Nieuw document';

  @override
  String get none => 'Geen';

  @override
  String get ocrAlreadyRunning =>
      'OCR wordt al uitgevoerd - wacht tot het klaar is of annuleer het';

  @override
  String get ocrBrowserInitFailed =>
      'Browser-OCR kon niet worden geïnitialiseerd';

  @override
  String get ocrCancelled => 'OCR geannuleerd';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR geannuleerd na $count tekstsegmenten',
      one: 'OCR geannuleerd na 1 tekstsegment',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Downloaden';

  @override
  String ocrDownloadFailed(String error) {
    return 'Kan het OCR-model niet downloaden: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Het toevoegen van een selecteerbare tekstlaag vereist het OCR-model op het apparaat$size. Het wordt eenmaal gedownload en werkt daarna offline.\n\nModel: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'OCR-model downloaden?';

  @override
  String ocrFailed(String error) {
    return 'OCR mislukt: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'OCR op het apparaat is niet beschikbaar op dit platform';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR heeft $count tekstsegmenten toegevoegd - de paginatekst is nu selecteerbaar',
      one:
          'OCR heeft 1 tekstsegment toegevoegd - de paginatekst is nu selecteerbaar',
      zero: 'OCR vond geen tekst op deze pagina\'s',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Web-OCR downloadt een Florence-2 visie-taalmodel en voert het lokaal uit met WebGPU/WASM via Transformers.js. De PDF-pagina\'s blijven in deze browser; alleen modelbestanden worden bij het eerste gebruik opgehaald.';

  @override
  String get ocrWebPromptTitle => 'AI-OCR in deze browser uitvoeren?';

  @override
  String get ocrWebStart => 'OCR starten';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Plakken';

  @override
  String get printDlgPreparing => 'Voorbereiden…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Pagina $rendered van $total renderen…';
  }

  @override
  String get printDlgTitle => 'Afdrukken';

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
  String get settingsAbout => 'Info';

  @override
  String get settingsAppearance => 'Weergave';

  @override
  String get settingsCheckNow => 'Nu controleren';

  @override
  String get settingsLanguage => 'Taal';

  @override
  String get settingsLanguageSystem => 'Systeemstandaard';

  @override
  String get settingsCheckingForUpdates => 'Controleren op updates…';

  @override
  String get settingsCouldNotOpenDownload => 'Kan de download niet openen';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Kan systeeminstellingen niet openen';

  @override
  String get settingsDeveloperTools => 'Ontwikkelaarshulpmiddelen';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Statistieken, logboeken, rendermodi (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '$version downloaden';
  }

  @override
  String get settingsOpenSettings => 'Instellingen openen';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count onthouden',
      one: '1 onthouden',
      zero: 'Geen recente bestanden',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Recente bestanden';

  @override
  String get settingsSetUpAsDefault => 'Instellen als standaardtoepassing';

  @override
  String get settingsSystem => 'Systeem';

  @override
  String get settingsThemeDark => 'Donker';

  @override
  String get settingsThemeLight => 'Licht';

  @override
  String get settingsThemeSystem => 'Systeem';

  @override
  String get settingsTitle => 'Instellingen';

  @override
  String settingsUpToDate(String version) {
    return 'U heeft de nieuwste versie ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Versie $version is beschikbaar (u heeft $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Kan niet op updates controleren. Probeer het later opnieuw.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'U heeft $name $version.';
  }

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsViewSource => 'Broncode bekijken op GitHub';

  @override
  String get undo => 'Ongedaan maken';

  @override
  String get welcomeOpenPdf => 'Een PDF openen';

  @override
  String get welcomePickAgainToReopen => 'Kies opnieuw om te heropenen';

  @override
  String get welcomeRecent => 'Recent';

  @override
  String get welcomeRemoveFromRecent => 'Verwijderen uit recent';

  @override
  String get welcomeTapToReopen => 'Tik om te heropenen';

  @override
  String get welcomeViewAsGrid => 'Rasterweergave';

  @override
  String get welcomeViewAsList => 'Lijstweergave';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web':
            'Installeer de web-app en kies deze vervolgens voor PDF-bestanden.',
        'windows':
            'Open de Windows-instellingen voor standaard-apps voor PDF\'s.',
        'macos': 'Volg de stappen “Altijd openen met” van Finder.',
        'linux':
            'Gebruik de instellingen voor standaardtoepassingen van uw bureaublad.',
        'android': 'Kies DartPDF bij het openen van een PDF en tik op Altijd.',
        'ios':
            'Gebruik Delen of Open in vanuit Bestanden om PDF\'s hierheen te sturen.',
        'other': 'Configureer de PDF-bestandshandler van uw systeem.',
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
            'Installeer DartPDF eerst vanuit uw browser. Gebruik daarna de bestandshandler-instellingen van de browser of het besturingssysteem om PDF-bestanden aan de geïnstalleerde app te koppelen.',
        'windows':
            'Windows-instellingen opent bij Standaard-apps. Zoek naar “.pdf” of “PDF”, kies de huidige PDF-app en selecteer vervolgens DartPDF.',
        'macos':
            'Selecteer in Finder een willekeurige PDF, kies Archief > Toon info, vouw “Open met” uit, kies DartPDF en klik vervolgens op “Wijzig alle…”.',
        'linux':
            'Open de bureaubladinstellingen voor Standaardtoepassingen, of klik met de rechtermuisknop op een PDF in Bestanden, kies Eigenschappen en stel DartPDF in als standaard voor PDF-documenten.',
        'android':
            'Open een PDF vanuit Bestanden of Downloads, kies DartPDF in de app-kiezer en selecteer vervolgens Altijd. Als een andere app PDF\'s al opent, wis dan eerst de standaardinstellingen van die app in Android-instellingen.',
        'ios':
            'iOS biedt geen globale standaard-PDF-editor. Gebruik Bestanden > Delen, of houd een PDF ingedrukt en kies Delen/Open in, en kies vervolgens DartPDF.',
        'other':
            'Gebruik de systeeminstellingen voor bestandshandlers om PDF-documenten aan DartPDF te koppelen.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'OCR-model downloaden…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Model downloaden $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'OCR afronden…';

  @override
  String get fileTypePdf => 'PDF-documenten';

  @override
  String get fileTypeImages => 'Afbeeldingen';

  @override
  String get fileTypeStampBundle => 'DartPDF-stempels';

  @override
  String get appSigKeyFileType => 'RSA-privésleutels';

  @override
  String get appSigCertificateFileType => 'X.509-certificaten';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Selecteer minstens één X.509-certificaat.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Certificaat $index is geen geldige X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'De privésleutel komt met geen enkel geselecteerd RSA-certificaat overeen.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Versleutelde privésleutels worden niet ondersteund. Kies een onversleutelde RSA PKCS#1- of PKCS#8-sleutel.';

  @override
  String get appSigErrorKeyNotRsa =>
      'De privésleutel is geen onversleutelde RSA PKCS#1- of PKCS#8-sleutel.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Er zijn geen X.509-certificaten gevonden.';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get add => 'Add';

  @override
  String get appSigAddLogo => 'Add logo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'All $pageCount pages';
  }

  @override
  String get appSigAppearance => 'Appearance';

  @override
  String get appSigAppearanceDescription =>
      'The signature is drawn where you placed it. The signer name and details are always shown; you can add a hand-drawn mark and a logo backdrop.';

  @override
  String appSigApplyTo(String label) {
    return 'Apply to: $label';
  }

  @override
  String get appSigApplyToPages => 'Apply to pages…';

  @override
  String get appSigChooseCertificate => 'Choose certificate file…';

  @override
  String get appSigChooseKeyDescription =>
      'Choose your private key (RSA, PEM or DER) and its certificate file. The key is only used to sign and is never saved.';

  @override
  String get appSigChoosePngOrJpeg => 'Choose a PNG or JPEG image.';

  @override
  String get appSigChoosePrivateKey => 'Choose private key…';

  @override
  String get appSigContactInfo => 'Contact info';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Could not capture the signature.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Could not read the certificate: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Could not read the key: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Create a signature on this device';

  @override
  String appSigDate(String date) {
    return 'Date: $date';
  }

  @override
  String get appSigDigitallySign => 'Digitally sign';

  @override
  String get appSigDrawSignature => 'Draw signature…';

  @override
  String get appSigFieldHelper =>
      'Leave blank to create a new signature field.';

  @override
  String get appSigFieldLabel => 'Existing signature field (optional)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificates',
      one: '1 certificate',
    );
    return '$_temp0 · valid $validFrom to $validUntil';
  }

  @override
  String get appSigIntro =>
      'A digital signature proves you signed this document and that it has not been changed since. Pick how you want to sign.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'The selected key or certificate could not be read.';

  @override
  String get appSigKeylessDescription =>
      'Easiest. We confirm it\'s you by email and sign for you, with a trusted timestamp. Nothing to install or set up.';

  @override
  String get appSigKeylessIdentity => 'Keyless identity';

  @override
  String get appSigKeylessSignInExpired =>
      'Your keyless sign-in expired. Please sign in again.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Keyless sign-in failed: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Keyless · timestamped · validity unknown';

  @override
  String get appSigKeylessWebNote =>
      'Signing in with your email is the easiest way — it\'s available in the DartPDF desktop and mobile apps. For security reasons it can\'t run in a web browser.';

  @override
  String get appSigLocation => 'Location';

  @override
  String get appSigLogoAdded => 'Logo added ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Pages $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Preview - the signed box may differ slightly.';

  @override
  String get appSigReason => 'Reason';

  @override
  String appSigReasonLine(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Refreshing sign-in…';

  @override
  String get appSigRemoveLogo => 'Remove logo';

  @override
  String get appSigRemoveSignature => 'Remove signature';

  @override
  String get appSigSelfSignedDescription =>
      'No sign-in or files needed. Best for personal use — it\'s saved on this device for next time. Some PDF readers will show it as \"signed, validity unknown\", which is normal for a signature you make yourself.';

  @override
  String get appSigSelfSignedIdentity => 'Self-signed identity';

  @override
  String get appSigSelfSignedSubtitle => 'Self-signed · validity unknown';

  @override
  String get appSigShowSignatureOnPages => 'Show the signature on pages';

  @override
  String get appSigSign => 'Sign';

  @override
  String get appSigSignInWithEmail => 'Sign in with your email';

  @override
  String get appSigSignatureAdded => 'Signature added ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Digitally signed by $signerName';
  }

  @override
  String get appSigSigner => 'Signer';

  @override
  String get appSigSigningYouIn => 'Signing you in…';

  @override
  String get appSigThisPageOnly => 'This page only';

  @override
  String get appSigUseOwnCertificate => 'Use your own certificate';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'For a signing certificate from your organization';

  @override
  String get appSigX509Signer => 'X.509 signer';

  @override
  String get apply => 'Apply';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get cut => 'Cut';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Open these $count PDFs in a new tab, or insert their pages into \"$title\"?',
      one: 'Open this PDF in a new tab, or insert its pages into \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add dropped PDFs',
      one: 'Add dropped PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Annotation text copied';

  @override
  String get editorAppMenuTooltip => 'DartPDF menu';

  @override
  String get editorCancelOcr => 'Cancel OCR';

  @override
  String get editorClearRecentFiles => 'Clear recent files';

  @override
  String get editorCloseAll => 'Close all';

  @override
  String get editorCloseOthers => 'Close others';

  @override
  String get editorCloseTab => 'Close tab';

  @override
  String get editorCloseTabsToRight => 'Close tabs to the right';

  @override
  String get editorCompareFailedTitle => 'Compare failed';

  @override
  String editorCompareTitle(String title) {
    return 'Compare: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Copied to clipboard';

  @override
  String get editorCopySelectedTextTooltip => 'Copy selected text (⌘C)';

  @override
  String get editorCopyText => 'Copy text';

  @override
  String editorCouldNotExport(String title) {
    return 'Could not export $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Could not import stamps: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Could not insert the dropped PDFs',
      one: 'Could not insert the dropped PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Could not open $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'Could not open containing folder';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Could not open the second file\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Could not open the selected file\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Could not open $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Could not print $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Could not reopen $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Could not digitally sign: $error';
  }

  @override
  String get editorDiscard => 'Discard';

  @override
  String get editorDiscardChangesTitle => 'Discard changes?';

  @override
  String get editorDocumentSigned => 'Document digitally signed';

  @override
  String get editorDownload => 'Download';

  @override
  String get editorDropToOpen => 'Drop PDF to open';

  @override
  String get editorDropToOpenOrInsert => 'Drop PDF to open or insert';

  @override
  String get editorInsertPages => 'Insert pages';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Inserted $count; could not read $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Inserted $count PDFs into $title',
      one: 'Inserted pages into $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Invalid link: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'This document tried to run JavaScript (ignored)';

  @override
  String get editorLoadingFullDocument => 'Loading full document';

  @override
  String get editorMenuCompareWith => 'Compare with…';

  @override
  String get editorMenuDigitallySign => 'Digitally sign…';

  @override
  String get editorMenuDigitallySigning => 'Digitally signing…';

  @override
  String get editorMenuExportImage => 'Export page as image…';

  @override
  String get editorMenuNewDocument => 'New document…';

  @override
  String get editorMenuNewWindow => 'New window';

  @override
  String get editorMoveToNewWindow => 'Move to new window';

  @override
  String get editorUnableToOpenNewWindow => 'Couldn’t open a new window';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Open a PDF…';

  @override
  String get editorMenuPrint => 'Print…';

  @override
  String get editorMenuSaveAs => 'Save as…';

  @override
  String get editorMenuScanDocument => 'Scan to new document…';

  @override
  String get editorMenuInsertDocument => 'Insert document…';

  @override
  String get editorMenuInsertScan => 'Insert scan…';

  @override
  String get editorScanFailed => 'Couldn\'t scan the document.';

  @override
  String get editorInsertedScan => 'Inserted scanned pages.';

  @override
  String get editorMenuSettings => 'Settings';

  @override
  String get editorMenuSectionFile => 'File';

  @override
  String get editorMenuSectionDocument => 'This document';

  @override
  String get editorMenuSectionApp => 'App';

  @override
  String get editorMenuReadOnly => 'Read-only';

  @override
  String get editorMenuSearchActions => 'Search actions…';

  @override
  String get paletteHint => 'Search actions, tools and panels';

  @override
  String get paletteNoMatch => 'No command matches';

  @override
  String get paletteKeyHints => '↑↓ move · ⏎ run · esc close';

  @override
  String paletteCount(int count) {
    return '$count commands';
  }

  @override
  String paletteCountFiltered(int count, int total) {
    return '$count of $total';
  }

  @override
  String get paletteSourceMenu => 'Menu';

  @override
  String get paletteSourcePanel => 'Panel';

  @override
  String get paletteSourceView => 'View';

  @override
  String get paletteSourceFile => 'File';

  @override
  String paletteSourceTool(String group) {
    return '$group tool';
  }

  @override
  String get paletteNeedsDocument => 'Needs an open document';

  @override
  String editorNamedAction(String name) {
    return 'Named action: $name';
  }

  @override
  String get editorNoRecentFiles => 'No recent files';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'Open a document before running OCR';

  @override
  String get editorOpenFailedTitle => 'Open failed';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Open in new tabs',
      one: 'Open in new tab',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Open PDF in a new tab';

  @override
  String get editorOpenRecent => 'Open Recent';

  @override
  String get editorViewAllRecentFiles => 'View all recent files…';

  @override
  String get editorOpenTabs => 'Open tabs';

  @override
  String get editorOpeningDocumentSemantic => 'Opening document';

  @override
  String get editorOpeningPdf => 'Opening PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Opening $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get editorPreviewComparison => 'Comparison';

  @override
  String get editorPreviewCouldNotOpen => 'Could not open';

  @override
  String get editorPreviewOpening => 'Opening';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Recovered unsaved changes in $count documents from your last session.',
      one: 'Recovered unsaved changes from your last session.',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'Signature removed';

  @override
  String get editorSnapshotCopied => 'Snapshot copied to clipboard';

  @override
  String get editorSnapshotCopyFailed => 'Could not copy snapshot to clipboard';

  @override
  String get editorTabs => 'Tabs';

  @override
  String editorTabsOpenCount(int count) {
    return '$count open';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents have unsaved changes.',
      one: 'A document has unsaved changes.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Unsupported action: $type';
  }

  @override
  String get editorUntitled => 'Untitled';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version is available.';
  }

  @override
  String get editorUpdateLater => 'Later';

  @override
  String get updateInstallNow => 'Update now';

  @override
  String get updateDownloadingTitle => 'Downloading update';

  @override
  String get updatePreparing => 'Preparing…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateRestarting => 'Restarting to finish the update…';

  @override
  String get updateHandedOff => 'Update downloaded. Opening the installer…';

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get editorViewAllTabs => 'View all tabs';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Export';

  @override
  String get imgExportFormat => 'Format';

  @override
  String get imgExportResolution => 'Resolution';

  @override
  String get imgExportTitle => 'Export page as image';

  @override
  String get newDocCreate => 'Create';

  @override
  String get newDocLandscape => 'Landscape';

  @override
  String get newDocOrientation => 'Orientation';

  @override
  String get newDocPageSize => 'Page size';

  @override
  String get newDocPortrait => 'Portrait';

  @override
  String get newDocTitle => 'New document';

  @override
  String get none => 'None';

  @override
  String get ocrAlreadyRunning =>
      'OCR is already running - wait for it to finish or cancel it';

  @override
  String get ocrBrowserInitFailed => 'Browser OCR failed to initialize';

  @override
  String get ocrCancelled => 'OCR canceled';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR canceled after $count text spans',
      one: 'OCR canceled after 1 text span',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Download';

  @override
  String ocrDownloadFailed(String error) {
    return 'Could not download the OCR model: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Adding a selectable text layer needs the on-device OCR model$size. It downloads once and then runs offline.\n\nModel: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Download OCR model?';

  @override
  String ocrFailed(String error) {
    return 'OCR failed: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'On-device OCR is not available on this platform';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR added $count text spans - the page text is now selectable',
      one: 'OCR added 1 text span - the page text is now selectable',
      zero: 'OCR found no text on these pages',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Web OCR downloads a Florence-2 vision-language model and runs it locally with WebGPU/WASM through Transformers.js. The PDF pages stay in this browser; only model files are fetched on first use.';

  @override
  String get ocrWebPromptTitle => 'Run AI OCR in this browser?';

  @override
  String get ocrWebStart => 'Start OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Paste';

  @override
  String get printDlgPreparing => 'Preparing…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Rendering page $rendered of $total…';
  }

  @override
  String get printDlgTitle => 'Printing';

  @override
  String get printPreviewAll => 'All';

  @override
  String get printPreviewCurrent => 'Current';

  @override
  String get printPreviewFrom => 'From';

  @override
  String get printPreviewNextPage => 'Next page';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get printPreviewPreviousPage => 'Previous page';

  @override
  String get printPreviewPrint => 'Print';

  @override
  String get printPreviewRange => 'Range';

  @override
  String printPreviewRangeError(int total) {
    return 'Enter a page range between 1 and $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Pages to print: $count';
  }

  @override
  String get printPreviewTitle => 'Print preview';

  @override
  String get printPreviewTo => 'To';

  @override
  String get printPreviewUnavailable => 'Preview unavailable';

  @override
  String get redo => 'Redo';

  @override
  String get remove => 'Remove';

  @override
  String get rename => 'Rename';

  @override
  String get reset => 'Reset';

  @override
  String get save => 'Save';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsCheckNow => 'Check now';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsCheckingForUpdates => 'Checking for updates…';

  @override
  String get settingsCouldNotOpenDownload => 'Could not open the download';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Could not open system settings';

  @override
  String get settingsDeveloperTools => 'Developer tools';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Metrics, logs, render modes (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Download $version';
  }

  @override
  String get settingsOpenSettings => 'Open Settings';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count remembered',
      one: '1 remembered',
      zero: 'No recent files',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Recent files';

  @override
  String get settingsSetUpAsDefault => 'Set up as default application';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsTitle => 'Settings';

  @override
  String settingsUpToDate(String version) {
    return 'You’re on the latest version ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Version $version is available (you have $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Couldn’t check for updates. Try again later.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'You have $name $version.';
  }

  @override
  String get settingsNightlyUpdates => 'Nightly updates';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'Receive automatic update notifications for unsigned Windows test builds from main.';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsViewSource => 'View source on GitHub';

  @override
  String get undo => 'Undo';

  @override
  String get welcomeOpenPdf => 'Open a PDF';

  @override
  String get welcomePickAgainToReopen => 'Pick again to reopen';

  @override
  String get welcomeRecent => 'Recent';

  @override
  String get welcomeSearchRecentFiles => 'Search recent files';

  @override
  String get welcomeNoMatchingRecentFiles =>
      'No recent files match your search';

  @override
  String get welcomeRemoveFromRecent => 'Remove from recent';

  @override
  String get welcomeTapToReopen => 'Tap to reopen';

  @override
  String get welcomeViewAsGrid => 'Grid view';

  @override
  String get welcomeViewAsList => 'List view';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Install the web app, then choose it for PDF files.',
        'windows': 'Open Windows default apps settings for PDFs.',
        'macos': 'Follow Finder’s “Always Open With” steps.',
        'linux': 'Use your desktop’s default applications settings.',
        'android': 'Choose DartPDF when opening a PDF, then tap Always.',
        'ios': 'Use Share or Open In from Files to send PDFs here.',
        'other': 'Configure your system’s PDF file handler.',
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
            'Install DartPDF from your browser first. Then use the browser or operating system file-handler settings to associate PDF files with the installed app.',
        'windows':
            'Windows Settings will open to Default apps. Search for “.pdf” or “PDF”, choose the current PDF app, then select DartPDF.',
        'macos':
            'In Finder, select any PDF, choose File > Get Info, expand “Open with”, pick DartPDF, then click “Change All…”.',
        'linux':
            'Open your desktop settings for Default Applications, or right-click a PDF in Files, choose Properties, and set DartPDF as the default for PDF documents.',
        'android':
            'Open a PDF from Files or Downloads, choose DartPDF in the app picker, then select Always. If another app already opens PDFs, clear that app’s defaults in Android Settings first.',
        'ios':
            'iOS does not provide a global default PDF editor. Use Files > Share, or long-press a PDF and choose Share/Open In, then pick DartPDF.',
        'other':
            'Use the system settings for file handlers to associate PDF documents with DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Downloading OCR model…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Downloading model $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Finishing OCR…';

  @override
  String get fileTypePdf => 'PDF documents';

  @override
  String get fileTypeImages => 'Images';

  @override
  String get fileTypeStampBundle => 'DartPDF stamps';

  @override
  String get appSigKeyFileType => 'RSA private keys';

  @override
  String get appSigCertificateFileType => 'X.509 certificates';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Select at least one X.509 certificate.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Certificate $index is not valid X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'The private key does not match any selected RSA certificate.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Encrypted private keys are not supported. Choose an unencrypted RSA PKCS#1 or PKCS#8 key.';

  @override
  String get appSigErrorKeyNotRsa =>
      'The private key is not an unencrypted RSA PKCS#1 or PKCS#8 key.';

  @override
  String get appSigErrorNoCertificateFound =>
      'No X.509 certificates were found.';

  @override
  String get imageSourceTakePhoto => 'Take photo';

  @override
  String get imageSourceChooseFile => 'Choose file';

  @override
  String get imageSourceCameraFailed => 'Couldn\'t take a photo';

  @override
  String get settingsCachedDocuments => 'Cached documents';

  @override
  String settingsCacheUsage(String used, String limit) {
    return '$used MiB of $limit MiB used';
  }

  @override
  String settingsCacheExplanation(String limit) {
    return 'Files over $limit MiB are not cached. Clearing keeps your Recent list, open documents and unsaved changes; cached files must be picked again to reopen.';
  }

  @override
  String get settingsClearCachedDocuments => 'Clear cached documents';

  @override
  String get settingsCacheUnavailable => 'Cache size unavailable';

  @override
  String get settingsCacheClearFailed =>
      'Could not clear cached documents. Try again.';

  @override
  String get editorMenuReduceFileSize => 'Reduce file size…';

  @override
  String get reduceSizeTitle => 'Reduce file size';

  @override
  String get reduceSizeDescription =>
      'Optimize the current document, review the savings, then save a smaller copy.';

  @override
  String get reduceSizePreset => 'Preset';

  @override
  String get reduceSizeLossless => 'Lossless — preserve image quality';

  @override
  String get reduceSizeScreen => 'Screen — 72 DPI, JPEG quality 60';

  @override
  String get reduceSizeEbook => 'eBook — 150 DPI, JPEG quality 75';

  @override
  String get reduceSizePrinter => 'Print — 300 DPI, JPEG quality 90';

  @override
  String get reduceSizeLosslessHint =>
      'Image resolution and quality stay the same.';

  @override
  String get reduceSizeLossyHint =>
      'Images above the target resolution may be reduced and JPEG-encoded. Fine image detail can be lost; text and vector graphics stay sharp.';

  @override
  String get reduceSizeAdvanced => 'Advanced settings';

  @override
  String get reduceSizeRecompress => 'Recompress streams';

  @override
  String get reduceSizeUnusedResources => 'Remove unused resources';

  @override
  String get reduceSizeDeduplicate => 'Merge duplicate objects';

  @override
  String get reduceSizeSubsetFonts => 'Subset embedded fonts';

  @override
  String get reduceSizeDpi => 'Image target resolution';

  @override
  String get reduceSizeKeepImages => 'Keep original images (lossless)';

  @override
  String reduceSizeJpegQuality(int quality) {
    return 'JPEG quality: $quality';
  }

  @override
  String get reduceSizeSignaturesNotice =>
      'Rewriting this signed PDF invalidates its digital signatures in the saved copy.';

  @override
  String get reduceSizeInvalidateSignatures =>
      'Allow invalidating signatures in this copy';

  @override
  String get reduceSizeEncrypted => 'Encrypted PDFs cannot be optimized.';

  @override
  String get reduceSizeIncomplete =>
      'Wait for the document to finish loading before reducing its size.';

  @override
  String get reduceSizeRun => 'Optimize';

  @override
  String get reduceSizeRunning => 'Optimizing document…';

  @override
  String reduceSizeFailed(String error) {
    return 'Could not optimize this PDF: $error';
  }

  @override
  String reduceSizeSaveFailed(String error) {
    return 'Could not save the copy: $error';
  }

  @override
  String get reduceSizeSaveCopy => 'Save copy…';

  @override
  String get reduceSizeChangeSettings => 'Change settings';

  @override
  String get reduceSizeBefore => 'Original size';

  @override
  String get reduceSizeAfter => 'Optimized size';

  @override
  String get reduceSizeSavings => 'Space saved';

  @override
  String get reduceSizeNoSavings =>
      'This document is already compact with these settings. The original bytes were kept.';

  @override
  String get reduceSizeReportHint => 'Bytes saved by each optimization step:';

  @override
  String get reduceSizeStructure => 'Document structure';

  @override
  String get reduceSizeResources => 'Unused resources';

  @override
  String get reduceSizeFonts => 'Embedded fonts';

  @override
  String get reduceSizeImages => 'Images';

  @override
  String get reduceSizeDuplicates => 'Duplicate objects';

  @override
  String get reduceSizeCustom => 'Custom settings';

  @override
  String get printOptionsPrinter => 'Printer';

  @override
  String get printOptionsNativePrinter =>
      'Choose the printer, paper tray, color, duplex and device properties in the system print dialog next. Keep its scale at 100% and copies at 1 to use the layout shown here.';

  @override
  String get printOptionsPages => 'Pages';

  @override
  String get printOptionsSelected => 'Selected';

  @override
  String get printOptionsPageRange => 'Pages (for example, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Add files…';

  @override
  String get printOptionsAddFailed => 'Could not add the selected files.';

  @override
  String get printOptionsGetWindow => 'Get window';

  @override
  String get printOptionsClearWindow => 'Clear window';

  @override
  String get printOptionsWindowHint =>
      'Drag a rectangle on this source page to choose the area to print.';

  @override
  String get printOptionsPaper => 'Paper';

  @override
  String get printOptionsPaperSize => 'Paper size';

  @override
  String get printOptionsPageSize => 'Use document page size';

  @override
  String get printOptionsOrientation => 'Orientation';

  @override
  String get printOptionsAuto => 'Auto';

  @override
  String get printOptionsPortrait => 'Portrait';

  @override
  String get printOptionsLandscape => 'Landscape';

  @override
  String get printOptionsCopies => 'Copies';

  @override
  String get printOptionsCollate => 'Collate';

  @override
  String get printOptionsReverse => 'Reverse page order';

  @override
  String get printOptionsLayout => 'Page layout';

  @override
  String get printOptionsScaling => 'Page scaling';

  @override
  String get printOptionsScaleNone => 'None (actual size)';

  @override
  String get printOptionsFitPaper => 'Fit to paper';

  @override
  String get printOptionsReducePaper => 'Reduce to paper';

  @override
  String get printOptionsFitMargins => 'Fit to margins';

  @override
  String get printOptionsReduceMargins => 'Reduce to margins';

  @override
  String get printOptionsCustomScale => 'Custom scale';

  @override
  String get printOptionsMultiple => 'Multiple pages per sheet';

  @override
  String get printOptionsScalePercent => 'Scale (%)';

  @override
  String get printOptionsMargin => 'Margins (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Pages per sheet';

  @override
  String get printOptionsPageOrder => 'Page order';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal reversed';

  @override
  String get printOptionsVertical => 'Vertical';

  @override
  String get printOptionsVerticalReverse => 'Vertical reversed';

  @override
  String get printOptionsBorder => 'Print page borders';

  @override
  String get printOptionsRotation => 'Rotation (clockwise)';

  @override
  String get printOptionsNoRotation => 'None';

  @override
  String get printOptionsCenter => 'Center on paper';

  @override
  String get printOptionsOffsetX => 'Offset right (pt)';

  @override
  String get printOptionsOffsetY => 'Offset down (pt)';

  @override
  String get printOptionsContents => 'Print contents';

  @override
  String get printOptionsDocumentAndMarkups => 'Document and markups';

  @override
  String get printOptionsDocumentOnly => 'Document only';

  @override
  String get printOptionsMarkupsOnly => 'Markups only';

  @override
  String get printOptionsDimPage => 'Dim page content';

  @override
  String get printOptionsDimMarkups => 'Dim markups';

  @override
  String get printOptionsHyperlinks => 'Print visible hyperlinks';

  @override
  String get printOptionsDefaults => 'Defaults';

  @override
  String get printOptionsInvalidNumber =>
      'Enter valid numbers before printing.';

  @override
  String get printOptionsInvalidValue => 'Invalid value';

  @override
  String get printOptionsMarginGuide =>
      'Red lines show the margins; they do not print.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Window: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Source: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Sheet: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Sheet $sheet of $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'This layout could not be prepared. Check the paper size, margins and scale.';
}

/// The translations for English, as used in Australia (`en_AU`).
class AppLocalizationsEnAu extends AppLocalizationsEn {
  AppLocalizationsEnAu() : super('en_AU');

  @override
  String get add => 'Add';

  @override
  String get appSigAddLogo => 'Add logo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'All $pageCount pages';
  }

  @override
  String get appSigAppearance => 'Appearance';

  @override
  String get appSigAppearanceDescription =>
      'The signature is drawn where you placed it. The signer name and details are always shown; you can add a hand-drawn mark and a logo backdrop.';

  @override
  String appSigApplyTo(String label) {
    return 'Apply to: $label';
  }

  @override
  String get appSigApplyToPages => 'Apply to pages…';

  @override
  String get appSigChooseCertificate => 'Choose certificate file…';

  @override
  String get appSigChooseKeyDescription =>
      'Choose your private key (RSA, PEM or DER) and its certificate file. The key is only used to sign and is never saved.';

  @override
  String get appSigChoosePngOrJpeg => 'Choose a PNG or JPEG image.';

  @override
  String get appSigChoosePrivateKey => 'Choose private key…';

  @override
  String get appSigContactInfo => 'Contact info';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Could not capture the signature.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Could not read the certificate: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Could not read the key: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Create a signature on this device';

  @override
  String appSigDate(String date) {
    return 'Date: $date';
  }

  @override
  String get appSigDigitallySign => 'Digitally sign';

  @override
  String get appSigDrawSignature => 'Draw signature…';

  @override
  String get appSigFieldHelper =>
      'Leave blank to create a new signature field.';

  @override
  String get appSigFieldLabel => 'Existing signature field (optional)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificates',
      one: '1 certificate',
    );
    return '$_temp0 · valid $validFrom to $validUntil';
  }

  @override
  String get appSigIntro =>
      'A digital signature proves you signed this document and that it has not been changed since. Pick how you want to sign.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'The selected key or certificate could not be read.';

  @override
  String get appSigKeylessDescription =>
      'Easiest. We confirm it\'s you by email and sign for you, with a trusted timestamp. Nothing to install or set up.';

  @override
  String get appSigKeylessIdentity => 'Keyless identity';

  @override
  String get appSigKeylessSignInExpired =>
      'Your keyless sign-in expired. Please sign in again.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Keyless sign-in failed: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Keyless · timestamped · validity unknown';

  @override
  String get appSigKeylessWebNote =>
      'Signing in with your email is the easiest way — it\'s available in the DartPDF desktop and mobile apps. For security reasons it can\'t run in a web browser.';

  @override
  String get appSigLocation => 'Location';

  @override
  String get appSigLogoAdded => 'Logo added ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Pages $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Preview - the signed box may differ slightly.';

  @override
  String get appSigReason => 'Reason';

  @override
  String appSigReasonLine(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Refreshing sign-in…';

  @override
  String get appSigRemoveLogo => 'Remove logo';

  @override
  String get appSigRemoveSignature => 'Remove signature';

  @override
  String get appSigSelfSignedDescription =>
      'No sign-in or files needed. Best for personal use — it\'s saved on this device for next time. Some PDF readers will show it as \"signed, validity unknown\", which is normal for a signature you make yourself.';

  @override
  String get appSigSelfSignedIdentity => 'Self-signed identity';

  @override
  String get appSigSelfSignedSubtitle => 'Self-signed · validity unknown';

  @override
  String get appSigShowSignatureOnPages => 'Show the signature on pages';

  @override
  String get appSigSign => 'Sign';

  @override
  String get appSigSignInWithEmail => 'Sign in with your email';

  @override
  String get appSigSignatureAdded => 'Signature added ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Digitally signed by $signerName';
  }

  @override
  String get appSigSigner => 'Signer';

  @override
  String get appSigSigningYouIn => 'Signing you in…';

  @override
  String get appSigThisPageOnly => 'This page only';

  @override
  String get appSigUseOwnCertificate => 'Use your own certificate';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'For a signing certificate from your organisation';

  @override
  String get appSigX509Signer => 'X.509 signer';

  @override
  String get apply => 'Apply';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get cut => 'Cut';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Open these $count PDFs in a new tab, or insert their pages into \"$title\"?',
      one: 'Open this PDF in a new tab, or insert its pages into \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add dropped PDFs',
      one: 'Add dropped PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Annotation text copied';

  @override
  String get editorAppMenuTooltip => 'DartPDF menu';

  @override
  String get editorCancelOcr => 'Cancel OCR';

  @override
  String get editorClearRecentFiles => 'Clear recent files';

  @override
  String get editorCloseAll => 'Close all';

  @override
  String get editorCloseOthers => 'Close others';

  @override
  String get editorCloseTab => 'Close tab';

  @override
  String get editorCloseTabsToRight => 'Close tabs to the right';

  @override
  String get editorCompareFailedTitle => 'Compare failed';

  @override
  String editorCompareTitle(String title) {
    return 'Compare: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Copied to clipboard';

  @override
  String get editorCopySelectedTextTooltip => 'Copy selected text (⌘C)';

  @override
  String get editorCopyText => 'Copy text';

  @override
  String editorCouldNotExport(String title) {
    return 'Could not export $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Could not import stamps: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Could not insert the dropped PDFs',
      one: 'Could not insert the dropped PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Could not open $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'Could not open containing folder';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Could not open the second file\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Could not open the selected file\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Could not open $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Could not print $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Could not reopen $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Could not digitally sign: $error';
  }

  @override
  String get editorDiscard => 'Discard';

  @override
  String get editorDiscardChangesTitle => 'Discard changes?';

  @override
  String get editorDocumentSigned => 'Document digitally signed';

  @override
  String get editorDownload => 'Download';

  @override
  String get editorDropToOpen => 'Drop PDF to open';

  @override
  String get editorDropToOpenOrInsert => 'Drop PDF to open or insert';

  @override
  String get editorInsertPages => 'Insert pages';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Inserted $count; could not read $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Inserted $count PDFs into $title',
      one: 'Inserted pages into $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Invalid link: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'This document tried to run JavaScript (ignored)';

  @override
  String get editorLoadingFullDocument => 'Loading full document';

  @override
  String get editorMenuCompareWith => 'Compare with…';

  @override
  String get editorMenuDigitallySign => 'Digitally sign…';

  @override
  String get editorMenuDigitallySigning => 'Digitally signing…';

  @override
  String get editorMenuExportImage => 'Export page as image…';

  @override
  String get editorMenuNewDocument => 'New document…';

  @override
  String get editorMenuNewWindow => 'New window';

  @override
  String get editorMoveToNewWindow => 'Move to new window';

  @override
  String get editorUnableToOpenNewWindow => 'Couldn’t open a new window';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Open a PDF…';

  @override
  String get editorMenuPrint => 'Print…';

  @override
  String get editorMenuSaveAs => 'Save as…';

  @override
  String get editorMenuScanDocument => 'Scan to new document…';

  @override
  String get editorMenuInsertDocument => 'Insert document…';

  @override
  String get editorMenuInsertScan => 'Insert scan…';

  @override
  String get editorScanFailed => 'Couldn\'t scan the document.';

  @override
  String get editorInsertedScan => 'Inserted scanned pages.';

  @override
  String get editorMenuSettings => 'Settings';

  @override
  String get editorMenuSectionFile => 'File';

  @override
  String get editorMenuSectionDocument => 'This document';

  @override
  String get editorMenuSectionApp => 'App';

  @override
  String get editorMenuReadOnly => 'Read-only';

  @override
  String get editorMenuSearchActions => 'Search actions…';

  @override
  String get paletteHint => 'Search actions, tools and panels';

  @override
  String get paletteNoMatch => 'No command matches';

  @override
  String get paletteKeyHints => '↑↓ move · ⏎ run · esc close';

  @override
  String paletteCount(int count) {
    return '$count commands';
  }

  @override
  String paletteCountFiltered(int count, int total) {
    return '$count of $total';
  }

  @override
  String get paletteSourceMenu => 'Menu';

  @override
  String get paletteSourcePanel => 'Panel';

  @override
  String get paletteSourceView => 'View';

  @override
  String get paletteSourceFile => 'File';

  @override
  String paletteSourceTool(String group) {
    return '$group tool';
  }

  @override
  String get paletteNeedsDocument => 'Needs an open document';

  @override
  String editorNamedAction(String name) {
    return 'Named action: $name';
  }

  @override
  String get editorNoRecentFiles => 'No recent files';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'Open a document before running OCR';

  @override
  String get editorOpenFailedTitle => 'Open failed';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Open in new tabs',
      one: 'Open in new tab',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Open PDF in a new tab';

  @override
  String get editorOpenRecent => 'Open Recent';

  @override
  String get editorViewAllRecentFiles => 'View all recent files…';

  @override
  String get editorOpenTabs => 'Open tabs';

  @override
  String get editorOpeningDocumentSemantic => 'Opening document';

  @override
  String get editorOpeningPdf => 'Opening PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Opening $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get editorPreviewComparison => 'Comparison';

  @override
  String get editorPreviewCouldNotOpen => 'Could not open';

  @override
  String get editorPreviewOpening => 'Opening';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Recovered unsaved changes in $count documents from your last session.',
      one: 'Recovered unsaved changes from your last session.',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'Signature removed';

  @override
  String get editorSnapshotCopied => 'Snapshot copied to clipboard';

  @override
  String get editorSnapshotCopyFailed => 'Could not copy snapshot to clipboard';

  @override
  String get editorTabs => 'Tabs';

  @override
  String editorTabsOpenCount(int count) {
    return '$count open';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents have unsaved changes.',
      one: 'A document has unsaved changes.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Unsupported action: $type';
  }

  @override
  String get editorUntitled => 'Untitled';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version is available.';
  }

  @override
  String get editorUpdateLater => 'Later';

  @override
  String get updateInstallNow => 'Update now';

  @override
  String get updateDownloadingTitle => 'Downloading update';

  @override
  String get updatePreparing => 'Preparing…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateRestarting => 'Restarting to finish the update…';

  @override
  String get updateHandedOff => 'Update downloaded. Opening the installer…';

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get editorViewAllTabs => 'View all tabs';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Export';

  @override
  String get imgExportFormat => 'Format';

  @override
  String get imgExportResolution => 'Resolution';

  @override
  String get imgExportTitle => 'Export page as image';

  @override
  String get newDocCreate => 'Create';

  @override
  String get newDocLandscape => 'Landscape';

  @override
  String get newDocOrientation => 'Orientation';

  @override
  String get newDocPageSize => 'Page size';

  @override
  String get newDocPortrait => 'Portrait';

  @override
  String get newDocTitle => 'New document';

  @override
  String get none => 'None';

  @override
  String get ocrAlreadyRunning =>
      'OCR is already running - wait for it to finish or cancel it';

  @override
  String get ocrBrowserInitFailed => 'Browser OCR failed to initialise';

  @override
  String get ocrCancelled => 'OCR cancelled';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR cancelled after $count text spans',
      one: 'OCR cancelled after 1 text span',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Download';

  @override
  String ocrDownloadFailed(String error) {
    return 'Could not download the OCR model: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Adding a selectable text layer needs the on-device OCR model$size. It downloads once and then runs offline.\n\nModel: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Download OCR model?';

  @override
  String ocrFailed(String error) {
    return 'OCR failed: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'On-device OCR is not available on this platform';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR added $count text spans - the page text is now selectable',
      one: 'OCR added 1 text span - the page text is now selectable',
      zero: 'OCR found no text on these pages',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Web OCR downloads a Florence-2 vision-language model and runs it locally with WebGPU/WASM through Transformers.js. The PDF pages stay in this browser; only model files are fetched on first use.';

  @override
  String get ocrWebPromptTitle => 'Run AI OCR in this browser?';

  @override
  String get ocrWebStart => 'Start OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Paste';

  @override
  String get printDlgPreparing => 'Preparing…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Rendering page $rendered of $total…';
  }

  @override
  String get printDlgTitle => 'Printing';

  @override
  String get printPreviewAll => 'All';

  @override
  String get printPreviewCurrent => 'Current';

  @override
  String get printPreviewFrom => 'From';

  @override
  String get printPreviewNextPage => 'Next page';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get printPreviewPreviousPage => 'Previous page';

  @override
  String get printPreviewPrint => 'Print';

  @override
  String get printPreviewRange => 'Range';

  @override
  String printPreviewRangeError(int total) {
    return 'Enter a page range between 1 and $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Pages to print: $count';
  }

  @override
  String get printPreviewTitle => 'Print preview';

  @override
  String get printPreviewTo => 'To';

  @override
  String get printPreviewUnavailable => 'Preview unavailable';

  @override
  String get redo => 'Redo';

  @override
  String get remove => 'Remove';

  @override
  String get rename => 'Rename';

  @override
  String get reset => 'Reset';

  @override
  String get save => 'Save';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsCheckNow => 'Check now';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsCheckingForUpdates => 'Checking for updates…';

  @override
  String get settingsCouldNotOpenDownload => 'Could not open the download';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Could not open system settings';

  @override
  String get settingsDeveloperTools => 'Developer tools';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Metrics, logs, render modes (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Download $version';
  }

  @override
  String get settingsOpenSettings => 'Open Settings';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count remembered',
      one: '1 remembered',
      zero: 'No recent files',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Recent files';

  @override
  String get settingsSetUpAsDefault => 'Set up as default application';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsTitle => 'Settings';

  @override
  String settingsUpToDate(String version) {
    return 'You’re on the latest version ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Version $version is available (you have $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Couldn’t check for updates. Try again later.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'You have $name $version.';
  }

  @override
  String get settingsNightlyUpdates => 'Nightly updates';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'Receive automatic update notifications for unsigned Windows test builds from main.';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsViewSource => 'View source on GitHub';

  @override
  String get undo => 'Undo';

  @override
  String get welcomeOpenPdf => 'Open a PDF';

  @override
  String get welcomePickAgainToReopen => 'Pick again to reopen';

  @override
  String get welcomeRecent => 'Recent';

  @override
  String get welcomeSearchRecentFiles => 'Search recent files';

  @override
  String get welcomeNoMatchingRecentFiles =>
      'No recent files match your search';

  @override
  String get welcomeRemoveFromRecent => 'Remove from recent';

  @override
  String get welcomeTapToReopen => 'Tap to reopen';

  @override
  String get welcomeViewAsGrid => 'Grid view';

  @override
  String get welcomeViewAsList => 'List view';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Install the web app, then choose it for PDF files.',
        'windows': 'Open Windows default apps settings for PDFs.',
        'macos': 'Follow Finder’s “Always Open With” steps.',
        'linux': 'Use your desktop’s default applications settings.',
        'android': 'Choose DartPDF when opening a PDF, then tap Always.',
        'ios': 'Use Share or Open In from Files to send PDFs here.',
        'other': 'Configure your system’s PDF file handler.',
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
            'Install DartPDF from your browser first. Then use the browser or operating system file-handler settings to associate PDF files with the installed app.',
        'windows':
            'Windows Settings will open to Default apps. Search for “.pdf” or “PDF”, choose the current PDF app, then select DartPDF.',
        'macos':
            'In Finder, select any PDF, choose File > Get Info, expand “Open with”, pick DartPDF, then click “Change All…”.',
        'linux':
            'Open your desktop settings for Default Applications, or right-click a PDF in Files, choose Properties, and set DartPDF as the default for PDF documents.',
        'android':
            'Open a PDF from Files or Downloads, choose DartPDF in the app picker, then select Always. If another app already opens PDFs, clear that app’s defaults in Android Settings first.',
        'ios':
            'iOS does not provide a global default PDF editor. Use Files > Share, or long-press a PDF and choose Share/Open In, then pick DartPDF.',
        'other':
            'Use the system settings for file handlers to associate PDF documents with DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Downloading OCR model…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Downloading model $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Finishing OCR…';

  @override
  String get fileTypePdf => 'PDF documents';

  @override
  String get fileTypeImages => 'Images';

  @override
  String get fileTypeStampBundle => 'DartPDF stamps';

  @override
  String get appSigKeyFileType => 'RSA private keys';

  @override
  String get appSigCertificateFileType => 'X.509 certificates';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Select at least one X.509 certificate.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Certificate $index is not valid X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'The private key does not match any selected RSA certificate.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Encrypted private keys are not supported. Choose an unencrypted RSA PKCS#1 or PKCS#8 key.';

  @override
  String get appSigErrorKeyNotRsa =>
      'The private key is not an unencrypted RSA PKCS#1 or PKCS#8 key.';

  @override
  String get appSigErrorNoCertificateFound =>
      'No X.509 certificates were found.';

  @override
  String get imageSourceTakePhoto => 'Take photo';

  @override
  String get imageSourceChooseFile => 'Choose file';

  @override
  String get imageSourceCameraFailed => 'Couldn\'t take a photo';

  @override
  String get settingsCachedDocuments => 'Cached documents';

  @override
  String settingsCacheUsage(String used, String limit) {
    return '$used MiB of $limit MiB used';
  }

  @override
  String settingsCacheExplanation(String limit) {
    return 'Files over $limit MiB are not cached. Clearing keeps your Recent list, open documents and unsaved changes; cached files must be picked again to reopen.';
  }

  @override
  String get settingsClearCachedDocuments => 'Clear cached documents';

  @override
  String get settingsCacheUnavailable => 'Cache size unavailable';

  @override
  String get settingsCacheClearFailed =>
      'Could not clear cached documents. Try again.';

  @override
  String get editorMenuReduceFileSize => 'Reduce file size…';

  @override
  String get reduceSizeTitle => 'Reduce file size';

  @override
  String get reduceSizeDescription =>
      'Optimise the current document, review the savings, then save a smaller copy.';

  @override
  String get reduceSizePreset => 'Preset';

  @override
  String get reduceSizeLossless => 'Lossless — preserve image quality';

  @override
  String get reduceSizeScreen => 'Screen — 72 DPI, JPEG quality 60';

  @override
  String get reduceSizeEbook => 'eBook — 150 DPI, JPEG quality 75';

  @override
  String get reduceSizePrinter => 'Print — 300 DPI, JPEG quality 90';

  @override
  String get reduceSizeLosslessHint =>
      'Image resolution and quality stay the same.';

  @override
  String get reduceSizeLossyHint =>
      'Images above the target resolution may be reduced and JPEG-encoded. Fine image detail can be lost; text and vector graphics stay sharp.';

  @override
  String get reduceSizeAdvanced => 'Advanced settings';

  @override
  String get reduceSizeRecompress => 'Recompress streams';

  @override
  String get reduceSizeUnusedResources => 'Remove unused resources';

  @override
  String get reduceSizeDeduplicate => 'Merge duplicate objects';

  @override
  String get reduceSizeSubsetFonts => 'Subset embedded fonts';

  @override
  String get reduceSizeDpi => 'Image target resolution';

  @override
  String get reduceSizeKeepImages => 'Keep original images (lossless)';

  @override
  String reduceSizeJpegQuality(int quality) {
    return 'JPEG quality: $quality';
  }

  @override
  String get reduceSizeSignaturesNotice =>
      'Rewriting this signed PDF invalidates its digital signatures in the saved copy.';

  @override
  String get reduceSizeInvalidateSignatures =>
      'Allow invalidating signatures in this copy';

  @override
  String get reduceSizeEncrypted => 'Encrypted PDFs cannot be optimised.';

  @override
  String get reduceSizeIncomplete =>
      'Wait for the document to finish loading before reducing its size.';

  @override
  String get reduceSizeRun => 'Optimise';

  @override
  String get reduceSizeRunning => 'Optimising document…';

  @override
  String reduceSizeFailed(String error) {
    return 'Could not optimise this PDF: $error';
  }

  @override
  String reduceSizeSaveFailed(String error) {
    return 'Could not save the copy: $error';
  }

  @override
  String get reduceSizeSaveCopy => 'Save copy…';

  @override
  String get reduceSizeChangeSettings => 'Change settings';

  @override
  String get reduceSizeBefore => 'Original size';

  @override
  String get reduceSizeAfter => 'Optimised size';

  @override
  String get reduceSizeSavings => 'Space saved';

  @override
  String get reduceSizeNoSavings =>
      'This document is already compact with these settings. The original bytes were kept.';

  @override
  String get reduceSizeReportHint => 'Bytes saved by each optimisation step:';

  @override
  String get reduceSizeStructure => 'Document structure';

  @override
  String get reduceSizeResources => 'Unused resources';

  @override
  String get reduceSizeFonts => 'Embedded fonts';

  @override
  String get reduceSizeImages => 'Images';

  @override
  String get reduceSizeDuplicates => 'Duplicate objects';

  @override
  String get reduceSizeCustom => 'Custom settings';

  @override
  String get printOptionsPrinter => 'Printer';

  @override
  String get printOptionsNativePrinter =>
      'Choose the printer, paper tray, colour, duplex and device properties in the system print dialog next. Keep its scale at 100% and copies at 1 to use the layout shown here.';

  @override
  String get printOptionsPages => 'Pages';

  @override
  String get printOptionsSelected => 'Selected';

  @override
  String get printOptionsPageRange => 'Pages (for example, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Add files…';

  @override
  String get printOptionsAddFailed => 'Could not add the selected files.';

  @override
  String get printOptionsGetWindow => 'Get window';

  @override
  String get printOptionsClearWindow => 'Clear window';

  @override
  String get printOptionsWindowHint =>
      'Drag a rectangle on this source page to choose the area to print.';

  @override
  String get printOptionsPaper => 'Paper';

  @override
  String get printOptionsPaperSize => 'Paper size';

  @override
  String get printOptionsPageSize => 'Use document page size';

  @override
  String get printOptionsOrientation => 'Orientation';

  @override
  String get printOptionsAuto => 'Auto';

  @override
  String get printOptionsPortrait => 'Portrait';

  @override
  String get printOptionsLandscape => 'Landscape';

  @override
  String get printOptionsCopies => 'Copies';

  @override
  String get printOptionsCollate => 'Collate';

  @override
  String get printOptionsReverse => 'Reverse page order';

  @override
  String get printOptionsLayout => 'Page layout';

  @override
  String get printOptionsScaling => 'Page scaling';

  @override
  String get printOptionsScaleNone => 'None (actual size)';

  @override
  String get printOptionsFitPaper => 'Fit to paper';

  @override
  String get printOptionsReducePaper => 'Reduce to paper';

  @override
  String get printOptionsFitMargins => 'Fit to margins';

  @override
  String get printOptionsReduceMargins => 'Reduce to margins';

  @override
  String get printOptionsCustomScale => 'Custom scale';

  @override
  String get printOptionsMultiple => 'Multiple pages per sheet';

  @override
  String get printOptionsScalePercent => 'Scale (%)';

  @override
  String get printOptionsMargin => 'Margins (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Pages per sheet';

  @override
  String get printOptionsPageOrder => 'Page order';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal reversed';

  @override
  String get printOptionsVertical => 'Vertical';

  @override
  String get printOptionsVerticalReverse => 'Vertical reversed';

  @override
  String get printOptionsBorder => 'Print page borders';

  @override
  String get printOptionsRotation => 'Rotation (clockwise)';

  @override
  String get printOptionsNoRotation => 'None';

  @override
  String get printOptionsCenter => 'Centre on paper';

  @override
  String get printOptionsOffsetX => 'Offset right (pt)';

  @override
  String get printOptionsOffsetY => 'Offset down (pt)';

  @override
  String get printOptionsContents => 'Print contents';

  @override
  String get printOptionsDocumentAndMarkups => 'Document and markups';

  @override
  String get printOptionsDocumentOnly => 'Document only';

  @override
  String get printOptionsMarkupsOnly => 'Markups only';

  @override
  String get printOptionsDimPage => 'Dim page content';

  @override
  String get printOptionsDimMarkups => 'Dim markups';

  @override
  String get printOptionsHyperlinks => 'Print visible hyperlinks';

  @override
  String get printOptionsDefaults => 'Defaults';

  @override
  String get printOptionsInvalidNumber =>
      'Enter valid numbers before printing.';

  @override
  String get printOptionsInvalidValue => 'Invalid value';

  @override
  String get printOptionsMarginGuide =>
      'Red lines show the margins; they do not print.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Window: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Source: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Sheet: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Sheet $sheet of $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'This layout could not be prepared. Check the paper size, margins and scale.';
}

/// The translations for English, as used in the United Kingdom (`en_GB`).
class AppLocalizationsEnGb extends AppLocalizationsEn {
  AppLocalizationsEnGb() : super('en_GB');

  @override
  String get add => 'Add';

  @override
  String get appSigAddLogo => 'Add logo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'All $pageCount pages';
  }

  @override
  String get appSigAppearance => 'Appearance';

  @override
  String get appSigAppearanceDescription =>
      'The signature is drawn where you placed it. The signer name and details are always shown; you can add a hand-drawn mark and a logo backdrop.';

  @override
  String appSigApplyTo(String label) {
    return 'Apply to: $label';
  }

  @override
  String get appSigApplyToPages => 'Apply to pages…';

  @override
  String get appSigChooseCertificate => 'Choose certificate file…';

  @override
  String get appSigChooseKeyDescription =>
      'Choose your private key (RSA, PEM or DER) and its certificate file. The key is only used to sign and is never saved.';

  @override
  String get appSigChoosePngOrJpeg => 'Choose a PNG or JPEG image.';

  @override
  String get appSigChoosePrivateKey => 'Choose private key…';

  @override
  String get appSigContactInfo => 'Contact info';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Could not capture the signature.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Could not read the certificate: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Could not read the key: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Create a signature on this device';

  @override
  String appSigDate(String date) {
    return 'Date: $date';
  }

  @override
  String get appSigDigitallySign => 'Digitally sign';

  @override
  String get appSigDrawSignature => 'Draw signature…';

  @override
  String get appSigFieldHelper =>
      'Leave blank to create a new signature field.';

  @override
  String get appSigFieldLabel => 'Existing signature field (optional)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificates',
      one: '1 certificate',
    );
    return '$_temp0 · valid $validFrom to $validUntil';
  }

  @override
  String get appSigIntro =>
      'A digital signature proves you signed this document and that it has not been changed since. Pick how you want to sign.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'The selected key or certificate could not be read.';

  @override
  String get appSigKeylessDescription =>
      'Easiest. We confirm it\'s you by email and sign for you, with a trusted timestamp. Nothing to install or set up.';

  @override
  String get appSigKeylessIdentity => 'Keyless identity';

  @override
  String get appSigKeylessSignInExpired =>
      'Your keyless sign-in expired. Please sign in again.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Keyless sign-in failed: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Keyless · timestamped · validity unknown';

  @override
  String get appSigKeylessWebNote =>
      'Signing in with your email is the easiest way — it\'s available in the DartPDF desktop and mobile apps. For security reasons it can\'t run in a web browser.';

  @override
  String get appSigLocation => 'Location';

  @override
  String get appSigLogoAdded => 'Logo added ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Pages $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Preview - the signed box may differ slightly.';

  @override
  String get appSigReason => 'Reason';

  @override
  String appSigReasonLine(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Refreshing sign-in…';

  @override
  String get appSigRemoveLogo => 'Remove logo';

  @override
  String get appSigRemoveSignature => 'Remove signature';

  @override
  String get appSigSelfSignedDescription =>
      'No sign-in or files needed. Best for personal use — it\'s saved on this device for next time. Some PDF readers will show it as \"signed, validity unknown\", which is normal for a signature you make yourself.';

  @override
  String get appSigSelfSignedIdentity => 'Self-signed identity';

  @override
  String get appSigSelfSignedSubtitle => 'Self-signed · validity unknown';

  @override
  String get appSigShowSignatureOnPages => 'Show the signature on pages';

  @override
  String get appSigSign => 'Sign';

  @override
  String get appSigSignInWithEmail => 'Sign in with your email';

  @override
  String get appSigSignatureAdded => 'Signature added ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Digitally signed by $signerName';
  }

  @override
  String get appSigSigner => 'Signer';

  @override
  String get appSigSigningYouIn => 'Signing you in…';

  @override
  String get appSigThisPageOnly => 'This page only';

  @override
  String get appSigUseOwnCertificate => 'Use your own certificate';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'For a signing certificate from your organisation';

  @override
  String get appSigX509Signer => 'X.509 signer';

  @override
  String get apply => 'Apply';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get cut => 'Cut';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Open these $count PDFs in a new tab, or insert their pages into \"$title\"?',
      one: 'Open this PDF in a new tab, or insert its pages into \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add dropped PDFs',
      one: 'Add dropped PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Annotation text copied';

  @override
  String get editorAppMenuTooltip => 'DartPDF menu';

  @override
  String get editorCancelOcr => 'Cancel OCR';

  @override
  String get editorClearRecentFiles => 'Clear recent files';

  @override
  String get editorCloseAll => 'Close all';

  @override
  String get editorCloseOthers => 'Close others';

  @override
  String get editorCloseTab => 'Close tab';

  @override
  String get editorCloseTabsToRight => 'Close tabs to the right';

  @override
  String get editorCompareFailedTitle => 'Compare failed';

  @override
  String editorCompareTitle(String title) {
    return 'Compare: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Copied to clipboard';

  @override
  String get editorCopySelectedTextTooltip => 'Copy selected text (⌘C)';

  @override
  String get editorCopyText => 'Copy text';

  @override
  String editorCouldNotExport(String title) {
    return 'Could not export $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Could not import stamps: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Could not insert the dropped PDFs',
      one: 'Could not insert the dropped PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Could not open $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'Could not open containing folder';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Could not open the second file\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Could not open the selected file\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Could not open $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Could not print $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Could not reopen $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Could not digitally sign: $error';
  }

  @override
  String get editorDiscard => 'Discard';

  @override
  String get editorDiscardChangesTitle => 'Discard changes?';

  @override
  String get editorDocumentSigned => 'Document digitally signed';

  @override
  String get editorDownload => 'Download';

  @override
  String get editorDropToOpen => 'Drop PDF to open';

  @override
  String get editorDropToOpenOrInsert => 'Drop PDF to open or insert';

  @override
  String get editorInsertPages => 'Insert pages';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Inserted $count; could not read $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Inserted $count PDFs into $title',
      one: 'Inserted pages into $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Invalid link: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'This document tried to run JavaScript (ignored)';

  @override
  String get editorLoadingFullDocument => 'Loading full document';

  @override
  String get editorMenuCompareWith => 'Compare with…';

  @override
  String get editorMenuDigitallySign => 'Digitally sign…';

  @override
  String get editorMenuDigitallySigning => 'Digitally signing…';

  @override
  String get editorMenuExportImage => 'Export page as image…';

  @override
  String get editorMenuNewDocument => 'New document…';

  @override
  String get editorMenuNewWindow => 'New window';

  @override
  String get editorMoveToNewWindow => 'Move to new window';

  @override
  String get editorUnableToOpenNewWindow => 'Couldn’t open a new window';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Open a PDF…';

  @override
  String get editorMenuPrint => 'Print…';

  @override
  String get editorMenuSaveAs => 'Save as…';

  @override
  String get editorMenuScanDocument => 'Scan to new document…';

  @override
  String get editorMenuInsertDocument => 'Insert document…';

  @override
  String get editorMenuInsertScan => 'Insert scan…';

  @override
  String get editorScanFailed => 'Couldn\'t scan the document.';

  @override
  String get editorInsertedScan => 'Inserted scanned pages.';

  @override
  String get editorMenuSettings => 'Settings';

  @override
  String get editorMenuSectionFile => 'File';

  @override
  String get editorMenuSectionDocument => 'This document';

  @override
  String get editorMenuSectionApp => 'App';

  @override
  String get editorMenuReadOnly => 'Read-only';

  @override
  String get editorMenuSearchActions => 'Search actions…';

  @override
  String get paletteHint => 'Search actions, tools and panels';

  @override
  String get paletteNoMatch => 'No command matches';

  @override
  String get paletteKeyHints => '↑↓ move · ⏎ run · esc close';

  @override
  String paletteCount(int count) {
    return '$count commands';
  }

  @override
  String paletteCountFiltered(int count, int total) {
    return '$count of $total';
  }

  @override
  String get paletteSourceMenu => 'Menu';

  @override
  String get paletteSourcePanel => 'Panel';

  @override
  String get paletteSourceView => 'View';

  @override
  String get paletteSourceFile => 'File';

  @override
  String paletteSourceTool(String group) {
    return '$group tool';
  }

  @override
  String get paletteNeedsDocument => 'Needs an open document';

  @override
  String editorNamedAction(String name) {
    return 'Named action: $name';
  }

  @override
  String get editorNoRecentFiles => 'No recent files';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'Open a document before running OCR';

  @override
  String get editorOpenFailedTitle => 'Open failed';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Open in new tabs',
      one: 'Open in new tab',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Open PDF in a new tab';

  @override
  String get editorOpenRecent => 'Open Recent';

  @override
  String get editorViewAllRecentFiles => 'View all recent files…';

  @override
  String get editorOpenTabs => 'Open tabs';

  @override
  String get editorOpeningDocumentSemantic => 'Opening document';

  @override
  String get editorOpeningPdf => 'Opening PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Opening $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get editorPreviewComparison => 'Comparison';

  @override
  String get editorPreviewCouldNotOpen => 'Could not open';

  @override
  String get editorPreviewOpening => 'Opening';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Recovered unsaved changes in $count documents from your last session.',
      one: 'Recovered unsaved changes from your last session.',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'Signature removed';

  @override
  String get editorSnapshotCopied => 'Snapshot copied to clipboard';

  @override
  String get editorSnapshotCopyFailed => 'Could not copy snapshot to clipboard';

  @override
  String get editorTabs => 'Tabs';

  @override
  String editorTabsOpenCount(int count) {
    return '$count open';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents have unsaved changes.',
      one: 'A document has unsaved changes.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Unsupported action: $type';
  }

  @override
  String get editorUntitled => 'Untitled';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version is available.';
  }

  @override
  String get editorUpdateLater => 'Later';

  @override
  String get updateInstallNow => 'Update now';

  @override
  String get updateDownloadingTitle => 'Downloading update';

  @override
  String get updatePreparing => 'Preparing…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateRestarting => 'Restarting to finish the update…';

  @override
  String get updateHandedOff => 'Update downloaded. Opening the installer…';

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get editorViewAllTabs => 'View all tabs';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Export';

  @override
  String get imgExportFormat => 'Format';

  @override
  String get imgExportResolution => 'Resolution';

  @override
  String get imgExportTitle => 'Export page as image';

  @override
  String get newDocCreate => 'Create';

  @override
  String get newDocLandscape => 'Landscape';

  @override
  String get newDocOrientation => 'Orientation';

  @override
  String get newDocPageSize => 'Page size';

  @override
  String get newDocPortrait => 'Portrait';

  @override
  String get newDocTitle => 'New document';

  @override
  String get none => 'None';

  @override
  String get ocrAlreadyRunning =>
      'OCR is already running - wait for it to finish or cancel it';

  @override
  String get ocrBrowserInitFailed => 'Browser OCR failed to initialise';

  @override
  String get ocrCancelled => 'OCR cancelled';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR cancelled after $count text spans',
      one: 'OCR cancelled after 1 text span',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Download';

  @override
  String ocrDownloadFailed(String error) {
    return 'Could not download the OCR model: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Adding a selectable text layer needs the on-device OCR model$size. It downloads once and then runs offline.\n\nModel: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Download OCR model?';

  @override
  String ocrFailed(String error) {
    return 'OCR failed: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'On-device OCR is not available on this platform';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR added $count text spans - the page text is now selectable',
      one: 'OCR added 1 text span - the page text is now selectable',
      zero: 'OCR found no text on these pages',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Web OCR downloads a Florence-2 vision-language model and runs it locally with WebGPU/WASM through Transformers.js. The PDF pages stay in this browser; only model files are fetched on first use.';

  @override
  String get ocrWebPromptTitle => 'Run AI OCR in this browser?';

  @override
  String get ocrWebStart => 'Start OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Paste';

  @override
  String get printDlgPreparing => 'Preparing…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Rendering page $rendered of $total…';
  }

  @override
  String get printDlgTitle => 'Printing';

  @override
  String get printPreviewAll => 'All';

  @override
  String get printPreviewCurrent => 'Current';

  @override
  String get printPreviewFrom => 'From';

  @override
  String get printPreviewNextPage => 'Next page';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get printPreviewPreviousPage => 'Previous page';

  @override
  String get printPreviewPrint => 'Print';

  @override
  String get printPreviewRange => 'Range';

  @override
  String printPreviewRangeError(int total) {
    return 'Enter a page range between 1 and $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Pages to print: $count';
  }

  @override
  String get printPreviewTitle => 'Print preview';

  @override
  String get printPreviewTo => 'To';

  @override
  String get printPreviewUnavailable => 'Preview unavailable';

  @override
  String get redo => 'Redo';

  @override
  String get remove => 'Remove';

  @override
  String get rename => 'Rename';

  @override
  String get reset => 'Reset';

  @override
  String get save => 'Save';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsCheckNow => 'Check now';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsCheckingForUpdates => 'Checking for updates…';

  @override
  String get settingsCouldNotOpenDownload => 'Could not open the download';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Could not open system settings';

  @override
  String get settingsDeveloperTools => 'Developer tools';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Metrics, logs, render modes (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Download $version';
  }

  @override
  String get settingsOpenSettings => 'Open Settings';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count remembered',
      one: '1 remembered',
      zero: 'No recent files',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Recent files';

  @override
  String get settingsSetUpAsDefault => 'Set up as default application';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsTitle => 'Settings';

  @override
  String settingsUpToDate(String version) {
    return 'You’re on the latest version ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Version $version is available (you have $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Couldn’t check for updates. Try again later.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'You have $name $version.';
  }

  @override
  String get settingsNightlyUpdates => 'Nightly updates';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'Receive automatic update notifications for unsigned Windows test builds from main.';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsViewSource => 'View source on GitHub';

  @override
  String get undo => 'Undo';

  @override
  String get welcomeOpenPdf => 'Open a PDF';

  @override
  String get welcomePickAgainToReopen => 'Pick again to reopen';

  @override
  String get welcomeRecent => 'Recent';

  @override
  String get welcomeSearchRecentFiles => 'Search recent files';

  @override
  String get welcomeNoMatchingRecentFiles =>
      'No recent files match your search';

  @override
  String get welcomeRemoveFromRecent => 'Remove from recent';

  @override
  String get welcomeTapToReopen => 'Tap to reopen';

  @override
  String get welcomeViewAsGrid => 'Grid view';

  @override
  String get welcomeViewAsList => 'List view';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Install the web app, then choose it for PDF files.',
        'windows': 'Open Windows default apps settings for PDFs.',
        'macos': 'Follow Finder’s “Always Open With” steps.',
        'linux': 'Use your desktop’s default applications settings.',
        'android': 'Choose DartPDF when opening a PDF, then tap Always.',
        'ios': 'Use Share or Open In from Files to send PDFs here.',
        'other': 'Configure your system’s PDF file handler.',
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
            'Install DartPDF from your browser first. Then use the browser or operating system file-handler settings to associate PDF files with the installed app.',
        'windows':
            'Windows Settings will open to Default apps. Search for “.pdf” or “PDF”, choose the current PDF app, then select DartPDF.',
        'macos':
            'In Finder, select any PDF, choose File > Get Info, expand “Open with”, pick DartPDF, then click “Change All…”.',
        'linux':
            'Open your desktop settings for Default Applications, or right-click a PDF in Files, choose Properties, and set DartPDF as the default for PDF documents.',
        'android':
            'Open a PDF from Files or Downloads, choose DartPDF in the app picker, then select Always. If another app already opens PDFs, clear that app’s defaults in Android Settings first.',
        'ios':
            'iOS does not provide a global default PDF editor. Use Files > Share, or long-press a PDF and choose Share/Open In, then pick DartPDF.',
        'other':
            'Use the system settings for file handlers to associate PDF documents with DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Downloading OCR model…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Downloading model $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Finishing OCR…';

  @override
  String get fileTypePdf => 'PDF documents';

  @override
  String get fileTypeImages => 'Images';

  @override
  String get fileTypeStampBundle => 'DartPDF stamps';

  @override
  String get appSigKeyFileType => 'RSA private keys';

  @override
  String get appSigCertificateFileType => 'X.509 certificates';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Select at least one X.509 certificate.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Certificate $index is not valid X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'The private key does not match any selected RSA certificate.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Encrypted private keys are not supported. Choose an unencrypted RSA PKCS#1 or PKCS#8 key.';

  @override
  String get appSigErrorKeyNotRsa =>
      'The private key is not an unencrypted RSA PKCS#1 or PKCS#8 key.';

  @override
  String get appSigErrorNoCertificateFound =>
      'No X.509 certificates were found.';

  @override
  String get imageSourceTakePhoto => 'Take photo';

  @override
  String get imageSourceChooseFile => 'Choose file';

  @override
  String get imageSourceCameraFailed => 'Couldn\'t take a photo';

  @override
  String get settingsCachedDocuments => 'Cached documents';

  @override
  String settingsCacheUsage(String used, String limit) {
    return '$used MiB of $limit MiB used';
  }

  @override
  String settingsCacheExplanation(String limit) {
    return 'Files over $limit MiB are not cached. Clearing keeps your Recent list, open documents and unsaved changes; cached files must be picked again to reopen.';
  }

  @override
  String get settingsClearCachedDocuments => 'Clear cached documents';

  @override
  String get settingsCacheUnavailable => 'Cache size unavailable';

  @override
  String get settingsCacheClearFailed =>
      'Could not clear cached documents. Try again.';

  @override
  String get editorMenuReduceFileSize => 'Reduce file size…';

  @override
  String get reduceSizeTitle => 'Reduce file size';

  @override
  String get reduceSizeDescription =>
      'Optimise the current document, review the savings, then save a smaller copy.';

  @override
  String get reduceSizePreset => 'Preset';

  @override
  String get reduceSizeLossless => 'Lossless — preserve image quality';

  @override
  String get reduceSizeScreen => 'Screen — 72 DPI, JPEG quality 60';

  @override
  String get reduceSizeEbook => 'eBook — 150 DPI, JPEG quality 75';

  @override
  String get reduceSizePrinter => 'Print — 300 DPI, JPEG quality 90';

  @override
  String get reduceSizeLosslessHint =>
      'Image resolution and quality stay the same.';

  @override
  String get reduceSizeLossyHint =>
      'Images above the target resolution may be reduced and JPEG-encoded. Fine image detail can be lost; text and vector graphics stay sharp.';

  @override
  String get reduceSizeAdvanced => 'Advanced settings';

  @override
  String get reduceSizeRecompress => 'Recompress streams';

  @override
  String get reduceSizeUnusedResources => 'Remove unused resources';

  @override
  String get reduceSizeDeduplicate => 'Merge duplicate objects';

  @override
  String get reduceSizeSubsetFonts => 'Subset embedded fonts';

  @override
  String get reduceSizeDpi => 'Image target resolution';

  @override
  String get reduceSizeKeepImages => 'Keep original images (lossless)';

  @override
  String reduceSizeJpegQuality(int quality) {
    return 'JPEG quality: $quality';
  }

  @override
  String get reduceSizeSignaturesNotice =>
      'Rewriting this signed PDF invalidates its digital signatures in the saved copy.';

  @override
  String get reduceSizeInvalidateSignatures =>
      'Allow invalidating signatures in this copy';

  @override
  String get reduceSizeEncrypted => 'Encrypted PDFs cannot be optimised.';

  @override
  String get reduceSizeIncomplete =>
      'Wait for the document to finish loading before reducing its size.';

  @override
  String get reduceSizeRun => 'Optimise';

  @override
  String get reduceSizeRunning => 'Optimising document…';

  @override
  String reduceSizeFailed(String error) {
    return 'Could not optimise this PDF: $error';
  }

  @override
  String reduceSizeSaveFailed(String error) {
    return 'Could not save the copy: $error';
  }

  @override
  String get reduceSizeSaveCopy => 'Save copy…';

  @override
  String get reduceSizeChangeSettings => 'Change settings';

  @override
  String get reduceSizeBefore => 'Original size';

  @override
  String get reduceSizeAfter => 'Optimised size';

  @override
  String get reduceSizeSavings => 'Space saved';

  @override
  String get reduceSizeNoSavings =>
      'This document is already compact with these settings. The original bytes were kept.';

  @override
  String get reduceSizeReportHint => 'Bytes saved by each optimisation step:';

  @override
  String get reduceSizeStructure => 'Document structure';

  @override
  String get reduceSizeResources => 'Unused resources';

  @override
  String get reduceSizeFonts => 'Embedded fonts';

  @override
  String get reduceSizeImages => 'Images';

  @override
  String get reduceSizeDuplicates => 'Duplicate objects';

  @override
  String get reduceSizeCustom => 'Custom settings';

  @override
  String get printOptionsPrinter => 'Printer';

  @override
  String get printOptionsNativePrinter =>
      'Choose the printer, paper tray, colour, duplex and device properties in the system print dialog next. Keep its scale at 100% and copies at 1 to use the layout shown here.';

  @override
  String get printOptionsPages => 'Pages';

  @override
  String get printOptionsSelected => 'Selected';

  @override
  String get printOptionsPageRange => 'Pages (for example, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Add files…';

  @override
  String get printOptionsAddFailed => 'Could not add the selected files.';

  @override
  String get printOptionsGetWindow => 'Get window';

  @override
  String get printOptionsClearWindow => 'Clear window';

  @override
  String get printOptionsWindowHint =>
      'Drag a rectangle on this source page to choose the area to print.';

  @override
  String get printOptionsPaper => 'Paper';

  @override
  String get printOptionsPaperSize => 'Paper size';

  @override
  String get printOptionsPageSize => 'Use document page size';

  @override
  String get printOptionsOrientation => 'Orientation';

  @override
  String get printOptionsAuto => 'Auto';

  @override
  String get printOptionsPortrait => 'Portrait';

  @override
  String get printOptionsLandscape => 'Landscape';

  @override
  String get printOptionsCopies => 'Copies';

  @override
  String get printOptionsCollate => 'Collate';

  @override
  String get printOptionsReverse => 'Reverse page order';

  @override
  String get printOptionsLayout => 'Page layout';

  @override
  String get printOptionsScaling => 'Page scaling';

  @override
  String get printOptionsScaleNone => 'None (actual size)';

  @override
  String get printOptionsFitPaper => 'Fit to paper';

  @override
  String get printOptionsReducePaper => 'Reduce to paper';

  @override
  String get printOptionsFitMargins => 'Fit to margins';

  @override
  String get printOptionsReduceMargins => 'Reduce to margins';

  @override
  String get printOptionsCustomScale => 'Custom scale';

  @override
  String get printOptionsMultiple => 'Multiple pages per sheet';

  @override
  String get printOptionsScalePercent => 'Scale (%)';

  @override
  String get printOptionsMargin => 'Margins (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Pages per sheet';

  @override
  String get printOptionsPageOrder => 'Page order';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal reversed';

  @override
  String get printOptionsVertical => 'Vertical';

  @override
  String get printOptionsVerticalReverse => 'Vertical reversed';

  @override
  String get printOptionsBorder => 'Print page borders';

  @override
  String get printOptionsRotation => 'Rotation (clockwise)';

  @override
  String get printOptionsNoRotation => 'None';

  @override
  String get printOptionsCenter => 'Centre on paper';

  @override
  String get printOptionsOffsetX => 'Offset right (pt)';

  @override
  String get printOptionsOffsetY => 'Offset down (pt)';

  @override
  String get printOptionsContents => 'Print contents';

  @override
  String get printOptionsDocumentAndMarkups => 'Document and markups';

  @override
  String get printOptionsDocumentOnly => 'Document only';

  @override
  String get printOptionsMarkupsOnly => 'Markups only';

  @override
  String get printOptionsDimPage => 'Dim page content';

  @override
  String get printOptionsDimMarkups => 'Dim markups';

  @override
  String get printOptionsHyperlinks => 'Print visible hyperlinks';

  @override
  String get printOptionsDefaults => 'Defaults';

  @override
  String get printOptionsInvalidNumber =>
      'Enter valid numbers before printing.';

  @override
  String get printOptionsInvalidValue => 'Invalid value';

  @override
  String get printOptionsMarginGuide =>
      'Red lines show the margins; they do not print.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Window: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Source: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Sheet: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Sheet $sheet of $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'This layout could not be prepared. Check the paper size, margins and scale.';
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_th.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('ru'),
    Locale('th'),
    Locale('tr'),
    Locale('uk'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
  ];

  /// Generic button that adds a new item.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Button to pick a logo backdrop image for the signature box.
  ///
  /// In en, this message translates to:
  /// **'Add logo…'**
  String get appSigAddLogo;

  /// Label meaning the signature box is shown on every page of the document.
  ///
  /// In en, this message translates to:
  /// **'All {pageCount} pages'**
  String appSigAllPages(int pageCount);

  /// Section header for the visible signature box appearance options.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appSigAppearance;

  /// Explanatory text for the visible signature box appearance section.
  ///
  /// In en, this message translates to:
  /// **'The signature is drawn where you placed it. The signer name and details are always shown; you can add a hand-drawn mark and a logo backdrop.'**
  String get appSigAppearanceDescription;

  /// Row showing which pages the signature box will appear on.
  ///
  /// In en, this message translates to:
  /// **'Apply to: {label}'**
  String appSigApplyTo(String label);

  /// Button that opens the page-range picker for showing the signature box on multiple pages.
  ///
  /// In en, this message translates to:
  /// **'Apply to pages…'**
  String get appSigApplyToPages;

  /// Button label to pick a certificate file when none is selected yet.
  ///
  /// In en, this message translates to:
  /// **'Choose certificate file…'**
  String get appSigChooseCertificate;

  /// Instructions in the advanced section for choosing a private key and certificate file.
  ///
  /// In en, this message translates to:
  /// **'Choose your private key (RSA, PEM or DER) and its certificate file. The key is only used to sign and is never saved.'**
  String get appSigChooseKeyDescription;

  /// Error shown when the picked logo backdrop image is not a supported PNG or JPEG.
  ///
  /// In en, this message translates to:
  /// **'Choose a PNG or JPEG image.'**
  String get appSigChoosePngOrJpeg;

  /// Button label to pick a private key file when none is selected yet.
  ///
  /// In en, this message translates to:
  /// **'Choose private key…'**
  String get appSigChoosePrivateKey;

  /// Label for the signer contact info input field.
  ///
  /// In en, this message translates to:
  /// **'Contact info'**
  String get appSigContactInfo;

  /// Error shown when rasterizing the hand-drawn signature mark fails.
  ///
  /// In en, this message translates to:
  /// **'Could not capture the signature.'**
  String get appSigCouldNotCaptureSignature;

  /// Error shown when the selected certificate file cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Could not read the certificate: {error}'**
  String appSigCouldNotReadCertificate(String error);

  /// Error shown when the selected private key file cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Could not read the key: {error}'**
  String appSigCouldNotReadKey(String error);

  /// Button that creates a self-signed signing identity stored on the device.
  ///
  /// In en, this message translates to:
  /// **'Create a signature on this device'**
  String get appSigCreateOnDevice;

  /// Detail line in the signature box preview showing the signing date.
  ///
  /// In en, this message translates to:
  /// **'Date: {date}'**
  String appSigDate(String date);

  /// Title of the digital signing dialog.
  ///
  /// In en, this message translates to:
  /// **'Digitally sign'**
  String get appSigDigitallySign;

  /// Button to open the hand-drawn signature capture dialog.
  ///
  /// In en, this message translates to:
  /// **'Draw signature…'**
  String get appSigDrawSignature;

  /// Helper text for the existing signature field input.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to create a new signature field.'**
  String get appSigFieldHelper;

  /// Text field label for naming an existing signature field to sign into.
  ///
  /// In en, this message translates to:
  /// **'Existing signature field (optional)'**
  String get appSigFieldLabel;

  /// Subtitle summarizing a bring-your-own identity: number of certificates and validity dates.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 certificate} other{{count} certificates}} · valid {validFrom} to {validUntil}'**
  String appSigIdentitySubtitle(int count, String validFrom, String validUntil);

  /// Introductory explanation at the top of the digital signing dialog.
  ///
  /// In en, this message translates to:
  /// **'A digital signature proves you signed this document and that it has not been changed since. Pick how you want to sign.'**
  String get appSigIntro;

  /// Error shown when the chosen key or certificate could not be parsed for signing.
  ///
  /// In en, this message translates to:
  /// **'The selected key or certificate could not be read.'**
  String get appSigKeyOrCertUnreadable;

  /// Explanatory text under the keyless email signing button.
  ///
  /// In en, this message translates to:
  /// **'Easiest. We confirm it\'s you by email and sign for you, with a trusted timestamp. Nothing to install or set up.'**
  String get appSigKeylessDescription;

  /// Fallback title for a keyless identity that has no name.
  ///
  /// In en, this message translates to:
  /// **'Keyless identity'**
  String get appSigKeylessIdentity;

  /// Error shown when a short-lived keyless certificate has expired and re-signing is needed.
  ///
  /// In en, this message translates to:
  /// **'Your keyless sign-in expired. Please sign in again.'**
  String get appSigKeylessSignInExpired;

  /// Error shown when the Sigstore/Fulcio keyless sign-in flow fails.
  ///
  /// In en, this message translates to:
  /// **'Keyless sign-in failed: {failure}'**
  String appSigKeylessSignInFailed(String failure);

  /// Subtitle describing a keyless (Sigstore/Fulcio) signing identity.
  ///
  /// In en, this message translates to:
  /// **'Keyless · timestamped · validity unknown'**
  String get appSigKeylessSubtitle;

  /// Note shown on the web build explaining that keyless email signing is only available in the desktop and mobile apps.
  ///
  /// In en, this message translates to:
  /// **'Signing in with your email is the easiest way — it\'s available in the DartPDF desktop and mobile apps. For security reasons it can\'t run in a web browser.'**
  String get appSigKeylessWebNote;

  /// Label for the signing location input field.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get appSigLocation;

  /// Button label confirming a logo backdrop has been added.
  ///
  /// In en, this message translates to:
  /// **'Logo added ✓'**
  String get appSigLogoAdded;

  /// Label for a range of pages (1-based, inclusive) the signature box is shown on.
  ///
  /// In en, this message translates to:
  /// **'Pages {start}–{end}'**
  String appSigPagesRange(int start, int end);

  /// Caption under the signature box preview noting the rendered box may differ.
  ///
  /// In en, this message translates to:
  /// **'Preview - the signed box may differ slightly.'**
  String get appSigPreviewNote;

  /// Label for the signing reason input field.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get appSigReason;

  /// Detail line in the signature box preview showing the signing reason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String appSigReasonLine(String reason);

  /// Busy label on the Sign button while re-minting an about-to-expire keyless certificate.
  ///
  /// In en, this message translates to:
  /// **'Refreshing sign-in…'**
  String get appSigRefreshingSignIn;

  /// Button that clears the logo backdrop from the appearance preview.
  ///
  /// In en, this message translates to:
  /// **'Remove logo'**
  String get appSigRemoveLogo;

  /// Button that clears the hand-drawn signature mark from the appearance preview.
  ///
  /// In en, this message translates to:
  /// **'Remove signature'**
  String get appSigRemoveSignature;

  /// Explanatory text under the create-a-signature-on-this-device button.
  ///
  /// In en, this message translates to:
  /// **'No sign-in or files needed. Best for personal use — it\'s saved on this device for next time. Some PDF readers will show it as \"signed, validity unknown\", which is normal for a signature you make yourself.'**
  String get appSigSelfSignedDescription;

  /// Fallback title for a self-signed identity that has no name.
  ///
  /// In en, this message translates to:
  /// **'Self-signed identity'**
  String get appSigSelfSignedIdentity;

  /// Subtitle describing a self-signed signing identity.
  ///
  /// In en, this message translates to:
  /// **'Self-signed · validity unknown'**
  String get appSigSelfSignedSubtitle;

  /// Title of the dialog that chooses which pages the visible signature box appears on.
  ///
  /// In en, this message translates to:
  /// **'Show the signature on pages'**
  String get appSigShowSignatureOnPages;

  /// Confirm button that applies the digital signature.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get appSigSign;

  /// Button that starts the keyless email-based signing flow.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your email'**
  String get appSigSignInWithEmail;

  /// Button label confirming a hand-drawn signature mark has been added.
  ///
  /// In en, this message translates to:
  /// **'Signature added ✓'**
  String get appSigSignatureAdded;

  /// First detail line in the signature box preview naming the signer.
  ///
  /// In en, this message translates to:
  /// **'Digitally signed by {signerName}'**
  String appSigSignedBy(String signerName);

  /// Fallback text shown in the signature box preview when no signer name is known.
  ///
  /// In en, this message translates to:
  /// **'Signer'**
  String get appSigSigner;

  /// Busy label on the keyless button while the email sign-in is in progress.
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get appSigSigningYouIn;

  /// Label meaning the signature box is shown only on the placed page.
  ///
  /// In en, this message translates to:
  /// **'This page only'**
  String get appSigThisPageOnly;

  /// Title of the advanced section for signing with a bring-your-own key and certificate.
  ///
  /// In en, this message translates to:
  /// **'Use your own certificate'**
  String get appSigUseOwnCertificate;

  /// Subtitle for the advanced bring-your-own-certificate signing section.
  ///
  /// In en, this message translates to:
  /// **'For a signing certificate from your organisation'**
  String get appSigUseOwnCertificateSubtitle;

  /// Fallback title for an identity from a certificate that has no signer name.
  ///
  /// In en, this message translates to:
  /// **'X.509 signer'**
  String get appSigX509Signer;

  /// Generic button that applies pending changes.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// Button that dismisses a dialog without applying.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic button that clears the current value or selection.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Generic button/tooltip that closes a panel or dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Generic button/menu label to copy the current item.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Generic button/menu label to cut the current item.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// Generic button/menu label to delete the current item.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic button that finishes the current interaction.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Generic button/menu label to edit the current item.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Dialog body asking whether to open dropped PDFs in new tabs or insert their pages into the named open document.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Open this PDF in a new tab, or insert its pages into \"{title}\"?} other{Open these {count} PDFs in a new tab, or insert their pages into \"{title}\"?}}'**
  String editorAddDroppedMessage(int count, String title);

  /// Dialog title asking how to handle PDFs dropped while a document is open.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Add dropped PDF} other{Add dropped PDFs}}'**
  String editorAddDroppedTitle(int count);

  /// Toast confirming annotation text was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Annotation text copied'**
  String get editorAnnotationTextCopied;

  /// Tooltip on the app icon that opens the main application menu.
  ///
  /// In en, this message translates to:
  /// **'DartPDF menu'**
  String get editorAppMenuTooltip;

  /// Tooltip on the button that cancels the running background OCR job.
  ///
  /// In en, this message translates to:
  /// **'Cancel OCR'**
  String get editorCancelOcr;

  /// Open Recent submenu action to clear the recent files list.
  ///
  /// In en, this message translates to:
  /// **'Clear recent files'**
  String get editorClearRecentFiles;

  /// Tab context-menu action to close every open tab.
  ///
  /// In en, this message translates to:
  /// **'Close all'**
  String get editorCloseAll;

  /// Tab context-menu action to close all other tabs.
  ///
  /// In en, this message translates to:
  /// **'Close others'**
  String get editorCloseOthers;

  /// Tooltip on the per-tab close button.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get editorCloseTab;

  /// Tab context-menu action to close every tab to the right of this one.
  ///
  /// In en, this message translates to:
  /// **'Close tabs to the right'**
  String get editorCloseTabsToRight;

  /// Tab title when opening a second document for comparison failed.
  ///
  /// In en, this message translates to:
  /// **'Compare failed'**
  String get editorCompareFailedTitle;

  /// Tab title for a document comparison, naming the base document.
  ///
  /// In en, this message translates to:
  /// **'Compare: {title}'**
  String editorCompareTitle(String title);

  /// Toast confirming the text selection was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get editorCopiedToClipboard;

  /// Tooltip on the app-bar button that copies the current text selection.
  ///
  /// In en, this message translates to:
  /// **'Copy selected text (⌘C)'**
  String get editorCopySelectedTextTooltip;

  /// Annotation context-menu action to copy the annotation's text.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get editorCopyText;

  /// Toast when exporting the named document's page as an image failed.
  ///
  /// In en, this message translates to:
  /// **'Could not export {title}'**
  String editorCouldNotExport(String title);

  /// Toast when importing custom stamps failed, with the error detail.
  ///
  /// In en, this message translates to:
  /// **'Could not import stamps: {error}'**
  String editorCouldNotImportStamps(String error);

  /// Toast shown when none of the dropped PDFs could be inserted into the current document.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Could not insert the dropped PDF} other{Could not insert the dropped PDFs}}'**
  String editorCouldNotInsertDropped(int count);

  /// Error shown in a failed document tab: could not open the named file, with the underlying error detail.
  ///
  /// In en, this message translates to:
  /// **'Could not open {title}\n{error}'**
  String editorCouldNotOpenDetail(String title, String error);

  /// Toast when the tab's containing folder could not be revealed in the OS file manager.
  ///
  /// In en, this message translates to:
  /// **'Could not open containing folder'**
  String get editorCouldNotOpenFolder;

  /// Error tab body when the second document picked for comparison could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open the second file\n{error}'**
  String editorCouldNotOpenSecond(String error);

  /// Error tab body shown when the file chosen in the picker could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open the selected file\n{error}'**
  String editorCouldNotOpenSelected(String error);

  /// Toast when an external URL could not be launched.
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String editorCouldNotOpenUrl(String url);

  /// Toast when printing the named document failed.
  ///
  /// In en, this message translates to:
  /// **'Could not print {title}'**
  String editorCouldNotPrint(String title);

  /// Toast when a recent/session document could not be reopened.
  ///
  /// In en, this message translates to:
  /// **'Could not reopen {title}'**
  String editorCouldNotReopen(String title);

  /// Toast shown when digitally signing the document failed, with the error detail.
  ///
  /// In en, this message translates to:
  /// **'Could not digitally sign: {error}'**
  String editorCouldNotSign(String error);

  /// Confirmation-dialog action that discards unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get editorDiscard;

  /// Title of the confirmation dialog shown before discarding unsaved edits.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get editorDiscardChangesTitle;

  /// Snackbar confirming a digital signature was applied; offers an undo.
  ///
  /// In en, this message translates to:
  /// **'Document digitally signed'**
  String get editorDocumentSigned;

  /// Update banner action to download the newer release.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get editorDownload;

  /// Drop-zone hint when a dropped PDF can only be opened in a new tab.
  ///
  /// In en, this message translates to:
  /// **'Drop PDF to open'**
  String get editorDropToOpen;

  /// Drop-zone hint when a dropped PDF can be opened or inserted into the current document.
  ///
  /// In en, this message translates to:
  /// **'Drop PDF to open or insert'**
  String get editorDropToOpenOrInsert;

  /// Dialog action to insert dropped PDFs' pages into the current document.
  ///
  /// In en, this message translates to:
  /// **'Insert pages'**
  String get editorInsertPages;

  /// Toast when some dropped PDFs were inserted but others could not be read; files is a comma-separated list of names.
  ///
  /// In en, this message translates to:
  /// **'Inserted {count}; could not read {files}'**
  String editorInsertedButFailed(int count, String files);

  /// Toast confirming that dropped PDFs' pages were inserted into the named document.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Inserted pages into {title}} other{Inserted {count} PDFs into {title}}}'**
  String editorInsertedIntoTitle(int count, String title);

  /// Toast when a link annotation points to an unparseable URI.
  ///
  /// In en, this message translates to:
  /// **'Invalid link: {uri}'**
  String editorInvalidLink(String uri);

  /// Toast noting that an embedded JavaScript action was ignored for safety.
  ///
  /// In en, this message translates to:
  /// **'This document tried to run JavaScript (ignored)'**
  String get editorJavaScriptIgnored;

  /// Accessibility label for the progress bar loading the full document behind a progressive first paint.
  ///
  /// In en, this message translates to:
  /// **'Loading full document'**
  String get editorLoadingFullDocument;

  /// App menu item to compare the current document with another PDF.
  ///
  /// In en, this message translates to:
  /// **'Compare with…'**
  String get editorMenuCompareWith;

  /// App menu item to digitally sign the document.
  ///
  /// In en, this message translates to:
  /// **'Digitally sign…'**
  String get editorMenuDigitallySign;

  /// App menu item label while a digital signature is in progress.
  ///
  /// In en, this message translates to:
  /// **'Digitally signing…'**
  String get editorMenuDigitallySigning;

  /// App menu item to export the current page as an image.
  ///
  /// In en, this message translates to:
  /// **'Export page as image…'**
  String get editorMenuExportImage;

  /// App menu item to create a new blank document.
  ///
  /// In en, this message translates to:
  /// **'New document…'**
  String get editorMenuNewDocument;

  /// Experimental desktop app menu item to open another native editor window.
  ///
  /// In en, this message translates to:
  /// **'New window'**
  String get editorMenuNewWindow;

  /// Desktop tab context-menu item that moves the document into another native window.
  ///
  /// In en, this message translates to:
  /// **'Move to new window'**
  String get editorMoveToNewWindow;

  /// Toast shown when the experimental native window could not be created.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open a new window'**
  String get editorUnableToOpenNewWindow;

  /// App menu item to run on-device OCR over the document.
  ///
  /// In en, this message translates to:
  /// **'OCR…'**
  String get editorMenuOcr;

  /// App menu item to open a PDF file.
  ///
  /// In en, this message translates to:
  /// **'Open a PDF…'**
  String get editorMenuOpen;

  /// App menu item to print the document.
  ///
  /// In en, this message translates to:
  /// **'Print…'**
  String get editorMenuPrint;

  /// App menu item to save the document under a new name/location.
  ///
  /// In en, this message translates to:
  /// **'Save as…'**
  String get editorMenuSaveAs;

  /// App menu item (mobile/tablet) to scan pages with the device camera into a new document.
  ///
  /// In en, this message translates to:
  /// **'Scan to new document…'**
  String get editorMenuScanDocument;

  /// App menu item (mobile/tablet) to scan pages with the device camera and insert them into the open document.
  ///
  /// In en, this message translates to:
  /// **'Insert scan…'**
  String get editorMenuInsertScan;

  /// Toast shown when a device document scan fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t scan the document.'**
  String get editorScanFailed;

  /// Toast shown after scanned pages are inserted into the open document.
  ///
  /// In en, this message translates to:
  /// **'Inserted scanned pages.'**
  String get editorInsertedScan;

  /// App menu item to open the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get editorMenuSettings;

  /// App menu item to leave read-only mode and allow editing.
  ///
  /// In en, this message translates to:
  /// **'Switch to edit mode'**
  String get editorMenuSwitchToEdit;

  /// App menu item to switch the app into read-only mode.
  ///
  /// In en, this message translates to:
  /// **'Switch to read-only'**
  String get editorMenuSwitchToReadOnly;

  /// Toast reporting a PDF named action that the viewer does not navigate.
  ///
  /// In en, this message translates to:
  /// **'Named action: {name}'**
  String editorNamedAction(String name);

  /// Placeholder shown in the Open Recent submenu and toast when there are no recent files.
  ///
  /// In en, this message translates to:
  /// **'No recent files'**
  String get editorNoRecentFiles;

  /// Tab title for the OCR result derived from the named document.
  ///
  /// In en, this message translates to:
  /// **'{title} (OCR)'**
  String editorOcrTitle(String title);

  /// Tooltip on the running background OCR status chip, naming the document.
  ///
  /// In en, this message translates to:
  /// **'OCR · {title}'**
  String editorOcrTooltip(String title);

  /// Toast prompting the user to open a document before starting OCR.
  ///
  /// In en, this message translates to:
  /// **'Open a document before running OCR'**
  String get editorOpenDocBeforeOcr;

  /// Tab title for a document that failed to open.
  ///
  /// In en, this message translates to:
  /// **'Open failed'**
  String get editorOpenFailedTitle;

  /// Dialog action to open the dropped PDFs each in their own new tab.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Open in new tab} other{Open in new tabs}}'**
  String editorOpenInNewTab(int count);

  /// Tooltip on the button that opens a PDF in a new tab.
  ///
  /// In en, this message translates to:
  /// **'Open PDF in a new tab'**
  String get editorOpenPdfNewTab;

  /// App menu submenu / tooltip for reopening recently opened files.
  ///
  /// In en, this message translates to:
  /// **'Open Recent'**
  String get editorOpenRecent;

  /// Tooltip on the mobile app-bar button that shows the open tabs sheet.
  ///
  /// In en, this message translates to:
  /// **'Open tabs'**
  String get editorOpenTabs;

  /// Accessibility label for the opening-document progress indicator.
  ///
  /// In en, this message translates to:
  /// **'Opening document'**
  String get editorOpeningDocumentSemantic;

  /// Placeholder text while an untitled document is opening.
  ///
  /// In en, this message translates to:
  /// **'Opening PDF…'**
  String get editorOpeningPdf;

  /// Placeholder text while the named document is opening.
  ///
  /// In en, this message translates to:
  /// **'Opening {title}…'**
  String editorOpeningTitle(String title);

  /// Page indicator in a tab hover preview.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String editorPageNumber(int number);

  /// Tab preview placeholder label for a document comparison tab.
  ///
  /// In en, this message translates to:
  /// **'Comparison'**
  String get editorPreviewComparison;

  /// Tab preview placeholder label when the document failed to open.
  ///
  /// In en, this message translates to:
  /// **'Could not open'**
  String get editorPreviewCouldNotOpen;

  /// Tab preview placeholder label while the document is opening.
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get editorPreviewOpening;

  /// Tab preview placeholder label for a generic PDF with no rendered preview.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get editorPreviewPdf;

  /// Toast shown at launch when documents with unsaved edits were restored after a crash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Recovered unsaved changes from your last session.} other{Recovered unsaved changes in {count} documents from your last session.}}'**
  String editorRecoveredUnsavedChanges(int count);

  /// Toast confirming a just-placed signature was undone.
  ///
  /// In en, this message translates to:
  /// **'Signature removed'**
  String get editorSignatureRemoved;

  /// Toast confirming a captured snapshot was copied to the system clipboard.
  ///
  /// In en, this message translates to:
  /// **'Snapshot copied to clipboard'**
  String get editorSnapshotCopied;

  /// Toast when copying a captured snapshot to the clipboard failed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy snapshot to clipboard'**
  String get editorSnapshotCopyFailed;

  /// Header of the open-tabs grid overlay.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get editorTabs;

  /// Footer of the tabs grid showing how many tabs are open.
  ///
  /// In en, this message translates to:
  /// **'{count} open'**
  String editorTabsOpenCount(int count);

  /// Discard-confirmation message stating how many open documents have unsaved edits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A document has unsaved changes.} other{{count} documents have unsaved changes.}}'**
  String editorUnsavedChangesCount(int count);

  /// Toast reporting an unsupported PDF action type.
  ///
  /// In en, this message translates to:
  /// **'Unsupported action: {type}'**
  String editorUnsupportedAction(String type);

  /// Fallback display name for a document tab with no title.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get editorUntitled;

  /// Update banner text announcing that a newer release can be downloaded.
  ///
  /// In en, this message translates to:
  /// **'DartPDF {version} is available.'**
  String editorUpdateAvailable(String version);

  /// Update banner action to dismiss the update notice for now.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get editorUpdateLater;

  /// Button that downloads and installs the newer release in place (desktop), instead of opening a browser download.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateInstallNow;

  /// Title of the dialog shown while an in-app update is downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update'**
  String get updateDownloadingTitle;

  /// Status shown before download progress is known.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get updatePreparing;

  /// Download progress line with the percentage complete.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String updateDownloadingPercent(int percent);

  /// Status shown after the AppImage is replaced, just before the app relaunches.
  ///
  /// In en, this message translates to:
  /// **'Restarting to finish the update…'**
  String get updateRestarting;

  /// Snackbar shown after a macOS/Windows update is downloaded and handed to the OS installer.
  ///
  /// In en, this message translates to:
  /// **'Update downloaded. Opening the installer…'**
  String get updateHandedOff;

  /// Snackbar shown when an in-app update download or install fails.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String updateFailed(String error);

  /// Tooltip on the desktop button that opens the all-tabs grid dialog.
  ///
  /// In en, this message translates to:
  /// **'View all tabs'**
  String get editorViewAllTabs;

  /// A resolution option expressed in dots per inch.
  ///
  /// In en, this message translates to:
  /// **'{dpi} dpi'**
  String imgExportDpiValue(int dpi);

  /// Button that confirms the image export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get imgExportExport;

  /// Label for the image-format chooser in the export dialog.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get imgExportFormat;

  /// Label for the resolution (DPI) chooser in the export dialog.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get imgExportResolution;

  /// Title of the dialog that exports a page to an image file.
  ///
  /// In en, this message translates to:
  /// **'Export page as image'**
  String get imgExportTitle;

  /// Button that creates the new document with the chosen size and orientation.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get newDocCreate;

  /// Landscape page orientation option.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get newDocLandscape;

  /// Label for the orientation chooser in the new-document dialog.
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get newDocOrientation;

  /// Label for the page-size chooser in the new-document dialog.
  ///
  /// In en, this message translates to:
  /// **'Page size'**
  String get newDocPageSize;

  /// Portrait page orientation option.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get newDocPortrait;

  /// Title of the dialog that creates a new blank PDF.
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get newDocTitle;

  /// Label for the absence of a selection or value.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// Toast shown when starting OCR while another OCR job is in flight.
  ///
  /// In en, this message translates to:
  /// **'OCR is already running - wait for it to finish or cancel it'**
  String get ocrAlreadyRunning;

  /// Toast shown when the browser-local OCR bridge failed to initialize.
  ///
  /// In en, this message translates to:
  /// **'Browser OCR failed to initialise'**
  String get ocrBrowserInitFailed;

  /// Toast shown when an OCR job is cancelled before any pages are processed.
  ///
  /// In en, this message translates to:
  /// **'OCR cancelled'**
  String get ocrCancelled;

  /// Toast shown when OCR is cancelled after adding some text spans.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{OCR cancelled after 1 text span} other{OCR cancelled after {count} text spans}}'**
  String ocrCancelledAfterSpans(int count);

  /// Button that confirms downloading the OCR model.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get ocrDownload;

  /// Toast shown when the OCR model download fails.
  ///
  /// In en, this message translates to:
  /// **'Could not download the OCR model: {error}'**
  String ocrDownloadFailed(String error);

  /// Body of the OCR model download confirmation dialog. {size} is an optional approximate-size fragment (with leading space) or empty; {model} is the model's display name.
  ///
  /// In en, this message translates to:
  /// **'Adding a selectable text layer needs the on-device OCR model{size}. It downloads once and then runs offline.\n\nModel: {model}'**
  String ocrDownloadPromptBody(String size, String model);

  /// Title of the dialog confirming the one-time OCR model download.
  ///
  /// In en, this message translates to:
  /// **'Download OCR model?'**
  String get ocrDownloadPromptTitle;

  /// Toast shown when an OCR job throws an error.
  ///
  /// In en, this message translates to:
  /// **'OCR failed: {error}'**
  String ocrFailed(String error);

  /// Approximate download size of the OCR model, in megabytes, shown in the download prompt.
  ///
  /// In en, this message translates to:
  /// **'(~{mb} MB)'**
  String ocrModelApproxSize(int mb);

  /// Toast shown when on-device OCR is unsupported on the current platform.
  ///
  /// In en, this message translates to:
  /// **'On-device OCR is not available on this platform'**
  String get ocrNotAvailable;

  /// Toast summarizing an OCR run: either no text found or the number of selectable text spans added.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{OCR found no text on these pages} =1{OCR added 1 text span - the page text is now selectable} other{OCR added {count} text spans - the page text is now selectable}}'**
  String ocrResult(int count);

  /// Explanatory body of the browser-local OCR confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Web OCR downloads a Florence-2 vision-language model and runs it locally with WebGPU/WASM through Transformers.js. The PDF pages stay in this browser; only model files are fetched on first use.'**
  String get ocrWebPromptBody;

  /// Title of the dialog confirming browser-local AI OCR.
  ///
  /// In en, this message translates to:
  /// **'Run AI OCR in this browser?'**
  String get ocrWebPromptTitle;

  /// Button that starts browser-local OCR.
  ///
  /// In en, this message translates to:
  /// **'Start OCR'**
  String get ocrWebStart;

  /// Button that confirms a dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Generic button/menu label to paste from the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// Progress line shown before the first print page has rendered.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get printDlgPreparing;

  /// Progress line while pages are being rendered for printing.
  ///
  /// In en, this message translates to:
  /// **'Rendering page {rendered} of {total}…'**
  String printDlgRendering(int rendered, int total);

  /// Title of the modal dialog shown while a print job renders pages.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get printDlgTitle;

  /// Range option in the print preview: print every page.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get printPreviewAll;

  /// Range option in the print preview: print only the page the viewer is on.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get printPreviewCurrent;

  /// Label of the first page of the print range.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get printPreviewFrom;

  /// Tooltip on the print preview's next-page button.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get printPreviewNextPage;

  /// Which page of the document the print preview is showing.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {total}'**
  String printPreviewPageOf(int page, int total);

  /// Tooltip on the print preview's previous-page button.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get printPreviewPreviousPage;

  /// Button in the print preview that starts the print job.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printPreviewPrint;

  /// Range option in the print preview: print the typed page span.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get printPreviewRange;

  /// Error shown when the typed print range is not a range of pages.
  ///
  /// In en, this message translates to:
  /// **'Enter a page range between 1 and {total}.'**
  String printPreviewRangeError(int total);

  /// How many pages the chosen print range covers.
  ///
  /// In en, this message translates to:
  /// **'Pages to print: {count}'**
  String printPreviewSelection(int count);

  /// Title of the dialog previewing what a print job will look like.
  ///
  /// In en, this message translates to:
  /// **'Print preview'**
  String get printPreviewTitle;

  /// Label of the last page of the print range.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get printPreviewTo;

  /// Shown in place of the preview when a page could not be rendered.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable'**
  String get printPreviewUnavailable;

  /// Generic button/tooltip to redo the last undone change.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// Generic button that removes the current item.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Generic button/menu label to rename the current item.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Generic button that resets a value to its default.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Generic button that saves the document or changes.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Section header for the About block in settings.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Section header for theme/appearance controls in settings.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Button that triggers an immediate check for app updates.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get settingsCheckNow;

  /// Section header / label for the UI language picker in settings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Language picker option that follows the device's language instead of a fixed choice.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// Status line shown while an update check is in progress.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get settingsCheckingForUpdates;

  /// Snackbar shown when the update download link could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open the download'**
  String get settingsCouldNotOpenDownload;

  /// Snackbar shown when the OS default-apps settings could not be launched.
  ///
  /// In en, this message translates to:
  /// **'Could not open system settings'**
  String get settingsCouldNotOpenSystemSettings;

  /// Settings list tile title that opens the developer tools panel.
  ///
  /// In en, this message translates to:
  /// **'Developer tools'**
  String get settingsDeveloperTools;

  /// Subtitle describing what the developer tools panel offers.
  ///
  /// In en, this message translates to:
  /// **'Metrics, logs, render modes (F12)'**
  String get settingsDeveloperToolsSubtitle;

  /// Button that downloads the given available app version.
  ///
  /// In en, this message translates to:
  /// **'Download {version}'**
  String settingsDownloadVersion(String version);

  /// Button that opens the operating system's default-apps settings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get settingsOpenSettings;

  /// Summary line for how many recent files are remembered.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No recent files} =1{1 remembered} other{{count} remembered}}'**
  String settingsRecentCount(int count);

  /// Section header for the recent-files list in settings.
  ///
  /// In en, this message translates to:
  /// **'Recent files'**
  String get settingsRecentFiles;

  /// Title/label for the flow that makes the app the default PDF handler.
  ///
  /// In en, this message translates to:
  /// **'Set up as default application'**
  String get settingsSetUpAsDefault;

  /// Section header for system integration settings (default app, dev tools).
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystem;

  /// Dark theme mode option.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Light theme mode option.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme mode option that follows the operating system light/dark setting.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Title of the app settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Status line shown when the running build is the newest available.
  ///
  /// In en, this message translates to:
  /// **'You’re on the latest version ({version}).'**
  String settingsUpToDate(String version);

  /// Status line shown when a newer app version is available.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available (you have {currentVersion}).'**
  String settingsUpdateAvailable(String version, String currentVersion);

  /// Status line shown when an update check failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t check for updates. Try again later.'**
  String get settingsUpdateFailed;

  /// Status line shown before any update check has run, naming the current app and version.
  ///
  /// In en, this message translates to:
  /// **'You have {name} {version}.'**
  String settingsUpdateIdle(String name, String version);

  /// Windows-only setting that opts into rolling test builds from main.
  ///
  /// In en, this message translates to:
  /// **'Nightly updates'**
  String get settingsNightlyUpdates;

  /// Explains the risk and behavior of the nightly update channel.
  ///
  /// In en, this message translates to:
  /// **'Receive automatic update notifications for unsigned Windows test builds from main.'**
  String get settingsNightlyUpdatesSubtitle;

  /// Section header for the software-update block in settings.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdates;

  /// Link that opens the project's source repository on GitHub.
  ///
  /// In en, this message translates to:
  /// **'View source on GitHub'**
  String get settingsViewSource;

  /// Generic button/tooltip to undo the last change.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Primary button on the welcome screen that opens a PDF file.
  ///
  /// In en, this message translates to:
  /// **'Open a PDF'**
  String get welcomeOpenPdf;

  /// Subtitle for a recent file that must be re-selected from disk to reopen.
  ///
  /// In en, this message translates to:
  /// **'Pick again to reopen'**
  String get welcomePickAgainToReopen;

  /// Header for the recent-documents list on the welcome screen.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get welcomeRecent;

  /// Tooltip on the button that removes an entry from the recent-files list.
  ///
  /// In en, this message translates to:
  /// **'Remove from recent'**
  String get welcomeRemoveFromRecent;

  /// Subtitle for a recent file that can be reopened directly from a saved snapshot.
  ///
  /// In en, this message translates to:
  /// **'Tap to reopen'**
  String get welcomeTapToReopen;

  /// Tooltip on the toggle that shows recent documents as a thumbnail grid.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get welcomeViewAsGrid;

  /// Tooltip on the toggle that shows recent documents as a list.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get welcomeViewAsList;

  /// One-line hint on the Settings row explaining how to make DartPDF the default PDF app; the arm is chosen by the running platform.
  ///
  /// In en, this message translates to:
  /// **'{platform, select, web{Install the web app, then choose it for PDF files.} windows{Open Windows default apps settings for PDFs.} macos{Follow Finder’s “Always Open With” steps.} linux{Use your desktop’s default applications settings.} android{Choose DartPDF when opening a PDF, then tap Always.} ios{Use Share or Open In from Files to send PDFs here.} other{Configure your system’s PDF file handler.}}'**
  String settingsDefaultAppSubtitle(String platform);

  /// Full platform-specific steps for making DartPDF the default PDF app, shown in the setup dialog.
  ///
  /// In en, this message translates to:
  /// **'{platform, select, web{Install DartPDF from your browser first. Then use the browser or operating system file-handler settings to associate PDF files with the installed app.} windows{Windows Settings will open to Default apps. Search for “.pdf” or “PDF”, choose the current PDF app, then select DartPDF.} macos{In Finder, select any PDF, choose File > Get Info, expand “Open with”, pick DartPDF, then click “Change All…”.} linux{Open your desktop settings for Default Applications, or right-click a PDF in Files, choose Properties, and set DartPDF as the default for PDF documents.} android{Open a PDF from Files or Downloads, choose DartPDF in the app picker, then select Always. If another app already opens PDFs, clear that app’s defaults in Android Settings first.} ios{iOS does not provide a global default PDF editor. Use Files > Share, or long-press a PDF and choose Share/Open In, then pick DartPDF.} other{Use the system settings for file handlers to associate PDF documents with DartPDF.}}'**
  String settingsDefaultAppInstructions(String platform);

  /// OCR progress chip while the recognition model downloads (size unknown).
  ///
  /// In en, this message translates to:
  /// **'Downloading OCR model…'**
  String get ocrChipDownloadingModel;

  /// OCR progress chip while the recognition model downloads, with percent.
  ///
  /// In en, this message translates to:
  /// **'Downloading model {percent}%'**
  String ocrChipDownloadingModelPercent(int percent);

  /// OCR progress chip while recognizing text, showing page of total.
  ///
  /// In en, this message translates to:
  /// **'OCR {page}/{pageCount}'**
  String ocrChipRecognising(int page, int pageCount);

  /// OCR progress chip while assembling the recognized PDF after the last page.
  ///
  /// In en, this message translates to:
  /// **'Finishing OCR…'**
  String get ocrChipFinishing;

  /// File-picker filter label for PDF files.
  ///
  /// In en, this message translates to:
  /// **'PDF documents'**
  String get fileTypePdf;

  /// File-picker filter label for PNG/JPEG image files.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get fileTypeImages;

  /// File-picker filter label for exported custom-stamp JSON bundles.
  ///
  /// In en, this message translates to:
  /// **'DartPDF stamps'**
  String get fileTypeStampBundle;

  /// File-picker filter label when choosing a private key to sign with.
  ///
  /// In en, this message translates to:
  /// **'RSA private keys'**
  String get appSigKeyFileType;

  /// File-picker filter label when choosing signing certificates.
  ///
  /// In en, this message translates to:
  /// **'X.509 certificates'**
  String get appSigCertificateFileType;

  /// Signing error: the user picked a key but no certificate.
  ///
  /// In en, this message translates to:
  /// **'Select at least one X.509 certificate.'**
  String get appSigErrorNoCertificateSelected;

  /// Signing error: a chosen certificate file could not be parsed as X.509.
  ///
  /// In en, this message translates to:
  /// **'Certificate {index} is not valid X.509.'**
  String appSigErrorInvalidCertificate(int index);

  /// Signing error: the key pairs with none of the chosen certificates.
  ///
  /// In en, this message translates to:
  /// **'The private key does not match any selected RSA certificate.'**
  String get appSigErrorKeyCertificateMismatch;

  /// Signing error: the chosen private key is an encrypted PEM.
  ///
  /// In en, this message translates to:
  /// **'Encrypted private keys are not supported. Choose an unencrypted RSA PKCS#1 or PKCS#8 key.'**
  String get appSigErrorEncryptedKeyUnsupported;

  /// Signing error: the chosen private key could not be read as RSA.
  ///
  /// In en, this message translates to:
  /// **'The private key is not an unencrypted RSA PKCS#1 or PKCS#8 key.'**
  String get appSigErrorKeyNotRsa;

  /// Signing error: the chosen files contained no X.509 certificate.
  ///
  /// In en, this message translates to:
  /// **'No X.509 certificates were found.'**
  String get appSigErrorNoCertificateFound;

  /// Bottom-sheet option (mobile only) that photographs the picture to insert with the device camera.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get imageSourceTakePhoto;

  /// Bottom-sheet option (mobile only) that picks the picture to insert from a file instead of the camera.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get imageSourceChooseFile;

  /// Toast shown when the camera cannot be opened - no camera on the device, or access refused.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t take a photo'**
  String get imageSourceCameraFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'en',
        'es',
        'fr',
        'hi',
        'id',
        'it',
        'ja',
        'ko',
        'nl',
        'pl',
        'pt',
        'ru',
        'th',
        'tr',
        'uk',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'nl':
      return AppLocalizationsNl();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'th':
      return AppLocalizationsTh();
    case 'tr':
      return AppLocalizationsTr();
    case 'uk':
      return AppLocalizationsUk();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

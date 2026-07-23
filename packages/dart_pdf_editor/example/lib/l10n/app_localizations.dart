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
import 'app_localizations_ja.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
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
    Locale('ja'),
    Locale('pt'),
    Locale('ru'),
    Locale('zh')
  ];

  /// Generic button that adds a new item.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

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

  /// Toast surfacing a PDF JavaScript action's script to the host app.
  ///
  /// In en, this message translates to:
  /// **'JavaScript surfaced to the app: {script}'**
  String exActionJavaScript(String script);

  /// Toast describing a URI link action followed by the target URI.
  ///
  /// In en, this message translates to:
  /// **'Link: {uri}'**
  String exActionLink(String uri);

  /// Toast describing a PDF named action.
  ///
  /// In en, this message translates to:
  /// **'Named action: {name}'**
  String exActionNamed(String name);

  /// Toast describing an unhandled PDF action type.
  ///
  /// In en, this message translates to:
  /// **'Unhandled action type: {type}'**
  String exActionUnhandled(String type);

  /// Toast confirming an annotation's text was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Annotation text copied'**
  String get exAnnotationTextCopied;

  /// Helper text explaining how the OCR API key is transmitted.
  ///
  /// In en, this message translates to:
  /// **'Sent as Authorization: Bearer …'**
  String get exApiKeyHelper;

  /// Text-field label for the optional OCR API key or token.
  ///
  /// In en, this message translates to:
  /// **'API key / token (optional)'**
  String get exApiKeyLabel;

  /// Tooltip for the app's main menu button.
  ///
  /// In en, this message translates to:
  /// **'DartPDF menu'**
  String get exAppMenuTooltip;

  /// Menu action that clears the recent-files list.
  ///
  /// In en, this message translates to:
  /// **'Clear recent files'**
  String get exClearRecentFiles;

  /// Tooltip for the button that closes a document tab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get exCloseTab;

  /// Title of a document-comparison tab, naming the before and after files.
  ///
  /// In en, this message translates to:
  /// **'Compare: {before} ↔ {after}'**
  String exCompareTabTitle(String before, String after);

  /// App menu item that compares the active document against a second PDF.
  ///
  /// In en, this message translates to:
  /// **'Compare with another PDF…'**
  String get exCompareWithAnother;

  /// Toast confirming the selected text was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get exCopiedToClipboard;

  /// Tooltip for the app-bar button that copies the current text selection.
  ///
  /// In en, this message translates to:
  /// **'Copy selected text (⌘C)'**
  String get exCopySelectedText;

  /// Annotation right-click menu item that copies the annotation's text.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get exCopyText;

  /// Error-tab body when a picked file could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open {name}\n{error}'**
  String exCouldNotOpenFile(String name, String error);

  /// Error-tab body when a file at a given path could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open {path}\n{error}'**
  String exCouldNotOpenPath(String path, String error);

  /// Toast when an external link could not be launched.
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String exCouldNotOpenUrl(String url);

  /// Error-tab body when a remote PDF could not be opened, with a CORS hint.
  ///
  /// In en, this message translates to:
  /// **'Could not open {uri}\n{error}\n\nOn the web this is often a CORS restriction: the server must send Access-Control-Allow-Origin and expose the Range headers.'**
  String exCouldNotOpenUrlCors(String uri, String error);

  /// Error-tab body when a recent file could not be reopened.
  ///
  /// In en, this message translates to:
  /// **'Could not reopen {title}\n{error}'**
  String exCouldNotReopen(String title, String error);

  /// Error-tab body when a recent file's cached bytes have aged out.
  ///
  /// In en, this message translates to:
  /// **'Could not reopen {title} - its saved copy is no longer available.'**
  String exCouldNotReopenGone(String title);

  /// Hint text in the demo's floating note text box overlaying the page.
  ///
  /// In en, this message translates to:
  /// **'Type here - this text box floats above the page'**
  String get exDemoNoteHint;

  /// Toast confirming the feedback diagnostics were copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied to clipboard'**
  String get exDiagnosticsCopied;

  /// Toast confirming a file was downloaded (web/save flow).
  ///
  /// In en, this message translates to:
  /// **'Downloaded {name}'**
  String exDownloaded(String name);

  /// Toast after downloading a snapshot PNG, with a Ctrl+V paste hint (web/Windows/Linux).
  ///
  /// In en, this message translates to:
  /// **'Downloaded {name} - paste back into the PDF with Ctrl+V'**
  String exDownloadedSnapshotCtrl(String name);

  /// Button that confirms the image export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exExport;

  /// Toast when exporting a page image failed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exExportFailed(String error);

  /// App menu item that exports the current page as a raster image.
  ///
  /// In en, this message translates to:
  /// **'Export page as image…'**
  String get exExportPageImageMenu;

  /// Title of the export-page-as-image dialog.
  ///
  /// In en, this message translates to:
  /// **'Export page as image'**
  String get exExportPageImageTitle;

  /// Tab title for the built-in feature-showcase demo document.
  ///
  /// In en, this message translates to:
  /// **'Feature showcase'**
  String get exFeatureShowcase;

  /// Label for the image-format selector in the export dialog.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get exFormat;

  /// Tooltip to obscure the OCR API key field.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get exHide;

  /// App menu item that switches the viewer to horizontal continuous layout.
  ///
  /// In en, this message translates to:
  /// **'Horizontal page layout'**
  String get exHorizontalLayout;

  /// Button that opens documentation on setting up an OCR server.
  ///
  /// In en, this message translates to:
  /// **'How to set up an OCR server'**
  String get exHowToSetupOcr;

  /// Text-field label for the OCR model name.
  ///
  /// In en, this message translates to:
  /// **'Model name'**
  String get exModelName;

  /// Fallback toast when an app:// message action carries no text.
  ///
  /// In en, this message translates to:
  /// **'No message'**
  String get exNoMessage;

  /// Placeholder shown when there are no recently opened files.
  ///
  /// In en, this message translates to:
  /// **'No recent files'**
  String get exNoRecentFiles;

  /// Error-tab body when the entered remote-open text is not a valid URL.
  ///
  /// In en, this message translates to:
  /// **'Not a valid URL:\n{url}'**
  String exNotAValidUrl(String url);

  /// Toast reporting how many selectable text spans OCR added.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{OCR added 1 text span - the page text is now selectable} other{OCR added {count} text spans - the page text is now selectable}}'**
  String exOcrAddedSpans(int count);

  /// Explanatory text in the OCR settings dialog about what OCR does.
  ///
  /// In en, this message translates to:
  /// **'Adds a selectable, searchable text layer over scanned pages using a vision-language OCR model you host (dots.ocr on vLLM, or any OpenAI-compatible OCR endpoint).'**
  String get exOcrDescription;

  /// Tab title for the OCR result, suffixing the source document's title.
  ///
  /// In en, this message translates to:
  /// **'{title} (OCR)'**
  String exOcrDocumentTitle(String title);

  /// Toast when the OCR run failed.
  ///
  /// In en, this message translates to:
  /// **'OCR failed: {error}'**
  String exOcrFailed(String error);

  /// App menu item that starts the OCR text-layer flow.
  ///
  /// In en, this message translates to:
  /// **'OCR…'**
  String get exOcrMenu;

  /// Button that confirms opening the entered remote PDF URL.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get exOpen;

  /// Toast prompting the user to open a document before running OCR.
  ///
  /// In en, this message translates to:
  /// **'Open a document before running OCR'**
  String get exOpenDocumentBeforeOcr;

  /// Toast prompting the user to open a document before exporting an image.
  ///
  /// In en, this message translates to:
  /// **'Open a document first'**
  String get exOpenDocumentFirst;

  /// App menu item that opens a PDF from a remote URL.
  ///
  /// In en, this message translates to:
  /// **'Open from a URL…'**
  String get exOpenFromUrl;

  /// Title of the open-from-URL dialog.
  ///
  /// In en, this message translates to:
  /// **'Open from a URL'**
  String get exOpenFromUrlTitle;

  /// Tooltip for the tab-strip button that opens a PDF in a new tab.
  ///
  /// In en, this message translates to:
  /// **'Open PDF in a new tab'**
  String get exOpenInNewTab;

  /// App menu item that opens the built-in feature-showcase demo document.
  ///
  /// In en, this message translates to:
  /// **'Open the interactive demo'**
  String get exOpenInteractiveDemo;

  /// App menu item that opens a PDF from the file picker.
  ///
  /// In en, this message translates to:
  /// **'Open a PDF…'**
  String get exOpenPdf;

  /// Empty-state button that opens a PDF from the file picker.
  ///
  /// In en, this message translates to:
  /// **'Open a PDF'**
  String get exOpenPdfButton;

  /// App menu row that expands into the list of recently opened files.
  ///
  /// In en, this message translates to:
  /// **'Open Recent'**
  String get exOpenRecent;

  /// Explanatory text in the open-from-URL dialog about how remote loading works.
  ///
  /// In en, this message translates to:
  /// **'Streams the PDF over HTTP Range requests via PdfHttpByteSource, fetching only what the parser needs and falling back to a full download when the server has no range support.'**
  String get exOpenUrlDescription;

  /// Accessibility label for the document-loading progress region.
  ///
  /// In en, this message translates to:
  /// **'Opening document'**
  String get exOpeningDocument;

  /// Loading label while an untitled PDF is opening.
  ///
  /// In en, this message translates to:
  /// **'Opening PDF…'**
  String get exOpeningPdf;

  /// Loading label while a named document is opening.
  ///
  /// In en, this message translates to:
  /// **'Opening {title}…'**
  String exOpeningTitle(String title);

  /// Text-field label for the remote PDF URL in the open-from-URL dialog.
  ///
  /// In en, this message translates to:
  /// **'PDF URL'**
  String get exPdfUrlLabel;

  /// Worker-pool tooltip when the pool size is chosen automatically.
  ///
  /// In en, this message translates to:
  /// **'Performance: Auto'**
  String get exPerformanceAuto;

  /// Initial OCR progress message before page recognition begins.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get exPreparing;

  /// App menu item that opens the dart_pdf_editor package page on pub.dev.
  ///
  /// In en, this message translates to:
  /// **'dart_pdf_editor on pub.dev'**
  String get exPubDevMenuItem;

  /// OCR progress message naming the page being recognised and the total.
  ///
  /// In en, this message translates to:
  /// **'Recognising page {current} of {count}…'**
  String exRecognisingPage(int current, int count);

  /// Label for the resolution selector in the export dialog.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get exResolution;

  /// Title and confirm button of the OCR settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Run OCR'**
  String get exRunOcr;

  /// App menu item that saves the active document to a new file.
  ///
  /// In en, this message translates to:
  /// **'Save as…'**
  String get exSaveAs;

  /// Toast when saving a file failed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String exSaveFailed(String error);

  /// Toast confirming a file with the given name was saved.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}'**
  String exSavedName(String name);

  /// Toast after saving a snapshot PNG, with a Command-V paste hint (macOS).
  ///
  /// In en, this message translates to:
  /// **'Saved {name} - paste back into the PDF with ⌘V'**
  String exSavedSnapshotCmd(String name);

  /// Toast confirming the document was saved to a given path.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String exSavedTo(String path);

  /// App menu item that opens the scroll-indicator API demo screen.
  ///
  /// In en, this message translates to:
  /// **'Scroll indicator API demo'**
  String get exScrollIndicatorDemo;

  /// Text-field label for the OCR service endpoint URL.
  ///
  /// In en, this message translates to:
  /// **'Service endpoint'**
  String get exServiceEndpoint;

  /// Tooltip to reveal the obscured OCR API key field.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get exShow;

  /// Worker-pool menu item that pins the pool to a single background worker.
  ///
  /// In en, this message translates to:
  /// **'Single worker'**
  String get exSingleWorker;

  /// App menu item that opens the feedback dialog.
  ///
  /// In en, this message translates to:
  /// **'Supply feedback…'**
  String get exSupplyFeedback;

  /// App menu item that switches the viewer from read-only to edit mode.
  ///
  /// In en, this message translates to:
  /// **'Switch to edit mode'**
  String get exSwitchToEdit;

  /// App menu item that switches the viewer from edit mode to read-only.
  ///
  /// In en, this message translates to:
  /// **'Switch to read-only'**
  String get exSwitchToReadOnly;

  /// Theme-cycle menu label when the current theme is dark (next tap: system).
  ///
  /// In en, this message translates to:
  /// **'Theme: dark - switch to system'**
  String get exThemeDark;

  /// Theme-cycle menu label when the current theme is light (next tap: dark).
  ///
  /// In en, this message translates to:
  /// **'Theme: light - switch to dark'**
  String get exThemeLight;

  /// Theme-cycle menu label when the current theme is system (next tap: light).
  ///
  /// In en, this message translates to:
  /// **'Theme: system - switch to light'**
  String get exThemeSystem;

  /// Empty-state button that opens the interactive demo document.
  ///
  /// In en, this message translates to:
  /// **'Try the interactive demo'**
  String get exTryDemo;

  /// Fallback title for a document or tab with no name.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get exUntitled;

  /// App menu item that switches the viewer to vertical continuous layout.
  ///
  /// In en, this message translates to:
  /// **'Vertical page layout'**
  String get exVerticalLayout;

  /// App menu item that opens the project's GitHub repository.
  ///
  /// In en, this message translates to:
  /// **'View source on GitHub'**
  String get exViewSource;

  /// Worker-pool menu item that lets the app choose the pool size automatically.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get exWorkerAuto;

  /// Worker-pool tooltip showing the fixed number of background workers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Performance: single worker} other{Performance: {count} workers}}'**
  String exWorkerPoolTooltip(int count);

  /// Worker-pool menu item pinning the pool to a fixed number of workers.
  ///
  /// In en, this message translates to:
  /// **'{count} workers'**
  String exWorkersCount(int count);

  /// Checkbox label to attach the captured diagnostics to the feedback report.
  ///
  /// In en, this message translates to:
  /// **'Attach these diagnostics to the report'**
  String get feedbackAttachDiagnostics;

  /// Button that clears the captured diagnostics log.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get feedbackClearLog;

  /// Button that copies the diagnostics report to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get feedbackCopyDiagnostics;

  /// Notice in the feedback dialog explaining how diagnostics are used and privacy.
  ///
  /// In en, this message translates to:
  /// **'The feedback form opens in your browser. The diagnostics below are collected on this device only and are attached to help reproduce the problem. Review them first - do not include anything you would rather keep private.'**
  String get feedbackDiagnosticsNotice;

  /// Button that opens the GitHub feedback form with the report prefilled.
  ///
  /// In en, this message translates to:
  /// **'Open feedback form'**
  String get feedbackOpenForm;

  /// Title of the feedback dialog.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get feedbackTitle;

  /// Label for the absence of a selection or value.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

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

  /// Tooltip for the next-page button in the scroll-indicator demo.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get scrollDemoNextPage;

  /// Page bubble shown while dragging the demo scrubber (current page of total).
  ///
  /// In en, this message translates to:
  /// **'Page {current} / {count}'**
  String scrollDemoPageBubble(int current, int count);

  /// Tooltip for the previous-page button in the scroll-indicator demo.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get scrollDemoPreviousPage;

  /// Tooltip toggling the demo viewer to horizontal continuous layout.
  ///
  /// In en, this message translates to:
  /// **'Switch to horizontal layout'**
  String get scrollDemoSwitchHorizontal;

  /// Tooltip toggling the demo viewer to vertical continuous layout.
  ///
  /// In en, this message translates to:
  /// **'Switch to vertical layout'**
  String get scrollDemoSwitchVertical;

  /// App-bar title of the scroll-indicator API demo screen.
  ///
  /// In en, this message translates to:
  /// **'Scroll indicator API'**
  String get scrollDemoTitle;

  /// Generic button/tooltip to undo the last change.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// File-picker filter label for PDF files.
  ///
  /// In en, this message translates to:
  /// **'PDF documents'**
  String get exFileTypePdf;

  /// File-picker filter label for image files.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get exFileTypeImages;

  /// File-picker filter label for TrueType/OpenType font files.
  ///
  /// In en, this message translates to:
  /// **'Fonts'**
  String get exFileTypeFonts;
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
        'ja',
        'pt',
        'ru',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
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
    case 'ja':
      return AppLocalizationsJa();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

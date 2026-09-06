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
  String exActionJavaScript(String script) {
    return 'JavaScript surfaced to the app: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Link: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Named action: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Unhandled action type: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Annotation text copied';

  @override
  String get exApiKeyHelper => 'Sent as Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'API key / token (optional)';

  @override
  String get exAppMenuTooltip => 'DartPDF menu';

  @override
  String get exClearRecentFiles => 'Clear recent files';

  @override
  String get exCloseTab => 'Close tab';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Compare: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Compare with another PDF…';

  @override
  String get exCopiedToClipboard => 'Copied to clipboard';

  @override
  String get exCopySelectedText => 'Copy selected text (⌘C)';

  @override
  String get exCopyText => 'Copy text';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Could not open $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Could not open $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Could not open $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Could not open $uri\n$error\n\nOn the web this is often a CORS restriction: the server must send Access-Control-Allow-Origin and expose the Range headers.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Could not reopen $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Could not reopen $title - its saved copy is no longer available.';
  }

  @override
  String get exDemoNoteHint =>
      'Type here - this text box floats above the page';

  @override
  String get exDiagnosticsCopied => 'Diagnostics copied to clipboard';

  @override
  String exDownloaded(String name) {
    return 'Downloaded $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Downloaded $name - paste back into the PDF with Ctrl+V';
  }

  @override
  String get exExport => 'Export';

  @override
  String exExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get exExportPageImageMenu => 'Export page as image…';

  @override
  String get exExportPageImageTitle => 'Export page as image';

  @override
  String get exFeatureShowcase => 'Feature showcase';

  @override
  String get exFormat => 'Format';

  @override
  String get exHide => 'Hide';

  @override
  String get exHorizontalLayout => 'Horizontal page layout';

  @override
  String get exHowToSetupOcr => 'How to set up an OCR server';

  @override
  String get exModelName => 'Model name';

  @override
  String get exNoMessage => 'No message';

  @override
  String get exNoRecentFiles => 'No recent files';

  @override
  String exNotAValidUrl(String url) {
    return 'Not a valid URL:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR added $count text spans - the page text is now selectable',
      one: 'OCR added 1 text span - the page text is now selectable',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Adds a selectable, searchable text layer over scanned pages using a vision-language OCR model you host (dots.ocr on vLLM, or any OpenAI-compatible OCR endpoint).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR failed: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Open';

  @override
  String get exOpenDocumentBeforeOcr => 'Open a document before running OCR';

  @override
  String get exOpenDocumentFirst => 'Open a document first';

  @override
  String get exOpenFromUrl => 'Open from a URL…';

  @override
  String get exOpenFromUrlTitle => 'Open from a URL';

  @override
  String get exOpenInNewTab => 'Open PDF in a new tab';

  @override
  String get exOpenInteractiveDemo => 'Open the interactive demo';

  @override
  String get exOpenPdf => 'Open a PDF…';

  @override
  String get exOpenPdfButton => 'Open a PDF';

  @override
  String get exOpenRecent => 'Open Recent';

  @override
  String get exOpenUrlDescription =>
      'Streams the PDF over HTTP Range requests via PdfHttpByteSource, fetching only what the parser needs and falling back to a full download when the server has no range support.';

  @override
  String get exOpeningDocument => 'Opening document';

  @override
  String get exOpeningPdf => 'Opening PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Opening $title…';
  }

  @override
  String get exPdfUrlLabel => 'PDF URL';

  @override
  String get exPerformanceAuto => 'Performance: Auto';

  @override
  String get exPreparing => 'Preparing…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor on pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Recognizing page $current of $count…';
  }

  @override
  String get exResolution => 'Resolution';

  @override
  String get exRunOcr => 'Run OCR';

  @override
  String get exSaveAs => 'Save as…';

  @override
  String exSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Saved $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Saved $name - paste back into the PDF with ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Scroll indicator API demo';

  @override
  String get exServiceEndpoint => 'Service endpoint';

  @override
  String get exShow => 'Show';

  @override
  String get exSingleWorker => 'Single worker';

  @override
  String get exSupplyFeedback => 'Supply feedback…';

  @override
  String get exSwitchToEdit => 'Switch to edit mode';

  @override
  String get exSwitchToReadOnly => 'Switch to read-only';

  @override
  String get exThemeDark => 'Theme: dark - switch to system';

  @override
  String get exThemeLight => 'Theme: light - switch to dark';

  @override
  String get exThemeSystem => 'Theme: system - switch to light';

  @override
  String get exTryDemo => 'Try the interactive demo';

  @override
  String get exUntitled => 'Untitled';

  @override
  String get exVerticalLayout => 'Vertical page layout';

  @override
  String get exViewSource => 'View source on GitHub';

  @override
  String get exWorkerAuto => 'Auto';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Performance: $count workers',
      one: 'Performance: single worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count workers';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Attach these diagnostics to the report';

  @override
  String get feedbackClearLog => 'Clear log';

  @override
  String get feedbackCopyDiagnostics => 'Copy diagnostics';

  @override
  String get feedbackDiagnosticsNotice =>
      'The feedback form opens in your browser. The diagnostics below are collected on this device only and are attached to help reproduce the problem. Review them first - do not include anything you would rather keep private.';

  @override
  String get feedbackOpenForm => 'Open feedback form';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get none => 'None';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Paste';

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
  String get scrollDemoNextPage => 'Next page';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Page $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Previous page';

  @override
  String get scrollDemoSwitchHorizontal => 'Switch to horizontal layout';

  @override
  String get scrollDemoSwitchVertical => 'Switch to vertical layout';

  @override
  String get scrollDemoTitle => 'Scroll indicator API';

  @override
  String get undo => 'Undo';

  @override
  String get exFileTypePdf => 'PDF documents';

  @override
  String get exFileTypeImages => 'Images';

  @override
  String get exFileTypeFonts => 'Fonts';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - part $part.pdf';
  }
}

/// The translations for English, as used in Australia (`en_AU`).
class AppLocalizationsEnAu extends AppLocalizationsEn {
  AppLocalizationsEnAu() : super('en_AU');

  @override
  String get add => 'Add';

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
  String exActionJavaScript(String script) {
    return 'JavaScript surfaced to the app: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Link: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Named action: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Unhandled action type: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Annotation text copied';

  @override
  String get exApiKeyHelper => 'Sent as Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'API key / token (optional)';

  @override
  String get exAppMenuTooltip => 'DartPDF menu';

  @override
  String get exClearRecentFiles => 'Clear recent files';

  @override
  String get exCloseTab => 'Close tab';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Compare: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Compare with another PDF…';

  @override
  String get exCopiedToClipboard => 'Copied to clipboard';

  @override
  String get exCopySelectedText => 'Copy selected text (⌘C)';

  @override
  String get exCopyText => 'Copy text';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Could not open $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Could not open $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Could not open $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Could not open $uri\n$error\n\nOn the web this is often a CORS restriction: the server must send Access-Control-Allow-Origin and expose the Range headers.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Could not reopen $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Could not reopen $title - its saved copy is no longer available.';
  }

  @override
  String get exDemoNoteHint =>
      'Type here - this text box floats above the page';

  @override
  String get exDiagnosticsCopied => 'Diagnostics copied to clipboard';

  @override
  String exDownloaded(String name) {
    return 'Downloaded $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Downloaded $name - paste back into the PDF with Ctrl+V';
  }

  @override
  String get exExport => 'Export';

  @override
  String exExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get exExportPageImageMenu => 'Export page as image…';

  @override
  String get exExportPageImageTitle => 'Export page as image';

  @override
  String get exFeatureShowcase => 'Feature showcase';

  @override
  String get exFormat => 'Format';

  @override
  String get exHide => 'Hide';

  @override
  String get exHorizontalLayout => 'Horizontal page layout';

  @override
  String get exHowToSetupOcr => 'How to set up an OCR server';

  @override
  String get exModelName => 'Model name';

  @override
  String get exNoMessage => 'No message';

  @override
  String get exNoRecentFiles => 'No recent files';

  @override
  String exNotAValidUrl(String url) {
    return 'Not a valid URL:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR added $count text spans - the page text is now selectable',
      one: 'OCR added 1 text span - the page text is now selectable',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Adds a selectable, searchable text layer over scanned pages using a vision-language OCR model you host (dots.ocr on vLLM, or any OpenAI-compatible OCR endpoint).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR failed: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Open';

  @override
  String get exOpenDocumentBeforeOcr => 'Open a document before running OCR';

  @override
  String get exOpenDocumentFirst => 'Open a document first';

  @override
  String get exOpenFromUrl => 'Open from a URL…';

  @override
  String get exOpenFromUrlTitle => 'Open from a URL';

  @override
  String get exOpenInNewTab => 'Open PDF in a new tab';

  @override
  String get exOpenInteractiveDemo => 'Open the interactive demo';

  @override
  String get exOpenPdf => 'Open a PDF…';

  @override
  String get exOpenPdfButton => 'Open a PDF';

  @override
  String get exOpenRecent => 'Open Recent';

  @override
  String get exOpenUrlDescription =>
      'Streams the PDF over HTTP Range requests via PdfHttpByteSource, fetching only what the parser needs and falling back to a full download when the server has no range support.';

  @override
  String get exOpeningDocument => 'Opening document';

  @override
  String get exOpeningPdf => 'Opening PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Opening $title…';
  }

  @override
  String get exPdfUrlLabel => 'PDF URL';

  @override
  String get exPerformanceAuto => 'Performance: Auto';

  @override
  String get exPreparing => 'Preparing…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor on pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Recognising page $current of $count…';
  }

  @override
  String get exResolution => 'Resolution';

  @override
  String get exRunOcr => 'Run OCR';

  @override
  String get exSaveAs => 'Save as…';

  @override
  String exSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Saved $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Saved $name - paste back into the PDF with ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Scroll indicator API demo';

  @override
  String get exServiceEndpoint => 'Service endpoint';

  @override
  String get exShow => 'Show';

  @override
  String get exSingleWorker => 'Single worker';

  @override
  String get exSupplyFeedback => 'Supply feedback…';

  @override
  String get exSwitchToEdit => 'Switch to edit mode';

  @override
  String get exSwitchToReadOnly => 'Switch to read-only';

  @override
  String get exThemeDark => 'Theme: dark - switch to system';

  @override
  String get exThemeLight => 'Theme: light - switch to dark';

  @override
  String get exThemeSystem => 'Theme: system - switch to light';

  @override
  String get exTryDemo => 'Try the interactive demo';

  @override
  String get exUntitled => 'Untitled';

  @override
  String get exVerticalLayout => 'Vertical page layout';

  @override
  String get exViewSource => 'View source on GitHub';

  @override
  String get exWorkerAuto => 'Auto';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Performance: $count workers',
      one: 'Performance: single worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count workers';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Attach these diagnostics to the report';

  @override
  String get feedbackClearLog => 'Clear log';

  @override
  String get feedbackCopyDiagnostics => 'Copy diagnostics';

  @override
  String get feedbackDiagnosticsNotice =>
      'The feedback form opens in your browser. The diagnostics below are collected on this device only and are attached to help reproduce the problem. Review them first - do not include anything you would rather keep private.';

  @override
  String get feedbackOpenForm => 'Open feedback form';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get none => 'None';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Paste';

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
  String get scrollDemoNextPage => 'Next page';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Page $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Previous page';

  @override
  String get scrollDemoSwitchHorizontal => 'Switch to horizontal layout';

  @override
  String get scrollDemoSwitchVertical => 'Switch to vertical layout';

  @override
  String get scrollDemoTitle => 'Scroll indicator API';

  @override
  String get undo => 'Undo';

  @override
  String get exFileTypePdf => 'PDF documents';

  @override
  String get exFileTypeImages => 'Images';

  @override
  String get exFileTypeFonts => 'Fonts';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - part $part.pdf';
  }
}

/// The translations for English, as used in the United Kingdom (`en_GB`).
class AppLocalizationsEnGb extends AppLocalizationsEn {
  AppLocalizationsEnGb() : super('en_GB');

  @override
  String get add => 'Add';

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
  String exActionJavaScript(String script) {
    return 'JavaScript surfaced to the app: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Link: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Named action: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Unhandled action type: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Annotation text copied';

  @override
  String get exApiKeyHelper => 'Sent as Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'API key / token (optional)';

  @override
  String get exAppMenuTooltip => 'DartPDF menu';

  @override
  String get exClearRecentFiles => 'Clear recent files';

  @override
  String get exCloseTab => 'Close tab';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Compare: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Compare with another PDF…';

  @override
  String get exCopiedToClipboard => 'Copied to clipboard';

  @override
  String get exCopySelectedText => 'Copy selected text (⌘C)';

  @override
  String get exCopyText => 'Copy text';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Could not open $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Could not open $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Could not open $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Could not open $uri\n$error\n\nOn the web this is often a CORS restriction: the server must send Access-Control-Allow-Origin and expose the Range headers.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Could not reopen $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Could not reopen $title - its saved copy is no longer available.';
  }

  @override
  String get exDemoNoteHint =>
      'Type here - this text box floats above the page';

  @override
  String get exDiagnosticsCopied => 'Diagnostics copied to clipboard';

  @override
  String exDownloaded(String name) {
    return 'Downloaded $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Downloaded $name - paste back into the PDF with Ctrl+V';
  }

  @override
  String get exExport => 'Export';

  @override
  String exExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get exExportPageImageMenu => 'Export page as image…';

  @override
  String get exExportPageImageTitle => 'Export page as image';

  @override
  String get exFeatureShowcase => 'Feature showcase';

  @override
  String get exFormat => 'Format';

  @override
  String get exHide => 'Hide';

  @override
  String get exHorizontalLayout => 'Horizontal page layout';

  @override
  String get exHowToSetupOcr => 'How to set up an OCR server';

  @override
  String get exModelName => 'Model name';

  @override
  String get exNoMessage => 'No message';

  @override
  String get exNoRecentFiles => 'No recent files';

  @override
  String exNotAValidUrl(String url) {
    return 'Not a valid URL:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR added $count text spans - the page text is now selectable',
      one: 'OCR added 1 text span - the page text is now selectable',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Adds a selectable, searchable text layer over scanned pages using a vision-language OCR model you host (dots.ocr on vLLM, or any OpenAI-compatible OCR endpoint).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR failed: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Open';

  @override
  String get exOpenDocumentBeforeOcr => 'Open a document before running OCR';

  @override
  String get exOpenDocumentFirst => 'Open a document first';

  @override
  String get exOpenFromUrl => 'Open from a URL…';

  @override
  String get exOpenFromUrlTitle => 'Open from a URL';

  @override
  String get exOpenInNewTab => 'Open PDF in a new tab';

  @override
  String get exOpenInteractiveDemo => 'Open the interactive demo';

  @override
  String get exOpenPdf => 'Open a PDF…';

  @override
  String get exOpenPdfButton => 'Open a PDF';

  @override
  String get exOpenRecent => 'Open Recent';

  @override
  String get exOpenUrlDescription =>
      'Streams the PDF over HTTP Range requests via PdfHttpByteSource, fetching only what the parser needs and falling back to a full download when the server has no range support.';

  @override
  String get exOpeningDocument => 'Opening document';

  @override
  String get exOpeningPdf => 'Opening PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Opening $title…';
  }

  @override
  String get exPdfUrlLabel => 'PDF URL';

  @override
  String get exPerformanceAuto => 'Performance: Auto';

  @override
  String get exPreparing => 'Preparing…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor on pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Recognising page $current of $count…';
  }

  @override
  String get exResolution => 'Resolution';

  @override
  String get exRunOcr => 'Run OCR';

  @override
  String get exSaveAs => 'Save as…';

  @override
  String exSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Saved $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Saved $name - paste back into the PDF with ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Scroll indicator API demo';

  @override
  String get exServiceEndpoint => 'Service endpoint';

  @override
  String get exShow => 'Show';

  @override
  String get exSingleWorker => 'Single worker';

  @override
  String get exSupplyFeedback => 'Supply feedback…';

  @override
  String get exSwitchToEdit => 'Switch to edit mode';

  @override
  String get exSwitchToReadOnly => 'Switch to read-only';

  @override
  String get exThemeDark => 'Theme: dark - switch to system';

  @override
  String get exThemeLight => 'Theme: light - switch to dark';

  @override
  String get exThemeSystem => 'Theme: system - switch to light';

  @override
  String get exTryDemo => 'Try the interactive demo';

  @override
  String get exUntitled => 'Untitled';

  @override
  String get exVerticalLayout => 'Vertical page layout';

  @override
  String get exViewSource => 'View source on GitHub';

  @override
  String get exWorkerAuto => 'Auto';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Performance: $count workers',
      one: 'Performance: single worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count workers';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Attach these diagnostics to the report';

  @override
  String get feedbackClearLog => 'Clear log';

  @override
  String get feedbackCopyDiagnostics => 'Copy diagnostics';

  @override
  String get feedbackDiagnosticsNotice =>
      'The feedback form opens in your browser. The diagnostics below are collected on this device only and are attached to help reproduce the problem. Review them first - do not include anything you would rather keep private.';

  @override
  String get feedbackOpenForm => 'Open feedback form';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get none => 'None';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Paste';

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
  String get scrollDemoNextPage => 'Next page';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Page $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Previous page';

  @override
  String get scrollDemoSwitchHorizontal => 'Switch to horizontal layout';

  @override
  String get scrollDemoSwitchVertical => 'Switch to vertical layout';

  @override
  String get scrollDemoTitle => 'Scroll indicator API';

  @override
  String get undo => 'Undo';

  @override
  String get exFileTypePdf => 'PDF documents';

  @override
  String get exFileTypeImages => 'Images';

  @override
  String get exFileTypeFonts => 'Fonts';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - part $part.pdf';
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'dart_pdf_printing_localizations_ar.dart';
import 'dart_pdf_printing_localizations_de.dart';
import 'dart_pdf_printing_localizations_en.dart';
import 'dart_pdf_printing_localizations_es.dart';
import 'dart_pdf_printing_localizations_fr.dart';
import 'dart_pdf_printing_localizations_hi.dart';
import 'dart_pdf_printing_localizations_id.dart';
import 'dart_pdf_printing_localizations_it.dart';
import 'dart_pdf_printing_localizations_ja.dart';
import 'dart_pdf_printing_localizations_ko.dart';
import 'dart_pdf_printing_localizations_nl.dart';
import 'dart_pdf_printing_localizations_pl.dart';
import 'dart_pdf_printing_localizations_pt.dart';
import 'dart_pdf_printing_localizations_ru.dart';
import 'dart_pdf_printing_localizations_th.dart';
import 'dart_pdf_printing_localizations_tr.dart';
import 'dart_pdf_printing_localizations_uk.dart';
import 'dart_pdf_printing_localizations_vi.dart';
import 'dart_pdf_printing_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of DartPdfPrintingLocalizations
/// returned by `DartPdfPrintingLocalizations.of(context)`.
///
/// Applications need to include `DartPdfPrintingLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/dart_pdf_printing_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: DartPdfPrintingLocalizations.localizationsDelegates,
///   supportedLocales: DartPdfPrintingLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the DartPdfPrintingLocalizations.supportedLocales
/// property.
abstract class DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static DartPdfPrintingLocalizations? of(BuildContext context) {
    return Localizations.of<DartPdfPrintingLocalizations>(
        context, DartPdfPrintingLocalizations);
  }

  static const LocalizationsDelegate<DartPdfPrintingLocalizations> delegate =
      _DartPdfPrintingLocalizationsDelegate();

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
    Locale('en', 'AU'),
    Locale('en', 'GB'),
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

  /// Button that dismisses a dialog without applying.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

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

  /// Shown in place of the preview when a page could not be rendered.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable'**
  String get printPreviewUnavailable;

  /// Print settings dialog: Printer
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get printOptionsPrinter;

  /// Print settings dialog: Choose the printer, paper tray, color, duplex and device properties in the system print dialog next. Keep its scale at 100% and copies at 1 to use the layout shown here.
  ///
  /// In en, this message translates to:
  /// **'Choose the printer, paper tray, color, duplex and device properties in the system print dialog next. Keep its scale at 100% and copies at 1 to use the layout shown here.'**
  String get printOptionsNativePrinter;

  /// Print settings dialog: Pages
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get printOptionsPages;

  /// Print settings dialog: Selected
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get printOptionsSelected;

  /// Print settings dialog: Pages (for example, 1, 3-5)
  ///
  /// In en, this message translates to:
  /// **'Pages (for example, 1, 3-5)'**
  String get printOptionsPageRange;

  /// Print settings dialog: Add files…
  ///
  /// In en, this message translates to:
  /// **'Add files…'**
  String get printOptionsAddFiles;

  /// Print settings dialog: Could not add the selected files.
  ///
  /// In en, this message translates to:
  /// **'Could not add the selected files.'**
  String get printOptionsAddFailed;

  /// Print settings dialog: Get window
  ///
  /// In en, this message translates to:
  /// **'Get window'**
  String get printOptionsGetWindow;

  /// Print settings dialog: Clear window
  ///
  /// In en, this message translates to:
  /// **'Clear window'**
  String get printOptionsClearWindow;

  /// Print settings dialog: Drag a rectangle on this source page to choose the area to print.
  ///
  /// In en, this message translates to:
  /// **'Drag a rectangle on this source page to choose the area to print.'**
  String get printOptionsWindowHint;

  /// Print settings dialog: Paper
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get printOptionsPaper;

  /// Print settings dialog: Paper size
  ///
  /// In en, this message translates to:
  /// **'Paper size'**
  String get printOptionsPaperSize;

  /// Print settings dialog: Use document page size
  ///
  /// In en, this message translates to:
  /// **'Use document page size'**
  String get printOptionsPageSize;

  /// Print settings dialog: Orientation
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get printOptionsOrientation;

  /// Print settings dialog: Auto
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get printOptionsAuto;

  /// Print settings dialog: Portrait
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get printOptionsPortrait;

  /// Print settings dialog: Landscape
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get printOptionsLandscape;

  /// Print settings dialog: Copies
  ///
  /// In en, this message translates to:
  /// **'Copies'**
  String get printOptionsCopies;

  /// Print settings dialog: Collate
  ///
  /// In en, this message translates to:
  /// **'Collate'**
  String get printOptionsCollate;

  /// Print settings dialog: Reverse page order
  ///
  /// In en, this message translates to:
  /// **'Reverse page order'**
  String get printOptionsReverse;

  /// Print settings dialog: Page layout
  ///
  /// In en, this message translates to:
  /// **'Page layout'**
  String get printOptionsLayout;

  /// Print settings dialog: Page scaling
  ///
  /// In en, this message translates to:
  /// **'Page scaling'**
  String get printOptionsScaling;

  /// Print settings dialog: None (actual size)
  ///
  /// In en, this message translates to:
  /// **'None (actual size)'**
  String get printOptionsScaleNone;

  /// Print settings dialog: Fit to paper
  ///
  /// In en, this message translates to:
  /// **'Fit to paper'**
  String get printOptionsFitPaper;

  /// Print settings dialog: Reduce to paper
  ///
  /// In en, this message translates to:
  /// **'Reduce to paper'**
  String get printOptionsReducePaper;

  /// Print settings dialog: Fit to margins
  ///
  /// In en, this message translates to:
  /// **'Fit to margins'**
  String get printOptionsFitMargins;

  /// Print settings dialog: Reduce to margins
  ///
  /// In en, this message translates to:
  /// **'Reduce to margins'**
  String get printOptionsReduceMargins;

  /// Print settings dialog: Custom scale
  ///
  /// In en, this message translates to:
  /// **'Custom scale'**
  String get printOptionsCustomScale;

  /// Print settings dialog: Multiple pages per sheet
  ///
  /// In en, this message translates to:
  /// **'Multiple pages per sheet'**
  String get printOptionsMultiple;

  /// Print settings dialog: Scale (%)
  ///
  /// In en, this message translates to:
  /// **'Scale (%)'**
  String get printOptionsScalePercent;

  /// Print settings dialog: Margins (pt)
  ///
  /// In en, this message translates to:
  /// **'Margins (pt)'**
  String get printOptionsMargin;

  /// Print settings dialog: Pages per sheet
  ///
  /// In en, this message translates to:
  /// **'Pages per sheet'**
  String get printOptionsPagesPerSheet;

  /// Print settings dialog: Page order
  ///
  /// In en, this message translates to:
  /// **'Page order'**
  String get printOptionsPageOrder;

  /// Print settings dialog: Horizontal
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get printOptionsHorizontal;

  /// Print settings dialog: Horizontal reversed
  ///
  /// In en, this message translates to:
  /// **'Horizontal reversed'**
  String get printOptionsHorizontalReverse;

  /// Print settings dialog: Vertical
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get printOptionsVertical;

  /// Print settings dialog: Vertical reversed
  ///
  /// In en, this message translates to:
  /// **'Vertical reversed'**
  String get printOptionsVerticalReverse;

  /// Print settings dialog: Print page borders
  ///
  /// In en, this message translates to:
  /// **'Print page borders'**
  String get printOptionsBorder;

  /// Print settings dialog: Rotation (clockwise)
  ///
  /// In en, this message translates to:
  /// **'Rotation (clockwise)'**
  String get printOptionsRotation;

  /// Print settings dialog: None
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get printOptionsNoRotation;

  /// Print settings dialog: Center on paper
  ///
  /// In en, this message translates to:
  /// **'Center on paper'**
  String get printOptionsCenter;

  /// Print settings dialog: Offset right (pt)
  ///
  /// In en, this message translates to:
  /// **'Offset right (pt)'**
  String get printOptionsOffsetX;

  /// Print settings dialog: Offset down (pt)
  ///
  /// In en, this message translates to:
  /// **'Offset down (pt)'**
  String get printOptionsOffsetY;

  /// Print settings dialog: Print contents
  ///
  /// In en, this message translates to:
  /// **'Print contents'**
  String get printOptionsContents;

  /// Print settings dialog: Document and markups
  ///
  /// In en, this message translates to:
  /// **'Document and markups'**
  String get printOptionsDocumentAndMarkups;

  /// Print settings dialog: Document only
  ///
  /// In en, this message translates to:
  /// **'Document only'**
  String get printOptionsDocumentOnly;

  /// Print settings dialog: Markups only
  ///
  /// In en, this message translates to:
  /// **'Markups only'**
  String get printOptionsMarkupsOnly;

  /// Print settings dialog: Dim page content
  ///
  /// In en, this message translates to:
  /// **'Dim page content'**
  String get printOptionsDimPage;

  /// Print settings dialog: Dim markups
  ///
  /// In en, this message translates to:
  /// **'Dim markups'**
  String get printOptionsDimMarkups;

  /// Print settings dialog: Print visible hyperlinks
  ///
  /// In en, this message translates to:
  /// **'Print visible hyperlinks'**
  String get printOptionsHyperlinks;

  /// Print settings dialog: Defaults
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get printOptionsDefaults;

  /// Print settings dialog: Enter valid numbers before printing.
  ///
  /// In en, this message translates to:
  /// **'Enter valid numbers before printing.'**
  String get printOptionsInvalidNumber;

  /// Print settings dialog: Invalid value
  ///
  /// In en, this message translates to:
  /// **'Invalid value'**
  String get printOptionsInvalidValue;

  /// Print settings dialog: Red lines show the margins; they do not print.
  ///
  /// In en, this message translates to:
  /// **'Red lines show the margins; they do not print.'**
  String get printOptionsMarginGuide;

  /// Print settings preview label.
  ///
  /// In en, this message translates to:
  /// **'Window: {width} × {height} pt'**
  String printOptionsAreaSize(String width, String height);

  /// Print settings preview label.
  ///
  /// In en, this message translates to:
  /// **'Source: {width} × {height} pt'**
  String printOptionsSourceSize(String width, String height);

  /// Print settings preview label.
  ///
  /// In en, this message translates to:
  /// **'Sheet: {width} × {height} pt'**
  String printOptionsSheetSize(String width, String height);

  /// Print settings preview label.
  ///
  /// In en, this message translates to:
  /// **'Sheet {sheet} of {total}'**
  String printOptionsSheetOf(int sheet, int total);

  /// Print settings validation when the sheet cannot be composed.
  ///
  /// In en, this message translates to:
  /// **'This layout could not be prepared. Check the paper size, margins and scale.'**
  String get printOptionsInvalidLayout;

  /// Placeholder asking the user to select the printer for direct Windows printing.
  ///
  /// In en, this message translates to:
  /// **'Choose a printer'**
  String get printOptionsChoosePrinter;

  /// Empty state when Windows has no installed printers, with recovery instructions.
  ///
  /// In en, this message translates to:
  /// **'No printers are installed. Add a printer in Windows Settings, then retry.'**
  String get printOptionsNoPrinters;

  /// Error when the printer saved in print preferences is no longer available.
  ///
  /// In en, this message translates to:
  /// **'The saved printer \"{printer}\" is unavailable. Choose a printer to continue.'**
  String printOptionsPrinterUnavailable(String printer);

  /// Error when printer settings cannot be read, with connection and retry advice.
  ///
  /// In en, this message translates to:
  /// **'Could not load printer settings. Check the printer connection and retry.'**
  String get printOptionsPrinterError;

  /// Button that retries loading the installed printers and their settings.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get printOptionsRetry;

  /// Option for printing the document in color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get printOptionsColor;

  /// Option for printing the document in black and white.
  ///
  /// In en, this message translates to:
  /// **'Black and white'**
  String get printOptionsGrayscale;

  /// Label for the printer duplex mode selector.
  ///
  /// In en, this message translates to:
  /// **'Two-sided printing'**
  String get printOptionsDuplex;

  /// Option for printing on only one side of each sheet.
  ///
  /// In en, this message translates to:
  /// **'One-sided'**
  String get printOptionsSimplex;

  /// Duplex printing option that flips sheets along the long edge.
  ///
  /// In en, this message translates to:
  /// **'Flip on long edge'**
  String get printOptionsLongEdge;

  /// Duplex printing option that flips sheets along the short edge.
  ///
  /// In en, this message translates to:
  /// **'Flip on short edge'**
  String get printOptionsShortEdge;

  /// Label for the printer paper tray selector.
  ///
  /// In en, this message translates to:
  /// **'Paper tray'**
  String get printOptionsTray;

  /// Paper tray option that uses the printer default.
  ///
  /// In en, this message translates to:
  /// **'Printer default'**
  String get printOptionsDefaultTray;

  /// Button that opens the selected Windows printer driver properties.
  ///
  /// In en, this message translates to:
  /// **'Printer properties…'**
  String get printOptionsProperties;

  /// Explains that the Print button sends the job directly to the selected printer.
  ///
  /// In en, this message translates to:
  /// **'Print sends this job directly to the selected printer.'**
  String get printOptionsDirectPrinter;

  /// Error when the Windows printer driver properties cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open printer properties.'**
  String get printOptionsPropertiesError;

  /// Status while Windows printers are being loaded.
  ///
  /// In en, this message translates to:
  /// **'Loading printers…'**
  String get printOptionsLoadingPrinters;
}

class _DartPdfPrintingLocalizationsDelegate
    extends LocalizationsDelegate<DartPdfPrintingLocalizations> {
  const _DartPdfPrintingLocalizationsDelegate();

  @override
  Future<DartPdfPrintingLocalizations> load(Locale locale) {
    return SynchronousFuture<DartPdfPrintingLocalizations>(
        lookupDartPdfPrintingLocalizations(locale));
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
  bool shouldReload(_DartPdfPrintingLocalizationsDelegate old) => false;
}

DartPdfPrintingLocalizations lookupDartPdfPrintingLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return DartPdfPrintingLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'AU':
            return DartPdfPrintingLocalizationsEnAu();
          case 'GB':
            return DartPdfPrintingLocalizationsEnGb();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return DartPdfPrintingLocalizationsAr();
    case 'de':
      return DartPdfPrintingLocalizationsDe();
    case 'en':
      return DartPdfPrintingLocalizationsEn();
    case 'es':
      return DartPdfPrintingLocalizationsEs();
    case 'fr':
      return DartPdfPrintingLocalizationsFr();
    case 'hi':
      return DartPdfPrintingLocalizationsHi();
    case 'id':
      return DartPdfPrintingLocalizationsId();
    case 'it':
      return DartPdfPrintingLocalizationsIt();
    case 'ja':
      return DartPdfPrintingLocalizationsJa();
    case 'ko':
      return DartPdfPrintingLocalizationsKo();
    case 'nl':
      return DartPdfPrintingLocalizationsNl();
    case 'pl':
      return DartPdfPrintingLocalizationsPl();
    case 'pt':
      return DartPdfPrintingLocalizationsPt();
    case 'ru':
      return DartPdfPrintingLocalizationsRu();
    case 'th':
      return DartPdfPrintingLocalizationsTh();
    case 'tr':
      return DartPdfPrintingLocalizationsTr();
    case 'uk':
      return DartPdfPrintingLocalizationsUk();
    case 'vi':
      return DartPdfPrintingLocalizationsVi();
    case 'zh':
      return DartPdfPrintingLocalizationsZh();
  }

  throw FlutterError(
      'DartPdfPrintingLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class DartPdfPrintingLocalizationsEn extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

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
  String get printPreviewUnavailable => 'Preview unavailable';

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

  @override
  String get printOptionsChoosePrinter => 'Choose a printer';

  @override
  String get printOptionsNoPrinters =>
      'No printers are installed. Add a printer in Windows Settings, then retry.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'The saved printer \"$printer\" is unavailable. Choose a printer to continue.';
  }

  @override
  String get printOptionsPrinterError =>
      'Could not load printer settings. Check the printer connection and retry.';

  @override
  String get printOptionsRetry => 'Retry';

  @override
  String get printOptionsColor => 'Color';

  @override
  String get printOptionsGrayscale => 'Black and white';

  @override
  String get printOptionsDuplex => 'Two-sided printing';

  @override
  String get printOptionsSimplex => 'One-sided';

  @override
  String get printOptionsLongEdge => 'Flip on long edge';

  @override
  String get printOptionsShortEdge => 'Flip on short edge';

  @override
  String get printOptionsTray => 'Paper tray';

  @override
  String get printOptionsDefaultTray => 'Printer default';

  @override
  String get printOptionsProperties => 'Printer properties…';

  @override
  String get printOptionsDirectPrinter =>
      'Print sends this job directly to the selected printer.';

  @override
  String get printOptionsPropertiesError =>
      'Could not open printer properties.';

  @override
  String get printOptionsLoadingPrinters => 'Loading printers…';
}

/// The translations for English, as used in Australia (`en_AU`).
class DartPdfPrintingLocalizationsEnAu extends DartPdfPrintingLocalizationsEn {
  DartPdfPrintingLocalizationsEnAu() : super('en_AU');

  @override
  String get cancel => 'Cancel';

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
  String get printPreviewUnavailable => 'Preview unavailable';

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

  @override
  String get printOptionsChoosePrinter => 'Choose a printer';

  @override
  String get printOptionsNoPrinters =>
      'No printers are installed. Add a printer in Windows Settings, then retry.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'The saved printer \"$printer\" is unavailable. Choose a printer to continue.';
  }

  @override
  String get printOptionsPrinterError =>
      'Could not load printer settings. Check the printer connection and retry.';

  @override
  String get printOptionsRetry => 'Retry';

  @override
  String get printOptionsColor => 'Colour';

  @override
  String get printOptionsGrayscale => 'Black and white';

  @override
  String get printOptionsDuplex => 'Two-sided printing';

  @override
  String get printOptionsSimplex => 'One-sided';

  @override
  String get printOptionsLongEdge => 'Flip on long edge';

  @override
  String get printOptionsShortEdge => 'Flip on short edge';

  @override
  String get printOptionsTray => 'Paper tray';

  @override
  String get printOptionsDefaultTray => 'Printer default';

  @override
  String get printOptionsProperties => 'Printer properties…';

  @override
  String get printOptionsDirectPrinter =>
      'Print sends this job directly to the selected printer.';

  @override
  String get printOptionsPropertiesError =>
      'Could not open printer properties.';

  @override
  String get printOptionsLoadingPrinters => 'Loading printers…';
}

/// The translations for English, as used in the United Kingdom (`en_GB`).
class DartPdfPrintingLocalizationsEnGb extends DartPdfPrintingLocalizationsEn {
  DartPdfPrintingLocalizationsEnGb() : super('en_GB');

  @override
  String get cancel => 'Cancel';

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
  String get printPreviewUnavailable => 'Preview unavailable';

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

  @override
  String get printOptionsChoosePrinter => 'Choose a printer';

  @override
  String get printOptionsNoPrinters =>
      'No printers are installed. Add a printer in Windows Settings, then retry.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'The saved printer \"$printer\" is unavailable. Choose a printer to continue.';
  }

  @override
  String get printOptionsPrinterError =>
      'Could not load printer settings. Check the printer connection and retry.';

  @override
  String get printOptionsRetry => 'Retry';

  @override
  String get printOptionsColor => 'Colour';

  @override
  String get printOptionsGrayscale => 'Black and white';

  @override
  String get printOptionsDuplex => 'Two-sided printing';

  @override
  String get printOptionsSimplex => 'One-sided';

  @override
  String get printOptionsLongEdge => 'Flip on long edge';

  @override
  String get printOptionsShortEdge => 'Flip on short edge';

  @override
  String get printOptionsTray => 'Paper tray';

  @override
  String get printOptionsDefaultTray => 'Printer default';

  @override
  String get printOptionsProperties => 'Printer properties…';

  @override
  String get printOptionsDirectPrinter =>
      'Print sends this job directly to the selected printer.';

  @override
  String get printOptionsPropertiesError =>
      'Could not open printer properties.';

  @override
  String get printOptionsLoadingPrinters => 'Loading printers…';
}

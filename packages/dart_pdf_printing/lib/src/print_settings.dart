import 'package:pdf_document/pdf_document.dart';

enum PrintPaperSize { auto, a0, a1, a2, a3, a4, a5, letter, legal, tabloid }

extension PrintPaperDimensions on PrintPaperSize {
  /// Physical paper dimensions in PDF points (72 points per inch).
  (double, double)? get dimensions => switch (this) {
        PrintPaperSize.auto => null,
        PrintPaperSize.a0 => (841 * 72 / 25.4, 1189 * 72 / 25.4),
        PrintPaperSize.a1 => (594 * 72 / 25.4, 841 * 72 / 25.4),
        PrintPaperSize.a2 => (420 * 72 / 25.4, 594 * 72 / 25.4),
        PrintPaperSize.a3 => (297 * 72 / 25.4, 420 * 72 / 25.4),
        PrintPaperSize.a4 => (210 * 72 / 25.4, 297 * 72 / 25.4),
        PrintPaperSize.a5 => (148 * 72 / 25.4, 210 * 72 / 25.4),
        PrintPaperSize.letter => (612, 792),
        PrintPaperSize.legal => (612, 1008),
        PrintPaperSize.tabloid => (792, 1224),
      };
}

enum PrintOrientation { auto, portrait, landscape }

enum PrintScaling {
  none,
  fitPaper,
  reducePaper,
  custom,
  fitMargins,
  reduceMargins,
  multiple,
}

enum PrintRotation { auto, none, clockwise90, halfTurn, clockwise270 }

enum PrintPageLayout {
  horizontal,
  horizontalReverse,
  vertical,
  verticalReverse
}

enum PrintContent { documentAndMarkups, documentOnly, markupsOnly }

/// A snapshot of a print job. All lengths are physical PDF points, except
/// [region], which uses the viewer's rotated page coordinates before UserUnit.
class PrintSettings {
  PrintSettings({
    required List<int> pages,
    this.paperSize = PrintPaperSize.auto,
    this.orientation = PrintOrientation.auto,
    this.scaling = PrintScaling.none,
    this.rotation = PrintRotation.auto,
    this.customScale = 100,
    this.margin = 18,
    this.offsetX = 0,
    this.offsetY = 0,
    this.center = true,
    this.pagesPerSheet = 2,
    this.layout = PrintPageLayout.horizontal,
    this.printBorder = false,
    this.content = PrintContent.documentAndMarkups,
    this.dimPageContent = false,
    this.dimMarkups = false,
    this.printVisibleHyperlinks = true,
    this.copies = 1,
    this.collate = true,
    this.reverse = false,
    this.region,
  }) : pages = List.unmodifiable(pages);

  final List<int> pages;
  final PrintPaperSize paperSize;
  final PrintOrientation orientation;
  final PrintScaling scaling;
  final PrintRotation rotation;
  final double customScale;
  final double margin;

  /// Positive offsets move right and down on the printed sheet.
  final double offsetX;
  final double offsetY;
  final bool center;
  final int pagesPerSheet;
  final PrintPageLayout layout;
  final bool printBorder;
  final PrintContent content;
  final bool dimPageContent;
  final bool dimMarkups;
  final bool printVisibleHyperlinks;
  final int copies;
  final bool collate;
  final bool reverse;

  /// Display-space crop: left, top, right, bottom, in rotated page units,
  /// with y growing down. Only valid for a single selected source page.
  /// PdfRect's `bottom` member therefore carries the display-space top.
  final PdfRect? region;

  PrintSettings copyWith({
    List<int>? pages,
    PrintPaperSize? paperSize,
    PrintOrientation? orientation,
    PrintScaling? scaling,
    PrintRotation? rotation,
    double? customScale,
    double? margin,
    double? offsetX,
    double? offsetY,
    bool? center,
    int? pagesPerSheet,
    PrintPageLayout? layout,
    bool? printBorder,
    PrintContent? content,
    bool? dimPageContent,
    bool? dimMarkups,
    bool? printVisibleHyperlinks,
    int? copies,
    bool? collate,
    bool? reverse,
    PdfRect? region,
    bool clearRegion = false,
  }) =>
      PrintSettings(
        pages: pages ?? this.pages,
        paperSize: paperSize ?? this.paperSize,
        orientation: orientation ?? this.orientation,
        scaling: scaling ?? this.scaling,
        rotation: rotation ?? this.rotation,
        customScale: customScale ?? this.customScale,
        margin: margin ?? this.margin,
        offsetX: offsetX ?? this.offsetX,
        offsetY: offsetY ?? this.offsetY,
        center: center ?? this.center,
        pagesPerSheet: pagesPerSheet ?? this.pagesPerSheet,
        layout: layout ?? this.layout,
        printBorder: printBorder ?? this.printBorder,
        content: content ?? this.content,
        dimPageContent: dimPageContent ?? this.dimPageContent,
        dimMarkups: dimMarkups ?? this.dimMarkups,
        printVisibleHyperlinks:
            printVisibleHyperlinks ?? this.printVisibleHyperlinks,
        copies: copies ?? this.copies,
        collate: collate ?? this.collate,
        reverse: reverse ?? this.reverse,
        region: clearRegion ? null : region ?? this.region,
      );
}

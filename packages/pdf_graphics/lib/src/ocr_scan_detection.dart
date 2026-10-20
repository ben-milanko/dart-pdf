import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'text_extraction.dart';

/// The share of a page that its images must cover for [pdfPageLooksScanned]
/// to call it a scan.
const double defaultScanImageCoverage = 0.5;

/// How many leading pages [pdfDocumentLooksScanned] samples by default.
const int defaultScanSamplePages = 3;

/// How much text (non-whitespace characters) a scanned page may already
/// carry - a Bates number, a digitally stamped header - for
/// [pdfPageLooksScanned] to still call it a scan.
const int defaultScanMaxTextChars = 64;

/// Whether page [pageIndex] of [document] looks like a scan that OCR would
/// make selectable: raster images cover at least [minImageCoverage] of its
/// crop box, it carries at most [maxTextChars] characters of text, and it
/// has no invisible (`3 Tr`) text layer - the mark an earlier OCR pass,
/// ours or another tool's, leaves behind.
///
/// A page whose own resources declare no image XObject and whose content has
/// no inline image is rejected before any interpretation, so a born-digital
/// page costs one dictionary walk. Images reached only through a form XObject
/// are not looked for there - a conservative miss, never a false positive.
/// Malformed pages answer false.
bool pdfPageLooksScanned(
  PdfDocument document,
  int pageIndex, {
  double minImageCoverage = defaultScanImageCoverage,
  int maxTextChars = defaultScanMaxTextChars,
}) {
  try {
    final page = document.page(pageIndex);
    if (!_mayDrawImage(document, page)) return false;
    final reflow = PdfTextExtractor.reflowPage(document, pageIndex);
    final box = page.cropBox;
    final pageArea = box.width * box.height;
    if (pageArea <= 0) return false;
    var covered = 0.0;
    for (final image in reflow.images) {
      covered += _intersectionArea(image.bounds, box);
    }
    if (covered / pageArea < minImageCoverage) return false;
    if (reflow.text.replaceAll(_whitespace, '').length > maxTextChars) {
      return false;
    }
    return !_invisibleText.hasMatch(String.fromCharCodes(page.contentBytes()));
  } on Object {
    return false;
  }
}

/// Whether [document] looks like a scanned document worth running OCR over:
/// at least one of its first [samplePages] pages passes
/// [pdfPageLooksScanned]. A born-digital document with a scanned appendix far
/// in is deliberately not sampled - the check runs as a document opens, so it
/// stays bounded.
bool pdfDocumentLooksScanned(
  PdfDocument document, {
  int samplePages = defaultScanSamplePages,
  double minImageCoverage = defaultScanImageCoverage,
  int maxTextChars = defaultScanMaxTextChars,
}) {
  final int count;
  try {
    count = math.min(document.pageCount, samplePages);
  } on Object {
    return false;
  }
  for (var i = 0; i < count; i++) {
    if (pdfPageLooksScanned(document, i,
        minImageCoverage: minImageCoverage, maxTextChars: maxTextChars)) {
      return true;
    }
  }
  return false;
}

final _whitespace = RegExp(r'\s');

/// A `3 Tr` (invisible text render mode, §9.3.6) operation.
final _invisibleText = RegExp(r'(^|[\s\]\)>])3\s+Tr(?![A-Za-z])');

bool _mayDrawImage(PdfDocument document, PdfPage page) {
  final cos = document.cos;
  final xObjects = cos.resolve(page.resources['XObject']);
  if (xObjects is CosDictionary) {
    for (final entry in xObjects.entries.values) {
      final object = cos.resolve(entry);
      if (object is CosStream) {
        final subtype = object.dictionary['Subtype'];
        if (subtype is CosName && subtype.value == 'Image') return true;
      }
    }
  }
  return _hasInlineImage(page.contentBytes());
}

/// Whether [content] contains a `BI` operator token.
bool _hasInlineImage(List<int> content) {
  bool delimiter(int c) =>
      c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C;
  for (var i = 0; i + 1 < content.length; i++) {
    if (content[i] == 0x42 /* B */ &&
        content[i + 1] == 0x49 /* I */ &&
        (i == 0 || delimiter(content[i - 1])) &&
        (i + 2 >= content.length || delimiter(content[i + 2]))) {
      return true;
    }
  }
  return false;
}

double _intersectionArea(PdfRect a, PdfRect b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.top, b.top) - math.max(a.bottom, b.bottom);
  return w <= 0 || h <= 0 ? 0 : w * h;
}

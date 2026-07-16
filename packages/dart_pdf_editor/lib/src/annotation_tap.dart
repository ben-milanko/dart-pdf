import 'dart:ui';

import 'package:pdf_document/pdf_document.dart';

/// Called when the user taps or clicks a visible PDF annotation.
typedef PdfAnnotationTapHandler = void Function(
    PdfAnnotationTapDetails details);

/// Information about a PDF annotation tap.
class PdfAnnotationTapDetails {
  const PdfAnnotationTapDetails({
    required this.annotation,
    required this.pageIndex,
    required this.pagePoint,
    required this.pageViewPosition,
    required this.globalPosition,
  });

  /// The annotation hit by the tap.
  final PdfAnnotation annotation;

  /// Zero-based page index containing [annotation].
  final int pageIndex;

  /// Tap location in PDF page coordinates, in points.
  final Offset pagePoint;

  /// Tap location in the displayed page widget's local coordinates.
  final Offset pageViewPosition;

  /// Tap location in global Flutter coordinates.
  final Offset globalPosition;
}

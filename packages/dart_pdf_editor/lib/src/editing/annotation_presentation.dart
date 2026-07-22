import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../l10n/pdf_l10n.dart';
import 'line_style.dart';

/// Flutter-only presentation for PDF annotation subtypes.
///
/// Semantic editing policy lives in `PdfAnnotation.behavior` in
/// pdf_document; Material names and icons stay above the Flutter boundary.
/// The subtype string is the stable key; the visible name is resolved from
/// the localizations so the same mapping serves every consumer.
String pdfAnnotationLabel(BuildContext context, String subtype) {
  final l = pdfL10n(context);
  return switch (subtype) {
    'Highlight' => l.annotHighlight,
    'Underline' => l.annotUnderline,
    'StrikeOut' => l.annotStrikeOut,
    'Squiggly' => l.annotSquiggly,
    'Ink' => l.annotInk,
    'Square' => l.annotSquare,
    'Circle' => l.annotCircle,
    'Line' => l.annotLine,
    'Polygon' => l.annotPolygon,
    'PolyLine' => l.annotPolyline,
    'FreeText' => l.annotFreeText,
    'Text' => l.annotText,
    'Stamp' => l.annotStamp,
    'Link' => l.annotLink,
    'Widget' => l.annotWidget,
    'FileAttachment' => l.annotFileAttachment,
    'Caret' => l.annotCaret,
    'Redact' => l.annotRedact,
    _ => subtype,
  };
}

/// The localized name of a border [PdfLineStyle] (Solid/Dashed/…), for the
/// line-style pickers. The enum is the stable key.
String pdfLineStyleLabel(BuildContext context, PdfLineStyle style) {
  final l = pdfL10n(context);
  return switch (style) {
    PdfLineStyle.solid => l.lineStyleSolid,
    PdfLineStyle.dashed => l.lineStyleDashed,
    PdfLineStyle.dotted => l.lineStyleDotted,
    PdfLineStyle.dashDot => l.lineStyleDashDot,
  };
}

/// The localized name of a [PdfMeasurementKind], for the takeoff register
/// and measurement chrome.
String pdfMeasurementKindLabel(BuildContext context, PdfMeasurementKind kind) {
  final l = pdfL10n(context);
  return switch (kind) {
    PdfMeasurementKind.count => l.measKindCount,
    PdfMeasurementKind.distance => l.measKindLength,
    PdfMeasurementKind.perimeter => l.measKindPerimeter,
    PdfMeasurementKind.area => l.measKindArea,
    PdfMeasurementKind.areaCutout => l.measKindNetArea,
    PdfMeasurementKind.volume => l.measKindVolume,
    PdfMeasurementKind.angle => l.measKindAngle,
    PdfMeasurementKind.arc => l.measKindArc,
    PdfMeasurementKind.slope => l.measKindSlope,
  };
}

/// The localized name of a [PdfLineEnding] (None/Square/Open arrow/…), for
/// the line-ending pickers. Shared by the toolbar strip and the
/// Properties panel.
String pdfLineEndingLabel(BuildContext context, PdfLineEnding ending) {
  final l = pdfL10n(context);
  return switch (ending) {
    PdfLineEnding.none => l.none,
    PdfLineEnding.square => l.propLineEndingSquare,
    PdfLineEnding.circle => l.propLineEndingCircle,
    PdfLineEnding.diamond => l.propLineEndingDiamond,
    PdfLineEnding.openArrow => l.propLineEndingOpenArrow,
    PdfLineEnding.closedArrow => l.propLineEndingClosedArrow,
    PdfLineEnding.butt => l.propLineEndingButt,
    PdfLineEnding.rOpenArrow => l.propLineEndingOpenArrowRev,
    PdfLineEnding.rClosedArrow => l.propLineEndingClosedArrowRev,
    PdfLineEnding.slash => l.propLineEndingSlash,
  };
}

IconData pdfAnnotationIcon(String subtype) => switch (subtype) {
      'Highlight' => Icons.border_color,
      'Underline' => Icons.format_underlined,
      'StrikeOut' => Icons.format_strikethrough,
      'Squiggly' => Icons.gesture,
      'Ink' => Icons.draw,
      'Square' => Icons.rectangle_outlined,
      'Circle' => Icons.circle_outlined,
      'FreeText' => Icons.text_fields,
      'Text' => Icons.sticky_note_2_outlined,
      'Stamp' => Icons.approval,
      'Link' => Icons.link,
      'Widget' => Icons.input,
      'FileAttachment' => Icons.attach_file,
      _ => Icons.bookmark_border,
    };

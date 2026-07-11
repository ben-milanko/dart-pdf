import 'package:flutter/material.dart';

/// Flutter-only presentation for PDF annotation subtypes.
///
/// Semantic editing policy lives in `PdfAnnotation.behavior` in
/// pdf_document; Material names and icons stay above the Flutter boundary.
String pdfAnnotationLabel(String subtype) => switch (subtype) {
      'StrikeOut' => 'Strike-out',
      'FreeText' => 'Text box',
      'Text' => 'Note',
      'Widget' => 'Form field',
      _ => subtype,
    };

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

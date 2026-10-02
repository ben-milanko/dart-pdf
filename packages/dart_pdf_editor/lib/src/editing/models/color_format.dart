// The colour picker's value-row format, kept apart from the Material picker
// in editing_color_picker.dart (which re-exports it) so the persisted
// preferences can name it without importing flutter/material.
// See tool/check_design_imports.dart.

/// The value-entry formats [PdfColorPicker] can show: hex (the default),
/// RGB (0–255), HSL (degrees and percentages), and CMYK (percentages -
/// a naive device conversion for entry and display; the committed color
/// is still RGB, no color management is applied).
enum PdfColorFormat {
  hex('HEX'),
  rgb('RGB'),
  hsl('HSL'),
  cmyk('CMYK');

  const PdfColorFormat(this.label);

  /// The switcher's display name.
  final String label;
}

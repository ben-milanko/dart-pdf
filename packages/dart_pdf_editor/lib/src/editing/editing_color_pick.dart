import 'package:flutter/material.dart';

import 'editing_color_picker.dart';
import 'editing_controller.dart';

/// Opens the full colour picker for an editing session, wiring its
/// quick-pick grids from [controller]: the "Recent" grid from
/// `PdfEditingPreferences.recentColors` and the "In document" grid from
/// [PdfEditingController.documentAnnotationColors]. The value-entry format
/// is restored from and persisted back to the preferences, and a committed
/// colour is recorded as a recent.
///
/// Returns the chosen colour, or null when the dialog is dismissed. This is
/// the entry point the editing chrome should use instead of
/// [showPdfColorPicker] directly, so recents and document colours show up
/// everywhere a colour is chosen.
Future<Color?> pickEditingColor(
  BuildContext context,
  PdfEditingController controller, {
  required Color initial,
}) async {
  final preferences = controller.preferences;
  final picked = await showPdfColorPicker(
    context,
    initial: initial,
    initialFormat: preferences.colorPickerFormat,
    onFormatChanged: (format) => preferences.colorPickerFormat = format,
    recentColors: preferences.recentColors,
    documentColors: controller.documentAnnotationColors(),
  );
  if (picked != null) preferences.noteRecentColor(picked);
  return picked;
}

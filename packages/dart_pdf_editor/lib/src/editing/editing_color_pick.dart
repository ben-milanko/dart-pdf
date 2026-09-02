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
/// The picker also offers the eyedropper, so any colour choice can be
/// sampled off the page and not just the annotation colour the toolbar's
/// own eyedropper sets. Pressing it takes the dialog down (it is covering
/// the page it would sample), arms
/// [PdfEditingController.pickColorFromPage], and reopens the picker on the
/// sampled colour so the user can confirm or nudge it. Pass [fromPage]
/// false where the picker is nested inside another modal - the page is not
/// reachable from there, so the button would be a dead end.
///
/// Returns the chosen colour, or null when the dialog is dismissed. This is
/// the entry point the editing chrome should use instead of
/// [showPdfColorPicker] directly, so recents, document colours and the
/// eyedropper show up everywhere a colour is chosen.
Future<Color?> pickEditingColor(
  BuildContext context,
  PdfEditingController controller, {
  required Color initial,
  bool fromPage = true,
}) async {
  final preferences = controller.preferences;
  var current = initial;
  while (true) {
    var sampling = false;
    final picked = await showPdfColorPicker(
      context,
      initial: current,
      initialFormat: preferences.colorPickerFormat,
      onFormatChanged: (format) => preferences.colorPickerFormat = format,
      recentColors: preferences.recentColors,
      documentColors: controller.documentAnnotationColors(),
      onPickFromPage: fromPage ? () => sampling = true : null,
    );
    if (!sampling) {
      if (picked != null) preferences.noteRecentColor(picked);
      return picked;
    }
    // The dialog closed itself for the eyedropper; wait for the page tap.
    // A cancelled pick (Escape, the toolbar's own button) ends the whole
    // choice rather than bouncing the dialog back at the user.
    final sampled = await controller.pickColorFromPage();
    if (sampled == null || !context.mounted) return null;
    current = sampled;
  }
}

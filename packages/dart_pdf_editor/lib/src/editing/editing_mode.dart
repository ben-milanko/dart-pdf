import 'editing_controller.dart' show PdfEditTool, PdfMarkupKind;

/// What a [PdfEditingController]'s pointer input does - exactly one at a
/// time. The controller holds one of these and changes it at a single
/// transition point, which runs the exit and entry work (committing buffered
/// ink, swapping the style scope, dropping a selection the new mode can't
/// use) once for every pair of modes.
///
/// The eyedropper and image crop are not modes: they borrow the next press
/// from whichever mode is current and hand it back.
sealed class PdfEditingMode {
  const PdfEditingMode();

  /// The armed [PdfEditTool], or null outside [PdfToolMode].
  PdfEditTool? get tool => null;

  /// The armed text-markup kind, or null outside [PdfMarkupMode].
  PdfMarkupKind? get markup => null;

  /// Whether page presses belong to the editing overlay rather than the
  /// viewer's reader gestures (scrolling, text selection, links).
  bool get armsEditingGestures => false;
}

/// No tool: the viewer reads, selects text and follows links; a click may
/// still pick an annotation.
final class PdfReaderMode extends PdfEditingMode {
  const PdfReaderMode();

  @override
  bool operator ==(Object other) => other is PdfReaderMode;

  @override
  int get hashCode => (PdfReaderMode).hashCode;
}

/// Explicit Hand mode: every drag pans, long-presses don't select text.
final class PdfHandMode extends PdfEditingMode {
  const PdfHandMode();

  @override
  bool operator ==(Object other) => other is PdfHandMode;

  @override
  int get hashCode => (PdfHandMode).hashCode;
}

/// An editing tool is armed.
final class PdfToolMode extends PdfEditingMode {
  const PdfToolMode(this.tool);

  @override
  final PdfEditTool tool;

  @override
  bool get armsEditingGestures => true;

  @override
  bool operator ==(Object other) => other is PdfToolMode && other.tool == tool;

  @override
  int get hashCode => tool.hashCode;
}

/// A text-markup tool is armed: it rides the viewer's own text-selection
/// gestures, so presses stay the viewer's.
final class PdfMarkupMode extends PdfEditingMode {
  const PdfMarkupMode(this.markup);

  @override
  final PdfMarkupKind markup;

  @override
  bool operator ==(Object other) =>
      other is PdfMarkupMode && other.markup == markup;

  @override
  int get hashCode => markup.hashCode;
}

/// A saved annotation follows the pointer and drops where the user clicks.
final class PdfSavedAnnotationMode extends PdfEditingMode {
  const PdfSavedAnnotationMode(this.id);

  /// The [PdfSavedAnnotation.id] being placed.
  final String id;

  @override
  bool get armsEditingGestures => true;

  @override
  bool operator ==(Object other) =>
      other is PdfSavedAnnotationMode && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

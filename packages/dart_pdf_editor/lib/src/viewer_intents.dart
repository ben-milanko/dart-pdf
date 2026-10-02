// The viewer's keyboard commands as Intents, so a host can bind its own keys
// to them (a Shortcuts above the viewer, or PdfViewer.shortcuts) or replace
// what they do (an Actions above the viewer - the viewer's own actions are
// overridable). Widgets only.

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'editing/editing_controller.dart' show PdfEditTool;

/// Copies the selection: selected annotations to the editing clipboard, or
/// the selected text to the system clipboard (⌘C / Ctrl+C).
class PdfCopyIntent extends Intent {
  const PdfCopyIntent();
}

/// Cuts the selected annotations (⌘X / Ctrl+X). Editing only.
class PdfCutIntent extends Intent {
  const PdfCutIntent();
}

/// Pastes the editing clipboard, or a system clipboard image or text, at
/// the pointer (⌘V / Ctrl+V). Editing only.
class PdfPasteIntent extends Intent {
  const PdfPasteIntent();
}

/// Selects every annotation on the current page with the select tool, or
/// the page's whole text otherwise (⌘A / Ctrl+A).
class PdfSelectAllIntent extends Intent {
  const PdfSelectAllIntent();
}

/// Backs out one layer: a colour pick or crop, a placement, the
/// selection, the armed tool, then the text selection (Escape).
class PdfDismissIntent extends Intent {
  const PdfDismissIntent();
}

/// Undoes the last edit (⌘Z / Ctrl+Z). Editing only.
class PdfUndoIntent extends Intent {
  const PdfUndoIntent();
}

/// Redoes the last undone edit (⌘⇧Z / Ctrl+Shift+Z / Ctrl+Y). Editing only.
class PdfRedoIntent extends Intent {
  const PdfRedoIntent();
}

/// Deletes the selected annotations or page content (Delete / Backspace).
/// Editing only.
class PdfDeleteSelectionIntent extends Intent {
  const PdfDeleteSelectionIntent();
}

/// Shrinks or grows the selected text box to fit its text (⌥Z / Alt+Z).
/// Editing only.
class PdfAutosizeTextBoxIntent extends Intent {
  const PdfAutosizeTextBoxIntent();
}

/// Moves the selected annotations, or the selected page content, by
/// ([dx], [dy]) page points, y down the screen (the arrow keys: 1 pt, 10 pt
/// with Shift). Enabled only while something is selected, so an arrow key
/// still scrolls the page when nothing is.
class PdfNudgeSelectionIntent extends Intent {
  const PdfNudgeSelectionIntent(this.dx, this.dy);

  final double dx;
  final double dy;
}

/// Arms [tool], or drops back to Select when it is already armed - a
/// tool's single-key shortcut ([PdfViewer.toolShortcuts]). Goes through the
/// editor's commands when they drive the session, so a measure tool still
/// asks for its scale first. Editing only.
class PdfArmToolIntent extends Intent {
  const PdfArmToolIntent(this.tool);

  final PdfEditTool tool;
}

const double _nudge = 1;
const double _nudgeCoarse = 10;

/// The viewer's stock key bindings ([PdfViewer.shortcuts] defaults to
/// these). Every intent is listed for both ⌘ (macOS, iOS) and Ctrl. The
/// editing ones do nothing - and let the key through - without an editing
/// session; the tool keys ([PdfViewer.toolShortcuts]) are bound on top.
///
/// Copy it to rebind a key:
///
/// ```dart
/// PdfViewer(
///   shortcuts: {
///     ...pdfViewerDefaultShortcuts,
///     // Backspace no longer deletes; ⌘D does
///     const SingleActivator(LogicalKeyboardKey.backspace):
///         const DoNothingAndStopPropagationIntent(),
///     const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
///         const PdfDeleteSelectionIntent(),
///   },
/// )
/// ```
final Map<ShortcutActivator, Intent> pdfViewerDefaultShortcuts =
    Map.unmodifiable(<ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      const PdfCopyIntent(),
  const SingleActivator(LogicalKeyboardKey.keyC, control: true):
      const PdfCopyIntent(),
  const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const PdfSelectAllIntent(),
  const SingleActivator(LogicalKeyboardKey.keyA, control: true):
      const PdfSelectAllIntent(),
  const SingleActivator(LogicalKeyboardKey.escape): const PdfDismissIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
      const PdfUndoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
      const PdfUndoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, alt: true):
      const PdfAutosizeTextBoxIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
      const PdfRedoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
      const PdfRedoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyY, control: true):
      const PdfRedoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyX, meta: true):
      const PdfCutIntent(),
  const SingleActivator(LogicalKeyboardKey.keyX, control: true):
      const PdfCutIntent(),
  const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      const PdfPasteIntent(),
  const SingleActivator(LogicalKeyboardKey.keyV, control: true):
      const PdfPasteIntent(),
  const SingleActivator(LogicalKeyboardKey.delete):
      const PdfDeleteSelectionIntent(),
  const SingleActivator(LogicalKeyboardKey.backspace):
      const PdfDeleteSelectionIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const PdfNudgeSelectionIntent(-_nudge, 0),
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const PdfNudgeSelectionIntent(_nudge, 0),
  const SingleActivator(LogicalKeyboardKey.arrowUp):
      const PdfNudgeSelectionIntent(0, -_nudge),
  const SingleActivator(LogicalKeyboardKey.arrowDown):
      const PdfNudgeSelectionIntent(0, _nudge),
  const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
      const PdfNudgeSelectionIntent(-_nudgeCoarse, 0),
  const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
      const PdfNudgeSelectionIntent(_nudgeCoarse, 0),
  const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
      const PdfNudgeSelectionIntent(0, -_nudgeCoarse),
  const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
      const PdfNudgeSelectionIntent(0, _nudgeCoarse),
});

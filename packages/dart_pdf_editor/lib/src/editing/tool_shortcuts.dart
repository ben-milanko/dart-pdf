import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'editing_controller.dart';

/// A tool *type* - one dock group in [PdfEditingToolbar]. Pass a subset
/// to [PdfEditingToolbar.groups] (or [PdfEditorFeatures.toolGroups]) to
/// hide whole groups: e.g. `{PdfEditToolGroup.select,
/// PdfEditToolGroup.markup}` shows only the Select and Markup groups.
///
/// This is the coarse axis. The finer [PdfEditingToolbar.tools] hides
/// individual tools *within* the groups that survive this filter. It also
/// organises the keyboard-shortcuts editor (see [pdfEditToolGroupOf]).
enum PdfEditToolGroup {
  /// Select / move / resize existing annotations.
  select,

  /// Text-markup actions (highlight, underline, strike out, squiggly).
  markup,

  /// Freehand drawing, freehand highlight, and the ink eraser.
  draw,

  /// Rectangle, ellipse, line, arrow, polyline, polygon.
  shapes,

  /// Text box, note, stamp, image, signature.
  insert,

  /// Distance, perimeter and area measurement.
  measure,

  /// Page content, form fields and redaction.
  edit,
}

/// The dock group [tool] belongs to. Mirrors the layout of
/// [PdfEditingToolbar] so surfaces that list tools - the keyboard-shortcuts
/// editor in particular - can organise them the same way the toolbar reads.
///
/// Exhaustive over [PdfEditTool]: the compiler flags a missing case when the
/// tool set grows, so a new tool cannot silently land in the wrong group.
PdfEditToolGroup pdfEditToolGroupOf(PdfEditTool tool) {
  switch (tool) {
    case PdfEditTool.select:
      return PdfEditToolGroup.select;
    case PdfEditTool.ink:
    case PdfEditTool.highlight:
    case PdfEditTool.eraser:
      return PdfEditToolGroup.draw;
    case PdfEditTool.rectangle:
    case PdfEditTool.ellipse:
    case PdfEditTool.line:
    case PdfEditTool.arrow:
    case PdfEditTool.polyline:
    case PdfEditTool.polygon:
    case PdfEditTool.cloudPolygon:
      return PdfEditToolGroup.shapes;
    case PdfEditTool.freeText:
    case PdfEditTool.callout:
    case PdfEditTool.note:
    case PdfEditTool.stamp:
    case PdfEditTool.count:
    case PdfEditTool.image:
    case PdfEditTool.signature:
    case PdfEditTool.signatureBox:
      return PdfEditToolGroup.insert;
    case PdfEditTool.measureDistance:
    case PdfEditTool.measurePerimeter:
    case PdfEditTool.measureArea:
    case PdfEditTool.measureSlope:
    case PdfEditTool.measureAngle:
    case PdfEditTool.measureArc:
    case PdfEditTool.measureVolume:
    case PdfEditTool.calibrate:
      return PdfEditToolGroup.measure;
    case PdfEditTool.content:
    case PdfEditTool.contentDelete:
    case PdfEditTool.form:
    case PdfEditTool.redact:
    case PdfEditTool.snapshot:
    case PdfEditTool.link:
      return PdfEditToolGroup.edit;
  }
}

/// A single keyboard shortcut for arming an editing tool: a trigger key,
/// optionally "extended" with Shift.
///
/// The common tools sit on plain single letters (V select, P pen, R
/// rectangle…). Once those run out, a tool group's less-common siblings
/// reuse the group's letter with Shift held - the "extension" - so the
/// mnemonics stay grouped: Shift+L for the poly*line* beside L for the
/// line, Shift+M to calibrate the *measure* scale beside M for the
/// distance measure, Shift+H for the *highlighter* beside P for the pen.
/// Shift is the only modifier used, so tool shortcuts never collide with
/// the ⌘/Ctrl clipboard and undo/redo bindings.
@immutable
class PdfToolShortcut {
  const PdfToolShortcut(this.trigger, {this.shift = false});

  /// The letter (or digit) key that arms the tool.
  final LogicalKeyboardKey trigger;

  /// Whether Shift must be held. Distinguishes a group's secondary variants
  /// from its primary tool on the same [trigger].
  final bool shift;

  /// The activator the viewer binds for this shortcut. A plain
  /// (`shift: false`) shortcut only fires when Shift is *up*, so a primary
  /// tool and its Shift-extended sibling never fire together.
  ShortcutActivator get activator => SingleActivator(trigger, shift: shift);

  /// A short display label for tooltips and the shortcut sheet, e.g. `'R'`
  /// or `'⇧R'`. Empty when [trigger] has no printable label.
  String get label => shift ? '⇧${trigger.keyLabel}' : trigger.keyLabel;

  @override
  bool operator ==(Object other) =>
      other is PdfToolShortcut &&
      other.trigger == trigger &&
      other.shift == shift;

  @override
  int get hashCode => Object.hash(trigger, shift);

  @override
  String toString() => 'PdfToolShortcut($label)';
}

/// Default keyboard shortcuts for arming the editing tools.
///
/// Pass a replacement map to [PdfViewer.toolShortcuts] (and to
/// [PdfEditingToolbar.toolShortcuts] when using the stock toolbar) to rebind
/// or disable individual tool shortcuts.
///
/// These are bound by [PdfViewer] while an editing session is active and
/// no in-place text editor is open (typing into a free-text box or form
/// field disables every shortcut so the keys reach the editor), and they
/// are surfaced in the editing toolbar's tooltips for discoverability.
///
/// Pressing a tool's key arms it; pressing it again drops back to
/// [PdfEditTool.select], mirroring the toolbar chips.
///
/// Every tool is covered. The common ones sit on plain letters; a group's
/// less-common variants (the poly / cloud shapes, the extra measurement
/// modes, calibrate, count, the freehand highlighter, the signature box)
/// reuse their group's letter with Shift held - see [PdfToolShortcut].
const Map<PdfEditTool, PdfToolShortcut> pdfEditToolShortcuts = {
  // Select / move.
  PdfEditTool.select: PdfToolShortcut(LogicalKeyboardKey.keyV),

  // Draw group: pen, freehand highlighter, eraser.
  PdfEditTool.ink: PdfToolShortcut(LogicalKeyboardKey.keyP),
  PdfEditTool.highlight: PdfToolShortcut(LogicalKeyboardKey.keyH, shift: true),
  PdfEditTool.eraser: PdfToolShortcut(LogicalKeyboardKey.keyE),

  // Shapes group: rectangle, ellipse, line, arrow, and the poly/cloud
  // variants on Shift.
  PdfEditTool.rectangle: PdfToolShortcut(LogicalKeyboardKey.keyR),
  PdfEditTool.ellipse: PdfToolShortcut(LogicalKeyboardKey.keyO),
  PdfEditTool.line: PdfToolShortcut(LogicalKeyboardKey.keyL),
  PdfEditTool.arrow: PdfToolShortcut(LogicalKeyboardKey.keyA),
  PdfEditTool.polyline: PdfToolShortcut(LogicalKeyboardKey.keyL, shift: true),
  PdfEditTool.polygon: PdfToolShortcut(LogicalKeyboardKey.keyY, shift: true),
  PdfEditTool.cloudPolygon:
      PdfToolShortcut(LogicalKeyboardKey.keyD, shift: true),

  // Measure group: distance on M, the rest on Shift + a mnemonic letter,
  // calibrate on Shift+M (the measure scale itself).
  PdfEditTool.measureDistance: PdfToolShortcut(LogicalKeyboardKey.keyM),
  PdfEditTool.measurePerimeter:
      PdfToolShortcut(LogicalKeyboardKey.keyP, shift: true),
  PdfEditTool.measureArea:
      PdfToolShortcut(LogicalKeyboardKey.keyA, shift: true),
  PdfEditTool.measureSlope:
      PdfToolShortcut(LogicalKeyboardKey.keyS, shift: true),
  PdfEditTool.measureAngle:
      PdfToolShortcut(LogicalKeyboardKey.keyN, shift: true),
  PdfEditTool.measureArc: PdfToolShortcut(LogicalKeyboardKey.keyC, shift: true),
  PdfEditTool.measureVolume:
      PdfToolShortcut(LogicalKeyboardKey.keyV, shift: true),
  PdfEditTool.calibrate: PdfToolShortcut(LogicalKeyboardKey.keyM, shift: true),

  // Insert group: text box, callout, note, stamp, count, signature, image.
  PdfEditTool.freeText: PdfToolShortcut(LogicalKeyboardKey.keyT),
  PdfEditTool.callout: PdfToolShortcut(LogicalKeyboardKey.keyQ),
  PdfEditTool.note: PdfToolShortcut(LogicalKeyboardKey.keyN),
  PdfEditTool.stamp: PdfToolShortcut(LogicalKeyboardKey.keyS),
  PdfEditTool.count: PdfToolShortcut(LogicalKeyboardKey.keyT, shift: true),
  PdfEditTool.signature: PdfToolShortcut(LogicalKeyboardKey.keyH),
  PdfEditTool.image: PdfToolShortcut(LogicalKeyboardKey.keyI),

  // Edit group: content, form, redact, and link (Shift+K beside redact's K).
  PdfEditTool.content: PdfToolShortcut(LogicalKeyboardKey.keyC),
  PdfEditTool.contentDelete:
      PdfToolShortcut(LogicalKeyboardKey.keyE, shift: true),
  PdfEditTool.form: PdfToolShortcut(LogicalKeyboardKey.keyF),
  PdfEditTool.redact: PdfToolShortcut(LogicalKeyboardKey.keyK),
  PdfEditTool.link: PdfToolShortcut(LogicalKeyboardKey.keyK, shift: true),

  // Capture / sign.
  PdfEditTool.snapshot: PdfToolShortcut(LogicalKeyboardKey.keyG),
  PdfEditTool.signatureBox:
      PdfToolShortcut(LogicalKeyboardKey.keyB, shift: true),
};

/// The display label for [tool]'s shortcut key (e.g. `'V'` or `'⇧L'`), or
/// null when the tool has no bound key.
String? pdfEditToolShortcutLabel(
  PdfEditTool tool, {
  Map<PdfEditTool, PdfToolShortcut> shortcuts = pdfEditToolShortcuts,
}) =>
    shortcuts[tool]?.label;

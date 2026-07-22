import 'package:flutter/services.dart';

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
    case PdfEditTool.form:
    case PdfEditTool.redact:
    case PdfEditTool.snapshot:
    case PdfEditTool.link:
      return PdfEditToolGroup.edit;
  }
}

/// Default single-key keyboard shortcuts for arming the common editing tools.
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
/// [PdfEditTool.select], mirroring the toolbar chips. The keys carry no
/// modifier, so they never collide with the ⌘/Ctrl clipboard and
/// undo/redo shortcuts.
///
/// The less-common multi-segment variants (polyline, polygon, perimeter,
/// area measurement) deliberately have no key - they live one tap away in
/// their group's strip and would only need obscure bindings here.
const Map<PdfEditTool, LogicalKeyboardKey> pdfEditToolShortcuts = {
  PdfEditTool.select: LogicalKeyboardKey.keyV,
  PdfEditTool.ink: LogicalKeyboardKey.keyP,
  PdfEditTool.eraser: LogicalKeyboardKey.keyE,
  PdfEditTool.rectangle: LogicalKeyboardKey.keyR,
  PdfEditTool.ellipse: LogicalKeyboardKey.keyO,
  PdfEditTool.line: LogicalKeyboardKey.keyL,
  PdfEditTool.arrow: LogicalKeyboardKey.keyA,
  PdfEditTool.freeText: LogicalKeyboardKey.keyT,
  PdfEditTool.callout: LogicalKeyboardKey.keyQ,
  PdfEditTool.note: LogicalKeyboardKey.keyN,
  PdfEditTool.stamp: LogicalKeyboardKey.keyS,
  PdfEditTool.image: LogicalKeyboardKey.keyI,
  PdfEditTool.signature: LogicalKeyboardKey.keyH,
  PdfEditTool.measureDistance: LogicalKeyboardKey.keyM,
  PdfEditTool.form: LogicalKeyboardKey.keyF,
  PdfEditTool.content: LogicalKeyboardKey.keyC,
  PdfEditTool.redact: LogicalKeyboardKey.keyK,
  PdfEditTool.snapshot: LogicalKeyboardKey.keyG,
};

/// The display label for [tool]'s shortcut key (e.g. `'V'`), or null when
/// the tool has no bound key.
String? pdfEditToolShortcutLabel(
  PdfEditTool tool, {
  Map<PdfEditTool, LogicalKeyboardKey> shortcuts = pdfEditToolShortcuts,
}) =>
    shortcuts[tool]?.keyLabel;

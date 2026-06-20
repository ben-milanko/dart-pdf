import 'package:flutter/services.dart';

import 'editing_controller.dart';

/// Single-key keyboard shortcuts for arming the common editing tools.
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
/// area measurement) deliberately have no key — they live one tap away in
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
  PdfEditTool.note: LogicalKeyboardKey.keyN,
  PdfEditTool.stamp: LogicalKeyboardKey.keyS,
  PdfEditTool.image: LogicalKeyboardKey.keyI,
  PdfEditTool.signature: LogicalKeyboardKey.keyG,
  PdfEditTool.measureDistance: LogicalKeyboardKey.keyM,
  PdfEditTool.form: LogicalKeyboardKey.keyF,
  PdfEditTool.content: LogicalKeyboardKey.keyC,
  PdfEditTool.redact: LogicalKeyboardKey.keyK,
};

/// The display label for [tool]'s shortcut key (e.g. `'V'`), or null when
/// the tool has no bound key.
String? pdfEditToolShortcutLabel(PdfEditTool tool) =>
    pdfEditToolShortcuts[tool]?.keyLabel;

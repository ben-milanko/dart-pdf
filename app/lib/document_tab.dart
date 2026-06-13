import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';

/// One open document. Holds its own edit session and viewer controller so
/// switching tabs preserves edits, undo history, and scroll position.
///
/// A tab is one of three kinds: a normal editable [document], an [error]
/// placeholder, or a two-file [comparison].
class DocumentTab {
  DocumentTab.document({
    required this.title,
    required Uint8List bytes,
    required PdfEditingPreferences preferences,
    this.originPath,
  })  : session = PdfEditingController(bytes, preferences: preferences),
        viewer = PdfViewerController(),
        savedLength = bytes.length,
        error = null,
        compareBefore = null,
        compareAfter = null;

  DocumentTab.error({required this.title, required this.error})
      : session = null,
        viewer = null,
        originPath = null,
        savedLength = 0,
        compareBefore = null,
        compareAfter = null;

  /// A document-comparison tab hosting a [PdfComparisonView] over two files.
  DocumentTab.comparison({
    required this.title,
    required Uint8List before,
    required Uint8List after,
  })  : session = null,
        viewer = null,
        error = null,
        originPath = null,
        savedLength = 0,
        compareBefore = before,
        compareAfter = after;

  final String title;
  final String? error;

  /// The writable on-disk origin (desktop), when the document was opened from
  /// a real path. Save writes back here; updated when a Save As lands on a new
  /// path. Null means save-as only.
  String? originPath;

  /// Byte length of the last-saved revision. Revisions are byte prefixes of one
  /// buffer, so length uniquely identifies a revision — the document is dirty
  /// when the current [PdfEditingController.bytes] length differs from this.
  int savedLength;

  /// The two documents a comparison tab diffs; null on every other tab.
  final Uint8List? compareBefore;
  final Uint8List? compareAfter;

  bool get isComparison => compareAfter != null;

  /// True when the document has edits not yet written to disk.
  bool get isDirty => session != null && session!.bytes.length != savedLength;

  /// Marks the current revision as the saved baseline (call after a save).
  void markSaved() {
    if (session != null) savedLength = session!.bytes.length;
  }

  /// Null for an error or comparison tab. Preferences are owned by the app,
  /// so they outlive every tab.
  final PdfEditingController? session;
  final PdfViewerController? viewer;

  /// A stable identity per open document, used by the shells to remember the
  /// scroll position and zoom across reopens.
  String get documentId => title;

  void dispose() {
    session?.dispose();
    viewer?.dispose();
  }
}

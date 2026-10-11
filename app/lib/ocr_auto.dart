import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart' show PdfOcrEditing, PdfOcrSpan;
import 'package:shared_preferences/shared_preferences.dart';

/// The persisted "Automatically OCR scans" choice. On by default: a scanned
/// document gets a selectable, searchable text layer as soon as it is shown,
/// unless the user turns this off in Settings.
///
/// One instance serves every window ([instance]), so a change made in one
/// window's Settings applies to the next scan any window opens.
class AutoOcrSetting extends ValueNotifier<bool> {
  AutoOcrSetting() : super(true);

  /// The app-wide setting. Call [load] once at start-up.
  static final AutoOcrSetting instance = AutoOcrSetting();

  static const _key = 'dart_pdf_editor_app.ocr.auto';

  Future<void>? _loading;
  bool _chosen = false;

  /// Reads the saved choice. Safe to call more than once: every call waits
  /// on the one read, so nothing acts on the default before it lands.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // a choice made while the read was in flight wins over the stored one
      if (!_chosen) value = prefs.getBool(_key) ?? true;
    } catch (error) {
      debugPrint('Auto OCR setting unreadable: $error');
    }
  }

  /// Sets and saves the choice.
  Future<void> save(bool enabled) async {
    _chosen = true;
    value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (error) {
      debugPrint('Auto OCR setting not saved: $error');
    }
  }
}

/// What an edit session looked like when a background OCR job took its
/// snapshot, so the recognized text can be laid onto the *live* session
/// later - after the user kept annotating while the job ran - without ever
/// landing on pages whose content moved or changed underneath it.
///
/// Annotation edits leave a page's content stamp alone, so they never block
/// the layer. A reorder, insert or delete changes page identities; a content
/// edit or redaction burn changes the content stamps. Any of those refuses
/// the layer: the spans were placed against content that is no longer there,
/// and on a redacted page they could put removed words back as invisible text.
@immutable
class OcrSessionSnapshot {
  const OcrSessionSnapshot._(this._pages, this._destructive);

  /// Captures [controller]'s current revision.
  factory OcrSessionSnapshot.of(PdfEditingController controller) {
    final count = controller.document.pageCount;
    return OcrSessionSnapshot._(
      [
        for (var i = 0; i < count; i++)
          (
            controller.pageRenderIdentity(i),
            controller.pageContentRenderStamp(i),
          ),
      ],
      count == 0 ? 0 : controller.pageDestructiveStamp(0),
    );
  }

  final List<(Object, int)> _pages;
  final int _destructive;

  /// Whether [controller] still shows the same pages, with the same content,
  /// that this snapshot recorded.
  bool matches(PdfEditingController controller) {
    if (controller.document.pageCount != _pages.length) return false;
    if (_pages.isNotEmpty &&
        controller.pageDestructiveStamp(0) != _destructive) {
      return false;
    }
    for (var i = 0; i < _pages.length; i++) {
      final (identity, stamp) = _pages[i];
      if (controller.pageRenderIdentity(i) != identity ||
          controller.pageContentRenderStamp(i) != stamp) {
        return false;
      }
    }
    return true;
  }
}

/// Writes [spans] (by page index) onto [controller]'s current revision as one
/// undoable edit, and returns how many spans were written - or null when the
/// session moved on since [snapshot] in a way the layer can't follow (see
/// [OcrSessionSnapshot]).
int? applyOcrToSession(
  PdfEditingController controller,
  OcrSessionSnapshot snapshot,
  Map<int, List<PdfOcrSpan>> spans,
) {
  if (!snapshot.matches(controller)) return null;
  var written = 0;
  controller.apply((editor) {
    for (final MapEntry(key: page, value: pageSpans) in spans.entries) {
      written += editor.injectTextLayer(page, pageSpans);
    }
  });
  return written;
}

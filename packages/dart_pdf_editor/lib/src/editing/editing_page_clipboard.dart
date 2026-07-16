import 'package:flutter/foundation.dart';

/// A clipboard for whole PDF pages, shared across documents: copy or cut
/// pages in one [PdfEditingController]'s thumbnail view, then paste them
/// into the same document - or into a different open document tab, since
/// every controller shares the process-wide [instance] by default.
///
/// The copied pages are held as a self-contained PDF byte buffer (produced
/// by [PdfEditingController.exportPages]), so a paste deep-copies everything
/// each page references - content, resources, fonts, images, annotations -
/// and never depends on the source document staying open (or even the tab
/// it was copied from still existing).
///
/// A [ChangeNotifier] so paste affordances can enable and disable live as
/// the clipboard fills and clears. Controllers default to the shared
/// [instance] so a copy in one tab pastes into another with no wiring; pass
/// a private clipboard to a controller to isolate it (tests do this).
class PdfPageClipboard extends ChangeNotifier {
  /// The process-wide clipboard every [PdfEditingController] shares by
  /// default, so a copy in one document tab can be pasted into another.
  static final PdfPageClipboard instance = PdfPageClipboard();

  Uint8List? _bytes;
  int _pageCount = 0;

  /// The self-contained PDF holding the copied pages, or null when the
  /// clipboard is empty.
  Uint8List? get bytes => _bytes;

  /// How many pages the clipboard currently holds (0 when empty).
  int get pageCount => _pageCount;

  /// Whether there are pages waiting to be pasted.
  bool get isNotEmpty => _bytes != null;

  /// Whether the clipboard is empty.
  bool get isEmpty => _bytes == null;

  /// Fills the clipboard with [pageCount] pages held as the self-contained
  /// PDF [bytes], replacing any previous contents and notifying listeners.
  void setPages(Uint8List bytes, int pageCount) {
    _bytes = bytes;
    _pageCount = pageCount;
    notifyListeners();
  }

  /// Empties the clipboard (a no-op, no notification, when already empty).
  void clear() {
    if (_bytes == null) return;
    _bytes = null;
    _pageCount = 0;
    notifyListeners();
  }
}

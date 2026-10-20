import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

/// A clipboard for the Snapshot tool's captured vector region, shared across
/// documents: capture a region in one [PdfEditingController], then paste it
/// back as sharp vector graphics into the same document - or into a different
/// open document tab, since every controller shares the process-wide
/// [instance] by default.
///
/// The captured [PdfVectorSnapshot] is fully detached - the page content and
/// resources under the region are copied inline - so a paste never depends on
/// the source document staying open (or even the tab it was captured from
/// still existing). That is what lets a snapshot taken in one tab paste back
/// as vector in another: without a shared clipboard the target tab has no
/// vector copy and can only fall back to the raster (PNG) the capture also
/// dropped on the system clipboard, pasting the region as a flat image.
///
/// A [ChangeNotifier] so paste affordances can enable and disable live as the
/// clipboard fills and clears. Controllers default to the shared [instance] so
/// a capture in one tab pastes into another with no wiring; pass a private
/// clipboard to a controller to isolate it (tests do this).
class PdfSnapshotClipboard extends ChangeNotifier {
  /// The process-wide clipboard every [PdfEditingController] shares by
  /// default, so a region captured in one document tab can be pasted as
  /// vector into another.
  static final PdfSnapshotClipboard instance = PdfSnapshotClipboard();

  PdfVectorSnapshot? _snapshot;

  /// The captured vector region waiting to be pasted, or null when empty.
  PdfVectorSnapshot? get snapshot => _snapshot;

  /// Whether there is a captured region waiting to be pasted.
  bool get isNotEmpty => _snapshot != null;

  /// Whether the clipboard is empty.
  bool get isEmpty => _snapshot == null;

  /// Fills the clipboard with [snapshot], replacing any previous contents and
  /// notifying listeners.
  void set(PdfVectorSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  /// Empties the clipboard (a no-op, no notification, when already empty).
  void clear() {
    if (_snapshot == null) return;
    _snapshot = null;
    notifyListeners();
  }
}

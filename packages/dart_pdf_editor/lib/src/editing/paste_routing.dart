import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:pdf_document/pdf_document.dart';

import 'browser_paste.dart';
import 'editing_annotation_clipboard.dart';
import 'editing_controller.dart';
import 'editing_snapshot_clipboard.dart';
import 'models/prompts.dart';

/// What one paste placed (or [none]).
enum PdfPasteSource {
  /// A PDF from the system clipboard, pasted as a vector snapshot.
  systemPdf,

  /// An image from the system clipboard.
  systemImage,

  /// The in-app vector snapshot clipboard.
  snapshot,

  /// The in-app annotation clipboard.
  annotations,

  /// System clipboard text, placed as a FreeText box.
  systemText,

  /// Nothing was pasteable (or the paste went stale before it landed).
  none,
}

/// The system clipboard as the paste route reads it. Each read returns null
/// when the clipboard has nothing of that kind (or access was denied).
abstract interface class PdfSystemClipboardPort {
  /// Whether [readPdf] can ever produce anything. Decides whether empty page
  /// area offers Paste before any read happens.
  bool get offersPdf;

  Future<PdfClipboardPdf?> readPdf();

  Future<Uint8List?> readImage();

  Future<String?> readText();
}

/// [PdfSystemClipboardPort] over a host's injected providers. Without an
/// injected image or text reader, a keyboard paste on the web reads what the
/// browser's paste event carried ([pdfBrowserPaste]), and text falls back to
/// Flutter's [Clipboard]; a throwing provider reads as empty, so local paste
/// stays usable.
class PdfProviderClipboardPort implements PdfSystemClipboardPort {
  PdfProviderClipboardPort(
    this.context, {
    this.pdf,
    this.image,
    this.text,
  });

  final BuildContext context;
  final PdfSystemPdfPasteProvider? pdf;
  final PdfSystemImagePasteProvider? image;
  final PdfSystemTextPasteProvider? text;

  @override
  bool get offersPdf => pdf != null;

  @override
  Future<PdfClipboardPdf?> readPdf() async {
    try {
      return await pdf?.call(context);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> readImage() async {
    final provider = image;
    try {
      if (provider == null) return (await pdfBrowserPaste())?.image;
      return await provider(context);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readText() async {
    final provider = text;
    try {
      if (provider != null) return await provider(context);
      final pasted = await pdfBrowserPaste();
      if (pasted != null) return pasted.text;
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      return null;
    }
  }
}

/// The controller's two in-app clipboards, kept mutually exclusive: the most
/// recent copy wins Paste, so filling one empties the other.
class PdfInAppClipboard {
  PdfInAppClipboard(this.snapshots, this.annotations);

  final PdfSnapshotClipboard snapshots;
  final PdfAnnotationSnapshotClipboard annotations;

  /// What an in-app paste would place, or null when both are empty.
  PdfPasteSource? get next => snapshots.isNotEmpty
      ? PdfPasteSource.snapshot
      : annotations.isNotEmpty
          ? PdfPasteSource.annotations
          : null;

  void holdAnnotations(
    List<PdfAnnotationSnapshot> copies, {
    required Object owner,
    required int sourcePage,
    List<List<int>> groups = const [],
  }) {
    annotations.set(copies,
        owner: owner, sourcePage: sourcePage, groups: groups);
    snapshots.clear();
  }

  void holdSnapshot(PdfVectorSnapshot snapshot) {
    snapshots.set(snapshot);
    annotations.clear();
  }

  void clear() {
    annotations.clear();
    snapshots.clear();
  }
}

/// The system PDF revision last pasted per shared snapshot clipboard: once
/// pasted, an unchanged system copy yields to the in-app clipboard so a
/// later local copy stays reachable.
final _pastedSystemPdfCopies = Expando<Object>('pasted system PDF copy');

/// Decides what ⌘V / the context menu's Paste places. The one priority order:
///
/// 1. a new external PDF on the system clipboard (vector paste),
/// 2. a system image, when [systemImageFirst],
/// 3. the in-app snapshot clipboard, then the annotation clipboard,
/// 4. a system image,
/// 5. system text, as a FreeText box.
///
/// [paste] is async (system reads are); `stillCurrent` is consulted after
/// every read so a paste that raced an edit, a document swap or an unmount
/// places nothing.
class PdfPasteRouter {
  const PdfPasteRouter(this.port, {this.systemImageFirst = false});

  final PdfSystemClipboardPort port;

  /// The host's "a newly copied system image beats the in-app clipboard"
  /// policy ([PdfViewer.systemImagePasteOverridesLocalClipboard]).
  final bool systemImageFirst;

  /// Whether Paste has anything to offer on empty page area without reading
  /// the system clipboard: an in-app copy, or a host that can supply PDFs.
  static bool canOffer(PdfEditingController editing,
          {PdfSystemClipboardPort? port}) =>
      editing.inAppPasteSource != null || (port?.offersPdf ?? false);

  /// Pastes the in-app clipboard (snapshot first) onto [page]; the whole
  /// route when no system clipboard is wired.
  static PdfPasteSource pasteInApp(
      PdfEditingController editing, int page, (double, double)? at) {
    switch (editing.inAppPasteSource) {
      case PdfPasteSource.snapshot:
        return editing.pasteSnapshot(page, at: at)
            ? PdfPasteSource.snapshot
            : PdfPasteSource.none;
      case PdfPasteSource.annotations:
        return editing.pasteAnnotations(page, at: at)
            ? PdfPasteSource.annotations
            : PdfPasteSource.none;
      default:
        return PdfPasteSource.none;
    }
  }

  Future<PdfPasteSource> paste(
    PdfEditingController editing,
    int page,
    (double, double)? at, {
    bool Function()? stillCurrent,
  }) async {
    final revision = editing.revisionId;
    bool current() =>
        editing.revisionId == revision && (stillCurrent?.call() ?? true);

    final pdf = await port.readPdf();
    if (!current()) return PdfPasteSource.none;
    final token = pdf?.changeToken;
    final alreadyPasted = token != null &&
        _pastedSystemPdfCopies[editing.snapshotClipboard] == token;
    if (pdf != null &&
        !alreadyPasted &&
        editing.pasteSnapshotBytes(pdf.bytes, page, at: at)) {
      if (token != null) {
        _pastedSystemPdfCopies[editing.snapshotClipboard] = token;
      }
      return PdfPasteSource.systemPdf;
    }
    final imageFirst = systemImageFirst && !alreadyPasted;
    if (imageFirst && await _pasteImage(editing, page, at, current)) {
      return PdfPasteSource.systemImage;
    }
    if (!current()) return PdfPasteSource.none;
    if (editing.inAppPasteSource != null) {
      return pasteInApp(editing, page, at);
    }
    if (!imageFirst && await _pasteImage(editing, page, at, current)) {
      return PdfPasteSource.systemImage;
    }
    return await _pasteText(editing, page, at, current)
        ? PdfPasteSource.systemText
        : PdfPasteSource.none;
  }

  Future<bool> _pasteImage(PdfEditingController editing, int page,
      (double, double)? at, bool Function() current) async {
    final bytes = await port.readImage();
    if (bytes == null || bytes.isEmpty || !current()) return false;
    final point = _pointOn(editing, page, at);
    if (point == null) return false;
    return editing.placeImageAsync(page, point.$1, point.$2, bytes);
  }

  Future<bool> _pasteText(PdfEditingController editing, int page,
      (double, double)? at, bool Function() current) async {
    final text = await port.readText();
    if (text == null || text.trim().isEmpty || !current()) return false;
    final point = _pointOn(editing, page, at);
    if (point == null) return false;
    editing.placeFreeText(page, point.$1, point.$2, text);
    return true;
  }

  static bool _hasPage(PdfEditingController editing, int page) =>
      page >= 0 && page < editing.document.pageCount;

  /// [at], or the centre of [page]'s crop box; null for a missing page.
  static (double, double)? _pointOn(
      PdfEditingController editing, int page, (double, double)? at) {
    if (!_hasPage(editing, page)) return null;
    if (at != null) return at;
    final box = editing.pageAt(page).cropBox;
    return ((box.left + box.right) / 2, (box.bottom + box.top) / 2);
  }
}

import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_worker.dart';

/// Owns a [PdfRenderWorker]'s lifecycle across a document's revisions: starts
/// it, feeds incremental edits in place, restarts it on a non-incremental
/// change, and disposes it.
///
/// This is the worker half of a document session, factored out of the shell so
/// both the shell ([PdfShellSessionLifecycle]) and a bare [PdfViewer] standing
/// up its own default worker drive one identical state machine instead of two
/// that can drift. It knows nothing about editing, viewports, or widgets - just
/// "here is the current document/bytes, bring the worker in line".
class PdfRenderWorkerHost {
  /// [workerCount] supplies the pool size for each fresh generation (and may
  /// carry a side effect, e.g. advancing a performance controller's generation
  /// counter); null lets [startPdfRenderWorker] fall back to the global default.
  /// [onGeneration] fires just after a fresh worker starts (not on an in-place
  /// revision update) - the shell uses it to log its performance diagnostics.
  PdfRenderWorkerHost({int Function()? workerCount, VoidCallback? onGeneration})
      : _workerCount = workerCount,
        _onGeneration = onGeneration;

  final int Function()? _workerCount;
  final VoidCallback? _onGeneration;

  PdfRenderWorker? _worker;
  Object? _workerDocument;
  int _generations = 0;

  /// The live worker, or null before the first [sync] (or after [dispose]).
  PdfRenderWorker? get worker => _worker;

  /// How many worker generations this host has started - a fresh generation is
  /// a full (re)start, not an in-place revision update.
  int get generations => _generations;

  /// Brings the worker in line with [document].
  ///
  /// A no-op when [document] is already the loaded one. When [revision]
  /// describes a byte-prefix append to the current buffer (and its `newLength`
  /// matches [bytes]), the append is streamed into the live worker and only the
  /// changed pages' caches drop - no restart, so warm caches survive an edit.
  /// Otherwise (fresh open, a backend that can't update in place, or a
  /// structural/redaction change that replaced the buffer) a new generation
  /// starts.
  void sync({
    required PdfDocument document,
    required Uint8List bytes,
    required int pageCount,
    ({int baseLength, int newLength, Set<int>? changedPages})? revision,
  }) {
    if (identical(document, _workerDocument)) return;

    final worker = _worker;
    if (worker != null &&
        worker.supportsRevisionUpdate &&
        revision != null &&
        revision.newLength == bytes.length) {
      final appended = revision.newLength > revision.baseLength
          ? Uint8List.fromList(
              Uint8List.sublistView(bytes, revision.baseLength))
          : Uint8List(0);
      worker.updateRevision(
        revision.baseLength,
        appended,
        revision.newLength,
        revision.changedPages,
      );
      _workerDocument = document;
      return;
    }

    _worker?.dispose();
    // The session's grow-only buffer is replaced on edit, never mutated in
    // place, so the pool can seed from it directly - no defensive copy of a
    // possibly-huge document (#359).
    _worker = startPdfRenderWorker(bytes,
        pageCount: pageCount,
        workerCount: _workerCount?.call(),
        copySource: false);
    _workerDocument = document;
    _generations++;
    _onGeneration?.call();
  }

  void dispose() {
    _worker?.dispose();
    _worker = null;
    _workerDocument = null;
  }
}

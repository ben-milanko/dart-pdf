import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editing/editing_controller.dart';
import 'editing/editing_preferences.dart';
import 'perf_log.dart';
import 'performance_policy.dart';
import 'pdf_viewer.dart';
import 'render_worker.dart';
import 'shell_chrome.dart';

typedef PdfShellPrepareSession = void Function(PdfEditingController session);
typedef PdfShellSessionChanged = void Function(PdfEditingController session);

class PdfShellSessionUpdate {
  const PdfShellSessionUpdate({
    required this.sessionChanged,
    required this.viewerChanged,
    required this.documentKeyChanged,
  });

  final bool sessionChanged;
  final bool viewerChanged;
  final bool documentKeyChanged;
}

/// Shared resource lifecycle behind PdfReader and PdfEditorView.
///
/// Public shell policy stays in those widgets. This object owns only the
/// ordering-sensitive protocol: borrowed/owned resources, document sessions,
/// worker generations, viewport memory, search focus, and common shortcuts.
class PdfShellSessionLifecycle {
  PdfShellSessionLifecycle({
    required Uint8List? bytes,
    required PdfEditingController? controller,
    required PdfEditingPreferences? preferences,
    required PdfViewerController? viewerController,
    required PdfPerformanceController? performance,
    required String? documentId,
    PdfShellPrepareSession? prepareSession,
    PdfShellSessionChanged? onSessionChanged,
  })  : _bytes = bytes,
        _externalController = controller,
        _externalPreferences = preferences,
        _externalViewer = viewerController,
        _externalPerformance = performance,
        _documentId = documentId,
        _prepareSession = prepareSession,
        _onSessionChanged = onSessionChanged {
    _openSession();
    _bindViewportMemory(recreate: true);
  }

  Uint8List? _bytes;
  PdfEditingController? _externalController;
  PdfEditingPreferences? _externalPreferences;
  PdfViewerController? _externalViewer;
  PdfPerformanceController? _externalPerformance;
  String? _documentId;
  PdfShellPrepareSession? _prepareSession;
  PdfShellSessionChanged? _onSessionChanged;

  PdfEditingController? _ownedSession;
  PdfEditingPreferences? _ownedPreferences;
  PdfViewerController? _ownedViewer;
  PdfPerformanceController? _ownedPerformance;
  PdfViewportMemory? _viewportMemory;
  PdfRenderWorker? _worker;
  Object? _workerDocument;
  int _workerGenerations = 0;

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocus = FocusNode();

  PdfEditingController get session => _externalController ?? _ownedSession!;

  PdfEditingPreferences get preferences => session.preferences;

  PdfViewerController get viewer =>
      _externalViewer ?? (_ownedViewer ??= PdfViewerController());

  PdfPerformanceController get performance =>
      _externalPerformance ??
      (_ownedPerformance ??= PdfPerformanceController());

  PdfRenderWorker? get worker => _worker;

  String? get documentKey =>
      _documentId ?? (_bytes == null ? null : pdfDocumentKey(_bytes!));

  /// Number of actual worker generations started by this lifecycle.
  int get debugWorkerGenerations => _workerGenerations;
  bool get debugOwnsSession => _ownedSession != null;
  bool get debugOwnsPreferences => _ownedPreferences != null;
  bool get debugOwnsViewer => _ownedViewer != null;
  bool get debugOwnsPerformance => _ownedPerformance != null;

  void _openSession() {
    if (_externalController == null) {
      final bytes = _bytes;
      if (bytes == null) {
        throw ArgumentError(
            'bytes are required without an external controller');
      }
      final prefs = _externalPreferences ??
          (_ownedPreferences ??= PdfEditingPreferences());
      _ownedSession = PdfEditingController(bytes, preferences: prefs);
    }
    _prepareSession?.call(session);
    performance.configureDocument(
      pageCount: session.document.pageCount,
      documentBytes: session.bytes.length,
    );
    session.addListener(_handleSessionChanged);
    _syncWorker();
  }

  void _closeSession() {
    session.removeListener(_handleSessionChanged);
    _worker?.dispose();
    _worker = null;
    _workerDocument = null;
    _ownedSession?.dispose();
    _ownedSession = null;
  }

  void _handleSessionChanged() {
    _syncWorker();
    _onSessionChanged?.call(session);
  }

  void _syncWorker() {
    if (identical(session.document, _workerDocument)) return;

    // Revision-aware fast path: revisions are byte prefixes of one growing
    // buffer, so an edit to one page leaves every other page byte-identical.
    // Feed the incremental append into the live worker and evict only the
    // changed pages' cached renders instead of tearing down the whole pool and
    // re-parsing N private documents from cold. See issue #308.
    final worker = _worker;
    final delta = session.lastRevisionDelta;
    if (worker != null &&
        worker.supportsRevisionUpdate &&
        delta != null &&
        delta.newLength == session.bytes.length) {
      final appended = delta.newLength > delta.baseLength
          ? Uint8List.fromList(
              Uint8List.sublistView(session.bytes, delta.baseLength))
          : Uint8List(0);
      worker.updateRevision(
        delta.baseLength,
        appended,
        delta.newLength,
        delta.changedPages,
      );
      _workerDocument = session.document;
      return;
    }

    // Fresh open, a backend that can't update in place (web/null), or a
    // non-incremental transition (a structural edit or a redaction burn that
    // replaced the buffer): start a new worker generation.
    _worker?.dispose();
    final workerCount = performance.beginWorkerGeneration();
    // The session's grow-only buffer is replaced on edit, never mutated in
    // place, so the pool can seed from it directly - no defensive copy of a
    // possibly-huge document (#359).
    _worker = startPdfRenderWorker(session.bytes,
        pageCount: session.document.pageCount,
        workerCount: workerCount,
        copySource: false);
    _workerDocument = session.document;
    _workerGenerations++;
    PdfPerfLog.log(performance.diagnostics.toString());
  }

  void _bindViewportMemory({required bool recreate}) {
    final key = documentKey;
    if (recreate) {
      _viewportMemory?.dispose();
      _viewportMemory = null;
    }
    if (key == null) {
      _viewportMemory?.dispose();
      _viewportMemory = null;
    } else if (_viewportMemory == null) {
      _viewportMemory = PdfViewportMemory(
        viewer: viewer,
        preferences: preferences,
        documentKey: key,
      );
    } else {
      _viewportMemory!.rekey(key);
    }
  }

  /// Applies a rebuilt shell's resource inputs while preserving ownership.
  ///
  /// A document/session change restarts the worker once. A document-id-only
  /// change merely rekeys viewport memory; a performance object swap
  /// reconfigures the current document and takes effect on the next required
  /// worker generation, matching the previous shell behavior.
  PdfShellSessionUpdate update({
    required Uint8List? bytes,
    required PdfEditingController? controller,
    required PdfEditingPreferences? preferences,
    required PdfViewerController? viewerController,
    required PdfPerformanceController? performanceController,
    required String? documentId,
    PdfShellPrepareSession? prepareSession,
    PdfShellSessionChanged? onSessionChanged,
  }) {
    final oldKey = documentKey;
    final oldViewer = viewer;
    final oldPreferences = this.preferences;
    final preferencesInputChanged =
        !identical(preferences, _externalPreferences);
    final sessionChanged = !identical(controller, _externalController) ||
        !identical(bytes, _bytes) ||
        (controller == null && preferencesInputChanged);
    final viewerChanged = !identical(viewerController, _externalViewer);
    final performanceChanged =
        !identical(performanceController, _externalPerformance);

    if (sessionChanged) _closeSession();
    if (sessionChanged &&
        _externalController == null &&
        (controller != null || preferencesInputChanged)) {
      _viewportMemory?.dispose();
      _viewportMemory = null;
      _ownedPreferences?.dispose();
      _ownedPreferences = null;
    }
    if (viewerChanged && _externalViewer == null) {
      _viewportMemory?.dispose();
      _viewportMemory = null;
      _ownedViewer?.dispose();
      _ownedViewer = null;
    }
    if (performanceChanged && _externalPerformance == null) {
      _ownedPerformance?.dispose();
      _ownedPerformance = null;
    }

    _bytes = bytes;
    _externalController = controller;
    _externalPreferences = preferences;
    _externalViewer = viewerController;
    _externalPerformance = performanceController;
    _documentId = documentId;
    _prepareSession = prepareSession;
    _onSessionChanged = onSessionChanged;

    if (sessionChanged) {
      searchController.clear();
      _openSession();
    } else {
      _prepareSession?.call(session);
      if (performanceChanged) {
        performance.configureDocument(
          pageCount: session.document.pageCount,
          documentBytes: session.bytes.length,
        );
      }
    }

    final keyChanged = oldKey != documentKey;
    final effectiveViewerChanged = !identical(oldViewer, viewer);
    final effectivePreferencesChanged =
        !identical(oldPreferences, this.preferences);
    if (sessionChanged ||
        effectiveViewerChanged ||
        effectivePreferencesChanged) {
      _bindViewportMemory(
          recreate: effectiveViewerChanged || effectivePreferencesChanged);
    } else if (keyChanged) {
      _bindViewportMemory(recreate: false);
    }
    return PdfShellSessionUpdate(
      sessionChanged: sessionChanged,
      viewerChanged: viewerChanged,
      documentKeyChanged: keyChanged,
    );
  }

  void focusSearch() {
    searchFocus.requestFocus();
    searchController.selection = TextSelection(
        baseOffset: 0, extentOffset: searchController.text.length);
  }

  Map<ShortcutActivator, VoidCallback> searchShortcuts({
    required bool enabled,
  }) =>
      enabled
          ? {
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                  focusSearch,
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  focusSearch,
            }
          : const <ShortcutActivator, VoidCallback>{};

  void dispose() {
    _viewportMemory?.dispose();
    _closeSession();
    _ownedPreferences?.dispose();
    _ownedViewer?.dispose();
    _ownedPerformance?.dispose();
    searchController.dispose();
    searchFocus.dispose();
  }
}

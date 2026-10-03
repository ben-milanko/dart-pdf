// What the example keeps above its app root, so it survives a switch between
// the Material and the Cupertino design: the open documents (each with its
// own edit session and viewer controller), which one is active, the
// performance controller, and the design choice itself.
//
// The two designs are different app roots (MaterialApp vs CupertinoApp), so
// a switch rebuilds everything below the root. Nothing a user cares about
// lives down there: the hosts read and write the tabs in [ExampleWorkspace]
// and only own their chrome. An edit session (PdfEditingController) is just
// re-attached to the new host's PdfEditorView - the same thing a tab switch
// does - so unsaved edits, undo history and the page all carry over.

import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The design system the example's chrome is built with.
enum ExampleDesign { material, cupertino }

/// The user's [ExampleDesign], saved on the device next to the editor's own
/// preferences (same [PdfPreferencesStore], an example-specific key).
///
/// Material is the default. Values load asynchronously ([ready]); a change is
/// written back immediately. Without storage (plain widget tests) the
/// default stands.
class ExampleDesignPreference extends ChangeNotifier {
  /// [initial], when given, wins over the stored value and is saved - how
  /// `lib/cupertino_host.dart` starts the example in Cupertino.
  ExampleDesignPreference({PdfPreferencesStore? store, ExampleDesign? initial})
      : _injectedStore = store,
        _value = initial ?? ExampleDesign.material,
        _modified = initial != null {
    _ready = _load();
  }

  /// The preferences key the choice is stored under.
  static const storageKey = 'pdf_viewer_example.design';

  final PdfPreferencesStore? _injectedStore;
  PdfPreferencesStore? _store;
  late final Future<void> _ready;
  ExampleDesign _value;
  bool _modified;

  /// Completes once the stored choice has been applied (or storage turned
  /// out to be unavailable).
  Future<void> get ready => _ready;

  ExampleDesign get value => _value;

  set value(ExampleDesign next) {
    if (next == _value) return;
    _value = next;
    _modified = true;
    notifyListeners();
    final store = _store;
    if (store != null) unawaited(store.setString(storageKey, next.name));
  }

  Future<void> _load() async {
    final PdfPreferencesStore store;
    try {
      store = _injectedStore ?? await PdfPreferencesStore.sharedPreferences();
    } catch (_) {
      return; // no storage here; the default stands
    }
    _store = store;
    if (_modified) {
      // chosen before the store opened: that choice wins, and is saved
      unawaited(store.setString(storageKey, _value.name));
      return;
    }
    final stored =
        ExampleDesign.values.asNameMap()[store.getString(storageKey)];
    if (stored != null && stored != _value) {
      _value = stored;
      notifyListeners();
    }
  }
}

/// The documents open in the example, owned above the app root so either
/// design's host shows the same ones.
///
/// A plain holder: each host mutates it inside its own `setState`. The
/// owner (the app root) disposes it, and with it every tab.
class ExampleWorkspace {
  /// One entry per open document, in tab order.
  final List<DocumentTab> tabs = [];

  /// Index of the tab on screen; meaningless while [tabs] is empty.
  int activeIndex = 0;

  /// Whether a host has already opened the launch document. A host mounted
  /// by a design switch must not open the demo again.
  bool launched = false;

  /// App-wide render-performance state (the worker-pool choice), shared by
  /// both hosts.
  final PdfPerformanceController performance = PdfPerformanceController();

  /// Bumped when the worker pool configuration changes, so hosts key their
  /// viewers to rebuild against it.
  int workerConfigEpoch = 0;

  DocumentTab? get active =>
      tabs.isEmpty ? null : tabs[activeIndex.clamp(0, tabs.length - 1)];

  void dispose() {
    for (final tab in tabs) {
      tab.dispose();
    }
    tabs.clear();
    performance.dispose();
  }
}

/// One open document. Holds its own edit session and viewer controller
/// so switching tabs preserves edits, undo history, scroll position,
/// and any demo-specific overlay state.
class DocumentTab {
  DocumentTab.loading({required this.title, this.loadingProgress})
      : session = null,
        viewer = null,
        isDemo = false,
        isExtracted = false,
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = true;

  DocumentTab.document({
    required this.title,
    required Uint8List bytes,
    required PdfEditingPreferences preferences,
    this.isDemo = false,
    this.isExtracted = false,
  })  : session = PdfEditingController(bytes, preferences: preferences),
        viewer = PdfViewerController(),
        error = null,
        compareBefore = null,
        compareAfter = null,
        loadingProgress = null,
        isLoading = false;

  DocumentTab.error({required this.title, required this.error})
      : session = null,
        viewer = null,
        isDemo = false,
        isExtracted = false,
        compareBefore = null,
        compareAfter = null,
        loadingProgress = null,
        isLoading = false;

  /// A document-comparison tab: hosts a [PdfComparisonView] over two
  /// files. No edit session or viewer controller of its own.
  DocumentTab.comparison({
    required this.title,
    required Uint8List before,
    required Uint8List after,
  })  : session = null,
        viewer = null,
        isDemo = false,
        isExtracted = false,
        error = null,
        compareBefore = before,
        compareAfter = after,
        loadingProgress = null,
        isLoading = false;

  final String title;
  final String? error;
  final bool isDemo;
  // A new extraction has no saved file yet, even without any edits.
  final bool isExtracted;
  final bool isLoading;

  /// Download progress (0..1) for a remote-load ("Open from a URL") loading tab,
  /// or null for an indeterminate spinner. The notifier is owned by the code
  /// that started the load, not the tab.
  final ValueListenable<double>? loadingProgress;

  /// The two documents a comparison tab diffs; null on every other tab.
  final Uint8List? compareBefore;
  final Uint8List? compareAfter;

  bool get isComparison => compareAfter != null;

  /// Null for an error tab. Shared preferences are owned by the app, so
  /// they outlive the tab.
  final PdfEditingController? session;
  final PdfViewerController? viewer;

  // demo-specific state the PDF links and overlays drive, per document
  int counter = 0;
  bool switchOn = false;
  final noteField = TextEditingController();

  void dispose() {
    session?.dispose();
    viewer?.dispose();
    noteField.dispose();
  }
}

// A self-driving build of the app used only for capturing device
// screenshots. It steps through a fixed list of showcase states, holding
// each one still and printing a marker line the host capture tool
// watches for:
//
//   @@SHOT@@ <name>     a scene is settled and on screen — grab it now
//   @@SHOT_DONE@@       all scenes done — the host can quit `flutter run`
//
// tool/capture_screenshots.dart launches this with `flutter run` and
// fires the platform's native screenshot tool on each marker. Run by
// hand for a quick look with:
//
//   fvm flutter run -d <device> -t lib/screenshots_main.dart
//
// The state list here is the single source of truth for what gets
// captured; the gallery and CI artifacts follow it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'demo_document.dart';

/// Milliseconds each scene is held on screen after its marker, giving the
/// host time to capture. Overridable: `--dart-define=SHOT_HOLD_MS=4000`.
const _holdMs = int.fromEnvironment('SHOT_HOLD_MS', defaultValue: 2600);

void main() => runApp(const ScreenshotApp());

/// Which drop-in widget a scene shows.
enum _Mode { editor, reader }

/// One captured state.
class _Scene {
  const _Scene(
    this.name, {
    this.mode = _Mode.editor,
    this.page = 0,
    this.tool,
    this.thumbnails = false,
    this.annotationSidebar = false,
  });

  final String name;
  final _Mode mode;
  final int page;
  final PdfEditTool? tool;
  final bool thumbnails;
  final bool annotationSidebar;
}

const _scenes = <_Scene>[
  // Landing on the showcase document with the page thumbnails open.
  _Scene('01-document', page: 0, thumbnails: true),
  // Vector graphics page (dashes, gradients, blend modes).
  _Scene('02-graphics', page: 2),
  // The annotation list beside the annotated / forms page.
  _Scene('03-annotations', page: 5, annotationSidebar: true),
  // An editing tool armed: the bottom toolbar shows its style controls.
  _Scene('04-markup', page: 0, tool: PdfEditTool.ink),
  // The read-only drop-in (PdfReader) on the typography page.
  _Scene('05-reader', mode: _Mode.reader, page: 3),
];

class ScreenshotApp extends StatefulWidget {
  const ScreenshotApp({super.key});

  @override
  State<ScreenshotApp> createState() => _ScreenshotAppState();
}

class _ScreenshotAppState extends State<ScreenshotApp> {
  final _prefs = PdfEditingPreferences();
  late final Uint8List _bytes = buildDemoPdf();
  late final _editing = PdfEditingController(_bytes, preferences: _prefs);
  final _viewer = PdfViewerController();
  final _readerViewer = PdfViewerController();

  _Scene _scene = _scenes.first;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _editing.dispose();
    _viewer.dispose();
    _readerViewer.dispose();
    _prefs.dispose();
    super.dispose();
  }

  /// Lets the current scene paint and rasterize, then settles a moment.
  Future<void> _settle() async {
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1300));
  }

  Future<void> _run() async {
    // Wait for the first real layout before driving anything.
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    for (final scene in _scenes) {
      _prefs.showThumbnailSidebar = scene.thumbnails;
      _prefs.showAnnotationSidebar = scene.annotationSidebar;
      _editing.tool = scene.mode == _Mode.editor ? scene.tool : null;
      if (mounted) setState(() => _scene = scene);
      await _settle();

      // The viewer attaches on the first frame of its widget; jump after
      // the scene's widget is mounted and settled.
      final viewer =
          scene.mode == _Mode.editor ? _viewer : _readerViewer;
      await viewer.jumpToPage(scene.page);
      await _settle();

      debugPrint('@@SHOT@@ ${scene.name}');
      await Future<void>.delayed(Duration(milliseconds: _holdMs));
    }

    debugPrint('@@SHOT_DONE@@');
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_scene.mode) {
      _Mode.editor => PdfEditorView(
          key: const ValueKey('shot-editor'),
          controller: _editing,
          viewerController: _viewer,
        ),
      _Mode.reader => PdfReader(
          key: const ValueKey('shot-reader'),
          bytes: _bytes,
          controller: _readerViewer,
          preferences: _prefs,
        ),
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'dart-pdf viewer',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('dart-pdf viewer')),
        body: body,
      ),
    );
  }
}

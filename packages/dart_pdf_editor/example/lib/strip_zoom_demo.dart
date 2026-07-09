// EXPERIMENTAL (Track C): retained-scene zoom demo.
//
// Opens a PDF, records ONE page into a [PdfRetainedScene] (one interpret +
// one image-decode pass), then lets you pinch/scroll-zoom. Every re-render is
// a synchronous command-buffer replay + toImage at the gesture's scale -
// the content stream is never re-parsed and no image codec ever runs again.
// During a gesture the re-render is throttled to every ~3rd transform change
// (the stale raster scales meanwhile); the settle renders the final scale.
//
// Deliberately minimal and not wired into the viewer chrome - this page
// exists to demonstrate and eyeball the retained-scene substrate that the
// strip/shader replay devices will plug into.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/strips.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

class StripZoomDemoPage extends StatefulWidget {
  const StripZoomDemoPage({super.key, this.initialFilePath});

  /// Optional file to open on entry (e.g. a corpus path passed while
  /// experimenting); otherwise use the "Open PDF" action.
  final String? initialFilePath;

  @override
  State<StripZoomDemoPage> createState() => _StripZoomDemoPageState();
}

class _StripZoomDemoPageState extends State<StripZoomDemoPage> {
  final _transform = TransformationController();

  PdfDocument? _document;
  String _fileName = '';
  int _pageIndex = 0;
  PdfRetainedScene? _scene;

  ui.Image? _raster;

  /// The scale [_raster] was produced at (on top of the fit-to-viewport
  /// base), so the status line can show when the raster is stale.
  double _rasteredZoom = 1.0;

  Size _pageSize = Size.zero;
  Size _viewport = Size.zero;

  int _transformEvents = 0;
  bool _rendering = false;
  bool _renderQueued = false;

  /// Replay target: false = flat CanvasPdfDevice replay, true = Track B's
  /// StripPdfDevice (re-bin per settle; sharp-during-gesture comes with
  /// B3/Slug later).
  bool _useStrips = false;
  double _lastReplayMs = 0;
  double _lastRasterMs = 0;
  double _recordMs = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    final path = widget.initialFilePath;
    if (path != null) unawaited(_openPath(path));
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _scene?.dispose();
    _raster?.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'PDF', extensions: ['pdf'])
    ]);
    if (file != null) await _openPath(file.path, name: file.name);
  }

  Future<void> _openPath(String path, {String? name}) async {
    try {
      final bytes = await XFile(path).readAsBytes();
      final document = PdfDocument.open(bytes);
      setState(() {
        _document = document;
        _fileName = name ?? path.split('/').last;
        _pageIndex = 0;
        _error = null;
      });
      await _recordPage();
    } catch (e) {
      setState(() => _error = 'Could not open $path: $e');
    }
  }

  /// The one-time cost per page: interpret + decode into a retained scene.
  /// Zooming never comes back here.
  Future<void> _recordPage() async {
    final document = _document;
    if (document == null) return;
    final page = document.page(_pageIndex);
    final sw = Stopwatch()..start();
    final scene = await PdfRetainedScene.record(page);
    sw.stop();
    if (!mounted) {
      scene.dispose();
      return;
    }
    _scene?.dispose();
    _scene = scene;
    _pageSize = scene.pageSize;
    _recordMs = sw.elapsedMicroseconds / 1000.0;
    _transform.value = Matrix4.identity();
    setState(() {});
    await _rerender();
  }

  double get _currentZoom => _transform.value.getMaxScaleOnAxis();

  /// Fit-to-viewport pixel ratio at zoom 1 (whole page visible).
  double get _fitRatio {
    if (_pageSize == Size.zero || _viewport == Size.zero) return 1;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final fit = math.min(_viewport.width / _pageSize.width,
        _viewport.height / _pageSize.height);
    return fit * dpr;
  }

  void _onTransformChanged() {
    _transformEvents++;
    // Throttle: replay only every 3rd transform change while the gesture is
    // in flight; the RawImage scales under the InteractiveViewer transform
    // between replays. onInteractionEnd renders the exact settle scale.
    if (_transformEvents % 3 == 0) unawaited(_rerender());
  }

  /// Re-render from the retained scene at the current zoom: a synchronous
  /// command replay into a picture, then toImage. No interpretation, no
  /// decoding - this is the entire cost of a zoom step.
  Future<void> _rerender() async {
    final scene = _scene;
    if (scene == null || _pageSize == Size.zero) return;
    if (_rendering) {
      _renderQueued = true; // coalesce to the latest scale
      return;
    }
    _rendering = true;
    try {
      final zoom = _currentZoom;
      final ratio = (_fitRatio * zoom).clamp(0.05, 8.0);
      var sw = Stopwatch()..start();
      // Both modes are pure replay - no re-interpret, no re-decode. Strips
      // additionally re-bin the geometry at this ratio (Track B device).
      final picture = _useStrips
          ? await scene.replayStrips(pixelRatio: ratio)
          : scene.replay(pixelRatio: ratio);
      final replayMs = sw.elapsedMicroseconds / 1000.0;
      sw = Stopwatch()..start();
      final image = await picture.toImage(
        (_pageSize.width * ratio).ceil().clamp(1, 1 << 13),
        (_pageSize.height * ratio).ceil().clamp(1, 1 << 13),
      );
      final rasterMs = sw.elapsedMicroseconds / 1000.0;
      picture.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _raster?.dispose();
        _raster = image;
        _rasteredZoom = zoom;
        _lastReplayMs = replayMs;
        _lastRasterMs = rasterMs;
      });
    } finally {
      _rendering = false;
      if (_renderQueued) {
        _renderQueued = false;
        unawaited(_rerender());
      }
    }
  }

  Future<void> _goToPage(int index) async {
    final document = _document;
    if (document == null) return;
    final clamped = index.clamp(0, document.pageCount - 1);
    if (clamped == _pageIndex) return;
    setState(() => _pageIndex = clamped);
    await _recordPage();
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final scene = _scene;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retained-scene zoom (experimental)'),
        actions: [
          // Replay-target toggle: flat canvas replay vs strip re-bin.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Flat replay')),
                ButtonSegment(value: true, label: Text('Strip replay')),
              ],
              selected: {_useStrips},
              onSelectionChanged: (selection) {
                setState(() => _useStrips = selection.first);
                unawaited(_rerender());
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open a PDF',
            onPressed: () => unawaited(_pickFile()),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
            onPressed: document == null
                ? null
                : () => unawaited(_goToPage(_pageIndex - 1)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
            onPressed: document == null
                ? null
                : () => unawaited(_goToPage(_pageIndex + 1)),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              _viewport = Size(constraints.maxWidth, constraints.maxHeight);
              if (_error != null) {
                return Center(child: Text(_error!));
              }
              if (document == null || scene == null) {
                return const Center(
                  child: Text('Open a PDF to record a page into a '
                      'retained scene, then pinch or ctrl-scroll to zoom.'),
                );
              }
              final raster = _raster;
              final fit = _fitRatio /
                  (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0);
              final logical =
                  Size(_pageSize.width * fit, _pageSize.height * fit);
              return InteractiveViewer(
                transformationController: _transform,
                minScale: 0.5,
                maxScale: 16,
                boundaryMargin: const EdgeInsets.all(2000),
                onInteractionEnd: (_) => unawaited(_rerender()),
                child: Center(
                  child: SizedBox(
                    width: logical.width,
                    height: logical.height,
                    child: raster == null
                        ? const ColoredBox(color: Colors.white)
                        : RawImage(
                            image: raster,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          ),
                  ),
                ),
              );
            }),
          ),
          if (scene != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Theme.of(context).colorScheme.surface,
              child: Text(
                '$_fileName  p${_pageIndex + 1}/${document?.pageCount ?? 0}  '
                'commands=${scene.commands.length}  '
                'record(once)=${_recordMs.toStringAsFixed(1)}ms  '
                'mode=${_useStrips ? 'strip' : 'flat'}  '
                'zoom=${_currentZoom.toStringAsFixed(2)} '
                '(raster@${_rasteredZoom.toStringAsFixed(2)})  '
                'replay=${_lastReplayMs.toStringAsFixed(1)}ms '
                'toImage=${_lastRasterMs.toStringAsFixed(1)}ms  '
                'zero re-interpret / re-decode',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

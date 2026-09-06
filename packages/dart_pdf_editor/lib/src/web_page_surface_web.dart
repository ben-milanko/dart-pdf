import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'perf_log.dart';
import 'render_worker.dart';

Widget pdfWebPageSurface({
  required Key key,
  required PdfRenderWorker worker,
  required int pageIndex,
  required bool annotations,
  required int width,
  required int height,
  required int pageColor,
  PdfPageSurfaceRegion? region,
  required int? rotation,
  required int priority,
  required VoidCallback onReady,
  required VoidCallback onDeclined,
}) =>
    _PdfWebPageSurface(
      key: key,
      worker: worker,
      pageIndex: pageIndex,
      annotations: annotations,
      width: width,
      height: height,
      pageColor: pageColor,
      region: region,
      rotation: rotation,
      priority: priority,
      onReady: onReady,
      onDeclined: onDeclined,
    );

class _PdfWebPageSurface extends StatefulWidget {
  const _PdfWebPageSurface({
    super.key,
    required this.worker,
    required this.pageIndex,
    required this.annotations,
    required this.width,
    required this.height,
    required this.pageColor,
    required this.region,
    required this.rotation,
    required this.priority,
    required this.onReady,
    required this.onDeclined,
  });

  final PdfRenderWorker worker;
  final int pageIndex;
  final bool annotations;
  final int width;
  final int height;
  final int pageColor;
  final PdfPageSurfaceRegion? region;
  final int? rotation;
  final int priority;
  final VoidCallback onReady;
  final VoidCallback onDeclined;

  @override
  State<_PdfWebPageSurface> createState() => _PdfWebPageSurfaceState();
}

class _PdfWebPageSurfaceState extends State<_PdfWebPageSurface> {
  web.HTMLCanvasElement? _canvas;
  PdfPageSurfaceSession? _session;
  int _generation = 0;

  @override
  void didUpdateWidget(_PdfWebPageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex) {
      _canvas?.style.visibility = 'hidden';
      _canvas?.setAttribute(
        'data-dartpdf-worker-surface-page',
        '${widget.pageIndex}',
      );
    }
    if (oldWidget.region != widget.region) {
      _canvas?.style.visibility = 'hidden';
    }
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.annotations != widget.annotations ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.pageColor != widget.pageColor ||
        oldWidget.region != widget.region ||
        oldWidget.rotation != widget.rotation) {
      _render();
    }
  }

  void _created(Object element) {
    final canvas = element as web.HTMLCanvasElement;
    canvas.style
      ..width = '100%'
      ..height = '100%'
      ..display = 'block'
      ..visibility = 'hidden'
      ..pointerEvents = 'none';
    canvas.setAttribute('aria-hidden', 'true');
    // This stable, non-semantic marker lets the real-Chrome correctness
    // harness crop the worker-owned page surface precisely. It is deliberately
    // not an id: neighboring cached pages can have live surfaces concurrently.
    canvas.setAttribute('data-dartpdf-worker-surface', 'true');
    canvas.setAttribute(
      'data-dartpdf-worker-surface-region',
      '${widget.region != null}',
    );
    canvas.setAttribute(
      'data-dartpdf-worker-surface-page',
      '${widget.pageIndex}',
    );
    canvas.setAttribute('data-dartpdf-worker-surface-ready', 'false');
    _canvas = canvas;
    final offscreen = canvas.transferControlToOffscreen();
    _session = widget.worker.createPageSurface(
      offscreen as Object,
      pageIndex: widget.pageIndex,
    );
    if (_session == null) {
      widget.onDeclined();
      return;
    }
    _render();
  }

  void _render() {
    final session = _session;
    final canvas = _canvas;
    if (session == null || canvas == null) return;
    final generation = ++_generation;
    canvas.setAttribute('data-dartpdf-worker-surface-ready', 'false');
    final clock = Stopwatch()..start();
    unawaited(() async {
      final ok = await session.render(
        widget.pageIndex,
        annotations: widget.annotations,
        width: widget.width,
        height: widget.height,
        pageColor: widget.pageColor,
        region: widget.region,
        rotation: widget.rotation,
        priority: widget.priority,
      );
      clock.stop();
      if (!mounted || generation != _generation) return;
      PdfPerfLog.log(
        'web-worker-surface page=${widget.pageIndex} '
        '${widget.width}x${widget.height} ok=$ok '
        'region=${widget.region != null} '
        'elapsed=${clock.elapsedMicroseconds / 1000.0}ms',
      );
      if (!ok) {
        canvas.style.visibility = 'hidden';
        canvas.setAttribute('data-dartpdf-worker-surface-ready', 'false');
        widget.onDeclined();
        return;
      }
      canvas.style.visibility = 'visible';
      // Publish logical readiness with the same event that exposes the canvas.
      // Delaying this callback by two rAFs scheduled a second Flutter frame
      // after the already-visible worker pixels; the common Chrome capture
      // correctly treated that redundant platform-view recomposition as a
      // later visual change. The data attribute remains the stricter
      // correctness-harness marker and is set after two composited frames.
      widget.onReady();
      web.window.requestAnimationFrame(((num _) {
        web.window.requestAnimationFrame(((num _) {
          if (mounted && generation == _generation) {
            canvas.setAttribute('data-dartpdf-worker-surface-ready', 'true');
          }
        }).toJS);
      }).toJS);
    }());
  }

  @override
  void dispose() {
    _generation++;
    _session?.dispose();
    _session = null;
    _canvas = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'canvas',
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        onElementCreated: _created,
      );
}

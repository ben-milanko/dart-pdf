import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// A self-contained showcase of the viewer's public scroll-indicator API
/// (issue #326): [PdfViewer.scrollIndicatorBuilder] fed by a live
/// [PdfScrollMetrics], driven back with
/// [PdfViewerController.jumpToNormalized] and
/// [PdfViewerController.animateToPage].
///
/// The built-in scrollbar is replaced with a draggable page scrubber that
/// pops a page bubble while dragging, and a corner readout mirrors the raw
/// metrics so the numbers are visible as you scroll and zoom. The app opens
/// it as a full-screen route from the DartPDF menu.
class ScrollIndicatorDemoScreen extends StatefulWidget {
  const ScrollIndicatorDemoScreen({super.key, required this.bytes});

  /// The document to show - the app passes the feature-showcase demo PDF.
  final Uint8List bytes;

  @override
  State<ScrollIndicatorDemoScreen> createState() =>
      _ScrollIndicatorDemoScreenState();
}

class _ScrollIndicatorDemoScreenState extends State<ScrollIndicatorDemoScreen> {
  final _controller = PdfViewerController();
  late final PdfDocument _document = PdfDocument.open(widget.bytes);

  /// The latest metrics the viewer handed to [scrollIndicatorBuilder]. The
  /// corner readout renders from this so it is populated the moment the
  /// viewer lays out and tracks every scroll/zoom, without depending on when
  /// [PdfViewerController.viewportChanges] first fires.
  PdfScrollMetrics? _latest;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Called from the indicator builder (during layout). We cannot call
  /// [setState] mid-build, so stash the value after the frame - and only
  /// when it actually changed, to avoid a rebuild per identical frame.
  void _onMetrics(PdfScrollMetrics metrics) {
    if (metrics == _latest) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _latest = metrics);
    });
  }

  void _step(int delta) {
    final metrics = _controller.scrollMetrics;
    if (metrics == null) return;
    final target =
        (metrics.currentPage + delta).clamp(0, metrics.pageCount - 1);
    // animateToPage: the smooth sibling of jumpToPage
    _controller.animateToPage(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scroll indicator API'),
        actions: [
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: () => _step(-1),
          ),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => _step(1),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          PdfViewer(
            document: _document,
            controller: _controller,
            // width fit guarantees vertical overflow so the scrubber shows
            initialFit: PdfViewerFit.width,
            // the whole point of the demo: swap the stock bar for our own
            scrollIndicatorBuilder: (context, controller, metrics) {
              _onMetrics(metrics);
              return _PageScrubber(
                // a stable key keeps the scrubber's drag state across the
                // metric-driven rebuilds
                key: const ValueKey('demo-scrubber-state'),
                controller: controller,
                metrics: metrics,
              );
            },
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _MetricsReadout(metrics: _latest),
          ),
        ],
      ),
    );
  }
}

/// A draggable page scrubber that mirrors the stock scrollbar's geometry
/// from [PdfScrollMetrics] (thumb of height `extent` at `position`) and
/// drives the view with [PdfViewerController.jumpToNormalized].
class _PageScrubber extends StatefulWidget {
  const _PageScrubber({
    super.key,
    required this.controller,
    required this.metrics,
  });

  final PdfViewerController controller;
  final PdfScrollMetrics metrics;

  @override
  State<_PageScrubber> createState() => _PageScrubberState();
}

class _PageScrubberState extends State<_PageScrubber> {
  static const _trackWidth = 48.0;
  static const _minThumb = 44.0;

  bool _dragging = false;

  void _scrubTo(double localY, double trackHeight, double thumbHeight) {
    final span = trackHeight - thumbHeight;
    // map the pointer to the thumb's *centre*, so grabbing anywhere on the
    // thumb feels natural, then hand the fraction to the controller
    final fraction =
        span <= 0 ? 0.0 : ((localY - thumbHeight / 2) / span).clamp(0.0, 1.0);
    widget.controller.jumpToNormalized(fraction);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _trackWidth,
        child: LayoutBuilder(builder: (context, constraints) {
          final trackHeight = constraints.maxHeight;
          final thumbHeight =
              (metrics.extent * trackHeight).clamp(_minThumb, trackHeight);
          final thumbTop = metrics.position * (trackHeight - thumbHeight);
          return GestureDetector(
            // the drag target - a 48px strip down the right edge
            key: const ValueKey('demo-page-scrubber'),
            // opaque so the scrubber wins the vertical-drag gesture arena
            // over the scroll view underneath (as the stock bar's strip does)
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) {
              setState(() => _dragging = true);
              _scrubTo(d.localPosition.dy, trackHeight, thumbHeight);
            },
            onVerticalDragUpdate: (d) =>
                _scrubTo(d.localPosition.dy, trackHeight, thumbHeight),
            onVerticalDragEnd: (_) => setState(() => _dragging = false),
            onVerticalDragCancel: () => setState(() => _dragging = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // a faint track scrim down the right edge
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 8,
                  width: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // the thumb - height is metrics.extent, offset is position
                Positioned(
                  top: thumbTop,
                  right: 4,
                  width: _trackWidth - 8,
                  height: thumbHeight,
                  child: Center(
                    child: Container(
                      width: _dragging ? 16 : 12,
                      height: thumbHeight,
                      decoration: BoxDecoration(
                        color: _dragging
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: scheme.onSurface.withValues(alpha: 0.25)),
                      ),
                    ),
                  ),
                ),
                // a page bubble that follows the thumb while dragging
                if (_dragging)
                  Positioned(
                    right: _trackWidth,
                    top: (thumbTop + thumbHeight / 2 - 18)
                        .clamp(0.0, trackHeight - 36),
                    child: _Bubble(
                      'Page ${metrics.currentPage + 1} / ${metrics.pageCount}',
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          style: TextStyle(
              color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// A live readout of the raw [PdfScrollMetrics] the viewer last reported, so
/// the numbers behind the scrubber are visible as you scroll and zoom.
class _MetricsReadout extends StatelessWidget {
  const _MetricsReadout({required this.metrics});

  final PdfScrollMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = metrics;
    final lines = m == null
        ? const ['scrollMetrics: null (not laid out)']
        : [
            'page:      ${m.currentPage + 1} / ${m.pageCount}',
            'position:  ${m.position.toStringAsFixed(3)}',
            'extent:    ${m.extent.toStringAsFixed(3)}',
            'zoom:      ${m.zoom.toStringAsFixed(2)}x',
            'overflow:  ${m.hasOverflow}',
          ];
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.inverseSurface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines)
              Text(
                line,
                style: TextStyle(
                  color: scheme.onInverseSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'l10n/app_l10n.dart';

/// A self-contained showcase of the viewer's public scroll-indicator API
/// (issues #326 and #428): [PdfViewer.scrollIndicatorBuilder] fed by a live
/// [PdfScrollMetrics], driven back with
/// [PdfViewerController.jumpToNormalized] and
/// [PdfViewerController.animateToPage].
///
/// The built-in scrollbar is replaced with a draggable page scrubber that
/// pops a page bubble while dragging, and a corner readout mirrors the raw
/// metrics so the numbers are visible as you scroll and zoom. A layout toggle
/// flips the viewer between vertical and horizontal continuous reading; the
/// same scrubber re-orients itself from [PdfScrollMetrics.scrollAxis] (a
/// right-edge track vertically, a bottom-edge one horizontally), showing that
/// the metrics and [PdfViewerController.jumpToNormalized] describe whichever
/// axis is active. The app opens it as a full-screen route from the DartPDF
/// menu.
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

  /// The viewer's current continuous layout, flipped by the app-bar toggle.
  PdfPageLayout _layout = const PdfPageLayout.verticalContinuous();

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

  void _toggleLayout() {
    setState(() {
      _layout = _layout.scrollAxis == Axis.vertical
          ? const PdfPageLayout.horizontalContinuous()
          : const PdfPageLayout.verticalContinuous();
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = _layout.scrollAxis == Axis.horizontal;
    return Scaffold(
      appBar: AppBar(
        title: Text(appL10n(context).scrollDemoTitle),
        actions: [
          IconButton(
            tooltip: horizontal
                ? appL10n(context).scrollDemoSwitchVertical
                : appL10n(context).scrollDemoSwitchHorizontal,
            icon: Icon(horizontal ? Icons.view_day : Icons.view_column),
            onPressed: _toggleLayout,
          ),
          IconButton(
            tooltip: appL10n(context).scrollDemoPreviousPage,
            icon: Icon(
                horizontal ? Icons.keyboard_arrow_left : Icons.keyboard_arrow_up),
            onPressed: () => _step(-1),
          ),
          IconButton(
            tooltip: appL10n(context).scrollDemoNextPage,
            icon: Icon(horizontal
                ? Icons.keyboard_arrow_right
                : Icons.keyboard_arrow_down),
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
            pageLayout: _layout,
            // width fit guarantees main-axis overflow so the scrubber shows
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

/// A draggable page scrubber that mirrors the stock scrollbar's geometry from
/// [PdfScrollMetrics] (thumb of size `extent` at `position`) and drives the
/// view with [PdfViewerController.jumpToNormalized]. It orients itself from
/// [PdfScrollMetrics.scrollAxis]: a right-edge vertical track for a vertical
/// layout, a bottom-edge horizontal track for a horizontal one.
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
  static const _trackBreadth = 48.0;
  static const _minThumb = 44.0;

  bool _dragging = false;

  void _scrubTo(double localMain, double trackMain, double thumbMain) {
    final span = trackMain - thumbMain;
    // map the pointer to the thumb's *centre*, so grabbing anywhere on the
    // thumb feels natural, then hand the fraction to the controller
    final fraction =
        span <= 0 ? 0.0 : ((localMain - thumbMain / 2) / span).clamp(0.0, 1.0);
    widget.controller.jumpToNormalized(fraction);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    final horizontal = metrics.scrollAxis == Axis.horizontal;
    return Align(
      // the track hugs the edge along the scroll axis: the bottom for a
      // horizontal layout, the trailing edge (right in LTR, left in RTL) for
      // a vertical one
      alignment:
          horizontal ? Alignment.bottomCenter : AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: horizontal ? null : _trackBreadth,
        height: horizontal ? _trackBreadth : null,
        child: LayoutBuilder(builder: (context, constraints) {
          // the "main" extent is the track's length along the scroll axis
          final trackMain =
              horizontal ? constraints.maxWidth : constraints.maxHeight;
          final thumbMain =
              (metrics.extent * trackMain).clamp(_minThumb, trackMain);
          final thumbLead = metrics.position * (trackMain - thumbMain);
          void start(DragStartDetails d) {
            setState(() => _dragging = true);
            _scrubTo(horizontal ? d.localPosition.dx : d.localPosition.dy,
                trackMain, thumbMain);
          }

          void update(DragUpdateDetails d) => _scrubTo(
              horizontal ? d.localPosition.dx : d.localPosition.dy,
              trackMain,
              thumbMain);
          void end() => setState(() => _dragging = false);
          return GestureDetector(
            // the drag target - a 48px strip along the scroll edge. The drag
            // recognizer matches the scroll axis (like the stock bar's strip)
            // so, being opaque and on top, it wins the arena over the scroll
            // view underneath on that same axis.
            key: const ValueKey('demo-page-scrubber'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: horizontal ? null : start,
            onVerticalDragUpdate: horizontal ? null : update,
            onVerticalDragEnd: horizontal ? null : (_) => end(),
            onVerticalDragCancel: horizontal ? null : end,
            onHorizontalDragStart: horizontal ? start : null,
            onHorizontalDragUpdate: horizontal ? update : null,
            onHorizontalDragEnd: horizontal ? (_) => end() : null,
            onHorizontalDragCancel: horizontal ? end : null,
            child: _buildTrack(
                context, horizontal, thumbLead, thumbMain, trackMain, metrics),
          );
        }),
      ),
    );
  }

  Widget _buildTrack(BuildContext context, bool horizontal, double thumbLead,
      double thumbMain, double trackMain, PdfScrollMetrics metrics) {
    final scheme = Theme.of(context).colorScheme;
    // the thumb's cross-axis thickness grows a little while dragging
    final thumbCross = _dragging ? 16.0 : 12.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // a faint track scrim along the scroll edge
        Positioned(
          top: horizontal ? null : 0,
          bottom: horizontal ? 8 : 0,
          left: horizontal ? 0 : null,
          right: horizontal ? 0 : 8,
          width: horizontal ? null : 6,
          height: horizontal ? 6 : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        // the thumb - length is metrics.extent, offset is position
        Positioned(
          top: horizontal ? null : thumbLead,
          bottom: horizontal ? 4 : null,
          left: horizontal ? thumbLead : null,
          right: horizontal ? null : 4,
          width: horizontal ? thumbMain : _trackBreadth - 8,
          height: horizontal ? _trackBreadth - 8 : thumbMain,
          child: Center(
            child: Container(
              width: horizontal ? thumbMain : thumbCross,
              height: horizontal ? thumbCross : thumbMain,
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
            right: horizontal ? null : _trackBreadth,
            bottom: horizontal ? _trackBreadth : null,
            left: horizontal
                ? (thumbLead + thumbMain / 2 - 60).clamp(0.0, trackMain - 120)
                : null,
            top: horizontal
                ? null
                : (thumbLead + thumbMain / 2 - 18).clamp(0.0, trackMain - 36),
            child: _Bubble(
              appL10n(context).scrollDemoPageBubble(
                  metrics.currentPage + 1, metrics.pageCount),
            ),
          ),
      ],
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
            'axis:      ${m.scrollAxis.name}',
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

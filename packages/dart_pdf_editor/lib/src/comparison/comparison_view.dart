import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../editing/editing_panel.dart';
import '../page_geometry.dart';
import '../pdf_viewer.dart';
import '../scrollbar.dart';
import '../theme.dart';
import 'document_comparison.dart';

/// How a [PdfComparisonView] presents the two documents.
enum PdfComparisonMode {
  /// Two synchronized panes, scroll and zoom locked together.
  sideBySide,

  /// One pane showing the after document with a per-page colored diff
  /// composited over it (removed red, added green, changed amber, the rest
  /// dimmed).
  overlay,
}

/// Compares two PDF documents visually.
///
/// Pairs the documents' pages, diffs their text, and presents the result
/// as either synchronized side-by-side panes or a single overlay pane.
/// A [PdfDiffNavigatorPanel] steps through the changes.
class PdfComparisonView extends StatefulWidget {
  const PdfComparisonView({
    super.key,
    required this.before,
    required this.after,
    this.initialMode = PdfComparisonMode.sideBySide,
    this.showNavigator = true,
    this.pixelRatio = 1.5,
    this.viewerTheme,
  });

  /// The original ("before") document bytes.
  final Uint8List before;

  /// The revised ("after") document bytes.
  final Uint8List after;

  final PdfComparisonMode initialMode;

  /// Whether to dock the diff navigator panel.
  final bool showNavigator;

  /// Resolution the overlay diff rasters render at.
  final double pixelRatio;

  /// Wraps both panes in a [PdfViewerTheme].
  final PdfViewerThemeData? viewerTheme;

  @override
  State<PdfComparisonView> createState() => _PdfComparisonViewState();
}

class _PdfComparisonViewState extends State<PdfComparisonView> {
  late PdfDocument _beforeDoc;
  late PdfDocument _afterDoc;
  late PdfComparisonController _comparison;
  final PdfViewerController _beforeCtl = PdfViewerController();
  final PdfViewerController _afterCtl = PdfViewerController();
  _PdfSyncLink? _link;
  late PdfComparisonMode _mode;

  // Overlay-mode diff images, keyed by after-page index. Null while loading.
  final Map<int, ui.Image?> _overlayImages = {};
  final Set<int> _overlayLoading = {};

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _open();
    _comparison.addListener(_onComparison);
    // Build the change list after the first frame so the panes can attach.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _comparison.build();
    });
  }

  void _open() {
    _beforeDoc = PdfDocument.open(widget.before);
    _afterDoc = PdfDocument.open(widget.after);
    _comparison = PdfComparisonController(
      before: _beforeDoc,
      after: _afterDoc,
      pixelRatio: widget.pixelRatio,
    );
  }

  @override
  void didUpdateWidget(PdfComparisonView old) {
    super.didUpdateWidget(old);
    if (!_sameBytes(old.before, widget.before) ||
        !_sameBytes(old.after, widget.after)) {
      _comparison.removeListener(_onComparison);
      _comparison.dispose();
      _disposeOverlays();
      _open();
      _comparison.addListener(_onComparison);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _comparison.build();
      });
    }
  }

  bool _sameBytes(Uint8List a, Uint8List b) => identical(a, b);

  @override
  void dispose() {
    _link?.dispose();
    _comparison.removeListener(_onComparison);
    _comparison.dispose();
    _beforeCtl.dispose();
    _afterCtl.dispose();
    _disposeOverlays();
    super.dispose();
  }

  void _disposeOverlays() {
    for (final image in _overlayImages.values) {
      image?.dispose();
    }
    _overlayImages.clear();
    _overlayLoading.clear();
  }

  void _onComparison() {
    if (!mounted) return;
    _frameCurrentChange();
  }

  void _frameCurrentChange() {
    final index = _comparison.currentChange;
    if (index < 0 || index >= _comparison.changes.length) return;
    final change = _comparison.changes[index];
    final page = change.afterPage ?? change.beforePage ?? 0;
    final rect = change.afterBounds ?? change.beforeBounds;
    // Drive the after pane; in side-by-side the sync link mirrors the
    // before pane to the same scroll position.
    if (rect != null) {
      _afterCtl.showRect(page, rect);
    } else {
      _afterCtl.jumpToPage(page);
    }
  }

  void _setMode(PdfComparisonMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    Widget panes = _mode == PdfComparisonMode.sideBySide
        ? _sideBySide()
        : _overlayPane();
    if (widget.viewerTheme != null) {
      panes = PdfViewerTheme(data: widget.viewerTheme!, child: panes);
    }
    return Column(children: [
      _PdfComparisonToolbar(
        mode: _mode,
        onMode: _setMode,
        comparison: _comparison,
      ),
      const Divider(height: 1),
      Expanded(
        child: Row(children: [
          if (widget.showNavigator)
            PdfDiffNavigatorPanel(controller: _comparison),
          if (widget.showNavigator) const VerticalDivider(width: 1),
          Expanded(child: panes),
        ]),
      ),
    ]);
  }

  Widget _sideBySide() {
    // (Re)attach the sync link to the live controllers.
    _link ??= _PdfSyncLink(_beforeCtl, _afterCtl);
    return Row(children: [
      Expanded(
        child: _LabeledPane(
          label: 'Before',
          child: PdfViewer(
            key: const ValueKey('pdf-compare-before'),
            document: _beforeDoc,
            controller: _beforeCtl,
            initialFit: PdfViewerFit.width,
          ),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: _LabeledPane(
          label: 'After',
          child: PdfViewer(
            key: const ValueKey('pdf-compare-after'),
            document: _afterDoc,
            controller: _afterCtl,
            initialFit: PdfViewerFit.width,
          ),
        ),
      ),
    ]);
  }

  Widget _overlayPane() {
    // The overlay pane has no second viewer, so drop the link.
    _link?.dispose();
    _link = null;
    return PdfViewer(
      key: const ValueKey('pdf-compare-overlay'),
      document: _afterDoc,
      controller: _afterCtl,
      initialFit: PdfViewerFit.width,
      pageOverlayBuilder: _overlayBuilder,
    );
  }

  List<Widget> _overlayBuilder(
      BuildContext context, int pageIndex, PdfPageGeometry geometry) {
    final image = _overlayImages[pageIndex];
    if (image == null) {
      _ensureOverlayImage(pageIndex);
      return const [];
    }
    return [
      Positioned.fromRect(
        rect: geometry.toViewRect(geometry.cropBox),
        child: IgnorePointer(
          child: RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    ];
  }

  Future<void> _ensureOverlayImage(int afterPage) async {
    if (_overlayImages.containsKey(afterPage) ||
        _overlayLoading.contains(afterPage)) {
      return;
    }
    final pairIndex = _comparison.pairForAfterPage(afterPage);
    if (pairIndex < 0) return;
    _overlayLoading.add(afterPage);
    try {
      final diff = await _comparison.pixelDiff(pairIndex);
      final image = await diff.pixels.toImage();
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _overlayImages[afterPage] = image);
    } catch (_) {
      // A page that fails to render leaves no overlay; the underlying page
      // still shows.
    } finally {
      _overlayLoading.remove(afterPage);
    }
  }
}

/// Bidirectionally mirrors two viewers' scroll and zoom, with a guard so an
/// applied change doesn't echo back.
class _PdfSyncLink {
  _PdfSyncLink(this.a, this.b) {
    a.viewportChanges.addListener(_fromA);
    b.viewportChanges.addListener(_fromB);
  }

  final PdfViewerController a;
  final PdfViewerController b;
  bool _busy = false;

  void _fromA() => _mirror(a, b);
  void _fromB() => _mirror(b, a);

  void _mirror(PdfViewerController from, PdfViewerController to) {
    if (_busy) return;
    final sync = from.viewSync;
    if (sync == null) return;
    _busy = true;
    try {
      to.applyViewSync(sync);
    } finally {
      scheduleMicrotask(() => _busy = false);
    }
  }

  void dispose() {
    a.viewportChanges.removeListener(_fromA);
    b.viewportChanges.removeListener(_fromB);
  }
}

class _LabeledPane extends StatelessWidget {
  const _LabeledPane({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: scheme.surfaceContainerHighest,
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
      Expanded(child: child),
    ]);
  }
}

class _PdfComparisonToolbar extends StatelessWidget {
  const _PdfComparisonToolbar({
    required this.mode,
    required this.onMode,
    required this.comparison,
  });

  final PdfComparisonMode mode;
  final ValueChanged<PdfComparisonMode> onMode;
  final PdfComparisonController comparison;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        SegmentedButton<PdfComparisonMode>(
          key: const ValueKey('pdf-compare-mode'),
          segments: const [
            ButtonSegment(
              value: PdfComparisonMode.sideBySide,
              icon: Icon(Icons.view_column_outlined),
              label: Text('Side by side'),
            ),
            ButtonSegment(
              value: PdfComparisonMode.overlay,
              icon: Icon(Icons.layers_outlined),
              label: Text('Overlay'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onMode(s.first),
        ),
        const Spacer(),
        ListenableBuilder(
          listenable: comparison,
          builder: (context, _) {
            final count = comparison.changes.length;
            final current = comparison.currentChange;
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                count == 0
                    ? 'No changes'
                    : '${current + 1} / $count changes',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              IconButton(
                key: const ValueKey('pdf-compare-prev'),
                tooltip: 'Previous change',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: count == 0 ? null : comparison.previousChange,
              ),
              IconButton(
                key: const ValueKey('pdf-compare-next'),
                tooltip: 'Next change',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: count == 0 ? null : comparison.nextChange,
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// Lists every change in a [PdfComparisonController], grouped by page —
/// tap to jump, mirroring [PdfSearchResultsPanel]'s shape. The inner edge
/// is draggable.
class PdfDiffNavigatorPanel extends StatefulWidget {
  const PdfDiffNavigatorPanel({
    super.key,
    required this.controller,
    this.width = 280,
    this.side = PdfSidebarSide.left,
    this.resizable = true,
    this.minWidth = 200,
    this.maxWidth = 480,
  });

  final PdfComparisonController controller;
  final double width;
  final PdfSidebarSide side;
  final bool resizable;
  final double minWidth;
  final double maxWidth;

  @override
  State<PdfDiffNavigatorPanel> createState() => _PdfDiffNavigatorPanelState();
}

class _PdfDiffNavigatorPanelState extends State<PdfDiffNavigatorPanel> {
  final ScrollController _scroll = ScrollController();
  double? _dragWidth;

  double get _width =>
      (_dragWidth ?? widget.width).clamp(widget.minWidth, widget.maxWidth);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onResizeDelta(double delta) => setState(() {
        _dragWidth = (_width + delta).clamp(widget.minWidth, widget.maxWidth);
      });

  Widget _hint(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );

  ({IconData icon, Color color, String prefix}) _style(
      BuildContext context, PdfDiffChangeKind kind) {
    switch (kind) {
      case PdfDiffChangeKind.inserted:
      case PdfDiffChangeKind.pageInserted:
        return (icon: Icons.add, color: const Color(0xFF2E7D32), prefix: '');
      case PdfDiffChangeKind.deleted:
      case PdfDiffChangeKind.pageRemoved:
        return (
          icon: Icons.remove,
          color: const Color(0xFFE53935),
          prefix: ''
        );
      case PdfDiffChangeKind.replaced:
        return (
          icon: Icons.swap_horiz,
          color: const Color(0xFFF57C00),
          prefix: ''
        );
    }
  }

  Widget _tile(BuildContext context, int index, PdfDiffChange change) {
    final scheme = Theme.of(context).colorScheme;
    final style = _style(context, change.kind);
    return ListTile(
      key: ValueKey('pdf-diff-change-$index'),
      dense: true,
      leading: Icon(style.icon, color: style.color, size: 18),
      selected: index == widget.controller.currentChange,
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: scheme.onSecondaryContainer,
      title: Text(
        change.label.isEmpty ? '(empty)' : change.label,
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => widget.controller.goToChange(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final barClearance = PdfScrollbar.hitExtent +
        (widget.resizable && widget.side == PdfSidebarSide.left
            ? PdfSidebarResizeGrip.width
            : 0);
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: _width,
      child: Stack(children: [
        Positioned.fill(
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final changes = controller.changes;
                if (changes.isEmpty) {
                  return _hint('No differences between the two documents');
                }
                // Group entries by their display page with headers.
                final entries = <({int? header, int? change})>[];
                int? page;
                for (var i = 0; i < changes.length; i++) {
                  final p = changes[i].displayPage;
                  if (p != page) {
                    page = p;
                    entries.add((header: p, change: null));
                  }
                  entries.add((header: null, change: i));
                }
                return Stack(children: [
                  Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        changes.length == 1
                            ? '1 change'
                            : '${changes.length} changes',
                        style: textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: ListView.builder(
                          key: const ValueKey('pdf-diff-list'),
                          controller: _scroll,
                          padding: EdgeInsets.only(
                              right: barClearance, bottom: 8),
                          itemCount: entries.length,
                          itemBuilder: (context, i) {
                            final entry = entries[i];
                            if (entry.header != null) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 10, 16, 2),
                                child: Text('Page ${entry.header! + 1}',
                                    style: textTheme.labelMedium?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary)),
                              );
                            }
                            return _tile(context, entry.change!,
                                changes[entry.change!]);
                          },
                        ),
                      ),
                    ),
                  ]),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right:
                        widget.resizable && widget.side == PdfSidebarSide.left
                            ? PdfSidebarResizeGrip.width
                            : 0,
                    child: PdfScrollbar(
                      scroll: _scroll,
                      thumbKey: const ValueKey('pdf-diff-scrollbar-thumb'),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ),
        if (widget.resizable)
          Positioned(
            top: 0,
            bottom: 0,
            left: widget.side == PdfSidebarSide.right ? 0 : null,
            right: widget.side == PdfSidebarSide.left ? 0 : null,
            child: PdfSidebarResizeGrip(
              key: const ValueKey('pdf-diff-resize-grip'),
              side: widget.side,
              onWidthDelta: _onResizeDelta,
              onResizeEnd: () {},
            ),
          ),
      ]),
    );
  }
}

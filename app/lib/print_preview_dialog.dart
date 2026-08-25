import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_l10n.dart';
import 'middle_ellipsis_text.dart';
import 'l10n/app_localizations.dart';

/// Which pages a print job covers, as chosen in the preview.
enum PrintPageRange {
  /// Every page of the document.
  all,

  /// Just the page the viewer is on.
  current,

  /// An inclusive `from`-`to` span the user typed.
  custom,
}

/// Shows DartPDF's own print preview for [document] and resolves to the
/// 0-based page indices to print, or null when the user cancels.
///
/// This is the preview Windows and Linux never get from their own print
/// surfaces: the Win32 common print dialog is settings-only, and the modern
/// Windows 11 dialog that replaced it renders "This app doesn't support print
/// preview" in its preview pane, because the legacy print API hands Windows no
/// document content to show. See [platformProvidesPrintPreview] for who calls
/// this.
///
/// [currentPage] seeds the previewed page and the "Current" range.
Future<List<int>?> showPrintPreviewDialog(
  BuildContext context, {
  required PdfDocument document,
  required String title,
  int currentPage = 0,
}) {
  return showPdfDialog<List<int>>(
    context: context,
    useRootNavigator: true,
    builder: (_) => PrintPreviewDialog(
      document: document,
      title: title,
      currentPage: currentPage,
    ),
  );
}

/// The print preview: what the job will look like, plus the page range it
/// covers. Pops the chosen 0-based page indices, or nothing when cancelled.
///
/// Exposed (rather than private to [showPrintPreviewDialog]) so tests and
/// hosts can pump it directly.
class PrintPreviewDialog extends StatefulWidget {
  const PrintPreviewDialog({
    super.key,
    required this.document,
    required this.title,
    this.currentPage = 0,
  });

  /// The document to preview - the current revision, so unsaved edits show.
  final PdfDocument document;

  /// The document's title, shown as the dialog's subtitle.
  final String title;

  /// The page the viewer is on, 0-based.
  final int currentPage;

  @override
  State<PrintPreviewDialog> createState() => _PrintPreviewDialogState();
}

class _PrintPreviewDialogState extends State<PrintPreviewDialog> {
  late final int _pageCount = widget.document.pageCount;
  late final int _currentPage = widget.currentPage.clamp(0, _pageCount - 1);

  late final TextEditingController _from =
      TextEditingController(text: '${_currentPage + 1}');
  late final TextEditingController _to =
      TextEditingController(text: '$_pageCount');

  PrintPageRange _range = PrintPageRange.all;

  /// Position within [_pages] of the page being previewed - an offset into the
  /// selection rather than a page index, so narrowing the range moves the
  /// preview into it instead of leaving a page that won't print on screen.
  int _previewSlot = 0;

  /// Set when Print is pressed with an unparseable custom range.
  bool _rangeInvalid = false;

  @override
  void initState() {
    super.initState();
    _previewSlot = _pages.indexOf(_currentPage).clamp(0, _pageCount - 1);
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  /// The 0-based pages the current range covers. An empty or backwards custom
  /// range yields an empty list, which disables Print.
  List<int> get _pages {
    switch (_range) {
      case PrintPageRange.all:
        return [for (var i = 0; i < _pageCount; i++) i];
      case PrintPageRange.current:
        return [_currentPage];
      case PrintPageRange.custom:
        final from = _parse(_from);
        final to = _parse(_to);
        if (from == null || to == null || to < from) return const [];
        return [for (var i = from; i <= to; i++) i];
    }
  }

  /// A 1-based field as a 0-based page index, or null when it isn't a page.
  int? _parse(TextEditingController field) {
    final n = int.tryParse(field.text.trim());
    if (n == null || n < 1 || n > _pageCount) return null;
    return n - 1;
  }

  void _setRange(PrintPageRange range) {
    setState(() {
      _range = range;
      _rangeInvalid = false;
      _clampPreview();
    });
  }

  void _onRangeEdited() {
    setState(() {
      _range = PrintPageRange.custom;
      _rangeInvalid = false;
      _clampPreview();
    });
  }

  /// Keeps the previewed page inside the selection after the range changes.
  void _clampPreview() {
    final pages = _pages;
    if (pages.isEmpty) {
      _previewSlot = 0;
      return;
    }
    _previewSlot = _previewSlot.clamp(0, pages.length - 1);
  }

  void _step(int delta) {
    final pages = _pages;
    if (pages.isEmpty) return;
    setState(
        () => _previewSlot = (_previewSlot + delta).clamp(0, pages.length - 1));
  }

  void _print() {
    final pages = _pages;
    if (pages.isEmpty) {
      setState(() => _rangeInvalid = true);
      return;
    }
    Navigator.of(context).pop(pages);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    final theme = Theme.of(context);
    final pages = _pages;
    final previewPage =
        pages.isEmpty ? null : pages[_previewSlot.clamp(0, pages.length - 1)];

    // The dialog is desktop-first (it only opens where the OS print flow has
    // no preview of its own), but stay inside a small window rather than
    // overflowing it. AlertDialog doesn't scroll its content, so leave room
    // for the title, the actions and the dialog's own insets.
    final media = MediaQuery.of(context);
    final width = (media.size.width * 0.9).clamp(280.0, 460.0);
    final height = (media.size.height - 220).clamp(240.0, 560.0);

    return AlertDialog(
      key: const ValueKey('print-preview-dialog'),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.printPreviewTitle),
          MiddleEllipsisText(
            widget.title,
            hidePdfExtension: true,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: previewPage == null
                  ? const SizedBox.shrink()
                  : _PagePreview(
                      document: widget.document,
                      pageIndex: previewPage,
                    ),
            ),
            const SizedBox(height: 8),
            _pageNavigator(l10n, pages, previewPage),
            const Divider(height: 24),
            _rangeControls(l10n, theme),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('print-preview-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('print-preview-print'),
          onPressed: _print,
          child: Text(l10n.printPreviewPrint),
        ),
      ],
    );
  }

  /// "‹ Page 3 of 12 ›" over the selection, so the arrows walk exactly the
  /// pages that will come out of the printer.
  Widget _pageNavigator(
      AppLocalizations l10n, List<int> pages, int? previewPage) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('print-preview-previous'),
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.printPreviewPreviousPage,
          onPressed: _previewSlot > 0 ? () => _step(-1) : null,
        ),
        Text(
          previewPage == null
              ? '—'
              : l10n.printPreviewPageOf(previewPage + 1, _pageCount),
        ),
        IconButton(
          key: const ValueKey('print-preview-next'),
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.printPreviewNextPage,
          onPressed: _previewSlot < pages.length - 1 ? () => _step(1) : null,
        ),
      ],
    );
  }

  Widget _rangeControls(AppLocalizations l10n, ThemeData theme) {
    Widget field(String label, TextEditingController controller, Key key) =>
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _onRangeEdited(),
            onSubmitted: (_) => _print(),
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Long translations of three labels overrun a narrow dialog, and a
        // SegmentedButton neither wraps nor scrolls - scale it down instead.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SegmentedButton<PrintPageRange>(
            segments: [
              ButtonSegment(
                value: PrintPageRange.all,
                label: Text(l10n.printPreviewAll,
                    key: const ValueKey('print-preview-all')),
              ),
              ButtonSegment(
                value: PrintPageRange.current,
                label: Text(l10n.printPreviewCurrent,
                    key: const ValueKey('print-preview-current')),
              ),
              ButtonSegment(
                value: PrintPageRange.custom,
                label: Text(l10n.printPreviewRange,
                    key: const ValueKey('print-preview-custom')),
              ),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => _setRange(selection.first),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          field(l10n.printPreviewFrom, _from,
              const ValueKey('print-preview-from')),
          const SizedBox(width: 16),
          field(l10n.printPreviewTo, _to, const ValueKey('print-preview-to')),
        ]),
        const SizedBox(height: 8),
        Text(
          _rangeInvalid
              ? l10n.printPreviewRangeError(_pageCount)
              : l10n.printPreviewSelection(_pages.length),
          style: theme.textTheme.bodySmall?.copyWith(
            color: _rangeInvalid ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

/// One page rendered for the preview, fit into the space it is given.
///
/// The page is rasterised (rather than replayed as a picture on every paint)
/// for the same reason the thumbnail strip does it: the raster is painted for
/// free on scroll/resize, and a `ui.Image` is safe to dispose the moment it is
/// replaced.
class _PagePreview extends StatefulWidget {
  const _PagePreview({required this.document, required this.pageIndex});

  final PdfDocument document;
  final int pageIndex;

  @override
  State<_PagePreview> createState() => _PagePreviewState();
}

class _PagePreviewState extends State<_PagePreview> {
  ui.Image? _image;
  Size _pageSize = Size.zero;

  /// Guards against an out-of-order render landing: a fast click through the
  /// pages starts several, and only the newest may be shown.
  int _token = 0;

  /// The `(page, width bucket)` the shown image was rendered for.
  (int, int)? _rendered;

  bool _failed = false;

  @override
  void dispose() {
    _token++; // orphan any render still in flight
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  /// Renders [pageIndex] at [logicalWidth], unless that is already on screen.
  ///
  /// The width is bucketed so a resize drag doesn't queue a render per pixel.
  void _renderIfNeeded(int pageIndex, double logicalWidth, double ratio) {
    final bucket = (logicalWidth / 32).ceil();
    if (_rendered == (pageIndex, bucket)) return;
    _rendered = (pageIndex, bucket);
    final token = ++_token;
    final pixelWidth = bucket * 32 * ratio;
    () async {
      try {
        final page = widget.document.page(pageIndex);
        final size = PdfPageRenderer.pageSize(page);
        // Annotations print (the vector encoder keeps them), so preview them.
        final image = await PdfPageRenderer.renderImage(
          page,
          pixelRatio:
              size.width <= 0 ? 1.0 : (pixelWidth / size.width).clamp(0.2, 4.0),
        );
        if (!mounted || token != _token) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _pageSize = size;
          _failed = false;
        });
      } catch (_) {
        // A page this engine can't render still prints (the printer path has
        // its own fallbacks), so this is a preview-only miss.
        if (!mounted || token != _token) return;
        setState(() {
          _image?.dispose();
          _image = null;
          _failed = true;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(builder: (context, constraints) {
      // Render outside the build (a setState from inside one is illegal).
      final width =
          constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _renderIfNeeded(widget.pageIndex, width, ratio);
      });
      final image = _image;
      if (image == null) {
        return Center(
          child: _failed
              ? Text(appL10n(context).printPreviewUnavailable)
              : const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio:
              _pageSize.height <= 0 ? 1 : _pageSize.width / _pageSize.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: CustomPaint(
              key: const ValueKey('print-preview-page'),
              painter: _PagePreviewPainter(image),
            ),
          ),
        ),
      );
    });
  }
}

class _PagePreviewPainter extends CustomPainter {
  const _PagePreviewPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PagePreviewPainter old) => !identical(old.image, image);
}

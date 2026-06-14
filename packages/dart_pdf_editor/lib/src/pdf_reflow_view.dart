import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'image_decoder.dart';

/// A text-first view of a PDF document.
///
/// The PDF page graphics are not rendered here. Instead the content stream is
/// interpreted for positioned text and images, then [PdfTextExtractor] infers
/// visual lines, reading order, and paragraph blocks, interleaving the page's
/// figures and diagrams in place. This is useful for narrow screens and
/// accessibility-style reading where fixed page layout is less important than
/// continuous, reflowable content.
class PdfReflowView extends StatefulWidget {
  const PdfReflowView({
    super.key,
    required this.document,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    this.maxWidth = 760,
    this.showImages = true,
  });

  final PdfDocument document;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  /// Whether to interleave the page's images and diagrams with the text.
  /// When false the view is text-only (the historical behaviour).
  final bool showImages;

  @override
  State<PdfReflowView> createState() => _PdfReflowViewState();
}

class _ReflowContent {
  const _ReflowContent(this.pages, this.images);

  final List<PdfReflowPage> pages;

  /// Decoded images keyed by [pdfImageKey]; a key is absent when the image
  /// could not be decoded.
  final Map<Object, ui.Image> images;
}

class _PdfReflowViewState extends State<PdfReflowView> {
  late Future<_ReflowContent> _content;
  Map<Object, ui.Image> _ownedImages = const {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  @override
  void didUpdateWidget(PdfReflowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.document, oldWidget.document) ||
        widget.showImages != oldWidget.showImages) {
      _content = _load();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _disposeImages();
    super.dispose();
  }

  void _disposeImages() {
    for (final image in _ownedImages.values) {
      image.dispose();
    }
    _ownedImages = const {};
  }

  Future<_ReflowContent> _load() async {
    // Give the first frame a chance to show progress before long documents walk
    // every content stream.
    await Future<void>.delayed(Duration.zero);
    final pages = [
      for (var i = 0; i < widget.document.pageCount; i++)
        PdfTextExtractor.reflowPage(widget.document, i),
    ];
    var images = const <Object, ui.Image>{};
    if (widget.showImages) {
      final requests = [
        for (final page in pages)
          for (final image in page.images) image.request,
      ];
      if (requests.isNotEmpty) {
        images = await decodeImages(widget.document.cos, requests,
            cache: PdfImageCache.instance);
      }
    }
    // The decoded clones are ours to dispose; drop the previous load's set
    // and hold the new one for the widget's life (and reloads).
    _disposeImages();
    _ownedImages = images;
    return _ReflowContent(pages, images);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerLowest;
    return ColoredBox(
      color: background,
      child: FutureBuilder<_ReflowContent>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final content = snapshot.data;
          final pages = content?.pages ?? const <PdfReflowPage>[];
          bool empty(PdfReflowPage page) =>
              widget.showImages ? page.items.isEmpty : page.blocks.isEmpty;
          if (pages.every(empty)) {
            return Center(
              child: Text(
                'No extractable content',
                style: theme.textTheme.bodyLarge,
              ),
            );
          }
          // A non-lazy scroll lays every page out once, so the total scroll
          // extent is exact and the scrollbar thumb stays put. A lazy
          // ListView estimates the extent from built children, which jumps
          // as reflow pages of wildly different heights (text vs. tall image
          // pages) come into view — the heights can't be precomputed because
          // they depend on text wrap and image aspect ratio.
          final imageMap = content?.images ?? const <Object, ui.Image>{};
          return Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              key: const ValueKey('pdf-reflow-view'),
              controller: _scrollController,
              padding: widget.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final page in pages)
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: widget.maxWidth),
                        child: RepaintBoundary(
                          child: _ReflowPage(
                            page: page,
                            images: imageMap,
                            showImages: widget.showImages,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReflowPage extends StatelessWidget {
  const _ReflowPage({
    required this.page,
    required this.images,
    required this.showImages,
  });

  final PdfReflowPage page;
  final Map<Object, ui.Image> images;
  final bool showImages;

  @override
  Widget build(BuildContext context) {
    final items = showImages
        ? page.items
        : page.items.whereType<PdfReflowBlock>().toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final median = _median(page.blocks.map((block) => block.fontSize));
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Page ${page.pageIndex + 1}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: switch (item) {
                final PdfReflowBlock block => _block(theme, block, median),
                final PdfReflowImage image => _image(theme, image),
              },
            ),
        ],
      ),
    );
  }

  Widget _block(ThemeData theme, PdfReflowBlock block, double pageMedian) {
    final text = SelectableText(
      block.text,
      style: _styleFor(theme, block, pageMedian),
    );
    if (!block.isListItem) return text;
    // Hang the wrapped lines under the marker's text.
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: text,
    );
  }

  Widget _image(ThemeData theme, PdfReflowImage image) {
    final decoded = images[pdfImageKey(image.request)];
    if (decoded == null) {
      // Undecodable (or images turned off): leave a labelled placeholder so the
      // reading position still reflects that something sat here.
      return _ImagePlaceholder(aspectRatio: image.aspectRatio);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: AspectRatio(
        aspectRatio: image.aspectRatio <= 0 ? 1 : image.aspectRatio,
        child: RawImage(
          image: decoded,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }

  TextStyle? _styleFor(
      ThemeData theme, PdfReflowBlock block, double pageMedian) {
    final base = block.fontSize >= pageMedian * 1.3
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyLarge;
    return base?.copyWith(
      height: 1.45,
      fontWeight: block.fontSize >= pageMedian * 1.3
          ? FontWeight.w600
          : base.fontWeight,
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.aspectRatio});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: aspectRatio <= 0 ? 1 : aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

double _median(Iterable<double> values) {
  final sorted = [...values]..sort();
  if (sorted.isEmpty) return 0;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

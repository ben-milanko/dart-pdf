import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../page_geometry.dart';
import '../renderer.dart';

/// A small card showing [annotation]'s rendered normal appearance, fitted
/// into [width] x [height] - the leading preview of the annotation list and
/// the annotation library.
///
/// The card is always white paper, whatever the theme: appearances are
/// authored against a page, and a Multiply highlight or a black ink stroke
/// would vanish on a dark panel. [icon] stands in while the picture renders
/// and for annotations that carry no appearance stream (links, most
/// widgets, unrendered notes).
///
/// The picture is re-rendered whenever [page] or [annotation] is a new
/// object (every revision rebuilds both); the previous picture stays on
/// screen until its replacement lands, so an edit elsewhere never flashes
/// the row back to its icon.
class PdfAnnotationAppearancePreview extends StatefulWidget {
  const PdfAnnotationAppearancePreview({
    super.key,
    required this.page,
    required this.annotation,
    required this.icon,
    this.rotation,
    this.width = 48,
    this.height = 40,
  });

  /// The page [annotation] renders against (resources, crop box, /Rotate).
  final PdfPage page;
  final PdfAnnotation annotation;

  /// The fallback glyph while loading or when there is nothing to render.
  final IconData icon;

  /// The display rotation to render at; null uses the page's /Rotate, so
  /// the preview reads the way the annotation does on screen.
  final int? rotation;
  final double width;
  final double height;

  /// The margin, in logical pixels, kept between the artwork and the edge
  /// of the card.
  static const double inset = 3;

  /// The largest upscale applied to a tiny annotation, so a 4pt dot does
  /// not balloon into a blob.
  static const double maxScale = 4;

  @override
  State<PdfAnnotationAppearancePreview> createState() =>
      _PdfAnnotationAppearancePreviewState();
}

class _PdfAnnotationAppearancePreviewState
    extends State<PdfAnnotationAppearancePreview> {
  ui.Picture? _picture;

  /// The annotation's box in the picture's page raster space.
  Rect? _from;

  /// Bumped per render request so a slow, superseded render is discarded.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(PdfAnnotationAppearancePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.page, widget.page) ||
        !identical(oldWidget.annotation, widget.annotation) ||
        oldWidget.rotation != widget.rotation) {
      _render();
    }
  }

  @override
  void dispose() {
    _generation++;
    _picture?.dispose();
    super.dispose();
  }

  void _render() {
    final generation = ++_generation;
    final page = widget.page;
    final annotation = widget.annotation;
    final rotation = widget.rotation ?? page.rotation;
    if (annotation.normalAppearance == null) {
      _replace(null, null);
      return;
    }
    final geometry = PdfPageGeometry(
      cropBox: page.cropBox,
      rotation: rotation,
      viewSize: PdfPageRenderer.pageSize(page, rotation: rotation),
    );
    final from = geometry.toViewRect(annotation.rect);
    unawaited(() async {
      ui.Picture? picture;
      try {
        picture = await PdfPageRenderer.renderAnnotationPicture(
            page, annotation,
            rotation: rotation);
      } catch (_) {
        // an unrenderable appearance keeps the icon
      }
      if (!mounted || generation != _generation) {
        picture?.dispose();
        return;
      }
      setState(() => _replace(picture, from));
    }());
  }

  void _replace(ui.Picture? picture, Rect? from) {
    _picture?.dispose();
    _picture = picture;
    _from = from;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picture = _picture;
    final from = _from;
    final hasArtwork = picture != null &&
        from != null &&
        from.width.isFinite &&
        from.height.isFinite &&
        (from.width > 0 || from.height > 0);
    // a row's artwork only changes when its picture does; isolate it from
    // the list's scroll and hover repaints
    return RepaintBoundary(
        child: Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: hasArtwork
          ? CustomPaint(
              painter: _AppearancePainter(picture: picture, from: from),
            )
          : Center(
              // the card is white in every theme, so the icon is too dark
              // to read if it followed onSurface in a dark theme
              child: Icon(widget.icon,
                  size: math.min(22, widget.height * 0.55),
                  color: const Color(0xFF5F6368)),
            ),
    ));
  }
}

class _AppearancePainter extends CustomPainter {
  const _AppearancePainter({required this.picture, required this.from});

  final ui.Picture picture;
  final Rect from;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = PdfAnnotationAppearancePreview.inset;
    final room = Size(
      math.max(1, size.width - 2 * inset),
      math.max(1, size.height - 2 * inset),
    );
    // a zero-thickness box (a horizontal line's tight /Rect) still fits by
    // its long side
    final w = math.max(from.width, 1e-3);
    final h = math.max(from.height, 1e-3);
    final scale = math.min(
      PdfAnnotationAppearancePreview.maxScale,
      math.min(room.width / w, room.height / h),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-from.center.dx, -from.center.dy);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppearancePainter oldDelegate) =>
      !identical(oldDelegate.picture, picture) || oldDelegate.from != from;
}

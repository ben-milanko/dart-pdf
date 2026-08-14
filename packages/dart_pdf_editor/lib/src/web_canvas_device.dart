import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:web/web.dart' as web;

import 'font_substitution.dart';
import 'web_surface_profile.dart';

bool _sameDoubles(List<double>? a, List<double> b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// The SDK's typed-array view constructor was surfaced as a Dart helper in
// 3.6, while this package still supports 3.5. Bind the same browser constructor
// directly so the zero-copy opaque-image path remains available throughout
// the package's declared SDK range.
@JS('Uint8ClampedArray')
extension type _Uint8ClampedArrayView._(JSUint8ClampedArray _)
    implements JSUint8ClampedArray {
  external factory _Uint8ClampedArrayView(
    JSArrayBuffer buffer,
    int byteOffset,
    int length,
  );
}

/// Paints the deliberately small zero-copy browser surface profile.
///
/// The capability check runs before the canvas is resized or touched. A page
/// outside this profile therefore leaves the transferred canvas transparent
/// and the Flutter raster beneath it remains the correctness fallback. The
/// The profile covers ordinary paths, substituted text, and worker-decoded
/// images. It proves the worker-owned presentation seam without claiming that
/// Canvas2D is already a replacement for the full PDF compositor.
bool paintPdfBrowserPageSurface({
  required web.OffscreenCanvas canvas,
  required PdfPage page,
  required List<PdfRenderCommand> commands,
  required int width,
  required int height,
  required int pageColor,
  required int? rotation,
  ({
    double left,
    double top,
    double right,
    double bottom,
    double pixelRatio,
  })? region,
  bool commandsAreValidated = false,
  Map<Object, web.CanvasImageSource> browserImages = const {},
}) {
  if (!commandsAreValidated && !supportsPdfTextPageSurface(commands)) {
    return false;
  }
  // Browser canvas limits vary. Never resize first and discover a failed or
  // catastrophically large allocation afterwards: declining leaves the
  // established SkWasm pixels underneath as the correctness fallback.
  if (width <= 0 ||
      height <= 0 ||
      width > 16384 ||
      height > 16384 ||
      width * height > 64 * 1024 * 1024) {
    return false;
  }
  if (region != null &&
      (!region.left.isFinite ||
          !region.top.isFinite ||
          !region.right.isFinite ||
          !region.bottom.isFinite ||
          !region.pixelRatio.isFinite ||
          region.right <= region.left ||
          region.bottom <= region.top ||
          region.pixelRatio <= 0)) {
    return false;
  }

  canvas
    ..width = width
    ..height = height;
  final context =
      canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
  if (context == null) return false;

  context
    ..resetTransform()
    ..globalAlpha = 1
    ..globalCompositeOperation = 'source-over'
    ..fillStyle = _argbCss(pageColor).toJS
    ..fillRect(0, 0, width, height);

  final matrix = region == null
      ? _pageToDevice(page, width, height, rotation)
      : _pageToDeviceAtRatio(page, region.pixelRatio, rotation).concat(
          PdfMatrix.translation(
            -region.left * region.pixelRatio,
            -region.top * region.pixelRatio,
          ),
        );
  context.transform(
    matrix.a,
    matrix.b,
    matrix.c,
    matrix.d,
    matrix.e,
    matrix.f,
  );
  final scale = math.max(
    math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b),
    math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d),
  );
  replayCommands(
    commands,
    _BrowserCanvasDevice(
      context,
      scale > 0 ? 1 / scale : 1,
      browserImages,
    ),
  );
  return true;
}

PdfMatrix _pageToDevice(
    PdfPage page, int width, int height, int? rotationOverride) {
  final box = page.cropBox;
  final rotation = rotationOverride ?? page.rotation;
  final swap = rotation == 90 || rotation == 270;
  final pageWidth = swap ? box.height : box.width;
  final pageHeight = swap ? box.width : box.height;
  final ratio = pageWidth > 0 && pageHeight > 0
      ? (width / pageWidth + height / pageHeight) / 2
      : 1.0;
  return _pageToDeviceAtRatio(page, ratio, rotationOverride);
}

PdfMatrix _pageToDeviceAtRatio(
    PdfPage page, double ratio, int? rotationOverride) {
  final box = page.cropBox;
  final rotation = rotationOverride ?? page.rotation;
  final swap = rotation == 90 || rotation == 270;
  final pageWidth = swap ? box.height : box.width;
  final pageHeight = swap ? box.width : box.height;
  var matrix = PdfMatrix.translation(-box.left, -box.bottom)
      .concat(const PdfMatrix(1, 0, 0, -1, 0, 0))
      .concat(PdfMatrix.translation(0, box.height));
  switch (rotation) {
    case 90:
      matrix = matrix
          .concat(const PdfMatrix(0, 1, -1, 0, 0, 0))
          .concat(PdfMatrix.translation(pageWidth, 0));
    case 180:
      matrix = matrix
          .concat(const PdfMatrix(-1, 0, 0, -1, 0, 0))
          .concat(PdfMatrix.translation(pageWidth, pageHeight));
    case 270:
      matrix = matrix
          .concat(const PdfMatrix(0, -1, 1, 0, 0, 0))
          .concat(PdfMatrix.translation(0, pageHeight));
  }
  return matrix.concat(PdfMatrix.scaled(ratio, ratio));
}

class _BrowserCanvasDevice implements PdfDevice {
  _BrowserCanvasDevice(this.context, this.hairlineWidth, this.browserImages);

  final web.OffscreenCanvasRenderingContext2D context;
  final double hairlineWidth;
  final Map<Object, web.CanvasImageSource> browserImages;
  final Map<PdfDecodedPixels, web.OffscreenCanvas> _images = {};
  final Map<String, double> _textWidths = {};

  // Canvas2D property writes cross the Dart/JS boundary. Dense CAD pages can
  // contain hundreds of thousands of adjacent strokes with the same colour,
  // caps, joins, and empty dash pattern; assigning all seven properties for
  // every path costs more than the actual stroke. Cache the observable canvas
  // state in Dart and write only changes. A PDF restore can reveal an older JS
  // state, so invalidate after it rather than trying to shadow the full stack.
  String? _fillStyle;
  String? _strokeStyle;
  double? _lineWidth;
  String? _lineCap;
  String? _lineJoin;
  double? _miterLimit;
  List<double>? _lineDash;
  double? _lineDashOffset;

  @override
  void save() => context.save();

  @override
  void restore() {
    context.restore();
    _fillStyle = null;
    _strokeStyle = null;
    _lineWidth = null;
    _lineCap = null;
    _lineJoin = null;
    _miterLimit = null;
    _lineDash = null;
    _lineDashOffset = null;
  }

  void _path(PdfPath path) {
    context.beginPath();
    final cursor = path.cursor();
    while (cursor.moveNext()) {
      switch (cursor.verb) {
        case PdfPathVerb.moveTo:
          context.moveTo(cursor.x1, cursor.y1);
        case PdfPathVerb.lineTo:
          context.lineTo(cursor.x1, cursor.y1);
        case PdfPathVerb.cubicTo:
          context.bezierCurveTo(
              cursor.x1, cursor.y1, cursor.x2, cursor.y2, cursor.x3, cursor.y3);
        case PdfPathVerb.close:
          context.closePath();
      }
    }
  }

  void _paintWithAlpha(double alpha, void Function() paint) {
    final value = alpha.clamp(0.0, 1.0);
    if (value == 1) {
      paint();
      return;
    }
    final previous = context.globalAlpha;
    context.globalAlpha = value;
    try {
      paint();
    } finally {
      context.globalAlpha = previous;
    }
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    _path(path);
    final fillStyle = _rgbCss(color);
    if (_fillStyle != fillStyle) {
      context.fillStyle = fillStyle.toJS;
      _fillStyle = fillStyle;
    }
    _paintWithAlpha(
      alpha,
      () => context.fill(
        (rule == PdfFillRule.evenOdd ? 'evenodd' : 'nonzero').toJS,
      ),
    );
  }

  @override
  void strokePath(
    PdfPath path,
    PdfColor color,
    PdfStroke stroke,
    double alpha,
  ) {
    _path(path);
    final strokeStyle = _rgbCss(color);
    if (_strokeStyle != strokeStyle) {
      context.strokeStyle = strokeStyle.toJS;
      _strokeStyle = strokeStyle;
    }
    final lineWidth = pdfCanvas2dStrokeWidth(stroke.width, hairlineWidth);
    if (_lineWidth != lineWidth) {
      context.lineWidth = lineWidth;
      _lineWidth = lineWidth;
    }
    final lineCap = switch (stroke.cap) {
      1 => 'round',
      2 => 'square',
      _ => 'butt',
    };
    if (_lineCap != lineCap) {
      context.lineCap = lineCap;
      _lineCap = lineCap;
    }
    final lineJoin = switch (stroke.join) {
      1 => 'round',
      2 => 'bevel',
      _ => 'miter',
    };
    if (_lineJoin != lineJoin) {
      context.lineJoin = lineJoin;
      _lineJoin = lineJoin;
    }
    if (_miterLimit != stroke.miterLimit) {
      context.miterLimit = stroke.miterLimit;
      _miterLimit = stroke.miterLimit;
    }
    if (_lineDashOffset != stroke.dashPhase) {
      context.lineDashOffset = stroke.dashPhase;
      _lineDashOffset = stroke.dashPhase;
    }
    if (!_sameDoubles(_lineDash, stroke.dashArray)) {
      context.setLineDash(
        stroke.dashArray.map((value) => value.toJS).toList().toJS,
      );
      _lineDash = List<double>.from(stroke.dashArray);
    }
    _paintWithAlpha(alpha, () => context.stroke());
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible || run.text.isEmpty) return;
    const renderSize = 100.0;
    final name = run.fontName ?? '';
    final family = pdfCanvas2dSubstituteFamily(name);
    final weight = name.contains('Bold') ? 'bold' : 'normal';
    final style = name.contains('Italic') || name.contains('Oblique')
        ? 'italic'
        : 'normal';
    final font = '$style $weight ${renderSize}px $family';

    context.save();
    context.transform(
      run.transform.a,
      run.transform.b,
      run.transform.c,
      run.transform.d,
      run.transform.e,
      run.transform.f,
    );
    context
      ..font = font
      ..textAlign = 'left'
      ..textBaseline = 'alphabetic'
      // The exact-placement plan already carries Tc/Tw in its offsets. Keep
      // Canvas2D's own spacing out of its measurements and glyph shapes.
      ..letterSpacing = '0px'
      ..wordSpacing = '0px'
      ..fillStyle = _rgbCss(run.color).toJS;

    final placed = pdfCanvas2dTextLayout(
      run,
      (text) => _textWidths.putIfAbsent(
        '$font\u0000$text',
        () => context.measureText(text).width,
      ),
    );
    if (placed != null) {
      context.scale(1 / placed.unitsPerEm, -1 / renderSize);
      for (final part in placed.parts) {
        context.fillText(part.text, part.x, 0);
      }
      context.restore();
      return;
    }

    context
      ..letterSpacing = '${run.letterSpacing * renderSize}px'
      ..wordSpacing = '${run.wordSpacing * renderSize}px';
    final naturalWidth = context.measureText(run.text).width;
    final scaleX = run.width > 0 && naturalWidth > 0
        ? run.width * renderSize / naturalWidth
        : 1.0;
    context.scale(scaleX / renderSize, -1 / renderSize);
    context.fillText(run.text, 0, 0);
    context.restore();
  }

  @override
  void fillPathGradient(
          PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) =>
      throw UnsupportedError('text surface gradient');
  @override
  void fillMesh(PdfMesh mesh, double alpha) =>
      throw UnsupportedError('text surface mesh');
  @override
  void clipPath(PdfPath path, PdfFillRule rule) =>
      throw UnsupportedError('text surface clip');
  @override
  void drawImage(PdfImageRequest request) {
    final browserImage = browserImages[request.stream];
    final decoded = request.decoded;
    if ((decoded == null && browserImage == null) || request.isStencil) {
      throw UnsupportedError('browser surface image');
    }
    final image = browserImage ??
        _images.putIfAbsent(decoded!, () {
          final source = web.OffscreenCanvas(decoded.width, decoded.height);
          final sourceContext =
              source.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
          if (sourceContext == null) {
            throw UnsupportedError('browser surface image context');
          }
          final JSUint8ClampedArray rgba;
          if (pdfCanvas2dPixelsAreOpaque(decoded)) {
            // dart2js represents Uint8List as Uint8Array. Reinterpret the same
            // buffer as Uint8ClampedArray, which ImageData requires, rather than
            // allocating and copying another full scan-sized RGBA plane.
            final bytes = decoded.rgba.toJS;
            final buffer = bytes.getProperty('buffer'.toJS) as JSArrayBuffer;
            final byteOffset =
                (bytes.getProperty('byteOffset'.toJS) as JSNumber).toDartInt;
            rgba = _Uint8ClampedArrayView(
              buffer,
              byteOffset,
              decoded.rgba.length,
            );
          } else {
            rgba = pdfCanvas2dStraightRgba(decoded).toJS;
          }
          final imageData = web.ImageData(
            rgba,
            decoded.width,
            decoded.height.toJS,
          );
          sourceContext.putImageData(imageData, 0, 0);
          return source;
        });

    context.save();
    context.transform(
      request.transform.a,
      request.transform.b,
      request.transform.c,
      request.transform.d,
      request.transform.e,
      request.transform.f,
    );
    context
      ..translate(0, 1)
      ..scale(1, -1)
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high';
    _paintWithAlpha(
      request.alpha,
      () => context.drawImage(image, 0, 0, 1, 1),
    );
    context.restore();
  }

  @override
  void setBlendMode(PdfBlendMode mode) =>
      throw UnsupportedError('text surface blend');
  @override
  void setOverprint(
          {required bool fill, required bool stroke, required int mode}) =>
      throw UnsupportedError('text surface overprint');
  @override
  void beginGroup(double alpha, {bool knockout = false}) =>
      throw UnsupportedError('text surface group');
  @override
  void endGroup() => throw UnsupportedError('text surface group');
  @override
  void beginSoftMasked() => throw UnsupportedError('text surface soft mask');
  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) =>
      throw UnsupportedError('text surface soft mask');
}

String _rgbCss(PdfColor color) =>
    'rgb(${(color.red * 255).round().clamp(0, 255)} '
    '${(color.green * 255).round().clamp(0, 255)} '
    '${(color.blue * 255).round().clamp(0, 255)})';

String _argbCss(int argb) =>
    'rgba(${(argb >> 16) & 0xff}, ${(argb >> 8) & 0xff}, ${argb & 0xff}, '
    '${((argb >> 24) & 0xff) / 255})';

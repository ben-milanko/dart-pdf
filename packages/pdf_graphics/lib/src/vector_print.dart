/// Lowers a PDF page into a compact, self-contained **vector print** op
/// stream that a native OS print backend can replay onto its own vector canvas
/// (Windows GDI on the printer DC, Linux Cairo on a `GtkPrintOperation`
/// context) without a bundled PDF engine.
///
/// This is the engine-side half of vector printing on Windows and Linux - the
/// two platforms whose OS has no native PDF-print API (issue #303). On the
/// other platforms the OS prints the PDF's own vector content directly; here we
/// have to hand the print system primitives it already understands.
///
/// The stream is deliberately tiny and font-free:
///
///  * All geometry is pre-transformed into **device points**: a top-left
///    origin, x right, y **down**, one unit = one PDF point, with the page's
///    /Rotate and crop-box origin already folded in. The consumer only applies
///    one uniform points→pixels scale (its printer DPI) and a fit/centre
///    offset - it never does matrix math.
///  * **Embedded-font text** is emitted as filled glyph-outline paths (exact,
///    crisp vector, resolution-independent), so the consumer needs no fonts.
///  * **Substituted-font text** (non-embedded standard-14 fonts, which the
///    engine has no outlines for) is emitted as a `text` op carrying the
///    Unicode string, baseline transform and colour, so the consumer draws it
///    with a system font - selectable and searchable in the spooled output.
///  * **Images** are emitted as straight-alpha RGBA rasters with a device-space
///    placement quad - the one thing that legitimately stays raster.
///
/// Transparency, shadings and blend modes are approximated the way a printer
/// flattens them (gradients/meshes fall back to their average colour, group
/// and soft-mask alpha is dropped, a darkening blend like Multiply is lowered
/// to a constant alpha so a highlight stays see-through); these are the
/// documented hard parts.
///
/// The format is decoded back by [decodeVectorPrint] (the reference consumer,
/// used by the tests and mirrored by the native replayers) and the byte layout
/// is specified on [encodeVectorPrintPage].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'image_pixels.dart';
import 'interpreter.dart';
import 'mesh.dart';
import 'path.dart';
import 'recording_device.dart';
import 'render_command.dart';
import 'shading.dart';

/// Magic + version header of a vector-print stream (`VPR` + version 1).
const List<int> kVectorPrintMagic = [0x56, 0x50, 0x52, 0x01]; // 'V' 'P' 'R' 1

// Op tags. Stable within a build; the native replayers hardcode the same
// values, so only append new tags - never renumber.
const int _opSave = 0x01;
const int _opRestore = 0x02;
const int _opFillPath = 0x10;
const int _opStrokePath = 0x11;
const int _opClipPath = 0x12;
const int _opText = 0x20;
const int _opImage = 0x30;

// Path segment tags.
const int _segMove = 0;
const int _segLine = 1;
const int _segCubic = 2;
const int _segClose = 3;

/// Font-style flags packed into the `text` op's flag byte.
const int kVectorPrintFontBold = 0x01;
const int kVectorPrintFontItalic = 0x02;

/// Decodes the RGBA pixels of the images a page references, keyed by request.
///
/// The default ([decodeVectorPrintImagesPure]) is pure Dart, so the encoder
/// runs on a bare VM (tests, CLI, a background isolate). The Flutter app passes
/// a `dart:ui`-backed resolver that can also decode the platform-codec images
/// (baseline JPEG) the pure path declines.
typedef VectorPrintImageDecoder = Future<Map<PdfImageRequest, PdfDecodedPixels>>
    Function(CosDocument cos, List<PdfImageRequest> requests);

/// Pure-Dart image decode: everything [decodePdfImagePixels] can turn into
/// RGBA without the platform codec. Undecodable images (a baseline JPEG needs
/// `dart:ui`) are simply omitted, and the encoder skips drawing them.
Future<Map<PdfImageRequest, PdfDecodedPixels>> decodeVectorPrintImagesPure(
    CosDocument cos, List<PdfImageRequest> requests) async {
  final out = <PdfImageRequest, PdfDecodedPixels>{};
  for (final request in requests) {
    final decoded = request.decoded ?? decodePdfImagePixels(cos, request.stream);
    if (decoded != null) out[request] = decoded;
  }
  return out;
}

/// Interprets [page] and encodes it as a vector-print op stream (see the
/// library doc for the model and [decodeVectorPrint] for the reader).
///
/// [rotation] overrides the page's own /Rotate (used when the caller prints a
/// re-oriented view); [annotations] includes annotation appearances, matching
/// what the viewer paints. [decodeImages] resolves image pixels (defaults to
/// the pure-Dart path).
///
/// ## Byte layout (all little-endian)
///
/// ```
/// header : magic[4]=VPR1, f32 pageWidthPt, f32 pageHeightPt
/// body   : a sequence of ops until end-of-buffer, each a 1-byte tag:
///   0x01 save
///   0x02 restore
///   0x10 fillPath   : rgba[4] u8, fillRule u8(0 nonzero,1 evenOdd), path
///   0x11 strokePath : rgba[4] u8, f32 width, u8 cap, u8 join, f32 miter,
///                     u16 dashCount, f32 dash*dashCount, f32 dashPhase, path
///   0x12 clipPath   : fillRule u8, path
///   0x20 text       : rgba[4] u8, u8 fontFlags, f32 matrix[6] (em->device),
///                     f32 fontSizePt, u16 utf8Len, utf8 bytes
///   0x30 image      : f32 quad[6] (unit-square->device), u32 w, u32 h,
///                     rgba bytes (w*h*4, straight alpha, row-major top-down)
/// path   : u32 segCount, then per segment tag u8:
///   0 move  : f32 x, f32 y
///   1 line  : f32 x, f32 y
///   2 cubic : f32 x1,y1,x2,y2,x3,y3
///   3 close
/// ```
///
/// Coordinates are device points (top-left origin, y down); the consumer scales
/// them by printerDPI/72 and centres the page in the printable area.
Future<Uint8List> encodeVectorPrintPage(
  PdfPage page, {
  int? rotation,
  bool annotations = true,
  VectorPrintImageDecoder decodeImages = decodeVectorPrintImagesPure,
}) async {
  final cos = page.document.cos;

  final recorder = RecordingPdfDevice();
  final interpreter = PdfInterpreter(cos: cos, device: recorder)
    ..drawPageContent(page, page.contentBytes());
  if (annotations) interpreter.drawAnnotations(page, forPrint: true);

  final images = await decodeImages(cos, recorder.imageRequests);

  final geometry = _pageToDevice(page, rotation ?? page.rotation);
  final writer = _VectorPrintWriter()
    ..magic()
    ..f32(geometry.width)
    ..f32(geometry.height);
  final device = _EncodingDevice(writer, geometry.matrix, images);
  replayCommands(recorder.commands, device);
  return writer.take();
}

/// The device transform for a page: maps PDF user space (y-up, crop-box
/// relative) to device points (top-left origin, y-down), with /Rotate folded
/// in - the matrix form of the viewer's own `_applyPageTransform`. Returns it
/// together with the resulting device page size in points.
_PageGeometry _pageToDevice(PdfPage page, int rotation) {
  final box = page.cropBox;
  // Post-rotation device page size: 90/270 swap width and height.
  final swap = rotation == 90 || rotation == 270;
  final width = swap ? box.height : box.width;
  final height = swap ? box.width : box.height;

  // Build the same sequence the canvas applies, as a single matrix. Canvas ops
  // are applied to a point in reverse listed order; PdfMatrix.concat(a, b)
  // means "a then b", so we list them in application order.
  // 1) page space -> crop-relative, y still up
  var m = PdfMatrix.translation(-box.left, -box.bottom);
  // 2) flip y within the *unrotated* crop box height
  m = m.concat(const PdfMatrix.scaled(1, -1));
  m = m.concat(PdfMatrix.translation(0, box.height));
  // 3) apply /Rotate about the origin, then shift back into the +quadrant,
  //    matching canvas.rotate+translate in _applyPageTransform.
  switch (rotation) {
    case 90:
      // canvas: translate(size.width,0); rotate(+90deg)
      m = m.concat(_rotate90()).concat(PdfMatrix.translation(width, 0));
    case 180:
      m = m
          .concat(_rotate180())
          .concat(PdfMatrix.translation(width, height));
    case 270:
      m = m.concat(_rotate270()).concat(PdfMatrix.translation(0, height));
  }
  return _PageGeometry(m, width, height);
}

// +90deg clockwise in a y-down space: (x,y) -> (-y, x). As a row-vector matrix
// [a b c d e f] with x'=a*x+c*y+e, y'=b*x+d*y+f: a=0,b=1,c=-1,d=0.
PdfMatrix _rotate90() => const PdfMatrix(0, 1, -1, 0, 0, 0);
PdfMatrix _rotate180() => const PdfMatrix(-1, 0, 0, -1, 0, 0);
PdfMatrix _rotate270() => const PdfMatrix(0, -1, 1, 0, 0, 0);

class _PageGeometry {
  _PageGeometry(this.matrix, this.width, this.height);
  final PdfMatrix matrix;
  final double width;
  final double height;
}

/// A [PdfDevice] that writes the vector-print op stream. Coordinates arrive in
/// page space and are transformed by [_toDevice] into device points as they
/// are written.
class _EncodingDevice implements PdfDevice {
  _EncodingDevice(this._w, this._toDevice, this._images);

  final _VectorPrintWriter _w;
  final PdfMatrix _toDevice;
  final Map<PdfImageRequest, PdfDecodedPixels> _images;

  /// The blend mode the interpreter last set (gs /BM). The op set has no blend
  /// modes - GDI and Cairo composite source-over - so a darkening blend is
  /// approximated by lowering the paint's alpha ([_flattenAlpha]).
  ///
  /// Pushed/popped by [save]/[restore] ([_blendStack]) so a blend set inside a
  /// form or `q`/`Q` scope cannot leak past it: the interpreter brackets every
  /// form and appearance (and each `q`) with [save]/[restore] but restores its
  /// *own* graphics state on the way out without re-issuing [setBlendMode], so
  /// mirroring the blend on the save stack is what keeps this in step.
  PdfBlendMode _blend = PdfBlendMode.normal;
  final List<PdfBlendMode> _blendStack = [];

  /// Alpha a darkening blend (Multiply/Darken) lowers to for print. A highlight
  /// draws an *opaque* colour whose translucency is entirely the Multiply blend
  /// (both our own highlights and foreign InkHighlights work this way); with the
  /// blend dropped it would print as a solid block that hides the content
  /// underneath. Capping such paint at this alpha instead keeps the linework
  /// readable, the way a highlighter pen and a print flattener both do. No
  /// single alpha reproduces Multiply exactly (over white it stays saturated,
  /// over black it goes dark) - this is the readable-through compromise.
  static const double _blendFlattenAlpha = 0.4;

  /// [alpha] after the current blend mode's print approximation. Darkening
  /// blends are capped at [_blendFlattenAlpha] so an opaque highlight prints
  /// translucent; an already-fainter paint is left as-is (min, not scale).
  double _flattenAlpha(double alpha) => switch (_blend) {
        PdfBlendMode.multiply ||
        PdfBlendMode.darken =>
          alpha < _blendFlattenAlpha ? alpha : _blendFlattenAlpha,
        _ => alpha,
      };

  @override
  void save() {
    _blendStack.add(_blend);
    _w.u8(_opSave);
  }

  @override
  void restore() {
    // Lenient: a malformed stream can emit an unbalanced restore. Keep the
    // current blend rather than underflow.
    if (_blendStack.isNotEmpty) _blend = _blendStack.removeLast();
    _w.u8(_opRestore);
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    if (path.isEmpty) return;
    _w.u8(_opFillPath);
    _w.rgba(color, _flattenAlpha(alpha));
    _w.u8(rule == PdfFillRule.evenOdd ? 1 : 0);
    _writePath(path);
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    // No native gradient in the op set yet - flatten to the average colour,
    // the fallback the device contract sanctions for simple consumers.
    fillPath(path, gradient.averageColor, rule, alpha);
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    // Mesh shadings have no path here; skip. (A future op could carry the
    // triangles; a printer flattening to the average colour is acceptable and
    // callers that care can rasterise.)
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    if (path.isEmpty) return;
    _w.u8(_opStrokePath);
    _w.rgba(color, _flattenAlpha(alpha));
    _w.f32(stroke.width);
    _w.u8(stroke.cap);
    _w.u8(stroke.join);
    _w.f32(stroke.miterLimit);
    // Dash lengths, like the width and the path coordinates, are already in
    // page-space points; the page transform is an isometry (rotation/flip/
    // translation) so device points equal page points 1:1 - nothing to scale.
    _w.u16(stroke.dashArray.length);
    for (final d in stroke.dashArray) {
      _w.f32(d);
    }
    _w.f32(stroke.dashPhase);
    _writePath(path);
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    _w.u8(_opClipPath);
    _w.u8(rule == PdfFillRule.evenOdd ? 1 : 0);
    _writePath(path);
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible) return; // OCR/hidden layers occupy geometry, paint none
    if (run.hasOutlines) {
      _writeGlyphOutlines(run);
      return;
    }
    if (run.text.isEmpty || (!run.fill && run.strokeColor == null)) return;
    // Substituted font: emit selectable system-font text. em space (y-up) ->
    // device via the run transform then the page transform. A stroke-only run
    // (render mode 1) has no fill colour, so paint it in the stroke colour
    // rather than dropping the text.
    final color = run.fill ? run.color : run.strokeColor!;
    final m = run.transform.concat(_toDevice);
    _w.u8(_opText);
    _w.rgba(color, 1);
    _w.u8(_fontFlags(run.fontName));
    _w.matrix(m);
    _w.f32(run.fontSize);
    _w.utf8(run.text);
  }

  void _writeGlyphOutlines(PdfTextRun run) {
    for (final glyph in run.glyphs!) {
      final outline = glyph.outline;
      if (outline == null || outline.isEmpty) continue;
      // Glyph outline is em space (y-up); place it, then map to page then
      // device. Baked into device points so the consumer needs no matrix.
      final m = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform)
          .concat(_toDevice);
      if (run.fill) {
        _w.u8(_opFillPath);
        _w.rgba(run.color, 1);
        _w.u8(0); // glyph outlines fill nonzero
        _writePathTransformed(outline, m);
      }
      if (run.strokeColor != null) {
        _w.u8(_opStrokePath);
        _w.rgba(run.strokeColor!, 1);
        _w.f32(run.strokeWidth > 0 ? run.strokeWidth : 0);
        _w.u8(0);
        _w.u8(0);
        _w.f32(10);
        _w.u16(0);
        _w.f32(0);
        _writePathTransformed(outline, m);
      }
    }
  }

  @override
  void drawImage(PdfImageRequest request) {
    final pixels = _images[request];
    if (pixels == null) return; // undecodable image - skip rather than blank
    // The image transform maps the unit square (image space, y-up) to page
    // space; fold in the page transform so the quad is in device points.
    final m = request.transform.concat(_toDevice);
    _w.u8(_opImage);
    _w.matrix(m);
    _w.u32(pixels.width);
    _w.u32(pixels.height);
    _w.bytes(pixels.rgba);
  }

  @override
  void setBlendMode(PdfBlendMode mode) {
    // No blend op in the set; a darkening blend is instead approximated by
    // lowering subsequent paint alpha (see [_flattenAlpha]). Other modes still
    // flatten to normal.
    _blend = mode;
  }

  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {
    // Overprint (§8.6.7) is a subtractive colorant operation with no
    // equivalent in this print device's op set yet (issue #502).
  }

  @override
  void beginGroup(double alpha, {bool knockout = false}) {
    // Group alpha is dropped (approximated as opaque); the group's own content
    // still flows through the normal callbacks.
  }

  @override
  void endGroup() {}

  @override
  void beginSoftMasked() {}

  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    // The masked content was already emitted at full opacity; the mask itself
    // is not painted (its drawMask closure is intentionally not invoked), so
    // the result is the flattened-opaque approximation a printer would make.
  }

  void _writePath(PdfPath path) => _writePathTransformed(path, _toDevice);

  void _writePathTransformed(PdfPath path, PdfMatrix m) {
    _w.u32(path.segments.length);
    for (final seg in path.segments) {
      switch (seg) {
        case PdfMoveTo(:final x, :final y):
          _w.u8(_segMove);
          _w.point(m, x, y);
        case PdfLineTo(:final x, :final y):
          _w.u8(_segLine);
          _w.point(m, x, y);
        case PdfCubicTo(:final x1, :final y1, :final x2, :final y2, :final x3, :final y3):
          _w.u8(_segCubic);
          _w.point(m, x1, y1);
          _w.point(m, x2, y2);
          _w.point(m, x3, y3);
        case PdfClosePath():
          _w.u8(_segClose);
      }
    }
  }
}

int _fontFlags(String? fontName) {
  if (fontName == null) return 0;
  final n = fontName.toLowerCase();
  var flags = 0;
  if (n.contains('bold')) flags |= kVectorPrintFontBold;
  if (n.contains('italic') || n.contains('oblique')) {
    flags |= kVectorPrintFontItalic;
  }
  return flags;
}

/// Grows a byte buffer for the op stream. Scalars are little-endian; floats are
/// f32 (the render engine already truncates path coordinates to float32, so
/// this is lossless for geometry).
class _VectorPrintWriter {
  // copy: true because the scratch buffer below is reused for every scalar;
  // a non-copying builder would alias the same mutating bytes into every entry.
  final BytesBuilder _b = BytesBuilder(copy: true);
  final ByteData _scratch = ByteData(8);

  void magic() => _b.add(kVectorPrintMagic);

  void u8(int v) => _b.addByte(v & 0xff);

  void u16(int v) {
    _scratch.setUint16(0, v, Endian.little);
    _b.add(_scratch.buffer.asUint8List(0, 2));
  }

  void u32(int v) {
    _scratch.setUint32(0, v, Endian.little);
    _b.add(_scratch.buffer.asUint8List(0, 4));
  }

  void f32(double v) {
    _scratch.setFloat32(0, v, Endian.little);
    _b.add(_scratch.buffer.asUint8List(0, 4));
  }

  void rgba(PdfColor color, double alpha) {
    _b.addByte(_channel(color.red));
    _b.addByte(_channel(color.green));
    _b.addByte(_channel(color.blue));
    _b.addByte(_channel(alpha));
  }

  void matrix(PdfMatrix m) {
    f32(m.a);
    f32(m.b);
    f32(m.c);
    f32(m.d);
    f32(m.e);
    f32(m.f);
  }

  void point(PdfMatrix m, double x, double y) {
    f32(m.transformX(x, y));
    f32(m.transformY(x, y));
  }

  void utf8(String s) {
    final bytes = _utf8Encode(s);
    u16(bytes.length);
    _b.add(bytes);
  }

  void bytes(Uint8List data) => _b.add(data);

  Uint8List take() => _b.takeBytes();

  static int _channel(double v) => (v.clamp(0.0, 1.0) * 255).round();
}

Uint8List _utf8Encode(String s) {
  // Bounded to a u16 length prefix; clip pathological runs rather than overflow.
  final bytes = utf8.encode(s);
  return bytes.length <= 0xffff
      ? Uint8List.fromList(bytes)
      : Uint8List.fromList(bytes.sublist(0, 0xffff));
}

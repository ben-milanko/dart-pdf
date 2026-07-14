import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'image_pixels.dart';
import 'matrix.dart';
import 'mesh.dart';
import 'path.dart';
import 'render_command.dart';
import 'shading.dart';

/// Binary (de)serialization for a recorded [PdfRenderCommand] buffer.
///
/// The record/replay split produces a flat, `dart:ui`-free command list. To
/// move the recording onto another thread (a native isolate, or a Web Worker
/// reached over `postMessage`) the list has to cross a boundary that copies
/// only plain data - not live Dart objects. This codec flattens the buffer to
/// a [Uint8List] and back: re-serializing a decoded buffer yields the same
/// bytes. Path coordinates are carried at float32 precision (see [_writePath]),
/// which the render engine's own float32 truncation makes pixel-lossless;
/// everything else round-trips exactly.
///
/// Every command and value type the interpreter emits is a pure value
/// ([PdfPath], [PdfColor], [PdfMatrix], [PdfTextRun] with glyph outlines, …)
/// EXCEPT [PdfImageRequest], whose `stream` is a live [CosStream] (a COS
/// dictionary plus encoded bytes, often with nested references - colour
/// spaces, soft masks). Serializing that faithfully means serializing a slice
/// of the COS object graph: [serializeCommands] (given the source [CosDocument]
/// via `cos`) does exactly that for image XObjects - it inline-resolves the
/// image's stream subgraph (every [CosReference] replaced by a detached copy
/// of its resolved target, and every nested stream's bytes decrypted-but-still-
/// filtered so the consumer re-runs the filters), then writes that self-
/// contained tree. The consumer reconstructs the stream and decodes it with the
/// unchanged image decoder. This matters on CAD documents, whose drawing sheets
/// carry embedded raster underlays - without it the heaviest pages decline and
/// interpret synchronously on the UI thread.
///
/// Two cases still decline (the buffer serializes to `null`, and the caller
/// renders the page on the owning isolate): an INLINE image (`BI .. ID .. EI`),
/// whose `/CS` may name a page-resource colour space that isn't reachable from
/// the stream alone; and any image when no `cos` is supplied. Image-free pages
/// - the dense vector/text pages that also dominate the interpret cost -
/// serialize regardless.
///
/// Format: little notion of versioning beyond a leading byte; the producer and
/// consumer are the same build, shipped together, so a version mismatch is a
/// programming error, asserted on read.
const int _formatVersion = 2;

/// Microseconds spent reconstructing worker command buffers on the consuming
/// isolate. Accumulated for performance probes; this is the UI-thread half of
/// the record path and intentionally mirrors `decodeStripPlanMicros`.
int deserializeCommandsMicros = 0;

// Command tags. Stable within a build; order mirrors the sealed hierarchy.
const int _tSave = 0;
const int _tRestore = 1;
const int _tFillPath = 2;
const int _tFillPathGradient = 3;
const int _tFillMesh = 4;
const int _tStrokePath = 5;
const int _tClipPath = 6;
const int _tDrawText = 7;
const int _tDrawImage = 8;
const int _tSetBlendMode = 9;
const int _tBeginGroup = 10;
const int _tEndGroup = 11;
const int _tBeginSoftMasked = 12;
const int _tEndSoftMasked = 13;

/// Thrown internally when an image cannot be serialized (an inline image, or
/// no [CosDocument] to resolve against); [serializeCommands] catches it and
/// returns `null` so the caller falls back to a local render.
class _UnserializableImage implements Exception {
  const _UnserializableImage();
}

/// Serializes [commands] to bytes, or returns `null` if the buffer draws an
/// image that cannot be serialized (see the class doc). Image XObjects are
/// serialized by inline-resolving their stream subgraph against [cos]; pass it
/// whenever the buffer may contain images.
/// When [decodeImages] is true, the serializer ALSO decodes each image's
/// pixels off-thread (via the pure-Dart [decodePdfImagePixels]) and embeds the
/// premultiplied RGBA beside the command, so the consumer skips the decode and
/// only runs the engine codec - issue #73's image-decode offload. Images that
/// need the platform JPEG codec carry no pixels and decode locally as before.
/// When [imagePlaceholders] is true and [decodeImages] is false, images that
/// cannot be serialized as self-contained streams are kept as draw-image
/// placeholders. Replaying the buffer with images disabled then preserves the
/// page's vector/text command stream without forcing the caller to render the
/// whole page locally.
///
/// [maxImagePixelRatio] (screen pixels per page point, including the device
/// pixel ratio) caps the resolution of each decoded image to ~2× the pixels it
/// covers on screen - a giant raster underlay on a CAD sheet is shipped (and
/// later rasterized, and cached) at display resolution instead of its native
/// 100+ megapixels, which is what otherwise blocks the (single-threaded, on
/// web) raster thread for hundreds of milliseconds every time a settled scroll
/// re-rasters the page. Null leaves images at native resolution (the historic
/// behavior). Only consulted when [decodeImages] is true.
///
/// [imageDecodeRegion], when supplied, is a PDF page-space rectangle for the
/// visible detail patch. Axis-aligned image draws are decoded only for the
/// intersecting source pixels and their image transform is retargeted to the
/// cropped page area; unsupported transforms fall back to the full scaled
/// decode. The total decoded-image budget is also reduced to the region's own
/// raster footprint, rather than the full-page raster budget.
///
/// [compactStateScopes] removes `save`/`restore` pairs whose scope never
/// changes the device clip. Recorded geometry, image transforms, paint, and
/// blend state are already explicit in the commands (the interpreter also
/// emits blend restoration explicitly), so those pairs are redundant for
/// replay. Clip-bearing scopes remain byte-for-byte ordered. Render workers
/// enable this to shrink dense command buffers before they cross to the UI
/// isolate; the default stays false so the public codec remains a lossless
/// command-transcript round trip.
/// The page raster never exceeds this many pixels (the viewer's full-page
/// raster cap), so it is also the natural unit for the page image budget.
const int _maxImagePixels = 1 << 24;

/// Total decoded image pixels per page are bounded to this multiple of
/// [_maxImagePixels]. The per-image cap keeps each image near its own
/// on-screen footprint, but a sheet layered from dozens of overlapping raster
/// tiles can still sum to many times the page raster - only the topmost layer
/// per pixel is ever shown, so the rest is decoded, shipped, and cached for
/// nothing. This ceiling (~17 MP at the default) scales every image down to
/// fit, bounding the command buffer and the decoded-image cache no matter how
/// the sheet is layered. Larger keeps more sharpness on heavy overlap at the
/// cost of a bigger payload.
const double _imageBudgetFactor = 1.0;

int _imageBudgetPixels(double ratio, double factor,
    {PdfRect? imageDecodeRegion}) {
  var budget = (factor * _maxImagePixels).round();
  if (imageDecodeRegion != null &&
      imageDecodeRegion.width > 0 &&
      imageDecodeRegion.height > 0 &&
      ratio > 0) {
    final regionPixels =
        (imageDecodeRegion.width * imageDecodeRegion.height * ratio * ratio)
            .round();
    if (regionPixels > 0 && regionPixels < budget) {
      budget = (factor * regionPixels).round().clamp(1, budget);
    }
  }
  return budget;
}

Uint8List? serializeCommands(List<PdfRenderCommand> commands,
    {CosDocument? cos,
    bool decodeImages = false,
    double? maxImagePixelRatio,
    PdfRect? imageDecodeRegion,
    double imageBudgetFactor = _imageBudgetFactor,
    bool imagePlaceholders = false,
    int? commandLimit,
    bool compactStateScopes = false}) {
  final wireCommands = compactStateScopes
      ? _compactStateScopes(commands, commandLimit: commandLimit)
      : commands;
  final w = _Writer();
  w.u8(_formatVersion);
  // Page-pixel budget: a global downscale applied on top of the per-image
  // cap so the sum of all decoded images fits within a few page rasters. 1.0
  // (no-op) unless decoding with a per-image cap active and the page's images
  // overflow the budget.
  var budgetScale = 1.0;
  if (decodeImages && maxImagePixelRatio != null && cos != null) {
    budgetScale = _imageBudgetScale(
        wireCommands,
        cos,
        maxImagePixelRatio,
        _imageBudgetPixels(maxImagePixelRatio, imageBudgetFactor,
            imageDecodeRegion: imageDecodeRegion),
        imageDecodeRegion: imageDecodeRegion);
  }
  try {
    _writeCommands(w, wireCommands, cos,
        decode: decodeImages,
        maxImageRatio: maxImagePixelRatio,
        imageDecodeRegion: imageDecodeRegion,
        budgetScale: budgetScale,
        imagePlaceholders: imagePlaceholders && !decodeImages,
        commandLimit: compactStateScopes ? null : commandLimit);
  } on _UnserializableImage {
    return null;
  }
  return w.takeBytes();
}

/// Drops replay-state scopes that cannot change rendering.
///
/// A recorded `q`/`Q` pair only has an observable device effect when a clip
/// is installed at that same nesting depth. Paths are already transformed to
/// page space, every paint command owns its complete style, images own their
/// transform, and the interpreter emits an explicit blend-mode command when
/// `Q` restores a different blend. Nested clip scopes protect themselves, so
/// they do not make an otherwise empty parent scope necessary.
///
/// The command prefix is taken before compaction to preserve [commandLimit]'s
/// existing preview semantics. Unbalanced prefixes keep their unmatched
/// state commands. Soft-mask callback transcripts are compacted recursively.
List<PdfRenderCommand> _compactStateScopes(
  List<PdfRenderCommand> commands, {
  int? commandLimit,
}) {
  final length = commandLimit == null
      ? commands.length
      : math.min(commands.length, math.max(0, commandLimit));
  final keep = Uint8List(length)..fillRange(0, length, 1);
  final saveIndices = <int>[];
  final clipped = <bool>[];
  var removed = 0;

  for (var i = 0; i < length; i++) {
    switch (commands[i]) {
      case PdfSaveCommand():
        saveIndices.add(i);
        clipped.add(false);
      case PdfClipPathCommand():
        if (clipped.isNotEmpty) clipped[clipped.length - 1] = true;
      case PdfRestoreCommand():
        if (saveIndices.isEmpty) break;
        final save = saveIndices.removeLast();
        final scopeClipped = clipped.removeLast();
        if (!scopeClipped) {
          keep[save] = 0;
          keep[i] = 0;
          removed += 2;
        }
      default:
        break;
    }
  }

  final out = List<PdfRenderCommand>.filled(
    length - removed,
    const PdfSaveCommand(),
    growable: false,
  );
  var outputIndex = 0;
  for (var i = 0; i < length; i++) {
    if (keep[i] == 0) continue;
    final command = commands[i];
    if (command
        case PdfEndSoftMaskedCommand(
          :final luminosity,
          :final backdrop,
          :final maskCommands,
          :final backdropLuminance,
          :final transferScale,
          :final transferOffset,
        )) {
      out[outputIndex++] = PdfEndSoftMaskedCommand(
        luminosity: luminosity,
        backdrop: backdrop,
        maskCommands: _compactStateScopes(maskCommands),
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset,
      );
    } else {
      out[outputIndex++] = command;
    }
  }
  return out;
}

/// Linear downscale to apply to every image so the sum of the per-image-capped
/// target areas fits within [budgetPixels]. 1.0 when the page already fits.
/// Walks declared image dimensions only (no decode), descending soft-mask
/// groups, so it is a cheap pre-pass before the decoding write pass. Images
/// that ship un-decoded (platform-codec path) are counted too, so the scale is
/// conservative when those are mixed in - acceptable, and they are rare on the
/// raster-tiled sheets this targets.
double _imageBudgetScale(List<PdfRenderCommand> commands, CosDocument cos,
    double ratio, int budgetPixels,
    {PdfRect? imageDecodeRegion}) {
  var total = 0;
  void walk(List<PdfRenderCommand> cmds) {
    for (final c in cmds) {
      if (c is PdfDrawImageCommand) {
        final regionPlan = imageDecodeRegion == null
            ? null
            : _imageRegionPlan(cos, c.request, imageDecodeRegion, ratio, 1);
        if (regionPlan != null) {
          total += regionPlan.targetWidth * regionPlan.targetHeight;
        } else {
          final size = _declaredImageSize(cos, c.request.stream);
          if (size == null) continue;
          final t = c.request.transform;
          final wPts = math.sqrt(t.a * t.a + t.b * t.b);
          final hPts = math.sqrt(t.c * t.c + t.d * t.d);
          final (tw, th) =
              cappedImagePixelSize(size.$1, size.$2, wPts, hPts, ratio);
          total += tw * th;
        }
      } else if (c is PdfEndSoftMaskedCommand) {
        walk(c.maskCommands);
      }
    }
  }

  walk(commands);
  if (total == 0 || total <= budgetPixels) return 1.0;
  return math.sqrt(budgetPixels / total);
}

/// The native pixel dimensions an image stream declares (`/Width`, `/Height`),
/// or null when absent/degenerate. Cheap - no pixels are decoded.
(int, int)? _declaredImageSize(CosDocument cos, CosStream stream) {
  final w = _cosInt(cos.resolve(stream.dictionary['Width']));
  final h = _cosInt(cos.resolve(stream.dictionary['Height']));
  if (w == null || h == null || w < 1 || h < 1) return null;
  return (w, h);
}

int? _cosInt(CosObject? o) {
  if (o is CosInteger) return o.value;
  if (o is CosReal) return o.value.round();
  return null;
}

/// Returns [decoded] resampled down to ~2× the pixels it occupies on screen
/// (see [cappedImagePixelSize], whose ceilings match the viewer's full-page
/// raster caps so a sheet-sized underlay stays within a GPU texture limit and
/// the decoded-image cache), or unchanged when it already fits. [transform]
/// maps the unit image square to page points, so its column lengths are the
/// image's drawn width/height in points; [ratio] is screen px per point.
/// [budgetScale] (≤1) is the page-budget downscale applied on top of the
/// per-image cap (see [_imageBudgetScale]); 1.0 leaves the per-image result.
PdfDecodedPixels _capImageResolution(
    PdfDecodedPixels decoded, PdfMatrix transform, double ratio,
    [double budgetScale = 1.0]) {
  final widthPts =
      math.sqrt(transform.a * transform.a + transform.b * transform.b);
  final heightPts =
      math.sqrt(transform.c * transform.c + transform.d * transform.d);
  final capped = cappedImagePixelSize(
      decoded.width, decoded.height, widthPts, heightPts, ratio);
  var tw = capped.$1;
  var th = capped.$2;
  if (budgetScale < 1.0) {
    tw = (tw * budgetScale).ceil().clamp(1, decoded.width);
    th = (th * budgetScale).ceil().clamp(1, decoded.height);
  }
  if (tw == decoded.width && th == decoded.height) return decoded;
  return downsamplePdfDecodedPixels(decoded, tw, th);
}

/// Reconstructs the command buffer written by [serializeCommands].
List<PdfRenderCommand> deserializeCommands(Uint8List bytes) {
  final sw = Stopwatch()..start();
  final r = _Reader(bytes);
  final version = r.u8();
  assert(version == _formatVersion, 'render command format version mismatch');
  final commands = _readCommands(r);
  deserializeCommandsMicros += sw.elapsedMicroseconds;
  return commands;
}

void _writeCommands(
    _Writer w, List<PdfRenderCommand> commands, CosDocument? cos,
    {bool decode = false,
    double? maxImageRatio,
    PdfRect? imageDecodeRegion,
    double budgetScale = 1.0,
    bool imagePlaceholders = false,
    int? commandLimit}) {
  final length = commandLimit == null
      ? commands.length
      : math.min(commands.length, math.max(0, commandLimit));
  w.u32(length);
  for (var i = 0; i < length; i++) {
    final command = commands[i];
    _writeCommand(w, command, cos,
        decode: decode,
        maxImageRatio: maxImageRatio,
        imageDecodeRegion: imageDecodeRegion,
        budgetScale: budgetScale,
        imagePlaceholders: imagePlaceholders);
  }
}

List<PdfRenderCommand> _readCommands(_Reader r) {
  final n = r.u32();
  // The wire format gives us the exact count. Pre-size instead of growing a
  // 100k-command CAD page through repeated capacity reallocations on the UI
  // isolate. Keep the list growable to preserve deserializeCommands' public
  // behavior for callers that append diagnostic commands.
  final out = List<PdfRenderCommand>.filled(
    n,
    const PdfSaveCommand(),
    growable: true,
  );
  for (var i = 0; i < n; i++) {
    out[i] = _readCommand(r);
  }
  return out;
}

void _writeCommand(_Writer w, PdfRenderCommand command, CosDocument? cos,
    {bool decode = false,
    double? maxImageRatio,
    PdfRect? imageDecodeRegion,
    double budgetScale = 1.0,
    bool imagePlaceholders = false}) {
  switch (command) {
    case PdfSaveCommand():
      w.u8(_tSave);
    case PdfRestoreCommand():
      w.u8(_tRestore);
    case PdfFillPathCommand(
        :final path,
        :final color,
        :final rule,
        :final alpha
      ):
      w.u8(_tFillPath);
      _writePath(w, path);
      _writeColor(w, color);
      w.u8(rule.index);
      w.f64(alpha);
    case PdfFillPathGradientCommand(
        :final path,
        :final rule,
        :final gradient,
        :final alpha
      ):
      w.u8(_tFillPathGradient);
      _writePath(w, path);
      w.u8(rule.index);
      _writeGradient(w, gradient);
      w.f64(alpha);
    case PdfFillMeshCommand(:final mesh, :final alpha):
      w.u8(_tFillMesh);
      _writeMesh(w, mesh);
      w.f64(alpha);
    case PdfStrokePathCommand(
        :final path,
        :final color,
        :final stroke,
        :final alpha
      ):
      w.u8(_tStrokePath);
      _writePath(w, path);
      _writeColor(w, color);
      _writeStroke(w, stroke);
      w.f64(alpha);
    case PdfClipPathCommand(:final path, :final rule):
      w.u8(_tClipPath);
      _writePath(w, path);
      w.u8(rule.index);
    case PdfDrawTextCommand(:final run):
      w.u8(_tDrawText);
      _writeTextRun(w, run);
    case PdfDrawImageCommand(:final request):
      // Inline images can name a page-resource colour space unreachable from
      // the stream alone; decline them. XObjects serialize as a self-contained
      // (inline-resolved, decrypted) stream subgraph - any failure inlining or
      // decrypting it declines too, so the page falls back to a local render
      // rather than shipping a broken image.
      if (request.isInline || cos == null) {
        if (!imagePlaceholders) throw const _UnserializableImage();
        _writeImageCommand(w, request, _imagePlaceholderStream, null);
      } else {
        final document = cos;
        _CommandImage? decodedImage;
        if (decode) {
          decodedImage = _decodeImageForCommand(
              document, request, maxImageRatio, budgetScale, imageDecodeRegion);
        }
        CosObject inlined;
        try {
          inlined = decodedImage?.streamForKey ??
              _inlineCos(document, request.stream, 0);
        } catch (_) {
          if (!imagePlaceholders) throw const _UnserializableImage();
          inlined = _imagePlaceholderStream;
        }
        _writeImageCommand(w, decodedImage?.request ?? request, inlined,
            decodedImage?.decoded);
      }
    case PdfSetBlendModeCommand(:final mode):
      w.u8(_tSetBlendMode);
      w.u8(mode.index);
    case PdfBeginGroupCommand(:final alpha, :final knockout):
      w.u8(_tBeginGroup);
      w.f64(alpha);
      w.boolean(knockout);
    case PdfEndGroupCommand():
      w.u8(_tEndGroup);
    case PdfBeginSoftMaskedCommand():
      w.u8(_tBeginSoftMasked);
    case PdfEndSoftMaskedCommand(
        :final luminosity,
        :final backdrop,
        :final maskCommands,
        :final backdropLuminance,
        :final transferScale,
        :final transferOffset
      ):
      w.u8(_tEndSoftMasked);
      w.boolean(luminosity);
      _writeRect(w, backdrop);
      w.f64(backdropLuminance);
      w.f64(transferScale);
      w.f64(transferOffset);
      _writeCommands(w, maskCommands, cos,
          decode: decode,
          maxImageRatio: maxImageRatio,
          imageDecodeRegion: imageDecodeRegion,
          budgetScale: budgetScale,
          imagePlaceholders: imagePlaceholders); // nested
  }
}

_CommandImage? _decodeImageForCommand(
  CosDocument document,
  PdfImageRequest request,
  double? maxImageRatio,
  double budgetScale,
  PdfRect? imageDecodeRegion,
) {
  final predecoded = request.decoded;
  final regionPlan = imageDecodeRegion == null
      ? null
      : _imageRegionPlan(
          document, request, imageDecodeRegion, maxImageRatio, budgetScale);
  if (regionPlan != null) {
    var decoded = regionPlan.outside
        ? _transparentPixel
        : predecoded == null
            ? decodePdfImagePixelsRegionScaled(
                document,
                request.stream,
                regionPlan.sourceX,
                regionPlan.sourceY,
                regionPlan.sourceWidth,
                regionPlan.sourceHeight,
                regionPlan.targetWidth,
                regionPlan.targetHeight,
              )
            : _cropDownsampleDecodedPixels(
                predecoded,
                regionPlan.sourceX,
                regionPlan.sourceY,
                regionPlan.sourceWidth,
                regionPlan.sourceHeight,
                regionPlan.targetWidth,
                regionPlan.targetHeight,
              );
    // The fast region decoder ([decodePdfImagePixelsRegionScaled]) only handles
    // single-filter Flate RGB/gray/indexed streams; for any other image the
    // general decoder handles - an Indexed 8-bit palette, an /SMask'd logo, an
    // ICC/Lab/Separation colour space, 16-bit, a stacked filter - it returns
    // null. Falling through from here would leave the visible slice at the
    // full-page 2x cap, so those images stay soft under deep zoom while vector
    // text sharpens - the exact asymmetry the detail patch exists to remove.
    // Decode the whole image once and crop+downsample it to the visible region
    // instead, so every decodable image type re-sharpens on zoom. (Images that
    // need the platform JPEG codec still decode null here and ship un-decoded
    // at native resolution, so they are already sharp.)
    if (decoded == null && !regionPlan.outside && predecoded == null) {
      final full = decodePdfImagePixels(document, request.stream);
      if (full != null) {
        decoded = _cropDownsampleDecodedPixels(
          full,
          regionPlan.sourceX,
          regionPlan.sourceY,
          regionPlan.sourceWidth,
          regionPlan.sourceHeight,
          regionPlan.targetWidth,
          regionPlan.targetHeight,
        );
      }
    }
    if (decoded != null) {
      final croppedRequest = _copyImageRequest(request,
          transform: regionPlan.transform, decoded: decoded);
      return _CommandImage(croppedRequest, decoded,
          _regionKeyStream(request, regionPlan, decoded));
    }
  }
  if (predecoded != null) {
    final decoded = maxImageRatio == null
        ? predecoded
        : _capImageResolution(
            predecoded, request.transform, maxImageRatio, budgetScale);
    return _CommandImage(_copyImageRequest(request, decoded: decoded), decoded);
  }
  if (maxImageRatio != null) {
    final target =
        _targetDecodedSize(document, request, maxImageRatio, budgetScale);
    if (target != null) {
      final scaled = decodePdfImagePixelsScaled(
          document, request.stream, target.$1, target.$2);
      if (scaled != null) {
        return _CommandImage(
            _copyImageRequest(request, decoded: scaled), scaled);
      }
    }
  }
  final decoded = decodePdfImagePixels(document, request.stream);
  if (decoded == null) return null;
  final capped = maxImageRatio == null
      ? decoded
      : _capImageResolution(
          decoded, request.transform, maxImageRatio, budgetScale);
  return _CommandImage(_copyImageRequest(request, decoded: capped), capped);
}

(int, int)? _targetDecodedSize(
  CosDocument document,
  PdfImageRequest request,
  double ratio,
  double budgetScale,
) {
  final size = _declaredImageSize(document, request.stream);
  if (size == null) return null;
  final transform = request.transform;
  final widthPts =
      math.sqrt(transform.a * transform.a + transform.b * transform.b);
  final heightPts =
      math.sqrt(transform.c * transform.c + transform.d * transform.d);
  final capped =
      cappedImagePixelSize(size.$1, size.$2, widthPts, heightPts, ratio);
  var tw = capped.$1;
  var th = capped.$2;
  if (budgetScale < 1.0) {
    tw = (tw * budgetScale).ceil().clamp(1, size.$1);
    th = (th * budgetScale).ceil().clamp(1, size.$2);
  }
  if (tw == size.$1 && th == size.$2) return null;
  return (tw, th);
}

class _CommandImage {
  const _CommandImage(this.request, this.decoded, [this.streamForKey]);

  final PdfImageRequest request;
  final PdfDecodedPixels decoded;
  final CosStream? streamForKey;
}

class _ImageRegionPlan {
  const _ImageRegionPlan({
    required this.transform,
    required this.sourceX,
    required this.sourceY,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.targetWidth,
    required this.targetHeight,
    this.outside = false,
  });

  final PdfMatrix transform;
  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
  final int targetWidth;
  final int targetHeight;
  final bool outside;
}

final PdfDecodedPixels _transparentPixel =
    PdfDecodedPixels(Uint8List.fromList([0, 0, 0, 0]), 1, 1);

_ImageRegionPlan? _imageRegionPlan(
  CosDocument document,
  PdfImageRequest request,
  PdfRect region,
  double? ratio,
  double budgetScale,
) {
  final size = _declaredImageSize(document, request.stream);
  if (size == null) return null;
  final imageWidth = size.$1;
  final imageHeight = size.$2;
  final t = request.transform;
  const eps = 1e-9;
  if (t.a.abs() <= eps ||
      t.d.abs() <= eps ||
      t.b.abs() > eps ||
      t.c.abs() > eps) {
    return null;
  }

  final imageLeft = math.min(t.e, t.e + t.a);
  final imageRight = math.max(t.e, t.e + t.a);
  final imageBottom = math.min(t.f, t.f + t.d);
  final imageTop = math.max(t.f, t.f + t.d);
  final visible =
      PdfRect(imageLeft, imageBottom, imageRight, imageTop).intersect(region);
  if (visible.width <= eps || visible.height <= eps) {
    return _ImageRegionPlan(
      transform: t,
      sourceX: 0,
      sourceY: 0,
      sourceWidth: 1,
      sourceHeight: 1,
      targetWidth: 1,
      targetHeight: 1,
      outside: true,
    );
  }

  final u0 = ((visible.left - t.e) / t.a).clamp(0.0, 1.0);
  final u1 = ((visible.right - t.e) / t.a).clamp(0.0, 1.0);
  final v0 = ((visible.bottom - t.f) / t.d).clamp(0.0, 1.0);
  final v1 = ((visible.top - t.f) / t.d).clamp(0.0, 1.0);
  final uMin = math.min(u0, u1);
  final uMax = math.max(u0, u1);
  final vMin = math.min(v0, v1);
  final vMax = math.max(v0, v1);
  if (uMax <= uMin || vMax <= vMin) return null;

  final sx0 = (uMin * imageWidth).floor().clamp(0, imageWidth - 1);
  final sx1 = (uMax * imageWidth).ceil().clamp(sx0 + 1, imageWidth);
  // PDF image space is y-up; decoded samples are top-down. The visible v-range
  // therefore maps to source rows [1-vMax, 1-vMin).
  final sy0 = ((1 - vMax) * imageHeight).floor().clamp(0, imageHeight - 1);
  final sy1 = ((1 - vMin) * imageHeight).ceil().clamp(sy0 + 1, imageHeight);
  final sourceWidth = sx1 - sx0;
  final sourceHeight = sy1 - sy0;
  final unitX = sx0 / imageWidth;
  final unitY = 1 - sy1 / imageHeight;
  final unitWidth = sourceWidth / imageWidth;
  final unitHeight = sourceHeight / imageHeight;
  final croppedTransform =
      PdfMatrix(unitWidth, 0, 0, unitHeight, unitX, unitY).concat(t);

  var targetWidth = sourceWidth;
  var targetHeight = sourceHeight;
  if (ratio != null) {
    final widthPts = math.sqrt(croppedTransform.a * croppedTransform.a +
        croppedTransform.b * croppedTransform.b);
    final heightPts = math.sqrt(croppedTransform.c * croppedTransform.c +
        croppedTransform.d * croppedTransform.d);
    final capped = cappedImagePixelSize(
        sourceWidth, sourceHeight, widthPts, heightPts, ratio);
    targetWidth = capped.$1;
    targetHeight = capped.$2;
    if (budgetScale < 1.0) {
      targetWidth = (targetWidth * budgetScale).ceil().clamp(1, sourceWidth);
      targetHeight = (targetHeight * budgetScale).ceil().clamp(1, sourceHeight);
    }
  }
  return _ImageRegionPlan(
    transform: croppedTransform,
    sourceX: sx0,
    sourceY: sy0,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
}

PdfImageRequest _copyImageRequest(
  PdfImageRequest request, {
  PdfMatrix? transform,
  PdfDecodedPixels? decoded,
}) =>
    PdfImageRequest(
      stream: request.stream,
      transform: transform ?? request.transform,
      alpha: request.alpha,
      isStencil: request.isStencil,
      stencilColor: request.stencilColor,
      isInline: request.isInline,
      decoded: decoded ?? request.decoded,
    );

PdfDecodedPixels? _cropDownsampleDecodedPixels(
  PdfDecodedPixels decoded,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight,
) {
  if (sourceX < 0 ||
      sourceY < 0 ||
      sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      sourceX + sourceWidth > decoded.width ||
      sourceY + sourceHeight > decoded.height) {
    return null;
  }
  final cropped = Uint8List(sourceWidth * sourceHeight * 4);
  for (var y = 0; y < sourceHeight; y++) {
    final srcOffset = ((sourceY + y) * decoded.width + sourceX) * 4;
    final dstOffset = y * sourceWidth * 4;
    cropped.setRange(
        dstOffset, dstOffset + sourceWidth * 4, decoded.rgba, srcOffset);
  }
  final pixels = PdfDecodedPixels(cropped, sourceWidth, sourceHeight);
  return downsamplePdfDecodedPixels(pixels, targetWidth, targetHeight);
}

CosStream _regionKeyStream(
  PdfImageRequest request,
  _ImageRegionPlan plan,
  PdfDecodedPixels decoded,
) {
  final key = [
    'region-v1',
    _streamFingerprint(request.stream),
    plan.sourceX,
    plan.sourceY,
    plan.sourceWidth,
    plan.sourceHeight,
    decoded.width,
    decoded.height,
    plan.transform.a,
    plan.transform.b,
    plan.transform.c,
    plan.transform.d,
    plan.transform.e,
    plan.transform.f,
    plan.outside,
  ].join('|');
  return CosStream(
    CosDictionary({
      'DartPdfRegionKey': CosString(Uint8List.fromList(utf8.encode(key))),
    }),
    Uint8List(0),
  );
}

String _streamFingerprint(CosStream stream) {
  var hash = 0x811c9dc5;
  const prime = 0x01000193;
  final bytes = stream.rawBytes;
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * prime) & 0xffffffff;
  }
  return '${stream.dictionary}|${bytes.length}|$hash';
}

void _writeImageCommand(_Writer w, PdfImageRequest request, CosObject inlined,
    PdfDecodedPixels? decoded) {
  w.u8(_tDrawImage);
  _writeMatrix(w, request.transform);
  w.f64(request.alpha);
  w.boolean(request.isStencil);
  _writeColor(w, request.stencilColor);
  _writeCos(w, inlined);
  // Optional off-thread decode: the premultiplied pixels ride beside the
  // stream so the consumer skips the pure-Dart decode. The stream above is
  // still written, so the pixels cache by content like a local render.
  w.boolean(decoded != null);
  if (decoded != null) {
    w.u32(decoded.width);
    w.u32(decoded.height);
    w.bytes(decoded.rgba);
  }
}

final CosStream _imagePlaceholderStream =
    CosStream(CosDictionary(), Uint8List(0));

PdfRenderCommand _readCommand(_Reader r) {
  final tag = r.u8();
  switch (tag) {
    case _tSave:
      return const PdfSaveCommand();
    case _tRestore:
      return const PdfRestoreCommand();
    case _tFillPath:
      final path = _readPath(r);
      final color = _readColor(r);
      final rule = PdfFillRule.values[r.u8()];
      final alpha = r.f64();
      return PdfFillPathCommand(path, color, rule, alpha);
    case _tFillPathGradient:
      final path = _readPath(r);
      final rule = PdfFillRule.values[r.u8()];
      final gradient = _readGradient(r);
      final alpha = r.f64();
      return PdfFillPathGradientCommand(path, rule, gradient, alpha);
    case _tFillMesh:
      final mesh = _readMesh(r);
      final alpha = r.f64();
      return PdfFillMeshCommand(mesh, alpha);
    case _tStrokePath:
      final path = _readPath(r);
      final color = _readColor(r);
      final stroke = _readStroke(r);
      final alpha = r.f64();
      return PdfStrokePathCommand(path, color, stroke, alpha);
    case _tClipPath:
      final path = _readPath(r);
      final rule = PdfFillRule.values[r.u8()];
      return PdfClipPathCommand(path, rule);
    case _tDrawText:
      return PdfDrawTextCommand(_readTextRun(r));
    case _tDrawImage:
      final transform = _readMatrix(r);
      final alpha = r.f64();
      final isStencil = r.boolean();
      final stencilColor = _readColor(r);
      final stream = _readCos(r) as CosStream;
      PdfDecodedPixels? decoded;
      if (r.boolean()) {
        final width = r.u32();
        final height = r.u32();
        decoded =
            PdfDecodedPixels(r.bytes(allowLargeView: true), width, height);
      }
      // isInline forces value (content) cache keying on replay: the
      // reconstructed stream is a fresh object every record, so stream-identity
      // keying would miss the decoded-image cache and re-decode each scroll-by.
      return PdfDrawImageCommand(PdfImageRequest(
        stream: stream,
        transform: transform,
        alpha: alpha,
        isStencil: isStencil,
        stencilColor: stencilColor,
        isInline: true,
        decoded: decoded,
      ));
    case _tSetBlendMode:
      return PdfSetBlendModeCommand(PdfBlendMode.values[r.u8()]);
    case _tBeginGroup:
      final alpha = r.f64();
      final knockout = r.boolean();
      return PdfBeginGroupCommand(alpha, knockout: knockout);
    case _tEndGroup:
      return const PdfEndGroupCommand();
    case _tBeginSoftMasked:
      return const PdfBeginSoftMaskedCommand();
    case _tEndSoftMasked:
      final luminosity = r.boolean();
      final backdrop = _readRect(r);
      final backdropLuminance = r.f64();
      final transferScale = r.f64();
      final transferOffset = r.f64();
      final maskCommands = _readCommands(r);
      return PdfEndSoftMaskedCommand(
        luminosity: luminosity,
        backdrop: backdrop,
        maskCommands: maskCommands,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset,
      );
    default:
      throw StateError('unknown render command tag $tag');
  }
}

// --- value types ---

// Path coordinates are written as float32, not float64. A graphics-rich (CAD)
// page is overwhelmingly path geometry - hundreds of thousands of segments -
// so halving each coordinate halves the serialized buffer and the time to
// write and read it. The precision is not lost in practice: the render engine
// truncates every coordinate to float32 anyway (Skia/Impeller are 32-bit), and
// that truncation is idempotent, so shipping the float32 image renders
// pixel-identically to shipping the original double (verified against the Ghent
// baselines). Everything that needs full precision - transforms, colours,
// stroke widths, text placement - stays float64.
void _writePath(_Writer w, PdfPath path) {
  w.u32(path.segments.length);
  for (final s in path.segments) {
    switch (s) {
      case PdfMoveTo(:final x, :final y):
        w.u8(0);
        w.f32(x);
        w.f32(y);
      case PdfLineTo(:final x, :final y):
        w.u8(1);
        w.f32(x);
        w.f32(y);
      case PdfCubicTo(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x3,
          :final y3
        ):
        w.u8(2);
        w.f32(x1);
        w.f32(y1);
        w.f32(x2);
        w.f32(y2);
        w.f32(x3);
        w.f32(y3);
      case PdfClosePath():
        w.u8(3);
    }
  }
}

PdfPath _readPath(_Reader r) {
  final n = r.u32();
  final segments = List<PdfPathSegment>.filled(
    n,
    const PdfClosePath(),
    growable: true,
  );
  for (var i = 0; i < n; i++) {
    segments[i] = switch (r.u8()) {
      0 => PdfMoveTo(r.f32(), r.f32()),
      1 => PdfLineTo(r.f32(), r.f32()),
      2 => PdfCubicTo(r.f32(), r.f32(), r.f32(), r.f32(), r.f32(), r.f32()),
      3 => const PdfClosePath(),
      _ => throw FormatException('unknown path segment tag'),
    };
  }
  return PdfPath(segments);
}

void _writeColor(_Writer w, PdfColor c) {
  w.f64(c.red);
  w.f64(c.green);
  w.f64(c.blue);
}

PdfColor _readColor(_Reader r) => PdfColor(r.f64(), r.f64(), r.f64());

void _writeStroke(_Writer w, PdfStroke s) {
  w.f64(s.width);
  w.u8(s.cap);
  w.u8(s.join);
  w.f64(s.miterLimit);
  w.f64List(s.dashArray);
  w.f64(s.dashPhase);
}

PdfStroke _readStroke(_Reader r) => PdfStroke(
      width: r.f64(),
      cap: r.u8(),
      join: r.u8(),
      miterLimit: r.f64(),
      dashArray: r.f64List(),
      dashPhase: r.f64(),
    );

void _writeMatrix(_Writer w, PdfMatrix m) {
  w.f64(m.a);
  w.f64(m.b);
  w.f64(m.c);
  w.f64(m.d);
  w.f64(m.e);
  w.f64(m.f);
}

PdfMatrix _readMatrix(_Reader r) =>
    PdfMatrix(r.f64(), r.f64(), r.f64(), r.f64(), r.f64(), r.f64());

void _writeRect(_Writer w, PdfRect rect) {
  w.f64(rect.left);
  w.f64(rect.bottom);
  w.f64(rect.right);
  w.f64(rect.top);
}

PdfRect _readRect(_Reader r) => PdfRect(r.f64(), r.f64(), r.f64(), r.f64());

void _writeGradient(_Writer w, PdfGradient g) {
  w.boolean(g.isRadial);
  w.f64List(g.coords);
  w.u32(g.colors.length);
  for (final c in g.colors) {
    _writeColor(w, c);
  }
  w.f64List(g.stops);
  _writeMatrix(w, g.transform);
  w.boolean(g.extendStart);
  w.boolean(g.extendEnd);
}

PdfGradient _readGradient(_Reader r) {
  final isRadial = r.boolean();
  final coords = r.f64List();
  final n = r.u32();
  final colors = <PdfColor>[for (var i = 0; i < n; i++) _readColor(r)];
  final stops = r.f64List();
  final transform = _readMatrix(r);
  final extendStart = r.boolean();
  final extendEnd = r.boolean();
  return PdfGradient(
    isRadial: isRadial,
    coords: coords,
    colors: colors,
    stops: stops,
    transform: transform,
    extendStart: extendStart,
    extendEnd: extendEnd,
  );
}

void _writeMesh(_Writer w, PdfMesh mesh) {
  w.u32(mesh.vertices.length);
  for (final v in mesh.vertices) {
    w.f64(v.x);
    w.f64(v.y);
    _writeColor(w, v.color);
  }
  w.i32List(mesh.triangles);
}

PdfMesh _readMesh(_Reader r) {
  final n = r.u32();
  final vertices = <PdfMeshVertex>[
    for (var i = 0; i < n; i++) PdfMeshVertex(r.f64(), r.f64(), _readColor(r)),
  ];
  final triangles = r.i32List();
  return PdfMesh(vertices, triangles);
}

void _writeTextRun(_Writer w, PdfTextRun run) {
  w.str(run.text);
  _writeMatrix(w, run.transform);
  _writeColor(w, run.color);
  w.f64(run.width);
  // gradient?
  if (run.gradient == null) {
    w.boolean(false);
  } else {
    w.boolean(true);
    _writeGradient(w, run.gradient!);
  }
  w.strOpt(run.fontName);
  w.f64(run.fontSize);
  // glyphs?
  final glyphs = run.glyphs;
  if (glyphs == null) {
    w.boolean(false);
  } else {
    w.boolean(true);
    w.u32(glyphs.length);
    for (final g in glyphs) {
      w.f64(g.offset);
      w.f64(g.offsetY);
      w.strOpt(g.text);
      if (g.outline == null) {
        w.boolean(false);
      } else {
        w.boolean(true);
        _writePath(w, g.outline!);
      }
    }
  }
  w.boolean(run.invisible);
  w.boolean(run.fill);
  if (run.strokeColor == null) {
    w.boolean(false);
  } else {
    w.boolean(true);
    _writeColor(w, run.strokeColor!);
  }
  w.f64(run.strokeWidth);
}

PdfTextRun _readTextRun(_Reader r) {
  final text = r.str();
  final transform = _readMatrix(r);
  final color = _readColor(r);
  final width = r.f64();
  final gradient = r.boolean() ? _readGradient(r) : null;
  final fontName = r.strOpt();
  final fontSize = r.f64();
  List<PdfGlyphPlacement>? glyphs;
  if (r.boolean()) {
    final n = r.u32();
    glyphs = List<PdfGlyphPlacement>.filled(
      n,
      const PdfGlyphPlacement(offset: 0),
      growable: true,
    );
    for (var i = 0; i < n; i++) {
      final offset = r.f64();
      final offsetY = r.f64();
      final text = r.strOpt();
      final outline = r.boolean() ? _readPath(r) : null;
      glyphs[i] = PdfGlyphPlacement(
          offset: offset, offsetY: offsetY, outline: outline, text: text);
    }
  }
  final invisible = r.boolean();
  final fill = r.boolean();
  final strokeColor = r.boolean() ? _readColor(r) : null;
  final strokeWidth = r.f64();
  return PdfTextRun(
    text: text,
    transform: transform,
    color: color,
    width: width,
    gradient: gradient,
    fontName: fontName,
    fontSize: fontSize,
    glyphs: glyphs,
    invisible: invisible,
    fill: fill,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
  );
}

// --- image COS subgraph ---

// COS value tags for the self-contained image stream tree.
const int _cNull = 0;
const int _cBool = 1;
const int _cInt = 2;
const int _cReal = 3;
const int _cString = 4;
const int _cName = 5;
const int _cArray = 6;
const int _cDict = 7;
const int _cStream = 8;

/// Returns a detached deep copy of [object] (resolved against [cos]) with every
/// [CosReference] replaced by a copy of its target, so the result stands alone -
/// the consumer can decode it with no access to the source document. Stream
/// bytes are taken decrypted-but-still-filtered (encryption removed, filters
/// left for the consumer to undo); on an unencrypted document that is the raw
/// bytes unchanged. [depth] guards against pathological reference cycles.
CosObject _inlineCos(CosDocument cos, CosObject? object, int depth) {
  if (depth > 64) return CosNull.instance;
  final r = cos.resolve(object);
  if (r is CosStream) {
    final dict = <String, CosObject>{};
    r.dictionary.entries.forEach((k, v) {
      dict[k] = _inlineCos(cos, v, depth + 1);
    });
    final raw = cos.decodeStreamData(r,
        stopBeforeFilter: _firstFilterName(cos, r.dictionary));
    dict['Length'] = CosInteger(raw.length);
    return CosStream(CosDictionary(dict), raw);
  }
  if (r is CosDictionary) {
    final dict = <String, CosObject>{};
    r.entries.forEach((k, v) {
      dict[k] = _inlineCos(cos, v, depth + 1);
    });
    return CosDictionary(dict);
  }
  if (r is CosArray) {
    return CosArray([for (final it in r.items) _inlineCos(cos, it, depth + 1)]);
  }
  return r; // scalar (null/bool/int/real/string/name)
}

/// The first filter name on [dict] (`/Filter` as a name or array), or null when
/// the stream is unfiltered - what [_inlineCos] stops before so the shipped
/// bytes stay filtered (decryption alone is undone).
String? _firstFilterName(CosDocument cos, CosDictionary dict) {
  final filter = cos.resolve(dict['Filter']);
  if (filter is CosName) return filter.value;
  if (filter is CosArray) {
    for (final f in filter.items) {
      final name = cos.resolve(f);
      if (name is CosName) return name.value;
    }
  }
  return null;
}

void _writeCos(_Writer w, CosObject object) {
  switch (object) {
    case CosNull():
      w.u8(_cNull);
    case CosBoolean(:final value):
      w.u8(_cBool);
      w.boolean(value);
    case CosInteger(:final value):
      w.u8(_cInt);
      w.i64(value);
    case CosReal(:final value):
      w.u8(_cReal);
      w.f64(value);
    case CosString(:final bytes, :final isHex):
      w.u8(_cString);
      w.bytes(bytes);
      w.boolean(isHex);
    case CosName(:final value):
      w.u8(_cName);
      w.str(value);
    case CosArray(:final items):
      w.u8(_cArray);
      w.u32(items.length);
      for (final it in items) {
        _writeCos(w, it);
      }
    case CosStream(:final dictionary, :final rawBytes):
      w.u8(_cStream);
      _writeCos(w, dictionary);
      w.bytes(rawBytes);
    case CosDictionary(:final entries):
      w.u8(_cDict);
      w.u32(entries.length);
      entries.forEach((k, v) {
        w.str(k);
        _writeCos(w, v);
      });
    case CosReference():
      // _inlineCos resolves every reference away; a stray one decodes to null.
      w.u8(_cNull);
  }
}

CosObject _readCos(_Reader r) {
  switch (r.u8()) {
    case _cNull:
      return CosNull.instance;
    case _cBool:
      return CosBoolean(r.boolean());
    case _cInt:
      return CosInteger(r.i64());
    case _cReal:
      return CosReal(r.f64());
    case _cString:
      final bytes = r.bytes();
      return CosString(bytes, isHex: r.boolean());
    case _cName:
      return CosName(r.str());
    case _cArray:
      final n = r.u32();
      return CosArray([for (var i = 0; i < n; i++) _readCos(r)]);
    case _cStream:
      final dict = _readCos(r) as CosDictionary;
      return CosStream(dict, r.bytes(allowLargeView: true));
    case _cDict:
      final n = r.u32();
      final entries = <String, CosObject>{};
      for (var i = 0; i < n; i++) {
        final key = r.str();
        entries[key] = _readCos(r);
      }
      return CosDictionary(entries);
    default:
      throw StateError('unknown COS tag');
  }
}

// --- low-level reader/writer ---

class _Writer {
  // A graphics-rich (CAD) page serializes to many MB of mostly path geometry -
  // millions of scalar writes. The old BytesBuilder approach allocated a fresh
  // ByteData and a Uint8List view per scalar (and a `_b.add` per call), which
  // dominated the serialize cost. Instead grow one backing buffer and write
  // scalars straight into a [ByteData] view of it at a running offset - no
  // per-value allocation. The output bytes are unchanged (ByteData defaults to
  // big-endian, matching the old per-scalar ByteData), so this rewrite is a
  // pure speed-up: it emits exactly the bytes the BytesBuilder version did.
  Uint8List _buf = Uint8List(1 << 16);
  late ByteData _view = ByteData.view(_buf.buffer);
  int _len = 0;

  void _ensure(int extra) {
    final need = _len + extra;
    if (need <= _buf.length) return;
    var cap = _buf.length * 2;
    while (cap < need) {
      cap *= 2;
    }
    final grown = Uint8List(cap)..setRange(0, _len, _buf);
    _buf = grown;
    _view = ByteData.view(grown.buffer);
  }

  void u8(int v) {
    _ensure(1);
    _buf[_len++] = v & 0xff;
  }

  void u32(int v) {
    _ensure(4);
    _view.setUint32(_len, v);
    _len += 4;
  }

  // ByteData's 64-bit int accessors throw on the web (JS has no 64-bit int),
  // and this codec crosses the isolate/Web-Worker boundary, so encode the value
  // as a float64 instead - exact for |v| <= 2^53, which covers every PDF
  // integer we serialize (on the web a Dart int is already capped at 2^53).
  void i64(int v) {
    _ensure(8);
    _view.setFloat64(_len, v.toDouble());
    _len += 8;
  }

  /// A length-prefixed raw byte run (image stream bytes, COS string bytes).
  void bytes(Uint8List xs) {
    u32(xs.length);
    _ensure(xs.length);
    _buf.setRange(_len, _len + xs.length, xs);
    _len += xs.length;
  }

  void f64(double v) {
    _ensure(8);
    _view.setFloat64(_len, v);
    _len += 8;
  }

  void f32(double v) {
    _ensure(4);
    _view.setFloat32(_len, v);
    _len += 4;
  }

  void boolean(bool v) => u8(v ? 1 : 0);

  void str(String s) {
    final encoded = utf8.encode(s);
    u32(encoded.length);
    _ensure(encoded.length);
    _buf.setRange(_len, _len + encoded.length, encoded);
    _len += encoded.length;
  }

  void strOpt(String? s) {
    if (s == null) {
      boolean(false);
    } else {
      boolean(true);
      str(s);
    }
  }

  void f64List(List<double> xs) {
    u32(xs.length);
    _ensure(xs.length * 8);
    for (final x in xs) {
      _view.setFloat64(_len, x);
      _len += 8;
    }
  }

  void i32List(List<int> xs) {
    u32(xs.length);
    _ensure(xs.length * 4);
    for (final x in xs) {
      _view.setInt32(_len, x);
      _len += 4;
    }
  }

  /// The written bytes as a tight copy (the backing buffer is over-allocated by
  /// up to 2x and would otherwise pin that slack across the isolate transfer).
  Uint8List takeBytes() =>
      Uint8List.fromList(Uint8List.sublistView(_buf, 0, _len));
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _o = 0;

  int u8() => _data.getUint8(_o++);

  int u32() {
    final v = _data.getUint32(_o);
    _o += 4;
    return v;
  }

  int i32() {
    final v = _data.getInt32(_o);
    _o += 4;
    return v;
  }

  int i64() {
    final v = _data.getFloat64(_o); // see [_Writer.i64] - float64-encoded
    _o += 8;
    return v.toInt();
  }

  /// Reads a length-prefixed raw byte run. Small values are copied so a tiny
  /// COS string cannot pin a multi-megabyte transferred command buffer. Large
  /// image streams/pixel planes may instead keep a zero-copy view: those bytes
  /// dominate the buffer and are retained by the command list anyway, so
  /// copying them only adds UI-thread latency and a second large allocation.
  Uint8List bytes({bool allowLargeView = false}) {
    final n = u32();
    final slice = Uint8List.sublistView(_bytes, _o, _o + n);
    final out =
        allowLargeView && n >= (1 << 20) ? slice : Uint8List.fromList(slice);
    _o += n;
    return out;
  }

  double f64() {
    final v = _data.getFloat64(_o);
    _o += 8;
    return v;
  }

  double f32() {
    final v = _data.getFloat32(_o);
    _o += 4;
    return v;
  }

  bool boolean() => u8() == 1;

  String str() {
    final n = u32();
    final s = utf8.decode(Uint8List.sublistView(_bytes, _o, _o + n));
    _o += n;
    return s;
  }

  String? strOpt() => boolean() ? str() : null;

  List<double> f64List() {
    final n = u32();
    return <double>[for (var i = 0; i < n; i++) f64()];
  }

  List<int> i32List() {
    final n = u32();
    return <int>[for (var i = 0; i < n; i++) i32()];
  }
}

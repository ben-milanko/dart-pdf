import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'color_context.dart';
import 'color_space.dart';
import 'colorants.dart';
import 'device.dart';
import 'font_info.dart';
import 'function.dart';
import 'icc.dart';
import 'image_colorants.dart';
import 'overprint_compositor.dart';
import 'path.dart';
import 'recording_device.dart';
import 'render_command.dart';
import 'shading.dart';
import 'translating_device.dart';

/// What an image draw resolves to once overprint has been applied: the stream
/// the device should draw, and the colour a stencil paints through its mask
/// (issue #604).
typedef PdfImageDraw = ({
  CosStream stream,
  PdfColor stencilColor,
  bool overprint,
});

/// Graphics state, mirroring §8.4. Text state parameters live here too
/// because `Tf`, `Tc` etc. are saved and restored by `q`/`Q`.
class _GraphicsState {
  _GraphicsState([PdfColorContext? colorContext])
      : ctm = PdfMatrix.identity,
        fillColor = PdfColor.black,
        strokeColor = PdfColor.black,
        fillAlpha = 1,
        strokeAlpha = 1,
        stroke = const PdfStroke(),
        fillSpace = colorContext == null
            ? PdfColorSpace.deviceGray
            : _deviceGraySpace(colorContext),
        strokeSpace = colorContext == null
            ? PdfColorSpace.deviceGray
            : _deviceGraySpace(colorContext),
        fillOperands = null,
        strokeOperands = null,
        fillPattern = null,
        fillPatternComponents = const [],
        font = null,
        fontDict = null,
        fontSize = 0,
        charSpacing = 0,
        wordSpacing = 0,
        horizontalScale = 1,
        leading = 0,
        rise = 0,
        renderMode = 0,
        fillOverprint = false,
        strokeOverprint = false,
        overprintMode = 0,
        renderingIntent = PdfRenderingIntent.relativeColorimetric,
        fillInk = null,
        strokeInk = null,
        fillBlendInk = null,
        strokeBlendInk = null;

  static PdfColorSpace _deviceGraySpace(PdfColorContext colorContext) =>
      _ContextGraySpace(colorContext);

  _GraphicsState.from(_GraphicsState other)
      : ctm = other.ctm,
        fillColor = other.fillColor,
        strokeColor = other.strokeColor,
        fillAlpha = other.fillAlpha,
        strokeAlpha = other.strokeAlpha,
        stroke = other.stroke,
        fillSpace = other.fillSpace,
        strokeSpace = other.strokeSpace,
        fillOperands = other.fillOperands,
        strokeOperands = other.strokeOperands,
        fillPattern = other.fillPattern,
        fillPatternComponents = other.fillPatternComponents,
        softMask = other.softMask,
        blendMode = other.blendMode,
        font = other.font,
        fontDict = other.fontDict,
        fontSize = other.fontSize,
        charSpacing = other.charSpacing,
        wordSpacing = other.wordSpacing,
        horizontalScale = other.horizontalScale,
        leading = other.leading,
        rise = other.rise,
        renderMode = other.renderMode,
        fillOverprint = other.fillOverprint,
        strokeOverprint = other.strokeOverprint,
        overprintMode = other.overprintMode,
        renderingIntent = other.renderingIntent,
        fillInk = other.fillInk,
        strokeInk = other.strokeInk,
        fillBlendInk = other.fillBlendInk,
        strokeBlendInk = other.strokeBlendInk;

  PdfMatrix ctm;
  PdfColor fillColor;
  PdfColor strokeColor;
  double fillAlpha;
  double strokeAlpha;
  PdfStroke stroke;

  /// Active fill/stroke color spaces for bare `sc`/`scn` operands.
  PdfColorSpace fillSpace;
  PdfColorSpace strokeSpace;

  /// Numeric operands that selected the current generic `sc[n]`/`SC[N]`
  /// colour. They remain in the source colour space so a later `ri` can
  /// re-run a CIE→device conversion before the colour is painted. PDF stores
  /// the source colour in graphics state; eager conversion at `sc` time made
  /// `60 0 0 sc /Perceptual ri ... f` use the preceding intent (GWG221).
  /// Null for device shorthand colours and patterns, which need no refresh.
  List<CosObject>? fillOperands;
  List<CosObject>? strokeOperands;

  /// The active fill pattern (stream for tiling, dictionary for shading)
  /// when the fill space is /Pattern, plus the underlying color components
  /// for uncolored (PaintType 2) tiling patterns.
  CosObject? fillPattern;
  List<double> fillPatternComponents;

  /// The active ExtGState /SMask, shared by reference across q/Q clones so
  /// the interpreter can tell inherited masks from newly opened ones.
  _ActiveSoftMask? softMask;
  PdfBlendMode blendMode = PdfBlendMode.normal;

  PdfFontInfo? font;
  CosDictionary? fontDict;
  double fontSize;
  double charSpacing;
  double wordSpacing;
  double horizontalScale; // Tz / 100
  double leading;
  double rise;
  int renderMode;

  /// Overprint state (gs /op, /OP, /OPM; PDF §8.6.7). [fillOverprint] is the
  /// nonstroking flag (/op), [strokeOverprint] the stroking flag (/OP), and
  /// [overprintMode] the overprint mode (/OPM, 0 or 1).
  bool fillOverprint;
  bool strokeOverprint;
  int overprintMode;
  PdfRenderingIntent renderingIntent;

  /// The device colorants the current fill/stroke colour writes (§8.6.7), or
  /// null when its colour space has no colorant reading (DeviceRGB, ICCBased,
  /// Indexed, Pattern, ...). Tracked alongside the sRGB so the overprint
  /// compositor can work in ink space; null makes it decline and leaves the
  /// painting device's approximation in charge.
  PdfInkColorants? fillInk;
  PdfInkColorants? strokeInk;
  PdfInkColorants? fillBlendInk;
  PdfInkColorants? strokeBlendInk;
}

/// Initial DeviceGray bound to the document output condition. Named device
/// spaces selected later go through [PdfColorSpace.parse].
class _ContextGraySpace extends PdfColorSpace {
  const _ContextGraySpace(this.context);

  final PdfColorContext context;

  @override
  int get channels => 1;

  @override
  String get family => 'DeviceGray';

  @override
  PdfColor toSrgb(List<double> values) =>
      context.deviceGray(values.isEmpty ? 0 : values[0]);

  @override
  PdfColor toSrgbIntent(List<double> values, PdfRenderingIntent intent) =>
      context.deviceGray(values.isEmpty ? 0 : values[0], intent: intent);

  @override
  PdfInkColorants inkColorants(List<double> values) =>
      PdfInkColorants.deviceGray(values.isEmpty ? 0 : values[0]);
}

/// Reads `sc`/`scn` numeric operands as a plain device colour by count -
/// the fallback when the operand count does not match the selected space's
/// channels (lenient on malformed content). Pattern or unsupported counts
/// keep [current].
PdfColor _colorFromValues(List<double> values, PdfColor current,
    [PdfColorContext? colorContext,
    PdfRenderingIntent intent = PdfRenderingIntent.relativeColorimetric]) {
  switch (values.length) {
    case 1:
      return colorContext?.deviceGray(values[0], intent: intent) ??
          PdfColor.gray(values[0]);
    case 3:
      return PdfColor(values[0], values[1], values[2]);
    case 4:
      return colorContext?.deviceCmyk(
              values[0], values[1], values[2], values[3],
              intent: intent) ??
          PdfColor.cmyk(values[0], values[1], values[2], values[3]);
  }
  // pattern or unsupported: keep something visible
  return current;
}

class _ActiveSoftMask {
  _ActiveSoftMask(
    this.form,
    this.matrix,
    this.luminosity,
    this.frameDepth, {
    this.backdropLuminance = 0,
    this.transferScale = 1,
    this.transferOffset = 0,
  });

  final CosStream form;

  /// The CTM at the moment the mask was set - mask coordinates live there.
  final PdfMatrix matrix;
  final bool luminosity;

  /// Luminance of the /BC backdrop colour for areas the mask group leaves
  /// unpainted (default black). Only meaningful for luminosity masks.
  final double backdropLuminance;

  /// Linearised /TR transfer function: `out = value * scale + offset`.
  final double transferScale;
  final double transferOffset;

  /// q-nesting depth where the mask was opened; it closes when that frame
  /// pops (or when replaced at the same depth).
  final int frameDepth;
  bool closed = false;
}

/// Cooperative cancellation for in-flight interpreter walks.
///
/// The worker sets [cancelled] from outside (via a message handler) while
/// `_runOps` is yielding; the interpreter checks it every [_cancelCheckInterval]
/// operators and throws [PdfCancelledException] to abandon the walk early.
class PdfCancellationToken {
  bool cancelled = false;
}

/// Thrown when a [PdfCancellationToken] fires mid-walk.
class PdfCancelledException implements Exception {
  const PdfCancelledException();
}

/// Executes page content streams against a [PdfDevice].
///
/// Coverage: paths, transforms, device color spaces, clipping, text
/// positioning/showing (with metric-accurate advances), form XObjects,
/// image XObjects and inline images (decoding delegated to the device),
/// shadings, patterns, soft masks, Type3 fonts, and annotation
/// appearance streams.
class PdfInterpreter {
  PdfInterpreter(
      {required this.cos,
      required this.device,
      bool scanImagesOnly = false,
      this.resolveOverprint = true,
      this.collectCharOffsets = false,
      this.cancellation})
      : _scanImagesOnly = scanImagesOnly,
        _scanImages = scanImagesOnly,
        _colorContext = PdfColorContext.forDocument(cos) {
    _state = _GraphicsState(_colorContext);
  }

  final CosDocument cos;

  final PdfColorContext _colorContext;

  /// The render target. Mutable only for the record-once/replay-per-tile
  /// path (#524), which briefly redirects the walk into a
  /// [RecordingPdfDevice] while a tiling-pattern cell is captured; it is
  /// always restored before control returns to the caller.
  PdfDevice device;

  final PdfCancellationToken? cancellation;

  /// Whether to resolve overprint (§8.6.7) against a colorant buffer rather
  /// than leaving the painting device to approximate it (issue #502).
  ///
  /// On for painting and recording walks: on a page that actually enables
  /// overprint, every draw's colorants are tracked in a
  /// [PdfOverprintCompositor] and an overprinting draw is handed the sRGB the
  /// subtractive composite really produces, with its overprint flag cleared
  /// so the device paints it plainly. Off for consumers that never look at
  /// colour (text extraction, the image-collect scan), which would only pay
  /// for the buffer.
  final bool resolveOverprint;

  /// Whether to fill in [PdfTextRun.charOffsets] - the em-space pen position
  /// of every character boundary in a run (issue #647) - for *every* run.
  ///
  /// On for text extraction, which needs exact intra-run geometry to land a
  /// selection or search highlight on the glyphs of a proportional font.
  /// Painting walks leave it off: an embedded font already carries those
  /// positions in [PdfTextRun.glyphs], so the list would be paid for nothing.
  ///
  /// Runs with **no** embedded font program get the table regardless of this
  /// flag (issue #649): the device substitutes a system font there, and
  /// without the PDF's own per-character advances it can only match the run
  /// total, letting interior glyphs drift by several points against the
  /// geometry that selection, search, and hit-testing use.
  final bool collectCharOffsets;

  /// Process-wide kill switch for the colorant-buffer overprint path
  /// (issue #502). Off, overprint state is still parsed and delivered but no
  /// buffer is built and no draw is resolved, so painting devices fall back to
  /// their own approximation - the A/B baseline the guard test measures
  /// against.
  static bool debugResolveOverprint = true;

  /// The colorant buffer for the page being walked, or null when the page
  /// enables no overprint (the overwhelmingly common case) or [resolveOverprint]
  /// is off.
  PdfOverprintCompositor? _overprint;

  /// Last overprint tuple handed to the device. Tracked rather than derived
  /// from [_state] because a resolved draw is delivered with its flag cleared
  /// - the device must paint it plainly, since the composite is already in
  /// the colour.
  bool _deliveredFillOverprint = false;
  bool _deliveredStrokeOverprint = false;
  int _deliveredOverprintMode = 0;

  static const _maxFormDepth = 16;
  static const _cancelCheckInterval = 64;
  static const _yieldInterval = 512;

  // Cross-render font cache. [PdfFontInfo.load] parses embedded font programs
  // (TrueType/CFF/Type1), CMaps, ToUnicode maps and width tables - several
  // microseconds per font - and the result is immutable and read-only, so one
  // load is safe to share across the two interpreter passes of a single render
  // (image-scan collect + paint) and across every re-render of the page. That
  // is a large cold-render saving (the paint pass reuses the collect pass's
  // loads) and an even larger warm one (a re-render touches the cache only),
  // and because the cached font's glyph programs keep their own outline memos,
  // [PdfFontInfo.outlineFor] hands back stable [PdfPath] identities across
  // renders - which the device's glyph-path cache keys on, so the win
  // compounds.
  //
  // Keyed by the font dictionary's identity: the COS object cache returns the
  // same [CosDictionary] instance for a given reference (so it is stable within
  // a document), [CosDictionary] uses identity equality (so keys never collide
  // across documents), and an edited document produces a fresh dict instance
  // (so a stale entry is simply never looked up again). A bounded LRU keeps a
  // long multi-document session from growing without limit.
  static final LinkedHashMap<CosDictionary, PdfFontInfo> _sharedFonts =
      LinkedHashMap.identity();
  static const int _sharedFontCapacity = 128;

  static PdfFontInfo _loadFont(CosDocument cos, CosDictionary font) {
    final hit = _sharedFonts.remove(font);
    if (hit != null) {
      _sharedFonts[font] = hit; // re-insert as most-recently-used
      return hit;
    }
    final loaded = PdfFontInfo.load(cos, font);
    _sharedFonts[font] = loaded;
    if (_sharedFonts.length > _sharedFontCapacity) {
      _sharedFonts.remove(_sharedFonts.keys.first); // evict least-recently-used
    }
    return loaded;
  }

  /// Empties the shared font cache. Tests that assert on load behaviour or
  /// measure cold timings call this first; ordinary rendering never needs to.
  static void clearFontCache() => _sharedFonts.clear();

  /// Number of fonts currently held in the shared cache (test hook).
  static int get debugFontCacheLength => _sharedFonts.length;

  // When true, the interpreter only walks the content to discover image draw
  // requests - it skips the image-free build work (path segment lists, glyph
  // outlines, colour/ICC conversion, shadings, text runs, and the no-op device
  // paint calls). Every image source - image/form XObjects, inline images,
  // Type3 glyph procs, tiling patterns, soft-mask groups - reaches the device
  // through `_run`, which runs on this same instance, so the flag is inherited
  // by every nested stream and the discovered image set is identical to a full
  // interpretation. It lets a render's decode-collect pass cost a fraction of a
  // pass instead of a redundant second full interpretation (see
  // PdfPageRenderer.renderPicture).
  //
  // Reset from `_scanImagesOnly` whenever the overprint state is (re)opened:
  // a page that resolves overprint has to be walked in full even to *collect*
  // its images, because an overprinting raster is drawn as a substitute stream
  // the colorant buffer builds (issue #604), and a collect pass that skipped
  // the buffer would hand the decoder a different stream than the paint pass
  // draws - the image would then silently fail to appear. See
  // `_beginOverprint`.
  bool _scanImages;

  // The scan-only mode the caller asked for; `_scanImages` is what is in force
  // for the page being interpreted.
  final bool _scanImagesOnly;

  late _GraphicsState _state;
  final List<_GraphicsState> _stateStack = [];
  // Parsed content operations keyed by stream identity, so a form XObject,
  // annotation appearance, soft-mask group, tiling pattern, or Type3 CharProc
  // drawn more than once in a render (including the image-collect pass plus the
  // paint pass) is filter-decoded and parsed once. Per-interpreter, so it never
  // outlives a render; stream identity changes when an edit rewrites content.
  final Map<CosStream, List<ContentOperation>> _opsCache = {};

  /// Memoises parsed ICC profiles across `cs`/`CS` selections so a colour
  /// space chosen repeatedly parses its profile only once.
  final Map<CosStream, IccProfile?> _iccCache = {};
  bool _paintingLuminosityMask = false;
  final List<bool> _visibilityStack = [];
  // Marked-content id stack, kept in lockstep with [_visibilityStack]: one
  // entry per BDC/BMC, holding that sequence's /MCID (null when it declares
  // none). The current MCID for a text run is the innermost non-null entry -
  // this is how tagged-PDF content is tied back to structure elements.
  final List<int?> _mcidStack = [];
  Set<CosReference>? _optionalContentOn;
  Set<CosReference>? _optionalContentOff;
  String? _optionalContentBaseState;
  int _currentFormDepth = 0;

  // Tiling-pattern streams currently being painted, by identity - a pattern
  // whose cell re-enters itself (through a form) is a reference cycle.
  final Set<CosStream> _activeTilingPatterns = Set.identity();
  PdfRect? _pageBox;

  // current path, built in page space
  PdfPathBuilder _segments = PdfPathBuilder();
  double _currentX = 0, _currentY = 0; // user-space current point
  double _startX = 0, _startY = 0;
  PdfFillRule? _pendingClip;

  // While scanning for images we don't build the segment list - only the
  // current path's page-space bounding box, which is all a tiling-pattern fill
  // needs to bound its tile loop (over-estimating the box only runs extra
  // tiles, never misses an image). Reset after each paint, like _segments.
  double _scanMinX = double.infinity, _scanMinY = double.infinity;
  double _scanMaxX = double.negativeInfinity,
      _scanMaxY = double.negativeInfinity;

  // text matrices
  PdfMatrix _textMatrix = PdfMatrix.identity;
  PdfMatrix _lineMatrix = PdfMatrix.identity;

  // Text clipping (render modes 4–7, §9.4.1): glyph outlines painted between
  // BT and ET accumulate in page space and intersect the clip at ET. The
  // flag is set independently of the segments so a clip with no resolvable
  // outlines (e.g. a broken embedded font) correctly clips everything away.
  bool _textClipPending = false;
  final List<PdfPathSegment> _textClipSegments = [];

  // Reused across every [_showText] call to assemble the run's Unicode text -
  // a page issues thousands of show operators, so a fresh buffer per call is
  // pure allocation churn. Cleared at the start of each call; `toString()`
  // yields the same text either way. A Type3 glyph's CharProc can re-enter
  // _showText mid-loop, so the guard hands the nested call a private buffer
  // and leaves the outer accumulation intact.
  final StringBuffer _textBuffer = StringBuffer();
  bool _textBufferInUse = false;

  /// True while executing a Type3 CharProc that opened with `d1` (§9.6.5):
  /// such a glyph is a pure shape painted in the text colour, so colour-setting
  /// operators inside it "shall be ignored". Set by the `d1` case, saved and
  /// restored around each CharProc, and consulted before the colour ops.
  bool _type3ColorLocked = false;

  void drawPage(PdfPage page) => drawPageContent(page, page.contentBytes());

  /// Parses and interprets [content] incrementally without retaining a
  /// page-sized [ContentOperation] list.
  ///
  /// This is the preferred path when the content is consumed once. Renderers
  /// that deliberately interpret the same page more than once should parse a
  /// list once and use [drawPageOperations] for each pass instead.
  void drawPageContent(PdfPage page, Uint8List content, {int? operationLimit}) {
    _state = _GraphicsState(_colorContext);
    _visibilityStack.clear();
    _mcidStack.clear();
    _pageBox = page.mediaBox;
    _beginOverprint(page);
    device.save();
    try {
      _runCursor(
        ContentStreamParser.cursor(content, operationLimit: operationLimit),
        page.resources,
        0,
      );
      final mask = _state.softMask;
      if (mask != null) _finalizeSoftMask(mask);
    } finally {
      device.restore();
    }
  }

  /// Runs an already-parsed page content stream. Parsing (and the underlying
  /// stream decompression) dominates rendering on graphics-rich pages, so a
  /// renderer that interprets a page more than once - e.g. the image-collect
  /// pass and the paint pass in PdfPageRenderer.renderPicture - parses the
  /// content once and feeds the same [operations] to both passes.
  void drawPageOperations(PdfPage page, List<ContentOperation> operations) {
    _state = _GraphicsState(_colorContext);
    _visibilityStack.clear();
    _mcidStack.clear();
    _pageBox = page.mediaBox;
    _beginOverprint(page);
    device.save();
    try {
      _run(operations, page.resources, 0);
      final mask = _state.softMask;
      if (mask != null) _finalizeSoftMask(mask);
    } finally {
      device.restore();
    }
  }

  /// Like [drawPageOperations] but yields to the event loop every
  /// [_yieldInterval] operators so a [PdfCancellationToken] set from outside
  /// (via an isolate message or Web Worker postMessage handler) can fire.
  ///
  /// Used by the render worker's isolate/worker entrypoint: the synchronous
  /// [drawPageOperations] can't receive cancel messages mid-walk because Dart's
  /// event loop is blocked, so the async variant interleaves the walk with
  /// micro-yields that let the port listener run. [yieldInterval] lets a
  /// backend balance cancellation latency against its event-loop cost; browser
  /// timers are substantially more expensive than native isolate yields.
  Future<void> drawPageOperationsAsync(
      PdfPage page, List<ContentOperation> operations,
      {int yieldInterval = _yieldInterval}) async {
    if (yieldInterval <= 0) {
      throw ArgumentError.value(yieldInterval, 'yieldInterval', 'must be > 0');
    }
    _state = _GraphicsState(_colorContext);
    _visibilityStack.clear();
    _mcidStack.clear();
    _pageBox = page.mediaBox;
    _beginOverprint(page);
    device.save();
    try {
      await _runAsync(operations, page.resources, 0, yieldInterval);
      final mask = _state.softMask;
      if (mask != null) _finalizeSoftMask(mask);
    } finally {
      device.restore();
    }
  }

  /// Async, cancellable counterpart to [drawPageContent].
  ///
  /// Parsing and interpretation advance together, yielding after each
  /// [yieldInterval] operations. This removes the uncancellable synchronous
  /// parse prefix and avoids retaining every parsed operation in render
  /// workers that only record the page once.
  Future<void> drawPageContentAsync(PdfPage page, Uint8List content,
      {int? operationLimit, int yieldInterval = _yieldInterval}) async {
    if (yieldInterval <= 0) {
      throw ArgumentError.value(yieldInterval, 'yieldInterval', 'must be > 0');
    }
    // Expressed through the resumable walk so the two share one implementation
    // - this path is exercised by the whole corpus, which is what keeps the
    // chunked form honest.
    final walk =
        beginPageContent(page, content, operationLimit: operationLimit);
    await walk.advance(yieldInterval: yieldInterval);
  }

  /// Begins a **resumable** walk of this page's content.
  ///
  /// [PdfPageContentWalk.advance] records a bounded number of operations and
  /// can be called again to continue from where it stopped, appending to the
  /// same device instead of restarting - the cursor holds the parse position
  /// and this interpreter holds the graphics state. That is the difference
  /// from calling [drawPageContentAsync] twice with a larger `operationLimit`,
  /// which re-walks the prefix and re-emits everything it already drew.
  ///
  /// The caller owns the walk: it must either run it to completion (advance
  /// returns true) or call [PdfPageContentWalk.abandon], so the balancing
  /// `device.restore()` always happens.
  PdfPageContentWalk beginPageContent(PdfPage page, Uint8List content,
      {int? operationLimit}) {
    _state = _GraphicsState(_colorContext);
    _visibilityStack.clear();
    _mcidStack.clear();
    _pageBox = page.mediaBox;
    _beginOverprint(page);
    device.save();
    final walk = PdfPageContentWalk._(
      this,
      ContentStreamParser.cursor(content, operationLimit: operationLimit),
      page.resources,
      _currentFormDepth,
      _visibilityStack.length,
    );
    _currentFormDepth = 0;
    return walk;
  }

  /// Unwinds the page-level bookkeeping [beginPageContent] set up. Runs
  /// exactly once per walk (see [PdfPageContentWalk._finish]).
  void _endPageContent(
      int previousFormDepth, int previousVisibilityDepth, bool completed) {
    try {
      if (completed) {
        final mask = _state.softMask;
        if (mask != null) _finalizeSoftMask(mask);
      }
    } finally {
      while (_visibilityStack.length > previousVisibilityDepth) {
        _visibilityStack.removeLast();
      }
      while (_mcidStack.length > previousVisibilityDepth) {
        _mcidStack.removeLast();
      }
      _currentFormDepth = previousFormDepth;
      device.restore();
    }
  }

  /// Runs a parsed content stream against [resources] (used by tests).
  void run(List<ContentOperation> operations, CosDictionary resources) {
    _run(operations, resources, 0);
  }

  /// Default operations per [PdfPageContentWalk.advance] chunk when the caller
  /// does not choose one. Large enough that the per-chunk overhead is noise on
  /// a dense sheet, small enough that a chunk is a fraction of a heavy page.
  static const int defaultWalkChunkOperations = 20000;

  /// Draws the page's annotation appearance streams, normally called after
  /// [drawPage] so they paint over the content (§12.5.5).
  ///
  /// Hidden and NoView annotations are skipped, as are Popups and comment
  /// thread content - replies and review-state annotations
  /// ([PdfAnnotation.isReply]/[PdfAnnotation.isStateAnnotation]) are shown
  /// by a viewer in its comment pane, not painted as a second icon over
  /// the page (matching Acrobat).
  /// Paints a page's annotations.
  ///
  /// The /F visibility flags (§12.5.3) are screen-vs-print sensitive. On
  /// screen ([forPrint] false, the default) a Hidden or NoView annotation is
  /// skipped and the Print flag is ignored. For print output ([forPrint]
  /// true) the roles swap: NoView annotations DO print (NoView means
  /// "hide on screen, show on paper"), and an annotation is printed only when
  /// its Print flag is set - so screen-only markup (e.g. a viewer's own
  /// highlights) stays off the page. Hidden is honored either way.
  void drawAnnotations(PdfPage page,
      {bool Function(PdfAnnotation)? skip, bool forPrint = false}) {
    _pageBox = page.mediaBox;
    _overprint = null;
    _scanImages = _scanImagesOnly;
    for (final annotation in page.annotations) {
      if (annotation.isHidden) continue;
      if (forPrint) {
        if (!annotation.isPrint) continue;
      } else if (annotation.isNoView) {
        continue;
      }
      if (annotation.subtype == 'Popup') continue;
      if (annotation.isReply || annotation.isStateAnnotation) continue;
      if (skip != null && skip(annotation)) continue;
      final form = annotation.normalAppearance;
      if (form == null) {
        _drawFallbackAnnotation(annotation);
      } else {
        _drawAppearance(form, annotation.rect);
      }
    }
  }

  /// Draws a single annotation's appearance stream - the one-annotation
  /// slice of [drawAnnotations], for callers that need an annotation
  /// rendered in isolation (e.g. a live drag preview).
  void drawAnnotation(PdfPage page, PdfAnnotation annotation) {
    _pageBox = page.mediaBox;
    _overprint = null;
    _scanImages = _scanImagesOnly;
    final form = annotation.normalAppearance;
    if (form == null) {
      _drawFallbackAnnotation(annotation);
    } else {
      _drawAppearance(form, annotation.rect);
    }
  }

  void _drawFallbackAnnotation(PdfAnnotation annotation) {
    switch (annotation.subtype) {
      case 'Square':
        _drawFallbackSquare(annotation);
      case 'Circle':
        _drawFallbackCircle(annotation);
      case 'Line':
        _drawFallbackLine(annotation);
      case 'Ink':
        _drawFallbackInk(annotation);
      case 'Highlight' || 'Underline' || 'StrikeOut' || 'Squiggly':
        _drawFallbackTextMarkup(annotation);
      case 'Polygon':
        _drawFallbackPolygon(annotation, closed: true);
      case 'PolyLine':
        _drawFallbackPolygon(annotation, closed: false);
      case 'Link':
        _drawFallbackLink(annotation);
      case 'FreeText':
        _drawFallbackFreeText(annotation);
      case 'Widget':
        if (annotation is PdfWidgetAnnotation) {
          _drawFallbackWidget(annotation);
        }
    }
  }

  void _drawFallbackPolygon(PdfAnnotation annotation, {required bool closed}) {
    final points = annotation.vertices;
    if (points == null || points.length < 2) return;
    final segments = <PdfPathSegment>[
      PdfMoveTo(points.first.$1, points.first.$2),
      for (final p in points.skip(1)) PdfLineTo(p.$1, p.$2),
      if (closed) const PdfClosePath(),
    ];
    final path = PdfPath(segments);
    // A /Polygon may carry an interior fill (/IC); a /PolyLine is open.
    final fill = closed ? annotation.interiorColor : null;
    if (fill != null) {
      device.fillPath(path, _pdfColor(fill), PdfFillRule.nonzero,
          _annotationFillAlpha(annotation));
    }
    device.strokePath(path, _pdfColor(annotation.color ?? 0x000000),
        _annotationStroke(annotation), _annotationStrokeAlpha(annotation));
  }

  /// A /Link's visible border (§12.5.6.5): most links carry /Border [0 0 0]
  /// (invisible) and no /C, so this paints nothing for them - it draws only
  /// when the link declares both a colour and a positive border width.
  void _drawFallbackLink(PdfAnnotation annotation) {
    final color = annotation.color;
    if (color == null) return;
    final width =
        annotation.borderWidth ?? _annotationBorderWidth(annotation) ?? 0;
    if (width <= 0) return;
    final rect = _insetRect(annotation.rect, width / 2);
    if (rect.width <= 0 || rect.height <= 0) return;
    device.strokePath(_rectPath(rect), _pdfColor(color),
        _annotationStroke(annotation), _annotationStrokeAlpha(annotation));
  }

  /// A /FreeText's text body (§12.5.6.19), drawn from /Contents through the
  /// /DA appearance string when no /AP was generated. Explicit line breaks in
  /// /Contents are honored; the text is top-anchored and clipped to /Rect.
  /// Auto-wrapping and quadding are left to a real appearance stream.
  void _drawFallbackFreeText(PdfAnnotation annotation) {
    final text = annotation.contents;
    if (text == null || text.isEmpty) return;
    final rect = annotation.calloutBox ?? annotation.rect;
    if (rect.width <= 0 || rect.height <= 0) return;
    final da = cos.resolve(annotation.dict['DA']);
    final style = _parseDefaultAppearance(da is CosString ? da.text : '');
    final size = style.size;
    const pad = 2.0;
    final lineHeight = size * 1.15;
    // XChange and Bluebeam files sometimes omit /AP and expect the viewer to
    // construct the FreeText box and callout leader from semantic entries.
    final freeText = annotation.freeTextStyle;
    final fill = freeText?.fillColor;
    if (fill != null) {
      device.fillPath(_rectPath(rect), _pdfColor(fill), PdfFillRule.nonzero,
          _annotationFillAlpha(annotation));
    }
    final borderWidth = freeText?.borderWidth ?? 0;
    final border = freeText?.borderColor;
    if (borderWidth > 0 && border != null) {
      device.strokePath(
          _rectPath(_insetRect(rect, borderWidth / 2)),
          _pdfColor(border),
          _annotationStroke(annotation).copyWith(width: borderWidth),
          _annotationStrokeAlpha(annotation));
    }
    final callout = annotation.calloutLine;
    if (callout != null && callout.length >= 2) {
      device.strokePath(
          PdfPath([
            PdfMoveTo(callout.first.$1, callout.first.$2),
            for (final point in callout.skip(1)) PdfLineTo(point.$1, point.$2),
          ]),
          _pdfColor(freeText?.borderColor ?? annotation.color ?? 0x000000),
          _annotationStroke(annotation),
          _annotationStrokeAlpha(annotation));
    }
    final available = math.max(0.0, rect.width - pad * 2);
    final lines = <String>[];
    for (final paragraph in text.replaceAll('\r\n', '\n').split('\n')) {
      final words = paragraph.split(RegExp(r'\s+'));
      var line = '';
      for (final word in words) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty &&
            _fallbackTextGeometry(candidate, style.fontName).width * size >
                available) {
          lines.add(line);
          line = word;
        } else {
          line = candidate;
        }
      }
      lines.add(line);
    }
    device.save();
    try {
      device.clipPath(_rectPath(rect), PdfFillRule.nonzero);
      var y = rect.top - pad - size * 0.718;
      for (final line in lines) {
        if (y + size < rect.bottom) break;
        if (line.isNotEmpty) {
          final geometry = _fallbackTextGeometry(line, style.fontName);
          final measured = geometry.width * size;
          final q = cos.resolve(annotation.dict['Q']);
          final alignment = q is CosInteger ? q.value : 0;
          final x = switch (alignment) {
            1 => rect.left + (rect.width - measured) / 2,
            2 => rect.right - pad - measured,
            _ => rect.left + pad,
          };
          device.drawText(PdfTextRun(
            text: line,
            transform: PdfMatrix(size, 0, 0, size, x, y),
            color: style.color,
            width: geometry.width,
            fontName: style.fontName,
            fontSize: size,
            charOffsets: geometry.offsets,
          ));
        }
        y -= lineHeight;
      }
    } finally {
      device.restore();
    }
  }

  void _drawFallbackSquare(PdfAnnotation annotation) {
    final stroke = _annotationStroke(annotation);
    final rect = _insetRect(annotation.rect, stroke.width / 2);
    final path = _rectPath(rect);
    final fill = annotation.interiorColor;
    if (fill != null) {
      device.fillPath(path, _pdfColor(fill), PdfFillRule.nonzero,
          _annotationFillAlpha(annotation));
    }
    if (annotation.color != null || fill == null) {
      device.strokePath(path, _pdfColor(annotation.color ?? 0x000000), stroke,
          _annotationStrokeAlpha(annotation));
    }
  }

  void _drawFallbackCircle(PdfAnnotation annotation) {
    final stroke = _annotationStroke(annotation);
    final rect = _insetRect(annotation.rect, stroke.width / 2);
    final path = _ellipsePath(rect);
    final fill = annotation.interiorColor;
    if (fill != null) {
      device.fillPath(path, _pdfColor(fill), PdfFillRule.nonzero,
          _annotationFillAlpha(annotation));
    }
    if (annotation.color != null || fill == null) {
      device.strokePath(path, _pdfColor(annotation.color ?? 0x000000), stroke,
          _annotationStrokeAlpha(annotation));
    }
  }

  void _drawFallbackLine(PdfAnnotation annotation) {
    final line = annotation.line;
    if (line == null) return;
    device.strokePath(
      PdfPath([
        PdfMoveTo(line.$1.$1, line.$1.$2),
        PdfLineTo(line.$2.$1, line.$2.$2),
      ]),
      _pdfColor(annotation.color ?? 0x000000),
      _annotationStroke(annotation),
      _annotationStrokeAlpha(annotation),
    );
  }

  void _drawFallbackInk(PdfAnnotation annotation) {
    final strokes = annotation.inkList;
    if (strokes == null) return;
    // Ink is freehand: reference viewers (and pdf.js, which generated the
    // baselines) draw the centreline solid even when /BS carries a dash array,
    // so drop the dash here - a dashed ink stroke is neither useful nor what
    // any conforming viewer shows.
    final stroke = _annotationStroke(annotation).copyWith(
      cap: 1,
      join: 1,
      dashArray: const [],
    );
    for (final points in strokes) {
      if (points.isEmpty) continue;
      final segments = <PdfPathSegment>[
        PdfMoveTo(points.first.$1, points.first.$2)
      ];
      for (final point in points.skip(1)) {
        segments.add(PdfLineTo(point.$1, point.$2));
      }
      device.strokePath(
          PdfPath(segments),
          _pdfColor(annotation.color ?? 0x000000),
          stroke,
          _annotationStrokeAlpha(annotation));
    }
  }

  void _drawFallbackTextMarkup(PdfAnnotation annotation) {
    final quads = _quadRects(annotation);
    if (quads.isEmpty) return;
    final color = _pdfColor(annotation.color ?? 0xFFFF00);
    switch (annotation.subtype) {
      case 'Highlight':
        device.setBlendMode(PdfBlendMode.multiply);
        for (final rect in quads) {
          device.fillPath(_rectPath(rect), color, PdfFillRule.nonzero,
              _annotationFillAlpha(annotation, fallback: 0.35));
        }
        device.setBlendMode(PdfBlendMode.normal);
      case 'Underline' || 'StrikeOut':
        final atHeight = annotation.subtype == 'Underline' ? 0.08 : 0.45;
        for (final rect in quads) {
          final y = rect.bottom + rect.height * atHeight;
          device.strokePath(
            PdfPath([PdfMoveTo(rect.left, y), PdfLineTo(rect.right, y)]),
            color,
            _annotationStroke(annotation)
                .copyWith(width: math.max(1, rect.height * 0.06)),
            _annotationStrokeAlpha(annotation),
          );
        }
      case 'Squiggly':
        for (final rect in quads) {
          device.strokePath(
              _squigglyPath(rect),
              color,
              _annotationStroke(annotation)
                  .copyWith(width: math.max(1, rect.height * 0.06)),
              _annotationStrokeAlpha(annotation));
        }
    }
  }

  void _drawFallbackWidget(PdfWidgetAnnotation annotation) {
    switch (annotation.fieldType) {
      case 'Tx' || 'Ch':
        _drawFallbackTextWidget(annotation);
      case 'Btn':
        _drawFallbackButtonWidget(annotation);
    }
  }

  void _drawFallbackTextWidget(PdfWidgetAnnotation annotation) {
    final value = annotation.fieldValue;
    if (value == null || value.isEmpty) return;
    final rect = annotation.rect;
    if (rect.width <= 0 || rect.height <= 0) return;

    final style = _parseWidgetDefaultAppearance(annotation);
    const pad = 2.0;
    var size = style.size;
    final text = value.replaceAll('\n', ' ');
    final geometry = _fallbackTextGeometry(text, style.fontName);
    final ascent = size * 0.718;
    final y =
        ((rect.height - ascent) / 2 < pad ? pad : (rect.height - ascent) / 2) +
            rect.bottom;

    device.save();
    try {
      device.clipPath(
        _rectPath(PdfRect(
            rect.left + 1, rect.bottom + 1, rect.right - 1, rect.top - 1)),
        PdfFillRule.nonzero,
      );
      device.drawText(PdfTextRun(
        text: text,
        transform: PdfMatrix(size, 0, 0, size, rect.left + pad, y),
        color: style.color,
        width: geometry.width,
        fontName: style.fontName,
        fontSize: size,
        charOffsets: geometry.offsets,
      ));
    } finally {
      device.restore();
    }
  }

  ({
    String fontName,
    double size,
    PdfColor color
  }) _parseWidgetDefaultAppearance(PdfWidgetAnnotation annotation) =>
      _parseDefaultAppearance(_widgetDefaultAppearance(annotation) ?? '');

  /// Parses a /DA default-appearance string (§12.7.3.3) into the font name,
  /// size and colour it selects - the shared core behind text-field widgets
  /// and FreeText fallbacks.
  ({String fontName, double size, PdfColor color}) _parseDefaultAppearance(
      String da) {
    final tf = RegExp(r'/(\S+)\s+([\d.]+)\s+Tf').firstMatch(da);
    final rawName = tf?.group(1) ?? 'Helv';
    final fontName = switch (rawName) {
      'Helv' => 'Helvetica',
      'ZaDb' => 'ZapfDingbats',
      _ => rawName,
    };
    final parsedSize = double.tryParse(tf?.group(2) ?? '') ?? 12;
    final size = parsedSize <= 0 ? 12.0 : parsedSize;

    PdfColor color = PdfColor.black;
    for (final match
        in RegExp(r'([\d.]+)(?:\s+([\d.]+)\s+([\d.]+))?\s+(g|rg)\b')
            .allMatches(da)) {
      final op = match.group(4);
      if (op == 'g') {
        final gray = double.tryParse(match.group(1)!) ?? 0;
        color = PdfColor.gray(gray.clamp(0.0, 1.0));
      } else {
        final r = double.tryParse(match.group(1)!) ?? 0;
        final g = double.tryParse(match.group(2) ?? '') ?? 0;
        final b = double.tryParse(match.group(3) ?? '') ?? 0;
        color = PdfColor(
          r.clamp(0.0, 1.0),
          g.clamp(0.0, 1.0),
          b.clamp(0.0, 1.0),
        );
      }
    }
    return (fontName: fontName, size: size, color: color);
  }

  String? _widgetDefaultAppearance(PdfWidgetAnnotation annotation) {
    final cos = annotation.document.cos;
    CosDictionary? node = annotation.dict;
    final visited = <CosDictionary>{};
    while (node != null && visited.add(node)) {
      final da = cos.resolve(node['DA']);
      if (da is CosString) return da.text;
      final parent = cos.resolve(node['Parent']);
      node = parent is CosDictionary ? parent : null;
    }
    final acroForm = cos.resolve(annotation.document.catalog['AcroForm']);
    if (acroForm is CosDictionary) {
      final da = cos.resolve(acroForm['DA']);
      if (da is CosString) return da.text;
    }
    return null;
  }

  /// Fallback for a button field (/Btn) with no appearance stream: paints the
  /// /MK background and border (§12.5.6.19), a pushbutton's /MK caption, and a
  /// check/dot for a checkbox or radio whose own /AS is an on state.
  void _drawFallbackButtonWidget(PdfWidgetAnnotation annotation) {
    final rect = annotation.rect;
    if (rect.width <= 0 || rect.height <= 0) return;
    final mk = cos.resolve(annotation.dict['MK']);
    final mkDict = mk is CosDictionary ? mk : null;
    final bg = _mkColor(mkDict?['BG']);
    final bc = _mkColor(mkDict?['BC']);
    final stroke = _annotationStroke(annotation);
    if (bg != null) {
      device.fillPath(_rectPath(rect), bg, PdfFillRule.nonzero,
          _annotationFillAlpha(annotation));
    }
    if (bc != null && stroke.width > 0) {
      device.strokePath(_rectPath(_insetRect(rect, stroke.width / 2)), bc,
          stroke, _annotationStrokeAlpha(annotation));
    }

    final flags = _fieldFlags(annotation);
    const pushButton = 1 << 16; // /Ff bit 17 (§12.7.4.2, table 227)
    const radio = 1 << 15; // /Ff bit 16
    if (flags & pushButton != 0) {
      final ca = cos.resolve(mkDict?['CA']);
      if (ca is CosString && ca.text.isNotEmpty) {
        _drawButtonCaption(annotation, rect, ca.text);
      }
      return;
    }
    // Checkbox / radio: the widget's own /AS names its on/off appearance; an
    // on state paints the mark even without the /AP that would carry it.
    final as = cos.resolve(annotation.dict['AS']);
    if (as is! CosName || as.value == 'Off') return;
    _drawCheckMark(rect,
        radio: flags & radio != 0,
        color: bc ?? _pdfColor(0x000000),
        alpha: _annotationStrokeAlpha(annotation));
  }

  void _drawButtonCaption(
      PdfWidgetAnnotation annotation, PdfRect rect, String caption) {
    final style = _parseWidgetDefaultAppearance(annotation);
    // The DA size (defaulted to 12 when the string says auto-size), capped so
    // the caption fits a short button.
    final size = math.min(style.size, rect.height);
    final geometry = _fallbackTextGeometry(caption, style.fontName);
    final textWidth = geometry.width * size;
    final x = rect.left + (rect.width - textWidth) / 2;
    final y = rect.bottom + (rect.height - size * 0.718) / 2;
    device.save();
    try {
      device.clipPath(_rectPath(rect), PdfFillRule.nonzero);
      device.drawText(PdfTextRun(
        text: caption,
        transform: PdfMatrix(size, 0, 0, size, x, y),
        color: style.color,
        width: geometry.width,
        fontName: style.fontName,
        fontSize: size,
        charOffsets: geometry.offsets,
      ));
    } finally {
      device.restore();
    }
  }

  /// Base-14 advance geometry for text synthesized when an annotation has no
  /// appearance stream. Unlike ordinary page text there is no font object to
  /// supply per-code advances, so derive both the total and every character
  /// boundary from the same standard-font table. Canvas and retained backends
  /// can then place substitute glyphs at identical, authoritative positions.
  ({double width, List<double> offsets}) _fallbackTextGeometry(
      String text, String fontName) {
    final font =
        PdfStandardFont.tryFromName(fontName) ?? PdfStandardFont.helvetica;
    final offsets = <double>[0];
    var width = 0.0;
    for (final code in text.codeUnits) {
      width += font.widthOf(code) / 1000;
      offsets.add(width);
    }
    return (width: width, offsets: List.unmodifiable(offsets));
  }

  /// A checkbox check (stroked tick) or radio dot (filled disc), inset in
  /// [rect] - the synthesized on-state mark when a button carries no /AP.
  void _drawCheckMark(PdfRect rect,
      {required bool radio, required PdfColor color, required double alpha}) {
    final inset = _insetRect(rect, math.min(rect.width, rect.height) * 0.25);
    if (inset.width <= 0 || inset.height <= 0) return;
    if (radio) {
      device.fillPath(_ellipsePath(inset), color, PdfFillRule.nonzero, alpha);
      return;
    }
    final w = inset.width, h = inset.height;
    device.strokePath(
      PdfPath([
        PdfMoveTo(inset.left, inset.bottom + h * 0.55),
        PdfLineTo(inset.left + w * 0.35, inset.bottom + h * 0.15),
        PdfLineTo(inset.right, inset.top),
      ]),
      color,
      PdfStroke(width: math.max(1, math.min(w, h) * 0.15), cap: 1, join: 1),
      alpha,
    );
  }

  /// Parses an /MK colour array (0/1/3/4 components; §12.5.6.19). An empty
  /// array means "no colour" (transparent) and returns null.
  PdfColor? _mkColor(CosObject? raw) {
    final v = cos.resolve(raw);
    if (v is! CosArray) return null;
    final c = [for (final e in v.items) _numOf(cos.resolve(e))];
    return switch (c.length) {
      1 => PdfColor.gray(c[0].clamp(0.0, 1.0)),
      3 => PdfColor(
          c[0].clamp(0.0, 1.0), c[1].clamp(0.0, 1.0), c[2].clamp(0.0, 1.0)),
      4 => PdfColor.cmyk(c[0], c[1], c[2], c[3]),
      _ => null,
    };
  }

  /// The field flag word (/Ff), resolved up the /Parent chain (§12.7.3.1).
  int _fieldFlags(PdfAnnotation annotation) {
    CosDictionary? node = annotation.dict;
    final visited = <CosDictionary>{};
    while (node != null && visited.add(node)) {
      final ff = cos.resolve(node['Ff']);
      if (ff is CosInteger) return ff.value;
      final parent = cos.resolve(node['Parent']);
      node = parent is CosDictionary ? parent : null;
    }
    return 0;
  }

  PdfStroke _annotationStroke(PdfAnnotation annotation) => PdfStroke(
        width:
            annotation.borderWidth ?? _annotationBorderWidth(annotation) ?? 1,
        dashArray: annotation.borderDash ?? const [],
      );

  double? _annotationBorderWidth(PdfAnnotation annotation) {
    final border = cos.resolve(annotation.dict['Border']);
    if (border is! CosArray || border.length < 3) return null;
    final width = cos.resolve(border[2]);
    return switch (width) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => null,
    };
  }

  double _annotationStrokeAlpha(PdfAnnotation annotation) =>
      _annotationNumber(annotation, 'CA') ?? 1;

  double _annotationFillAlpha(PdfAnnotation annotation,
          {double fallback = 1}) =>
      _annotationNumber(annotation, 'ca') ??
      _annotationNumber(annotation, 'CA') ??
      fallback;

  double? _annotationNumber(PdfAnnotation annotation, String key) {
    final value = cos.resolve(annotation.dict[key]);
    return switch (value) {
      CosInteger(:final value) => value.toDouble().clamp(0.0, 1.0),
      CosReal(:final value) => value.clamp(0.0, 1.0),
      _ => null,
    };
  }

  PdfColor _pdfColor(int rgb) => PdfColor(
        ((rgb >> 16) & 0xFF) / 255,
        ((rgb >> 8) & 0xFF) / 255,
        (rgb & 0xFF) / 255,
      );

  PdfPath _rectPath(PdfRect rect) => PdfPath([
        PdfMoveTo(rect.left, rect.bottom),
        PdfLineTo(rect.right, rect.bottom),
        PdfLineTo(rect.right, rect.top),
        PdfLineTo(rect.left, rect.top),
        const PdfClosePath(),
      ]);

  PdfRect _insetRect(PdfRect rect, double inset) {
    final dx = math.min(inset, rect.width / 2);
    final dy = math.min(inset, rect.height / 2);
    return PdfRect(
        rect.left + dx, rect.bottom + dy, rect.right - dx, rect.top - dy);
  }

  PdfPath _ellipsePath(PdfRect rect) {
    const k = 0.5522847498307936;
    final cx = (rect.left + rect.right) / 2;
    final cy = (rect.bottom + rect.top) / 2;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    return PdfPath([
      PdfMoveTo(cx + rx, cy),
      PdfCubicTo(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry),
      PdfCubicTo(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy),
      PdfCubicTo(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry),
      PdfCubicTo(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy),
      const PdfClosePath(),
    ]);
  }

  List<PdfRect> _quadRects(PdfAnnotation annotation) {
    final raw = cos.resolve(annotation.dict['QuadPoints']);
    if (raw is! CosArray) return const [];
    final rects = <PdfRect>[];
    for (var i = 0; i + 7 < raw.length; i += 8) {
      final xs = <double>[];
      final ys = <double>[];
      for (var j = 0; j < 8; j += 2) {
        final x = _numOf(cos.resolve(raw[i + j]));
        final y = _numOf(cos.resolve(raw[i + j + 1]));
        xs.add(x);
        ys.add(y);
      }
      rects.add(PdfRect(
        xs.reduce(math.min),
        ys.reduce(math.min),
        xs.reduce(math.max),
        ys.reduce(math.max),
      ));
    }
    return rects;
  }

  PdfPath _squigglyPath(PdfRect rect) {
    final y = rect.bottom + rect.height * 0.12;
    final amp = math.max(1.0, rect.height * 0.06);
    final step = amp * 2;
    final segments = <PdfPathSegment>[PdfMoveTo(rect.left, y)];
    var x = rect.left;
    var up = true;
    while (x < rect.right) {
      x = math.min(rect.right, x + step);
      segments.add(PdfLineTo(x, y + (up ? amp : -amp)));
      up = !up;
    }
    return PdfPath(segments);
  }

  /// Filter-decodes and parses [stream]'s content operations, cached by stream
  /// identity ([_opsCache]). Returns null when the stream cannot be decoded.
  /// The returned list is read-only (shared across draws) - callers pass it to
  /// [_run], which never mutates it.
  List<ContentOperation>? _parsedOps(CosStream stream) {
    final cached = _opsCache[stream];
    if (cached != null) return cached;
    final Uint8List content;
    try {
      content = cos.decodeStreamData(stream);
    } on Exception {
      return null;
    }
    return _opsCache[stream] = ContentStreamParser.parse(content);
  }

  /// Renders one appearance form: the /BBox corners go through /Matrix,
  /// their bounding box is fitted onto the annotation's /Rect, and the
  /// content runs clipped to the BBox (the algorithm in §12.5.5).
  void _drawAppearance(CosStream form, PdfRect rect) {
    final ops = _parsedOps(form);
    if (ops == null) return;
    final dict = form.dictionary;
    final matrixObj = cos.resolve(dict['Matrix']);
    final matrix = matrixObj is CosArray && matrixObj.length >= 6
        ? _matrixFrom(matrixObj.items)
        : PdfMatrix.identity;
    final bbox = _numbersOf(dict['BBox']);

    var ctm = matrix;
    if (bbox.length >= 4 && rect.width > 0 && rect.height > 0) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final (x, y) in [
        (bbox[0], bbox[1]),
        (bbox[2], bbox[1]),
        (bbox[2], bbox[3]),
        (bbox[0], bbox[3]),
      ]) {
        minX = math.min(minX, matrix.transformX(x, y));
        minY = math.min(minY, matrix.transformY(x, y));
        maxX = math.max(maxX, matrix.transformX(x, y));
        maxY = math.max(maxY, matrix.transformY(x, y));
      }
      if (maxX > minX && maxY > minY) {
        final sx = rect.width / (maxX - minX);
        final sy = rect.height / (maxY - minY);
        ctm = matrix.concat(PdfMatrix(
            sx, 0, 0, sy, rect.left - minX * sx, rect.bottom - minY * sy));
      }
    }

    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    final savedVisibilityDepth = _visibilityStack.length;
    _overprint?.save();
    device.save();
    try {
      _state = _GraphicsState(_colorContext)..ctm = ctm;
      if (bbox.length >= 4) _clipToBox(bbox);
      final resources = cos.resolve(dict['Resources']);
      _run(
        ops,
        resources is CosDictionary ? resources : CosDictionary(),
        _currentFormDepth + 1,
      );
      final mask = _state.softMask;
      if (mask != null) _finalizeSoftMask(mask);
    } finally {
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      while (_visibilityStack.length > savedVisibilityDepth) {
        _visibilityStack.removeLast();
      }
      while (_mcidStack.length > savedVisibilityDepth) {
        _mcidStack.removeLast();
      }
      _restoreDeviceBlend(savedState);
      _state = savedState;
      _overprint?.restore();
      device.restore();
    }
  }

  void _run(
      List<ContentOperation> ops, CosDictionary resources, int formDepth) {
    final previousDepth = _currentFormDepth;
    final previousVisibilityDepth = _visibilityStack.length;
    _currentFormDepth = formDepth;
    try {
      _runOps(ops, resources, formDepth);
    } finally {
      while (_visibilityStack.length > previousVisibilityDepth) {
        _visibilityStack.removeLast();
      }
      while (_mcidStack.length > previousVisibilityDepth) {
        _mcidStack.removeLast();
      }
      _currentFormDepth = previousDepth;
    }
  }

  void _runCursor(
      ContentOperationCursor cursor, CosDictionary resources, int formDepth) {
    final previousDepth = _currentFormDepth;
    final previousVisibilityDepth = _visibilityStack.length;
    _currentFormDepth = formDepth;
    try {
      _runCursorOps(cursor, resources, formDepth);
    } finally {
      while (_visibilityStack.length > previousVisibilityDepth) {
        _visibilityStack.removeLast();
      }
      while (_mcidStack.length > previousVisibilityDepth) {
        _mcidStack.removeLast();
      }
      _currentFormDepth = previousDepth;
    }
  }

  Future<void> _runAsync(List<ContentOperation> ops, CosDictionary resources,
      int formDepth, int yieldInterval) async {
    final previousDepth = _currentFormDepth;
    final previousVisibilityDepth = _visibilityStack.length;
    _currentFormDepth = formDepth;
    try {
      await _runOpsAsync(ops, resources, formDepth, yieldInterval);
    } finally {
      while (_visibilityStack.length > previousVisibilityDepth) {
        _visibilityStack.removeLast();
      }
      while (_mcidStack.length > previousVisibilityDepth) {
        _mcidStack.removeLast();
      }
      _currentFormDepth = previousDepth;
    }
  }

  Future<void> _runOpsAsync(List<ContentOperation> ops, CosDictionary resources,
      int formDepth, int yieldInterval) async {
    final token = cancellation;
    var opCount = 0;
    for (final op in ops) {
      if (++opCount % yieldInterval == 0) {
        await Future<void>.delayed(Duration.zero);
        if (token != null && token.cancelled) {
          throw const PdfCancelledException();
        }
      } else if (token != null &&
          opCount & (_cancelCheckInterval - 1) == 0 &&
          token.cancelled) {
        throw const PdfCancelledException();
      }
      _execOp(op, resources, formDepth);
    }
  }

  /// Runs at most [maxOperations] more operations from [cursor] (null runs to
  /// exhaustion), returning true once the cursor is spent.
  ///
  /// The bounded form is what makes a page walk *resumable*: the cursor holds
  /// the parse position and this interpreter holds the graphics state, so a
  /// later call picks up exactly where this one stopped instead of re-walking
  /// from the top. Chunk boundaries land only between top-level operations -
  /// a form XObject runs to completion inside one [_execOp] - so the state is
  /// always at page level in between. See [PdfPageContentWalk].
  Future<bool> _advanceCursorAsync(
      ContentOperationCursor cursor,
      CosDictionary resources,
      int formDepth,
      int yieldInterval,
      int? maxOperations) async {
    final token = cancellation;
    var opCount = 0;
    while (maxOperations == null || opCount < maxOperations) {
      final op = cursor.nextOperation();
      if (op == null) return true;
      if (++opCount % yieldInterval == 0) {
        await Future<void>.delayed(Duration.zero);
        if (token != null && token.cancelled) {
          throw const PdfCancelledException();
        }
      } else if (token != null &&
          opCount & (_cancelCheckInterval - 1) == 0 &&
          token.cancelled) {
        throw const PdfCancelledException();
      }
      _execOp(op, resources, formDepth);
    }
    return false;
  }

  void _runOps(
      List<ContentOperation> ops, CosDictionary resources, int formDepth) {
    final token = cancellation;
    var opCount = 0;
    for (final op in ops) {
      if (token != null && ++opCount & (_cancelCheckInterval - 1) == 0) {
        if (token.cancelled) throw const PdfCancelledException();
      }
      _execOp(op, resources, formDepth);
    }
  }

  void _runCursorOps(
      ContentOperationCursor cursor, CosDictionary resources, int formDepth) {
    final token = cancellation;
    var opCount = 0;
    while (true) {
      final op = cursor.nextOperation();
      if (op == null) return;
      if (token != null && ++opCount & (_cancelCheckInterval - 1) == 0) {
        if (token.cancelled) throw const PdfCancelledException();
      }
      _execOp(op, resources, formDepth);
    }
  }

  void _execOp(ContentOperation op, CosDictionary resources, int formDepth) {
    final numbers = op.numberOperands;
    if (numbers != null) {
      // The incremental parser leaves number-only instructions unboxed. Keep
      // the dominant CAD path on primitive numbers all the way into path
      // construction: this avoids millions of short-lived CosReal objects and
      // their repeated runtime type checks. Programmatically-created
      // ContentOperations retain the general COS-object switch below.
      switch (op.operator) {
        case 'm':
          _moveTo(_number(numbers, 0), _number(numbers, 1));
          return;
        case 'l':
          _lineTo(_number(numbers, 0), _number(numbers, 1));
          return;
        case 'c':
          _curveTo(
            _number(numbers, 0),
            _number(numbers, 1),
            _number(numbers, 2),
            _number(numbers, 3),
            _number(numbers, 4),
            _number(numbers, 5),
          );
          return;
        case 'v':
          _curveTo(
            _currentX,
            _currentY,
            _number(numbers, 0),
            _number(numbers, 1),
            _number(numbers, 2),
            _number(numbers, 3),
          );
          return;
        case 'y':
          final x2 = _number(numbers, 2), y2 = _number(numbers, 3);
          _curveTo(_number(numbers, 0), _number(numbers, 1), x2, y2, x2, y2);
          return;
        case 're':
          final x = _number(numbers, 0), y = _number(numbers, 1);
          final w = _number(numbers, 2), h = _number(numbers, 3);
          _moveTo(x, y);
          _lineTo(x + w, y);
          _lineTo(x + w, y + h);
          _lineTo(x, y + h);
          _closePath();
          return;
        case 'cm':
          _state.ctm = PdfMatrix(
            _number(numbers, 0),
            _number(numbers, 1),
            _number(numbers, 2),
            _number(numbers, 3),
            _number(numbers, 4),
            _number(numbers, 5),
          ).concat(_state.ctm);
          return;
      }
    }
    final o = op.operands;
    // A `d1` Type3 glyph forbids colour operators (§9.6.5): the glyph paints
    // in the text colour that invoked it. The flag is false on every ordinary
    // page, so this is one short-circuited branch on the hot path.
    if (_type3ColorLocked && _isColorOp(op.operator)) return;
    switch (op.operator) {
      // Ordering here is deliberate and load-bearing: Dart lowers this
      // String switch to a linear chain of comparisons, not a jump table
      // (measured: one hot case moved ~36 positions later cost 5.9x).
      // Vector-dense pages are overwhelmingly path ops - l, m and S are 75%
      // of all operations on the CAD probe - so the path/painting group
      // leads and the rarer state/text groups follow (#401).
      // --- path construction ---
      case 'm':
        _moveTo(_num(o, 0), _num(o, 1));
      case 'l':
        _lineTo(_num(o, 0), _num(o, 1));
      case 'c':
        _curveTo(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3), _num(o, 4),
            _num(o, 5));
      case 'v':
        _curveTo(_currentX, _currentY, _num(o, 0), _num(o, 1), _num(o, 2),
            _num(o, 3));
      case 'y':
        _curveTo(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3), _num(o, 2),
            _num(o, 3));
      case 'h':
        _closePath();
      case 're':
        final x = _num(o, 0), y = _num(o, 1);
        final w = _num(o, 2), h = _num(o, 3);
        _moveTo(x, y);
        _lineTo(x + w, y);
        _lineTo(x + w, y + h);
        _lineTo(x, y + h);
        _closePath();

      // --- path painting ---
      case 'S':
        _paint(stroke: true);
      case 's':
        _closePath();
        _paint(stroke: true);
      case 'f' || 'F':
        _paint(fill: PdfFillRule.nonzero);
      case 'f*':
        _paint(fill: PdfFillRule.evenOdd);
      case 'B':
        _paint(fill: PdfFillRule.nonzero, stroke: true);
      case 'B*':
        _paint(fill: PdfFillRule.evenOdd, stroke: true);
      case 'b':
        _closePath();
        _paint(fill: PdfFillRule.nonzero, stroke: true);
      case 'b*':
        _closePath();
        _paint(fill: PdfFillRule.evenOdd, stroke: true);
      case 'n':
        _paint();
      case 'W':
        _pendingClip = PdfFillRule.nonzero;
      case 'W*':
        _pendingClip = PdfFillRule.evenOdd;

      // --- graphics state ---
      case 'q':
        _stateStack.add(_GraphicsState.from(_state));
        _overprint?.save();
        device.save();
      case 'Q':
        if (_stateStack.isNotEmpty) {
          final restored = _stateStack.removeLast();
          final mask = _state.softMask;
          if (mask != null && !identical(mask, restored.softMask)) {
            _finalizeSoftMask(mask);
          }
          if (_state.blendMode != restored.blendMode) {
            device.setBlendMode(restored.blendMode);
          }
          _deliverOverprint(restored.fillOverprint, restored.strokeOverprint,
              restored.overprintMode);
          _state = restored;
          _overprint?.restore();
          device.restore();
        }
      case 'cm':
        _state.ctm = _matrixFrom(o).concat(_state.ctm);
      case 'w':
        _state.stroke = _state.stroke.copyWith(width: _num(o, 0));
      case 'J':
        _state.stroke = _state.stroke.copyWith(cap: _num(o, 0).toInt());
      case 'j':
        _state.stroke = _state.stroke.copyWith(join: _num(o, 0).toInt());
      case 'M':
        _state.stroke = _state.stroke.copyWith(miterLimit: _num(o, 0));
      case 'd':
        _state.stroke = _state.stroke.copyWith(
          dashArray: o.isNotEmpty && o[0] is CosArray
              ? [for (final v in (o[0] as CosArray).items) _numOf(v)]
              : const [],
          dashPhase: _num(o, 1),
        );
      case 'gs':
        _applyExtGState(_dictResource(resources, 'ExtGState', o));
      case 'ri':
        if (o.isNotEmpty && o[0] is CosName) {
          _state.renderingIntent = switch ((o[0] as CosName).value) {
            'Perceptual' => PdfRenderingIntent.perceptual,
            'Saturation' => PdfRenderingIntent.saturation,
            'AbsoluteColorimetric' => PdfRenderingIntent.absoluteColorimetric,
            _ => PdfRenderingIntent.relativeColorimetric,
          };
          _refreshColorsForIntent();
        }
      case 'i':
        break;

      // --- color ---
      case 'g':
        _state.fillOperands = null;
        _state.fillSpace = PdfColorSpace.parse(cos, const CosName('DeviceGray'),
            colorContext: _colorContext);
        _state.fillColor = _paintingLuminosityMask
            ? PdfColor.gray(_num(o, 0))
            : _colorContext.deviceGray(_num(o, 0),
                intent: _state.renderingIntent);
        _state.fillInk = _overprint == null ? null : _grayInk(_num(o, 0));
        _state.fillBlendInk = _state.fillInk;
        _state.fillPattern = null;
      case 'G':
        _state.strokeOperands = null;
        _state.strokeSpace = PdfColorSpace.parse(
            cos, const CosName('DeviceGray'),
            colorContext: _colorContext);
        _state.strokeColor = _paintingLuminosityMask
            ? PdfColor.gray(_num(o, 0))
            : _colorContext.deviceGray(_num(o, 0),
                intent: _state.renderingIntent);
        _state.strokeInk = _overprint == null ? null : _grayInk(_num(o, 0));
        _state.strokeBlendInk = _state.strokeInk;
      case 'rg':
        _state.fillOperands = null;
        _state.fillSpace = PdfColorSpace.parse(cos, const CosName('DeviceRGB'),
            colorContext: _colorContext);
        final fillRgb = [_num(o, 0), _num(o, 1), _num(o, 2)];
        _state.fillColor = _maskColorFromValues(
            fillRgb, PdfColor(fillRgb[0], fillRgb[1], fillRgb[2]));
        _state.fillInk = null;
        _state.fillBlendInk = null;
        _state.fillPattern = null;
      case 'RG':
        _state.strokeOperands = null;
        _state.strokeSpace = PdfColorSpace.parse(
            cos, const CosName('DeviceRGB'),
            colorContext: _colorContext);
        final strokeRgb = [_num(o, 0), _num(o, 1), _num(o, 2)];
        _state.strokeColor = _maskColorFromValues(
            strokeRgb, PdfColor(strokeRgb[0], strokeRgb[1], strokeRgb[2]));
        _state.strokeInk = null;
        _state.strokeBlendInk = null;
      case 'k':
        _state.fillOperands = null;
        _state.fillSpace = PdfColorSpace.parse(cos, const CosName('DeviceCMYK'),
            colorContext: _colorContext);
        final fillCmyk = [_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3)];
        _state.fillColor = _maskColorFromValues(
            fillCmyk,
            _colorContext.deviceCmyk(
                fillCmyk[0], fillCmyk[1], fillCmyk[2], fillCmyk[3],
                intent: _state.renderingIntent));
        _state.fillInk = _overprint == null
            ? null
            : _cmykInk(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3));
        _state.fillBlendInk = _state.fillInk;
        _state.fillPattern = null;
      case 'K':
        _state.strokeOperands = null;
        _state.strokeSpace = PdfColorSpace.parse(
            cos, const CosName('DeviceCMYK'),
            colorContext: _colorContext);
        final strokeCmyk = [_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3)];
        _state.strokeColor = _maskColorFromValues(
            strokeCmyk,
            _colorContext.deviceCmyk(
                strokeCmyk[0], strokeCmyk[1], strokeCmyk[2], strokeCmyk[3],
                intent: _state.renderingIntent));
        _state.strokeInk = _overprint == null
            ? null
            : _cmykInk(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3));
        _state.strokeBlendInk = _state.strokeInk;
      case 'cs':
        // Selecting a fill space clears the pattern (tracked while scanning);
        // the space's tint/ICC machinery only matters for resolving colours,
        // which scanning skips.
        _state.fillPattern = null;
        if (_scanImages) break;
        // The colorants belong to the colour, not the space: a space selected
        // but not yet given components must not keep the previous space's
        // colorant reading (a stale one would overprint the wrong channels).
        _state.fillInk = null;
        _state.fillBlendInk = null;
        _state.fillOperands = null;
        _state.fillSpace = PdfColorSpace.parse(cos, o.isEmpty ? null : o[0],
            resources: resources, iccCache: _iccCache);
      case 'CS':
        if (_scanImages) break;
        _state.strokeInk = null;
        _state.strokeBlendInk = null;
        _state.strokeOperands = null;
        _state.strokeSpace = PdfColorSpace.parse(cos, o.isEmpty ? null : o[0],
            resources: resources, iccCache: _iccCache);
      case 'sc' || 'scn':
        // The fill pattern is tracked even while scanning - a tiling pattern
        // fill runs the cell content (which can draw images). The resolved
        // fill colour, though, is never needed when only collecting images.
        _state.fillPattern = null;
        if (o.isNotEmpty && o.last is CosName) {
          _state.fillOperands = null;
          _state.fillPattern =
              _resource(resources, 'Pattern', o.last as CosName);
          _state.fillPatternComponents = [
            for (final v in o)
              if (v is CosInteger || v is CosReal) _numOf(v),
          ];
          _state.fillInk = null;
          _state.fillBlendInk = null;
        } else if (!_scanImages) {
          _state.fillOperands = List<CosObject>.unmodifiable(o);
          _state.fillColor = _resolveScn(_state.fillSpace, o, _state.fillColor);
          _state.fillInk = _overprint == null
              ? null
              : _resolveInk(_state.fillSpace, o, _state.fillInk);
          _state.fillBlendInk = _overprint == null
              ? null
              : _resolveBlendInk(_state.fillSpace, o, _state.fillBlendInk);
        }
      case 'SC' || 'SCN':
        // Stroke colour never affects which images are drawn.
        if (_scanImages) break;
        if (o.isNotEmpty && o.last is CosName) {
          _state.strokeOperands = null;
          // stroke patterns: approximate with the pattern's average color
          final color = _patternAverageColor(
              _resource(resources, 'Pattern', o.last as CosName));
          if (color != null) _state.strokeColor = color;
          _state.strokeInk = null;
          _state.strokeBlendInk = null;
        } else {
          _state.strokeOperands = List<CosObject>.unmodifiable(o);
          _state.strokeColor =
              _resolveScn(_state.strokeSpace, o, _state.strokeColor);
          _state.strokeInk = _overprint == null
              ? null
              : _resolveInk(_state.strokeSpace, o, _state.strokeInk);
          _state.strokeBlendInk = _overprint == null
              ? null
              : _resolveBlendInk(_state.strokeSpace, o, _state.strokeBlendInk);
        }

      // --- text ---
      case 'BT':
        _textMatrix = PdfMatrix.identity;
        _lineMatrix = PdfMatrix.identity;
        _textClipPending = false;
        _textClipSegments.clear();
      case 'ET':
        if (_textClipPending) {
          // §9.4.1: combine the accumulated glyph outlines (nonzero rule)
          // and intersect with the current clip. No outlines → empty path
          // → everything painted afterward is clipped away.
          device.clipPath(
              PdfPath(List.of(_textClipSegments)), PdfFillRule.nonzero);
          _textClipPending = false;
          _textClipSegments.clear();
        }
      case 'Tf':
        _setFont(resources, o);
      case 'Td':
        _textLineMove(_num(o, 0), _num(o, 1));
      case 'TD':
        _state.leading = -_num(o, 1);
        _textLineMove(_num(o, 0), _num(o, 1));
      case 'Tm':
        _lineMatrix = _matrixFrom(o);
        _textMatrix = _lineMatrix;
      case 'T*':
        _textLineMove(0, -_state.leading);
      case 'TL':
        _state.leading = _num(o, 0);
      case 'Tc':
        _state.charSpacing = _num(o, 0);
      case 'Tw':
        _state.wordSpacing = _num(o, 0);
      case 'Tz':
        _state.horizontalScale = _num(o, 0) / 100;
      case 'Ts':
        _state.rise = _num(o, 0);
      case 'Tr':
        _state.renderMode = _num(o, 0).toInt();
      case 'Tj':
        if (o.isNotEmpty && o[0] is CosString) {
          _showText((o[0] as CosString).bytes);
        }
      case "'":
        _textLineMove(0, -_state.leading);
        if (o.isNotEmpty && o[0] is CosString) {
          _showText((o[0] as CosString).bytes);
        }
      case '"':
        _state.wordSpacing = _num(o, 0);
        _state.charSpacing = _num(o, 1);
        _textLineMove(0, -_state.leading);
        if (o.length > 2 && o[2] is CosString) {
          _showText((o[2] as CosString).bytes);
        }
      case 'TJ':
        if (o.isNotEmpty && o[0] is CosArray) {
          for (final item in (o[0] as CosArray).items) {
            if (item is CosString) {
              _showText(item.bytes);
            } else if (_state.font?.isVertical ?? false) {
              // Vertical writing: the adjustment moves the pen along y.
              final shift = -_numOf(item) / 1000 * _state.fontSize;
              _textMatrix = PdfMatrix.translation(0, shift).concat(_textMatrix);
            } else {
              final shift = -_numOf(item) /
                  1000 *
                  _state.fontSize *
                  _state.horizontalScale;
              _textMatrix = PdfMatrix.translation(shift, 0).concat(_textMatrix);
            }
          }
        }

      // --- XObjects and inline images ---
      case 'Do':
        if (_contentVisible) _doXObject(resources, o, formDepth);
      case 'BI':
        if (_contentVisible) _drawInlineImage(resources, o);

      case 'sh':
        // Shadings are gradients/meshes - never images.
        if (_contentVisible && !_scanImages) _applyShading(resources, o);

      // --- marked content, compatibility, Type3 metrics ---
      case 'BDC':
        _visibilityStack.add(_markedContentVisible(resources, o));
        _mcidStack.add(_markedContentMcid(resources, o));
      case 'BMC':
        _visibilityStack.add(true);
        _mcidStack.add(null);
      case 'EMC':
        if (_visibilityStack.isNotEmpty) _visibilityStack.removeLast();
        if (_mcidStack.isNotEmpty) _mcidStack.removeLast();
      case 'MP' || 'DP':
      case 'BX' || 'EX':
      case 'd0':
        break;
      case 'd1':
        // The glyph is a shape-only Type3 glyph: it paints in the invoking
        // text colour and its own colour operators are ignored (§9.6.5). The
        // width/BBox operands are advisory (the font already supplied widths).
        _type3ColorLocked = true;

      default:
        // unknown operator: PDF says ignore (in compatibility sections);
        // we ignore everywhere and rely on corpus testing to find gaps
        break;
    }
  }

  /// Whether [op] sets a colour or colour space - the operators a `d1` Type3
  /// CharProc must ignore (§9.6.5, referencing the colour operators of §8.6.8).
  static bool _isColorOp(String op) => switch (op) {
        'g' || 'G' || 'rg' || 'RG' || 'k' || 'K' => true,
        'cs' || 'CS' || 'sc' || 'scn' || 'SC' || 'SCN' => true,
        _ => false,
      };

  bool get _contentVisible => _visibilityStack.every((visible) => visible);

  /// The MCID of the innermost enclosing marked-content sequence that
  /// declared one, or null when no enclosing sequence is tagged.
  int? get _currentMcid {
    for (var i = _mcidStack.length - 1; i >= 0; i--) {
      final mcid = _mcidStack[i];
      if (mcid != null) return mcid;
    }
    return null;
  }

  /// The /MCID of a BDC operator's property list, or null. The properties
  /// are either an inline dictionary or a name into /Properties (§14.6.1).
  int? _markedContentMcid(CosDictionary resources, List<CosObject> operands) {
    if (operands.length < 2) return null;
    var property = operands[1];
    if (property is CosName) {
      final properties = cos.resolve(resources['Properties']);
      final named =
          properties is CosDictionary ? properties[property.value] : null;
      if (named == null) return null;
      property = cos.resolve(named);
    }
    if (property is! CosDictionary) return null;
    final mcid = cos.resolve(property['MCID']);
    return mcid is CosInteger ? mcid.value : null;
  }

  bool _markedContentVisible(
      CosDictionary resources, List<CosObject> operands) {
    if (operands.length < 2 ||
        operands[0] is! CosName ||
        (operands[0] as CosName).value != 'OC') {
      return true;
    }

    CosObject? property = operands[1];
    if (property is CosName) {
      final properties = cos.resolve(resources['Properties']);
      property =
          properties is CosDictionary ? properties[property.value] : null;
    }
    return _optionalContentVisible(property);
  }

  bool _optionalContentVisible(CosObject? object) {
    if (object == null) return true;
    final resolved = cos.resolve(object);
    if (resolved is! CosDictionary) return true;
    final type = cos.resolve(resolved['Type']);
    if (type is CosName && type.value == 'OCMD') {
      return _optionalContentMembershipVisible(resolved);
    }
    if (type is CosName && type.value != 'OCG') return true;
    final ref = object is CosReference ? object : cos.referenceTo(resolved);
    return ref == null ? true : _optionalContentGroupVisible(ref);
  }

  bool _optionalContentMembershipVisible(CosDictionary dict) {
    // §8.11.4.3: a /VE visibility expression, when present, takes precedence
    // over /OCGs + /P.
    final ve = cos.resolve(dict['VE']);
    if (ve is CosArray && ve.length > 0) {
      return _evaluateVisibilityExpression(ve);
    }
    final policy = cos.resolve(dict['P']);
    final policyName = policy is CosName ? policy.value : 'AnyOn';
    final groups = _optionalContentReferences(dict['OCGs']);
    if (groups.isEmpty) return true;
    final values = [
      for (final ref in groups) _optionalContentGroupVisible(ref)
    ];
    return switch (policyName) {
      'AllOn' => values.every((visible) => visible),
      'AnyOff' => values.any((visible) => !visible),
      'AllOff' => values.every((visible) => !visible),
      _ => values.any((visible) => visible),
    };
  }

  /// Evaluates a /VE visibility expression (§8.11.4.3): an array led by /And,
  /// /Or, or /Not whose operands are nested expressions or OCG references; a
  /// leaf OCG is true when its group is visible. Malformed nodes default to
  /// visible so content is never lost.
  bool _evaluateVisibilityExpression(CosObject? object) {
    final resolved = cos.resolve(object);
    if (object is CosReference && resolved is CosDictionary) {
      // A leaf operand: an OCG (or nested OCMD) reference.
      final type = cos.resolve(resolved['Type']);
      if (type is CosName && type.value == 'OCMD') {
        return _optionalContentMembershipVisible(resolved);
      }
      return _optionalContentGroupVisible(object);
    }
    if (resolved is! CosArray || resolved.length == 0) return true;
    final op = cos.resolve(resolved[0]);
    final name = op is CosName ? op.value : '';
    final operands = resolved.items.skip(1);
    switch (name) {
      case 'Not':
        final first = operands.isEmpty ? null : operands.first;
        return !_evaluateVisibilityExpression(first);
      case 'And':
        return operands.every(_evaluateVisibilityExpression);
      case 'Or':
        return operands.any(_evaluateVisibilityExpression);
      default:
        return true;
    }
  }

  Iterable<CosReference> _optionalContentReferences(CosObject? object) sync* {
    final resolved = cos.resolve(object);
    if (object is CosReference && resolved is CosDictionary) {
      yield object;
      return;
    }
    if (resolved is CosArray) {
      for (final item in resolved.items) {
        yield* _optionalContentReferences(item);
      }
    } else if (resolved is CosDictionary) {
      final ref = cos.referenceTo(resolved);
      if (ref != null) yield ref;
    }
  }

  bool _optionalContentGroupVisible(CosReference ref) {
    _ensureOptionalContentConfig();
    if (_optionalContentOff?.contains(ref) == true) return false;
    if (_optionalContentOn?.contains(ref) == true) return true;
    return _optionalContentBaseState != 'OFF';
  }

  void _ensureOptionalContentConfig() {
    if (_optionalContentOn != null) return;
    _optionalContentOn = <CosReference>{};
    _optionalContentOff = <CosReference>{};
    _optionalContentBaseState = 'ON';
    try {
      final properties = cos.resolve(cos.catalog['OCProperties']);
      if (properties is! CosDictionary) return;
      final config = cos.resolve(properties['D']);
      if (config is! CosDictionary) return;
      final base = cos.resolve(config['BaseState']);
      if (base is CosName) _optionalContentBaseState = base.value;
      _optionalContentOn!.addAll(_optionalContentReferences(config['ON']));
      _optionalContentOff!.addAll(_optionalContentReferences(config['OFF']));
    } on Object {
      // Broken optional-content config: default to visible content.
      _optionalContentOn = <CosReference>{};
      _optionalContentOff = <CosReference>{};
      _optionalContentBaseState = 'ON';
    }
  }

  // ---------- paths ----------

  // `m`/`l`/`re` are the highest-frequency operators in the walk (tens of
  // thousands per page on vector-dense art), so these transform the point with
  // the CTM once and append the segment directly - no per-point closure
  // allocation (the old `_addPoint(emit)` minted one [Function] per call) and
  // no double read of `_state.ctm`.
  void _moveTo(double x, double y) {
    _currentX = _startX = x;
    _currentY = _startY = y;
    final m = _state.ctm;
    final px = m.a * x + m.c * y + m.e;
    final py = m.b * x + m.d * y + m.f;
    if (_scanImages) {
      _scanPoint(px, py);
    } else {
      _segments.moveTo(px, py);
    }
  }

  void _lineTo(double x, double y) {
    _currentX = x;
    _currentY = y;
    final m = _state.ctm;
    final px = m.a * x + m.c * y + m.e;
    final py = m.b * x + m.d * y + m.f;
    if (_scanImages) {
      _scanPoint(px, py);
    } else {
      _segments.lineTo(px, py);
    }
  }

  void _curveTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    final m = _state.ctm;
    final px1 = m.a * x1 + m.c * y1 + m.e;
    final py1 = m.b * x1 + m.d * y1 + m.f;
    final px2 = m.a * x2 + m.c * y2 + m.e;
    final py2 = m.b * x2 + m.d * y2 + m.f;
    final px3 = m.a * x3 + m.c * y3 + m.e;
    final py3 = m.b * x3 + m.d * y3 + m.f;
    if (_scanImages) {
      // The Bézier hull (control points included) bounds the curve.
      _scanPoint(px1, py1);
      _scanPoint(px2, py2);
      _scanPoint(px3, py3);
      _currentX = x3;
      _currentY = y3;
      return;
    }
    _segments.cubicTo(px1, py1, px2, py2, px3, py3);
    _currentX = x3;
    _currentY = y3;
  }

  void _closePath() {
    // In scan mode the box already covers every point; nothing to add.
    if (!_scanImages) _segments.close();
    _currentX = _startX;
    _currentY = _startY;
  }

  void _scanPoint(double px, double py) {
    if (px < _scanMinX) _scanMinX = px;
    if (py < _scanMinY) _scanMinY = py;
    if (px > _scanMaxX) _scanMaxX = px;
    if (py > _scanMaxY) _scanMaxY = py;
  }

  void _resetScanBox() {
    _scanMinX = _scanMinY = double.infinity;
    _scanMaxX = _scanMaxY = double.negativeInfinity;
  }

  /// Opens (or clears) the page's colorant buffer and resets the overprint
  /// tuple the device has been told about.
  void _beginOverprint(PdfPage page) {
    _deliveredFillOverprint = false;
    _deliveredStrokeOverprint = false;
    _deliveredOverprintMode = 0;
    _overprint = null;
    _scanImages = _scanImagesOnly;
    if (!resolveOverprint || !debugResolveOverprint) return;
    // Building the buffer is only worth it on a page that enables overprint
    // or declares a DeviceCMYK transparency blending space. The latter needs
    // the same process-color raster even when /OP is never set: ICCBased
    // source colours must be converted and blended in that CMYK space before
    // display (GWG161/164).
    if (!_declaresOverprint(page.resources, 0, {})) return;
    final box = page.cropBox;
    _overprint = PdfOverprintCompositor.forPageBox(
        box.left, box.bottom, box.right, box.top,
        colorContext: _colorContext);
    // The buffer needs paths, clips and colours, none of which the scan-only
    // walk builds - and the substitute streams it produces have to be the ones
    // the collect pass decodes. So a page that opens a buffer is walked in
    // full even when the caller only wanted the image set. Pages that declare
    // no overprint (the overwhelming majority) keep the cheap scan.
    if (_overprint != null) _scanImages = false;
  }

  /// Whether any ExtGState reachable from [resources] turns overprint on.
  /// Walks into form XObjects and patterns (whose own resources can hold the
  /// `gs`), bounded in depth and breadth so a pathological resource graph
  /// cannot make the scan the expensive part.
  bool _declaresOverprint(
      CosDictionary? resources, int depth, Set<CosDictionary> seen) {
    if (resources == null || depth > 4 || !seen.add(resources)) return false;
    if (seen.length > 64) return false;
    final states = cos.resolve(resources['ExtGState']);
    if (states is CosDictionary) {
      for (final value in states.entries.values) {
        final gs = cos.resolve(value);
        if (gs is! CosDictionary) continue;
        if (cos.resolve(gs['OP']) == const CosBoolean(true) ||
            cos.resolve(gs['op']) == const CosBoolean(true)) {
          return true;
        }
      }
    }
    for (final group in const ['XObject', 'Pattern']) {
      final entries = cos.resolve(resources[group]);
      if (entries is! CosDictionary) continue;
      for (final value in entries.entries.values) {
        final entry = cos.resolve(value);
        if (entry is! CosStream) continue;
        final transparency = cos.resolve(entry.dictionary['Group']);
        if (transparency is CosDictionary) {
          final subtype = cos.resolve(transparency['S']);
          final blendSpace = cos.resolve(transparency['CS']);
          if (subtype is CosName &&
              subtype.value == 'Transparency' &&
              blendSpace is CosName &&
              blendSpace.value == 'DeviceCMYK') {
            return true;
          }
        }
        final nested = cos.resolve(entry.dictionary['Resources']);
        if (nested is CosDictionary &&
            _declaresOverprint(nested, depth + 1, seen)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Hands the device an overprint tuple, skipping the call when it already
  /// has it. Every delivery goes through here, and every paint re-syncs, so
  /// the state the device holds is exactly what the next paint needs.
  ///
  /// Re-syncing per paint also closes a leak the `gs`-only delivery had: a
  /// form XObject, a tiling-pattern cell and a soft-mask group each start from
  /// a fresh graphics state without telling the device, so overprint switched
  /// on inside one stayed switched on for everything drawn after it. It also
  /// carries the case this exists for - a draw whose overprint the colorant
  /// buffer already resolved must paint plainly, its composite being in the
  /// colour already.
  void _deliverOverprint(bool fill, bool stroke, int mode) {
    if (fill == _deliveredFillOverprint &&
        stroke == _deliveredStrokeOverprint &&
        mode == _deliveredOverprintMode) {
      return;
    }
    _deliveredFillOverprint = fill;
    _deliveredStrokeOverprint = stroke;
    _deliveredOverprintMode = mode;
    device.setOverprint(fill: fill, stroke: stroke, mode: mode);
  }

  /// Whether a paint composites plainly onto the page, which is what the
  /// colorant buffer models: full alpha, Normal blend, no soft mask.
  bool _opaquePaint(double alpha) =>
      alpha >= 1 &&
      _state.blendMode == PdfBlendMode.normal &&
      _state.softMask == null;

  void _paint({PdfFillRule? fill, bool stroke = false}) {
    // Image scan: no segment list was built. Only a tiling pattern fill draws
    // images (its cell content can), and it just needs the fill area's bounds
    // to know which tiles to run - so hand it the path's bounding box as a
    // rectangle. Solid/shading fills, strokes, and clips draw no images.
    if (_scanImages) {
      final pattern = _state.fillPattern;
      if (fill != null &&
          _contentVisible &&
          _isTilingPattern(pattern) &&
          _scanMinX <= _scanMaxX) {
        _fillWithPattern(
            PdfPath([
              PdfMoveTo(_scanMinX, _scanMinY),
              PdfLineTo(_scanMaxX, _scanMinY),
              PdfLineTo(_scanMaxX, _scanMaxY),
              PdfLineTo(_scanMinX, _scanMaxY),
              const PdfClosePath(),
            ]),
            fill,
            pattern!);
      }
      _pendingClip = null;
      _resetScanBox();
      return;
    }
    final path = _segments.takePath();
    // Reset the builder *before* dispatching: a pattern fill below re-enters
    // the interpreter to run the pattern's cell content, and with the live
    // list still installed the cell's first path ops would append into this
    // already-captured path - the outer region's geometry then leaked into
    // the first tile's paint (and, once cells are recorded and replayed for
    // #524, into every tile).
    final overprint = _overprint;
    if (!path.isEmpty && _contentVisible) {
      if (fill != null) {
        final pattern = _state.fillPattern;
        if (pattern != null) {
          _fillWithPattern(path, fill, pattern);
        } else {
          final resolved = overprint?.fill(
              path, fill, _state.fillColor, _state.fillInk,
              blendInk: _state.fillBlendInk,
              overprint: _state.fillOverprint,
              mode: _state.overprintMode,
              opaque: _opaquePaint(_state.fillAlpha));
          final skip = overprint?.takeSkipPaint() ?? false;
          final spatial = overprint?.takeSpatialPaint();
          _deliverOverprint(
              _state.fillOverprint &&
                  (overprint == null || _state.fillInk != null) &&
                  resolved == null &&
                  !skip &&
                  spatial == null,
              _state.strokeOverprint,
              _state.overprintMode);
          if (spatial != null) {
            device.save();
            device.clipPath(path, fill);
            for (final region in spatial) {
              device.fillPath(region.path, region.color, PdfFillRule.nonzero,
                  _state.fillAlpha);
            }
            device.restore();
          } else if (!skip) {
            device.fillPath(
                path, resolved ?? _state.fillColor, fill, _state.fillAlpha);
          }
        }
      }
      if (stroke) {
        final k = _state.ctm.scaleFactor;
        final scaled = _state.stroke.copyWith(
            // A zero width stays zero: PDF 32000-1 8.4.3.2 defines it as "the
            // thinnest line that can be rendered at device resolution: 1
            // device pixel", which is a device-space rule. Resolving it here
            // to one *user*-space unit made it correct only at pixel ratio 1
            // and three pixels wide at ratio 3. Devices apply the floor.
            width: _state.stroke.width * k,
            // dash lengths live in user space too (§8.4.3.6)
            dashArray: [for (final d in _state.stroke.dashArray) d * k],
            dashPhase: _state.stroke.dashPhase * k);
        final resolved = overprint?.strokeShape(
            path, scaled, _state.strokeColor, _state.strokeInk,
            blendInk: _state.strokeBlendInk,
            overprint: _state.strokeOverprint,
            mode: _state.overprintMode,
            opaque: _opaquePaint(_state.strokeAlpha));
        _deliverOverprint(
            _state.fillOverprint,
            _state.strokeOverprint &&
                (overprint == null || _state.strokeInk != null) &&
                resolved == null,
            _state.overprintMode);
        device.strokePath(
            path, resolved ?? _state.strokeColor, scaled, _state.strokeAlpha);
      }
      if (_pendingClip != null) {
        overprint?.clipPath(path, _pendingClip!);
        device.clipPath(path, _pendingClip!);
      }
    }
    _pendingClip = null;
    _segments.clear();
  }

  // ---------- color ----------

  void _applyExtGState(CosDictionary? gs) {
    if (gs == null) return;
    final ca = cos.resolve(gs['ca']);
    if (ca is CosInteger || ca is CosReal) _state.fillAlpha = _numOf(ca);
    final caStroke = cos.resolve(gs['CA']);
    if (caStroke is CosInteger || caStroke is CosReal) {
      _state.strokeAlpha = _numOf(caStroke);
    }
    final lw = cos.resolve(gs['LW']);
    if (lw is CosInteger || lw is CosReal) {
      _state.stroke = _state.stroke.copyWith(width: _numOf(lw));
    }
    _applyBlendMode(cos.resolve(gs['BM']));
    _applyOverprint(gs);
    _applySoftMask(cos.resolve(gs['SMask']));
  }

  /// Parses the overprint keys (/OP, /op, /OPM; PDF §8.6.7) into the graphics
  /// state and, when the effective state changes, delivers it to the device.
  /// Each key updates its flag only when present, mirroring ca/CA/LW.
  ///
  /// /OP is the stroking flag; /op the nonstroking flag. When /op is absent,
  /// /OP applies to nonstroking too (backward compatibility, §8.6.7 note).
  void _applyOverprint(CosDictionary gs) {
    final beforeFill = _state.fillOverprint;
    final beforeStroke = _state.strokeOverprint;
    final beforeMode = _state.overprintMode;
    final hasLower = gs.containsKey('op');
    final op = cos.resolve(gs['OP']);
    if (op is CosBoolean) {
      _state.strokeOverprint = op.value;
      if (!hasLower) _state.fillOverprint = op.value;
    }
    final opLower = cos.resolve(gs['op']);
    if (opLower is CosBoolean) _state.fillOverprint = opLower.value;
    final opm = cos.resolve(gs['OPM']);
    if (opm is CosInteger) _state.overprintMode = opm.value == 0 ? 0 : 1;
    if (_state.fillOverprint != beforeFill ||
        _state.strokeOverprint != beforeStroke ||
        _state.overprintMode != beforeMode) {
      _deliverOverprint(
          _state.fillOverprint, _state.strokeOverprint, _state.overprintMode);
    }
  }

  void _applyBlendMode(CosObject? bm) {
    var name = bm;
    if (name is CosArray && name.length > 0) name = cos.resolve(name[0]);
    if (name is! CosName) return;
    final mode = switch (name.value) {
      'Multiply' => PdfBlendMode.multiply,
      'Screen' => PdfBlendMode.screen,
      'Overlay' => PdfBlendMode.overlay,
      'Darken' => PdfBlendMode.darken,
      'Lighten' => PdfBlendMode.lighten,
      'ColorDodge' => PdfBlendMode.colorDodge,
      'ColorBurn' => PdfBlendMode.colorBurn,
      'HardLight' => PdfBlendMode.hardLight,
      'SoftLight' => PdfBlendMode.softLight,
      'Difference' => PdfBlendMode.difference,
      'Exclusion' => PdfBlendMode.exclusion,
      'Hue' => PdfBlendMode.hue,
      'Saturation' => PdfBlendMode.saturation,
      'Color' => PdfBlendMode.color,
      'Luminosity' => PdfBlendMode.luminosity,
      _ => PdfBlendMode.normal, // incl. /Normal and /Compatible
    };
    if (mode != _state.blendMode) {
      _state.blendMode = mode;
      device.setBlendMode(mode);
    }
  }

  void _applySoftMask(CosObject? smask) {
    if (smask is CosName && smask.value == 'None') {
      final mask = _state.softMask;
      if (mask != null && mask.frameDepth == _stateStack.length) {
        _finalizeSoftMask(mask);
      }
      _state.softMask = null;
      return;
    }
    if (smask is! CosDictionary) return;
    final form = cos.resolve(smask['G']);
    if (form is! CosStream) return;
    final mask = _state.softMask;
    if (mask != null && mask.frameDepth == _stateStack.length) {
      _finalizeSoftMask(mask);
    }
    final s = cos.resolve(smask['S']);
    final luminosity = s is CosName && s.value == 'Luminosity';

    // /BC backdrop colour (component values in the group's colour space) sets
    // the mask value for areas the group leaves unpainted; default black.
    var backdropLuminance = 0.0;
    final bc = cos.resolve(smask['BC']);
    if (bc is CosArray && bc.length > 0) {
      final c = [for (final v in bc.items) _numOf(cos.resolve(v))];
      backdropLuminance = switch (c.length) {
        1 => c[0],
        3 => 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2],
        4 => (1 - c[0]) * 0.3 + (1 - c[1]) * 0.59 + (1 - c[2]) * 0.11,
        _ => c[0],
      };
    }

    // /TR transfer function, linearised through its endpoints (exact for the
    // common FunctionType 2, N=1 case these masks use).
    var transferScale = 1.0;
    var transferOffset = 0.0;
    final tr = cos.resolve(smask['TR']);
    if (!(tr is CosName && tr.value == 'Identity')) {
      final fn = PdfFunction.parse(cos, smask['TR']);
      if (fn != null) {
        final lo = fn.evaluate(0);
        final hi = fn.evaluate(1);
        if (lo.isNotEmpty && hi.isNotEmpty) {
          transferOffset = lo[0];
          transferScale = hi[0] - lo[0];
        }
      }
    }

    _state.softMask = _ActiveSoftMask(
      form,
      _state.ctm,
      luminosity,
      _stateStack.length,
      backdropLuminance: backdropLuminance,
      transferScale: transferScale,
      transferOffset: transferOffset,
    );
    _overprint?.beginIsolated();
    device.beginSoftMasked();
  }

  void _finalizeSoftMask(_ActiveSoftMask mask) {
    if (mask.closed) return;
    mask.closed = true;
    device.endSoftMasked(
      luminosity: mask.luminosity,
      backdrop: _pageBox ?? const PdfRect(-1e5, -1e5, 1e5, 1e5),
      drawMask: () => _runSoftMaskForm(mask),
      backdropLuminance: mask.backdropLuminance,
      transferScale: mask.transferScale,
      transferOffset: mask.transferOffset,
    );
    _overprint?.endIsolated();
  }

  /// Runs the mask group's content with a fresh graphics state in the
  /// coordinate space captured when the mask was set.
  void _runSoftMaskForm(_ActiveSoftMask mask) {
    if (_currentFormDepth >= _maxFormDepth) return;
    final ops = _parsedOps(mask.form);
    if (ops == null) return;
    _overprint?.beginMaskCapture();
    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    final savedLuminosityMask = _paintingLuminosityMask;
    _overprint?.save();
    device.save();
    try {
      _paintingLuminosityMask = mask.luminosity;
      _state = _GraphicsState(_colorContext)..ctm = mask.matrix;
      final matrix = cos.resolve(mask.form.dictionary['Matrix']);
      if (matrix is CosArray && matrix.length >= 6) {
        _state.ctm = _matrixFrom(matrix.items).concat(_state.ctm);
      }
      final bbox = cos.resolve(mask.form.dictionary['BBox']);
      if (bbox is CosArray && bbox.length >= 4) {
        _clipToBox([for (var i = 0; i < 4; i++) _numOf(cos.resolve(bbox[i]))]);
      }
      final resources = cos.resolve(mask.form.dictionary['Resources']);
      _run(
        ops,
        resources is CosDictionary ? resources : CosDictionary(),
        _currentFormDepth + 1,
      );
      final nested = _state.softMask;
      if (nested != null) _finalizeSoftMask(nested);
    } finally {
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      _restoreDeviceBlend(savedState);
      _state = savedState;
      _paintingLuminosityMask = savedLuminosityMask;
      _overprint?.restore();
      _overprint?.endMaskCapture();
      device.restore();
    }
  }

  // ---------- text ----------

  void _setFont(CosDictionary resources, List<CosObject> o) {
    _state.fontSize = _num(o, 1);
    final fonts = cos.resolve(resources['Font']);
    CosDictionary? dict;
    if (o.isNotEmpty && o[0] is CosName && fonts is CosDictionary) {
      final resolved = cos.resolve(fonts[(o[0] as CosName).value]);
      if (resolved is CosDictionary) dict = resolved;
    }
    // An unresolvable font (no /Resources at all, or a dangling entry)
    // substitutes Helvetica so the text still paints - and stays
    // selectable/searchable - instead of vanishing.
    dict ??= _fallbackFontDict;
    _state.fontDict = dict;
    _state.font = _loadFont(cos, dict);
  }

  // A single shared substitute dict (document-independent standard Helvetica),
  // so the fallback font also resolves to one cache entry across interpreters
  // and renders rather than reloading per instance.
  static final CosDictionary _fallbackFontDict = CosDictionary()
    ..entries['Type'] = const CosName('Font')
    ..entries['Subtype'] = const CosName('Type1')
    ..entries['BaseFont'] = const CosName('Helvetica');

  void _textLineMove(double tx, double ty) {
    _lineMatrix = PdfMatrix.translation(tx, ty).concat(_lineMatrix);
    _textMatrix = _lineMatrix;
  }

  void _showText(Uint8List bytes) {
    final font = _state.font;
    final size = _state.fontSize;
    if (font == null) return;

    final codes = font.codesOf(bytes);
    final reentrant = _textBufferInUse;
    final buffer = reentrant ? StringBuffer() : (_textBuffer..clear());
    _textBufferInUse = true;
    final emScale = size * _state.horizontalScale;
    // a non-null (possibly empty-outlined) glyph list tells devices the font
    // is embedded, so they must not substitute. In image-scan mode we never
    // emit the run, so skip building outlines - but the Type3 loop below still
    // runs each glyph's CharProc (a content stream that can draw images).
    final glyphs =
        !_scanImages && (font.hasOutlines || font.isType3) && emScale != 0
            ? <PdfGlyphPlacement>[]
            : null;
    // Vertical writing mode (§9.7.4.3): glyphs stack downward. The pen advances
    // along y by the vertical displacement, and each glyph is shifted by its
    // position vector so the column centres on the baseline.
    final vertical = font.isVertical;
    // Per-character pen positions for text extraction (issue #647) and for
    // painting substituted text (issue #649 - a device with no embedded font
    // program has no other source for the PDF's intra-run distribution, so
    // those runs get the table whether or not the caller asked for it; a
    // glyph list already carries the same offsets). Only horizontal text has a
    // meaningful x offset per character; vertical runs advance along y and
    // leave this null.
    final charOffsets = (collectCharOffsets || glyphs == null) &&
            !vertical &&
            !_scanImages &&
            emScale != 0
        ? <double>[]
        : null;
    var lastOffset = 0.0; // tail of charOffsets, kept out of the list
    final hScale = _state.horizontalScale == 0 ? 1.0 : _state.horizontalScale;
    var advance = 0.0; // text-space along the writing direction (x or y)
    // Pen advance bracketing the visible (non-whitespace) glyphs: [leadingAdv]
    // to the start of the first visible glyph, [visibleAdvance] to the end of
    // the last. Edge whitespace (common in tabular content, where a space
    // carries a large Tw to reach the next column) stays in [advance] for
    // positioning but is handed to substituting devices separately so it opens
    // a real gap instead of stretching the visible glyphs - see
    // PdfTextRun.leadingSpace / .visibleWidth.
    var visibleAdvance = 0.0;
    var leadingAdv = 0.0;
    var sawVisible = false;
    for (final code in codes) {
      final text = font.charFor(code);
      buffer.write(text);
      // Non-allocating equivalent of `text.trim().isNotEmpty` - this runs once
      // per glyph on the hot text path, so avoid the per-glyph String.trim().
      final visible = !_isBlankText(text);
      if (visible && !sawVisible) {
        leadingAdv = advance;
        sawVisible = true;
      }
      if (glyphs != null) {
        if (vertical) {
          final v = font.verticalOriginOf(code);
          glyphs.add(PdfGlyphPlacement(
            // run.transform scales x by size*Th but the position vector scales
            // by size only, so divide x back out by Th; y is in em directly.
            offset: -v.x / hScale,
            offsetY: size == 0 ? 0 : advance / size - v.y,
            outline: font.outlineFor(code),
            text: text,
          ));
        } else {
          glyphs.add(PdfGlyphPlacement(
            offset: emScale == 0 ? 0 : advance / emScale,
            outline: font.outlineFor(code),
            text: text,
          ));
        }
      }
      if (font.isType3 &&
          _state.renderMode != 3 &&
          _state.renderMode != 7 &&
          size != 0) {
        _drawType3Glyph(font, code, advance);
      }
      final advanceBefore = advance;
      if (vertical) {
        // Tc applies along the writing direction; Tw only to single-byte 0x20.
        advance += font.verticalAdvanceOf(code) * size + _state.charSpacing;
      } else {
        var tx = font.widthOf(code) * size + _state.charSpacing;
        if (!font.isCid && code == 0x20) tx += _state.wordSpacing;
        advance += tx * _state.horizontalScale;
      }
      if (charOffsets != null && text.isNotEmpty) {
        // Consumers binary-search these, so keep them non-decreasing: a
        // pathological negative Tc can tighten past a glyph's own width and
        // walk the pen backwards. `lastOffset` tracks the tail in a local -
        // this runs once per glyph, so avoid re-reading charOffsets.last.
        final start = math.max(advanceBefore / emScale, lastOffset);
        if (text.length == 1) {
          charOffsets.add(start);
          lastOffset = start;
        } else {
          // One code can map to several characters through /ToUnicode (a
          // ligature). The PDF positions the code, not its pieces, so split
          // the advance evenly across them.
          final end = math.max(advance / emScale, start);
          final step = (end - start) / text.length;
          for (var i = 0; i < text.length; i++) {
            charOffsets.add(start + step * i);
          }
          lastOffset = start + step * (text.length - 1);
        }
      }
      if (visible) visibleAdvance = advance;
    }
    // Closing boundary, so charOffsets always has text.length + 1 entries.
    charOffsets?.add(math.max(advance / emScale, lastOffset));

    if (size != 0 && _contentVisible && !_scanImages) {
      // text rendering matrix: em space → page space (§9.4.4).
      // Mode 3 (invisible) still emits the run - flagged, so painting
      // devices skip it - because it IS the text of OCR'd scans, and
      // selection/search/extraction must see it.
      final transform = PdfMatrix(
        size * _state.horizontalScale, 0, //
        0, size, //
        0, _state.rise,
      ).concat(_textMatrix).concat(_state.ctm);
      final text = buffer.toString();

      // Text rendering modes (§9.4.3): 0 fill, 1 stroke, 2 fill+stroke,
      // 3 invisible, 4–6 = 0–2 plus clip, 7 clip only. Modes ≥4 add the
      // glyph outlines to the clipping path (applied at ET).
      final mode = _state.renderMode;
      if (mode >= 4 && glyphs != null) {
        _textClipPending = true;
        for (final g in glyphs) {
          final outline = g.outline;
          if (outline == null) continue;
          _appendTransformedPath(
            _textClipSegments,
            outline,
            PdfMatrix.translation(g.offset, g.offsetY).concat(transform),
          );
        }
      }

      assert(
          charOffsets == null || charOffsets.length == text.length + 1,
          'charOffsets must have one entry per character plus the closing '
          'boundary (${charOffsets.length} vs ${text.length + 1})');
      if (text.trim().isNotEmpty || glyphs != null) {
        final fillText = mode == 0 || mode == 2 || mode == 4 || mode == 6;
        final strokeText = mode == 1 || mode == 2 || mode == 5 || mode == 6;
        final pattern = fillText ? _state.fillPattern : null;
        final glyphPath =
            glyphs == null ? null : _glyphOutlinePath(glyphs, transform);
        // A tiling pattern can't be flattened to a gradient (shading patterns
        // can - see _gradientOfPattern). Paint it through the glyph outlines as
        // a clip, then emit the run invisibly so it stays selectable without
        // the solid fill colour showing through. Needs embedded outlines; a
        // substituted font falls back to the solid fill colour.
        var paintedAsTiling = false;
        if (fillText && glyphPath != null && _isTilingPattern(pattern)) {
          _fillWithPattern(glyphPath, PdfFillRule.nonzero, pattern!);
          paintedAsTiling = true;
        }
        // Embedded outlines keep the historical fill-only rendering: the
        // device has the real glyph shapes and stroke modes on embedded fonts
        // are a separate concern (and would shift many pinned baselines).
        // Substituted text - which the device draws by filling a system font -
        // honours stroke modes, so outlined display text actually outlines.
        final embedded = glyphs != null;
        // On a substituted font we have no outlines to clip a tiling pattern
        // through, so the device can't tile the cell over the glyphs. Fall back
        // to a representative solid colour for the pattern (what conforming
        // viewers approximate when the cell is dense) instead of dropping the
        // fill - otherwise the glyphs read black, or vanish entirely when the
        // mode also strokes. Only drop the fill if we can't derive a colour.
        var doFill = fillText && !paintedAsTiling;
        var textFill = _state.fillColor;
        if (!embedded && doFill && _isTilingPattern(pattern)) {
          final tilingColor = _tilingPatternColor(pattern as CosStream);
          if (tilingColor != null) {
            textFill = tilingColor;
          } else if (strokeText) {
            doFill = false;
          }
        }
        final k = _state.ctm.scaleFactor;
        // Embedded fonts expose their real outlines, so resolve and record
        // them in the colorant buffer just like any other vector path. This
        // is essential for print overprint tests: marking the whole em box as
        // unknown makes the RGB fallback preserve or reveal the fail marker
        // according to screen colour instead of the PDF colorants. A
        // substituted font has no PDF outline here and keeps the conservative
        // em-box fallback.
        var deliveredFill = _state.fillOverprint;
        var deliveredStroke = _state.strokeOverprint;
        var runFill = embedded && (mode == 1 || mode == 5)
            ? _state.strokeColor
            : textFill;
        if (mode != 3 && mode != 7 && !paintedAsTiling) {
          final overprint = _overprint;
          if (overprint != null && glyphPath != null && pattern == null) {
            // Embedded stroke-only text is historically rendered by filling
            // the glyph outline with the stroking colour. Resolve the same
            // geometry using the stroking overprint tuple, then deliver that
            // tuple as a fill because that is the primitive the device sees.
            final strokeOnly = mode == 1 || mode == 5;
            final ink = strokeOnly ? _state.strokeInk : _state.fillInk;
            final blendInk =
                strokeOnly ? _state.strokeBlendInk : _state.fillBlendInk;
            final isOverprint =
                strokeOnly ? _state.strokeOverprint : _state.fillOverprint;
            final alpha = strokeOnly ? _state.strokeAlpha : _state.fillAlpha;
            final resolved = overprint.fill(
              glyphPath,
              PdfFillRule.nonzero,
              runFill,
              ink,
              blendInk: blendInk,
              overprint: isOverprint,
              mode: _state.overprintMode,
              opaque: _opaquePaint(alpha),
            );
            if (resolved != null) runFill = resolved;
            deliveredFill = isOverprint && ink != null && resolved == null;
            deliveredStroke = false;
          } else {
            _markTextUnknown(transform, advance, emScale);
            // ICCBased/RGB text has no device-colorant reading and must never
            // inherit an overprint approximation merely because /op is true.
            if (_overprint != null) {
              if (_state.fillInk == null) deliveredFill = false;
              if (_state.strokeInk == null) deliveredStroke = false;
            }
          }
        }
        _deliverOverprint(deliveredFill, deliveredStroke, _state.overprintMode);
        device.drawText(PdfTextRun(
          text: text,
          transform: transform,
          color: runFill,
          fill: embedded ? true : doFill,
          strokeColor: !embedded && strokeText ? _state.strokeColor : null,
          strokeWidth: _state.stroke.width * k, // see strokePath: 0 stays 0
          // Embedded stroke-only text is historically approximated by
          // filling the real outline in the stroke colour; carry the matching
          // stroking alpha with that approximation too.
          fillAlpha: embedded && (mode == 1 || mode == 5)
              ? _state.strokeAlpha
              : _state.fillAlpha,
          strokeAlpha: _state.strokeAlpha,
          gradient: (embedded ? fillText : doFill)
              ? _gradientOfPattern(pattern)
              : null,
          width: emScale == 0 ? 0 : advance / emScale,
          visibleWidth: emScale == 0 || visibleAdvance == advance
              ? null
              : visibleAdvance / emScale,
          leadingSpace: emScale == 0 ? 0 : leadingAdv / emScale,
          // Tc/Tw are unscaled text-space units; the run transform already
          // carries size and Th, so normalise to em (divide by size) - Th
          // cancels. Tw never applies to composite fonts (§9.3.3).
          letterSpacing: size == 0 ? 0 : _state.charSpacing / size,
          wordSpacing: size == 0 || font.isCid ? 0 : _state.wordSpacing / size,
          fontName: font.baseFont,
          fontSize: size,
          glyphs: glyphs,
          charOffsets: charOffsets,
          invisible: mode == 3 || mode == 7 || paintedAsTiling,
          mcid: _currentMcid,
        ));
      }
    }
    // The pen advances along the writing direction: x for horizontal text,
    // y (downward, advance is negative) for vertical.
    _textMatrix = (vertical
            ? PdfMatrix.translation(0, advance)
            : PdfMatrix.translation(advance, 0))
        .concat(_textMatrix);
    _textBufferInUse = reentrant;
  }

  /// Records the area a text run covers as "colorants unknown".
  ///
  /// Glyphs are painted through cached device painters (and substituted fonts
  /// through system outlines), so the buffer does not model text as ink; what
  /// it needs is only that an overprint landing on glyphs declines rather than
  /// compositing against whatever was under them.
  ///
  /// The run's em box, not its glyph outlines: rasterizing outlines is by far
  /// the most expensive thing the buffer could be asked to do (a text-heavy
  /// page is thousands of contours, and it measured as most of the buffer's
  /// whole cost), while over-marking only makes a later overprint fall back to
  /// the device's approximation - which is where it was before any of this.
  void _markTextUnknown(PdfMatrix transform, double advance, double emScale) {
    final overprint = _overprint;
    if (overprint == null) return;
    // The run's advance wide, from a descender below the baseline to an
    // ascender above it, mapped through the run transform.
    final width = emScale == 0 ? 0.0 : advance / emScale;
    final box = PdfPath([
      PdfMoveTo(transform.transformX(0, -0.25), transform.transformY(0, -0.25)),
      PdfLineTo(transform.transformX(width, -0.25),
          transform.transformY(width, -0.25)),
      PdfLineTo(transform.transformX(width, 1), transform.transformY(width, 1)),
      PdfLineTo(transform.transformX(0, 1), transform.transformY(0, 1)),
      const PdfClosePath(),
    ]);
    overprint.markUnknownPath(box, PdfFillRule.nonzero);
  }

  /// The page-space quad an image covers: its unit square (image space, y-up)
  /// mapped through [transform].
  static PdfPath _imageQuad(PdfMatrix transform) => PdfPath([
        PdfMoveTo(transform.transformX(0, 0), transform.transformY(0, 0)),
        PdfLineTo(transform.transformX(1, 0), transform.transformY(1, 0)),
        PdfLineTo(transform.transformX(1, 1), transform.transformY(1, 1)),
        PdfLineTo(transform.transformX(0, 1), transform.transformY(0, 1)),
        const PdfClosePath(),
      ]);

  /// Records an image draw in the colorant buffer and resolves its overprint,
  /// returning what the device should actually draw (issue #604).
  ///
  /// An overprinting raster over a known backdrop is drawn as a **substitute**
  /// stream whose samples are already composited in ink space
  /// (`pdfImageOverprintStream`) - the same subtractive rule the vector path
  /// applies, one layer above any device, so the canvas, strip and worker paths
  /// agree by construction. Everywhere the buffer declines (no colorant
  /// reading, a backdrop that is unknown or not one vector, translucent paint,
  /// an open transparency group) the original stream is drawn exactly as
  /// before.
  ///
  /// A stencil (/ImageMask) carries no colour of its own - it paints the fill
  /// colour through its alpha - so it keeps its stream and gets a resolved
  /// [PdfImageDraw.stencilColor] instead (see [PdfOverprintCompositor.stencil]).
  PdfImageDraw _imageDrawFor(
      CosStream stream, CosDictionary? resources, bool isStencil) {
    final overprint = _overprint;
    final stencilColor = _state.fillColor;
    if (overprint == null) {
      return (
        stream: stream,
        stencilColor: stencilColor,
        overprint: _state.fillOverprint,
      );
    }
    final quad = _imageQuad(_state.ctm);
    if (isStencil) {
      final resolved = overprint.stencil(quad, stencilColor, _state.fillInk,
          overprint: _state.fillOverprint,
          mode: _state.overprintMode,
          opaque: _opaquePaint(_state.fillAlpha));
      return (
        stream: stream,
        stencilColor: resolved ?? stencilColor,
        overprint:
            _state.fillOverprint && _state.fillInk != null && resolved == null,
      );
    }
    final reading = pdfImageColorants(cos, stream, resources: resources);
    final imageWidth = _numOf(cos.resolve(stream.dictionary['Width'])).round();
    final imageHeight =
        _numOf(cos.resolve(stream.dictionary['Height'])).round();
    final resolved = overprint.image<CosStream>(
      quad,
      transform: _state.ctm,
      width: imageWidth,
      height: imageHeight,
      ink: reading?.backdropInk,
      color: reading?.uniformColor ?? PdfColor.black,
      hasColorants: reading != null,
      overprint: _state.fillOverprint,
      mode: _state.overprintMode,
      opaque: _opaquePaint(_state.fillAlpha),
      resolve: (backdrop, backdropColor) => pdfImageOverprintStream(
        cos,
        stream,
        resources: resources,
        backdrop: backdrop,
        backdropColor: backdropColor,
        mode: _state.overprintMode,
        spotEquivalents: overprint.spotEquivalents,
        colorContext: _colorContext,
      ),
      resolveSpatial: (backdrop) => pdfImageOverprintStream(
        cos,
        stream,
        resources: resources,
        spatialBackdrop: backdrop,
        mode: _state.overprintMode,
        spotEquivalents: overprint.spotEquivalents,
        colorContext: _colorContext,
      ),
    );
    return (
      stream: resolved ?? stream,
      stencilColor: stencilColor,
      overprint: _state.fillOverprint && reading != null && resolved == null,
    );
  }

  /// Executes a Type3 glyph procedure: a tiny content stream in glyph space,
  /// mapped through /FontMatrix and the text rendering matrix (§9.6.5).
  void _drawType3Glyph(PdfFontInfo font, int code, double penAdvance) {
    if (!_contentVisible || _currentFormDepth >= _maxFormDepth) return;
    final size = _state.fontSize;
    // The font owns "a Type3 glyph is a content stream" (the CharProc lookup
    // and its glyph-space /FontMatrix); the interpreter only supplies the
    // parse cache and the re-entry into its own run loop.
    font.renderGlyph(
      code,
      decode: (proc) {
        try {
          return _opsCache.putIfAbsent(proc,
              () => ContentStreamParser.parse(cos.decodeStreamData(proc)));
        } on Exception {
          return const [];
        }
      },
      execute: (ops, resources, glyphToText) {
        final ctm = glyphToText
            .concat(PdfMatrix(
                size * _state.horizontalScale, 0, 0, size, 0, _state.rise))
            .concat(PdfMatrix.translation(penAdvance, 0))
            .concat(_textMatrix)
            .concat(_state.ctm);

        // Record-once/stamp-per-occurrence (#535, the #524 sibling; PDFium's
        // CPDF_Type3Cache shape). Occurrences of the same glyph whose
        // composed CTMs share a linear part differ by a pure page-space
        // translation - one recorded cell serves them all, keyed by
        // everything else the recording bakes in (the paint state a d1 proc
        // inherits). Pattern fills and soft masks are page-anchored, not
        // translation-invariant, so those (rare) states bypass the cache.
        if (_state.softMask == null && _state.fillPattern == null) {
          final key = (
            font,
            code,
            ctm.a,
            ctm.b,
            ctm.c,
            ctm.d,
            _state.fillColor,
            _state.strokeColor,
            _state.fillAlpha,
            _state.strokeAlpha,
            _state.stroke.width,
          );
          var cell = _type3Cells[key];
          if (cell == null && _type3Cells.length < _maxType3Cells) {
            final recorder = RecordingPdfDevice();
            final outer = device;
            device = recorder;
            try {
              _executeType3Proc(ops, resources, ctm);
            } finally {
              device = outer;
            }
            cell = (recorder.commands, ctm.e, ctm.f);
            _type3Cells[key] = cell;
          }
          if (cell != null) {
            final dx = ctm.e - cell.$2, dy = ctm.f - cell.$3;
            final sink = device;
            if (sink is PdfTiledCellSink) {
              (sink as PdfTiledCellSink).drawTiledCell(PdfDrawTiledCellCommand(
                  cell.$1, Float64List(1)..[0] = dx, Float64List(1)..[0] = dy));
            } else if (dx == 0 && dy == 0) {
              replayCommands(cell.$1, device);
            } else {
              replayCommands(cell.$1, TranslatingPdfDevice(device, dx, dy));
            }
            return;
          }
        }
        _executeType3Proc(ops, resources, ctm);
      },
    );
  }

  /// Recorded Type3 glyph cells for this interpreter, keyed by glyph and the
  /// full non-translation state the recording depends on. Bounded so a
  /// pathological document (every glyph at a unique scale) degrades to the
  /// direct path instead of growing without limit.
  final Map<Object, (List<PdfRenderCommand>, double, double)> _type3Cells = {};
  static const _maxType3Cells = 1024;

  /// The direct Type3 CharProc execution behind [_drawType3Glyph]: fresh
  /// state at [ctm], the §9.6.5 text-object isolation, and its own path
  /// builder (a proc's unpainted trailing segments must not leak into the
  /// enclosing stream - same guard as [_runPatternCell]).
  void _executeType3Proc(
      List<ContentOperation> ops, CosDictionary resources, PdfMatrix ctm) {
    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    // A CharProc is its own content stream and usually opens its own
    // BT..ET (this font draws each glyph with a nested text object). Save
    // the outer text-object state so the inner BT/Tm/ET can't clobber the
    // caller's text matrix - otherwise every glyph after the first lands
    // at the wrong position (§9.6.5: the glyph description executes in
    // glyph space and must not disturb the text object that invoked it).
    final savedTextMatrix = _textMatrix;
    final savedLineMatrix = _lineMatrix;
    final savedClipPending = _textClipPending;
    final savedClipSegments = List.of(_textClipSegments);
    final savedSegments = _segments;
    _segments = PdfPathBuilder();
    // A `d1` inside this CharProc locks colour to the text colour; the lock
    // is per-glyph, so snapshot and clear it (a nested glyph mustn't inherit
    // an outer glyph's lock) and restore it afterwards. The glyph's effective
    // colour stays the inherited fill colour, which the cache key already
    // captures, so the record-once cache remains correct.
    final savedColorLocked = _type3ColorLocked;
    _type3ColorLocked = false;
    _overprint?.save();
    device.save();
    try {
      _state = _GraphicsState.from(savedState)
        ..ctm = ctm
        ..font = null
        ..softMask = savedState.softMask;
      _run(ops, resources, _currentFormDepth + 1);
    } finally {
      _type3ColorLocked = savedColorLocked;
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      // A blend mode a CharProc set (via its own gs) is not on the canvas save
      // stack, so device.restore() below won't undo it - re-sync it like the
      // other scope exits (#462/#503). When recording a cell the reset is
      // captured into the cell too, so a stamped glyph can't leak its blend.
      _restoreDeviceBlend(savedState);
      _state = savedState;
      _textMatrix = savedTextMatrix;
      _lineMatrix = savedLineMatrix;
      _textClipPending = savedClipPending;
      _textClipSegments
        ..clear()
        ..addAll(savedClipSegments);
      _segments = savedSegments;
      _overprint?.restore();
      device.restore();
    }
  }

  // ---------- patterns and shadings ----------

  /// Looks up a named resource and resolves it (dictionary or stream).
  CosObject? _resource(CosDictionary resources, String category, CosName name) {
    final group = cos.resolve(resources[category]);
    if (group is! CosDictionary) return null;
    final value = cos.resolve(group[name.value]);
    return value is CosNull ? null : value;
  }

  CosDictionary? _patternDict(CosObject? pattern) {
    if (pattern is CosStream) return pattern.dictionary;
    if (pattern is CosDictionary) return pattern;
    return null;
  }

  PdfMatrix _patternMatrix(CosDictionary dict) {
    final matrix = cos.resolve(dict['Matrix']);
    return matrix is CosArray && matrix.length >= 6
        ? _matrixFrom(matrix.items)
        : PdfMatrix.identity;
  }

  PdfColor? _patternAverageColor(CosObject? pattern) {
    final dict = _patternDict(pattern);
    if (dict == null) return null;
    final type = cos.resolve(dict['PatternType']);
    if (type is CosInteger && type.value == 1 && pattern is CosStream) {
      return _tilingPatternColor(pattern);
    }
    final shading = PdfShading.parse(cos, dict['Shading']);
    if (shading == null) return null;
    return shading.toGradient(PdfMatrix.identity)?.averageColor ??
        shading.toMesh(PdfMatrix.identity)?.averageColor ??
        shading.toFunctionMesh(PdfMatrix.identity)?.averageColor ??
        shading.toRadialConeMesh(PdfMatrix.identity)?.averageColor;
  }

  /// A representative solid colour for a tiling pattern, used where the cell
  /// can't be tiled through the fill shape (a substituted font's text has no
  /// outlines to clip against - §8.7.3.1). PaintType 2 (uncolored) carries the
  /// colour in the `scn` operands; for a colored pattern we take the last fill
  /// colour the cell content sets (the colour the tiles are painted in).
  PdfColor? _tilingPatternColor(CosStream pattern) {
    final dict = pattern.dictionary;
    final paintType = cos.resolve(dict['PaintType']);
    if (paintType is CosInteger && paintType.value == 2) {
      return _state.fillPatternComponents.isNotEmpty
          ? colorFromComponents(_state.fillPatternComponents)
          : null;
    }
    final List<ContentOperation> ops;
    try {
      ops = _opsCache.putIfAbsent(pattern,
          () => ContentStreamParser.parse(cos.decodeStreamData(pattern)));
    } on Exception {
      return null;
    }
    PdfColor? color;
    for (final op in ops) {
      final o = op.operands;
      switch (op.operator) {
        case 'g':
          color = PdfColor.gray(_num(o, 0));
        case 'rg':
          color = PdfColor(_num(o, 0), _num(o, 1), _num(o, 2));
        case 'k':
          color = PdfColor.cmyk(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3));
      }
    }
    return color;
  }

  PdfGradient? _gradientOfPattern(CosObject? pattern) {
    final dict = _patternDict(pattern);
    if (dict == null) return null;
    final type = cos.resolve(dict['PatternType']);
    if (type is! CosInteger || type.value != 2) return null;
    return PdfShading.parse(cos, dict['Shading'])?.toGradient(
      _patternMatrix(dict),
    );
  }

  bool _isTilingPattern(CosObject? pattern) {
    if (pattern is! CosStream) return false;
    final type = cos.resolve(pattern.dictionary['PatternType']);
    return type is CosInteger && type.value == 1;
  }

  /// The combined glyph outlines of a run as one page-space path, for filling
  /// text with a pattern. Null when no glyph carries an outline.
  PdfPath? _glyphOutlinePath(
      List<PdfGlyphPlacement> glyphs, PdfMatrix transform) {
    final segments = <PdfPathSegment>[];
    for (final g in glyphs) {
      final outline = g.outline;
      if (outline == null) continue;
      _appendTransformedPath(segments, outline,
          PdfMatrix.translation(g.offset, g.offsetY).concat(transform));
    }
    return segments.isEmpty ? null : PdfPath(segments);
  }

  void _fillWithPattern(PdfPath path, PdfFillRule rule, CosObject pattern) {
    final dict = _patternDict(pattern);
    if (dict == null) return;
    // A gradient or tiled cell puts colours on the page the colorant buffer
    // has no reading for, so the area becomes "unknown" and a later overprint
    // over it keeps the device's approximation. The cell content itself runs
    // isolated for the same reason.
    final overprint = _overprint;
    if (overprint != null) {
      overprint.markUnknownPath(path, rule);
      overprint.beginIsolated();
    }
    try {
      _fillWithPatternContent(path, rule, pattern, dict);
    } finally {
      overprint?.endIsolated();
    }
  }

  void _fillWithPatternContent(
      PdfPath path, PdfFillRule rule, CosObject pattern, CosDictionary dict) {
    final type = cos.resolve(dict['PatternType']);
    final patternType = type is CosInteger ? type.value : 0;

    if (patternType == 2) {
      // shading pattern: the matrix maps pattern space to page space
      final shading = PdfShading.parse(cos, dict['Shading']);
      final gradient = shading?.toGradient(_patternMatrix(dict));
      if (gradient != null) {
        device.fillPathGradient(path, rule, gradient, _state.fillAlpha);
        return;
      }
      final patternMatrix = _patternMatrix(dict);
      final mesh = shading?.toMesh(patternMatrix) ??
          shading?.toFunctionMesh(patternMatrix) ??
          shading?.toRadialConeMesh(patternMatrix, clip: _pathBounds(path));
      if (mesh != null) {
        device.save();
        device.clipPath(path, rule);
        device.fillMesh(mesh, _state.fillAlpha);
        device.restore();
      }
      // unsupported shading types: skip rather than paint a wrong solid
      return;
    }
    if (patternType == 1 && pattern is CosStream) {
      _fillWithTilingPattern(path, rule, pattern);
    }
  }

  /// Runs a tiling pattern's cell content once per tile across the fill
  /// area, clipped to the fill path (§8.7.3).
  void _fillWithTilingPattern(
      PdfPath path, PdfFillRule rule, CosStream pattern) {
    if (_activeTilingPatterns.contains(pattern)) {
      // A reference cycle: this pattern's cell content (via a form) fills with
      // the same pattern. Rather than recurse to the form-depth limit and
      // paint nothing, break the cycle by solid-filling the clipped area -
      // matching pdf.js, which detects the operator-list cycle and renders the
      // box. Uncolored (PaintType 2) patterns carry an explicit colour;
      // colored ones default to black like the initial fill colour.
      final fallback = _state.fillPatternComponents.isNotEmpty
          ? colorFromComponents(_state.fillPatternComponents)
          : PdfColor.black;
      device.fillPath(path, fallback, rule, _state.fillAlpha);
      return;
    }
    if (_currentFormDepth >= _maxFormDepth) return;
    final dict = pattern.dictionary;
    final matrix = _patternMatrix(dict);
    final inverse = matrix.inverted();
    if (inverse == null) return;

    final ops = _opsCache.putIfAbsent(pattern, () {
      try {
        return ContentStreamParser.parse(cos.decodeStreamData(pattern));
      } on Exception {
        return const [];
      }
    });
    if (ops.isEmpty) return;

    final bbox = _numbersOf(dict['BBox']);
    if (bbox.length < 4) return;
    var xStep = _numOf(cos.resolve(dict['XStep']));
    var yStep = _numOf(cos.resolve(dict['YStep']));
    if (xStep == 0) xStep = (bbox[2] - bbox[0]).abs();
    if (yStep == 0) yStep = (bbox[3] - bbox[1]).abs();
    if (xStep == 0 || yStep == 0) return;
    xStep = xStep.abs();
    yStep = yStep.abs();

    final paintTypeObj = cos.resolve(dict['PaintType']);
    final uncolored = paintTypeObj is CosInteger && paintTypeObj.value == 2;
    final resourcesObj = cos.resolve(dict['Resources']);
    final patternResources =
        resourcesObj is CosDictionary ? resourcesObj : CosDictionary();

    // fill-area bounds in pattern space decide which tiles to run
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final segment in path.segments) {
      for (final (x, y) in _segmentPoints(segment)) {
        minX = math.min(minX, inverse.transformX(x, y));
        minY = math.min(minY, inverse.transformY(x, y));
        maxX = math.max(maxX, inverse.transformX(x, y));
        maxY = math.max(maxY, inverse.transformY(x, y));
      }
    }
    if (minX > maxX) return;
    final i0 = ((minX - bbox[0]) / xStep).floor() - 1;
    final i1 = ((maxX - bbox[0]) / xStep).ceil();
    final j0 = ((minY - bbox[1]) / yStep).floor() - 1;
    final j1 = ((maxY - bbox[1]) / yStep).ceil();
    const maxTiles = 4096;
    if ((i1 - i0 + 1) * (j1 - j0 + 1) > maxTiles) return;

    device.save();
    device.clipPath(path, rule);
    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    final patternColor =
        uncolored ? colorFromComponents(_state.fillPatternComponents) : null;
    _activeTilingPatterns.add(pattern);
    try {
      // Record-once/replay-per-tile (#524, PDFium's CPDF_RenderTiling shape):
      // every tile runs the same cell ops from the same fresh graphics state -
      // the only per-tile difference is a pattern-space translation, which the
      // (affine) pattern matrix maps to a pure page-space translation. So for
      // multi-tile fills the cell is interpreted once at the base tile and
      // replayed translated for the rest, instead of re-executing the cell
      // content O(tiles) times. Small fills keep the direct loop - recording
      // has overhead and one or two tiles can't win it back.
      const minTilesToRecord = 4;
      final recordCell = (i1 - i0 + 1) * (j1 - j0 + 1) >= minTilesToRecord;
      List<PdfRenderCommand>? cell;
      if (recordCell) {
        final recorder = RecordingPdfDevice();
        final outer = device;
        device = recorder;
        try {
          _runPatternCell(
              ops, patternResources, bbox, matrix, i0, j0, xStep, yStep,
              patternColor: patternColor);
        } finally {
          device = outer;
        }
        cell = recorder.commands;
      }
      if (cell != null && device is PdfTiledCellSink) {
        // The device consumes the cell natively (a recorder keeps it nested -
        // O(cell + tiles) transcript instead of O(cell x tiles); a canvas can
        // stamp one sub-picture per origin). Origins are the page-space
        // images of the pattern-space steps - the linear part of the pattern
        // matrix only - base tile first at (0, 0).
        final tiles = (i1 - i0 + 1) * (j1 - j0 + 1);
        final originsX = Float64List(tiles);
        final originsY = Float64List(tiles);
        var t = 0;
        for (var j = j0; j <= j1; j++) {
          for (var i = i0; i <= i1; i++) {
            final du = (i - i0) * xStep, dv = (j - j0) * yStep;
            originsX[t] = matrix.a * du + matrix.c * dv;
            originsY[t] = matrix.b * du + matrix.d * dv;
            t++;
          }
        }
        (device as PdfTiledCellSink)
            .drawTiledCell(PdfDrawTiledCellCommand(cell, originsX, originsY));
      } else {
        for (var j = j0; j <= j1; j++) {
          for (var i = i0; i <= i1; i++) {
            if (cell != null) {
              if (i == i0 && j == j0) {
                replayCommands(cell, device);
              } else {
                // Page-space image of the pattern-space step from the base
                // tile - the linear part of the pattern matrix only.
                final du = (i - i0) * xStep, dv = (j - j0) * yStep;
                replayCommands(
                    cell,
                    TranslatingPdfDevice(device, matrix.a * du + matrix.c * dv,
                        matrix.b * du + matrix.d * dv));
              }
              continue;
            }
            _runPatternCell(
                ops, patternResources, bbox, matrix, i, j, xStep, yStep,
                patternColor: patternColor);
          }
        }
      }
    } finally {
      _activeTilingPatterns.remove(pattern);
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      _restoreDeviceBlend(savedState);
      _state = savedState;
      device.restore();
    }
  }

  /// Executes one tiling-pattern cell at tile (i, j): fresh graphics state at
  /// the tile's transform, §8.7.3.1 BBox clip, the cell content, and any
  /// pending soft-mask finalize - through whatever [device] currently is
  /// (the real target for direct tiles, a recorder for the #524 capture).
  void _runPatternCell(
      List<ContentOperation> ops,
      CosDictionary resources,
      List<double> bbox,
      PdfMatrix matrix,
      int i,
      int j,
      double xStep,
      double yStep,
      {PdfColor? patternColor}) {
    _state = _GraphicsState(_colorContext)
      ..ctm = PdfMatrix.translation(i * xStep, j * yStep).concat(matrix);
    if (patternColor != null) {
      _state.fillColor = patternColor;
      _state.strokeColor = patternColor;
    }
    // The cell runs with its own path builder: segments a cell leaves
    // unpainted must not prepend to the path the enclosing content stream
    // builds next (and the enclosing region's captured path must never grow
    // under a recorded cell - see _paintPath's early reset).
    final savedSegments = _segments;
    _segments = PdfPathBuilder();
    _overprint?.save();
    device.save();
    try {
      // §8.7.3.1: the cell content is clipped to the pattern BBox before
      // tiling - content drawn outside the cell (this pattern's red rect
      // overruns the BBox by 50 units) must not paint, leaving the white
      // border the baseline shows.
      _clipToBox(bbox);
      _run(ops, resources, _currentFormDepth + 1);
    } finally {
      final mask = _state.softMask;
      if (mask != null) _finalizeSoftMask(mask);
      _overprint?.restore();
      device.restore();
      _segments = savedSegments;
    }
  }

  void _applyShading(CosDictionary resources, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return;
    final shading =
        PdfShading.parse(cos, _resource(resources, 'Shading', o[0] as CosName));
    // sh geometry lives in the current user space (§8.7.4.2)
    final gradient = shading?.toGradient(_state.ctm);
    if (gradient == null) {
      // mesh and function-based shadings paint their own geometry; the
      // clip bounds them
      final mesh = shading?.toMesh(_state.ctm) ??
          shading?.toFunctionMesh(_state.ctm) ??
          shading?.toRadialConeMesh(_state.ctm,
              clip: _pageBox ?? const PdfRect(-1e5, -1e5, 1e5, 1e5));
      if (mesh != null) {
        _markShadingUnknown();
        device.fillMesh(mesh, _state.fillAlpha);
      }
      return;
    }
    // paint across the page; the active canvas clip bounds it
    final box = _pageBox ?? const PdfRect(-1e5, -1e5, 1e5, 1e5);
    final area = PdfPath([
      PdfMoveTo(box.left, box.bottom),
      PdfLineTo(box.right, box.bottom),
      PdfLineTo(box.right, box.top),
      PdfLineTo(box.left, box.top),
      const PdfClosePath(),
    ]);
    final recorded = _overprint?.gradient(
          area,
          gradient,
          overprint: _state.fillOverprint,
          mode: _state.overprintMode,
          opaque: _opaquePaint(_state.fillAlpha),
        ) ??
        false;
    if (!recorded) _markShadingUnknown();
    // When colorants were recorded, paint the smooth source gradient as the
    // knockout base. Any overprint-preserved backdrop colorants are replayed
    // immediately afterward as exact precomposited regions. Leaving /op on
    // here would darken the whole gradient in RGB and reveal GWG080's Xs.
    if (recorded) {
      _deliverOverprint(false, _state.strokeOverprint, _state.overprintMode);
    }
    final substitute = _overprint?.takeGradientSubstitute();
    device.fillPathGradient(
        area, PdfFillRule.nonzero, substitute ?? gradient, _state.fillAlpha);
    final spatial = _overprint?.takeGradientSpatialPaint();
    if (spatial != null) {
      for (final region in spatial) {
        device.fillPath(
            region.path, region.color, PdfFillRule.nonzero, _state.fillAlpha);
      }
    }
  }

  /// A bare `sh` paints across the whole clip in colours with no colorant
  /// reading; the buffer records that as unknown over the page box (the clip
  /// it tracks narrows it back down).
  void _markShadingUnknown() {
    final box = _pageBox;
    if (box == null) return;
    _overprint?.markUnknownBox(box.left, box.bottom, box.right, box.top);
  }

  List<double> _numbersOf(CosObject? object) {
    final v = cos.resolve(object);
    if (v is! CosArray) return const [];
    return [for (final item in v.items) _numOf(cos.resolve(item))];
  }

  /// Axis-aligned bounds of a path's control points, in user space - a
  /// conservative superset of the fill area, enough to size a shading mesh.
  static PdfRect? _pathBounds(PdfPath path) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final segment in path.segments) {
      for (final (x, y) in _segmentPoints(segment)) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    if (minX > maxX) return null;
    return PdfRect(minX, minY, maxX, maxY);
  }

  static Iterable<(double, double)> _segmentPoints(
      PdfPathSegment segment) sync* {
    switch (segment) {
      case PdfMoveTo(:final x, :final y) || PdfLineTo(:final x, :final y):
        yield (x, y);
      case PdfCubicTo():
        yield (segment.x1, segment.y1);
        yield (segment.x2, segment.y2);
        yield (segment.x3, segment.y3);
      case PdfClosePath():
        break;
    }
  }

  // ---------- XObjects ----------

  CosDictionary? _dictResource(
      CosDictionary resources, String category, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return null;
    final group = cos.resolve(resources[category]);
    if (group is! CosDictionary) return null;
    final value = cos.resolve(group[(o[0] as CosName).value]);
    return value is CosDictionary ? value : null;
  }

  void _doXObject(CosDictionary resources, List<CosObject> o, int formDepth) {
    if (o.isEmpty || o[0] is! CosName) return;
    final group = cos.resolve(resources['XObject']);
    if (group is! CosDictionary) return;
    final xobject = cos.resolve(group[(o[0] as CosName).value]);
    if (xobject is! CosStream) return;

    final subtype = xobject.dictionary['Subtype'];
    final name = subtype is CosName ? subtype.value : '';
    if (name == 'Image') {
      final isStencil = cos.resolve(xobject.dictionary['ImageMask']) ==
          const CosBoolean(true);
      final draw = _imageDrawFor(xobject, resources, isStencil);
      _deliverOverprint(
          draw.overprint, _state.strokeOverprint, _state.overprintMode);
      device.drawImage(PdfImageRequest(
        stream: draw.stream,
        transform: _state.ctm,
        alpha: _state.fillAlpha,
        isStencil: isStencil,
        stencilColor: draw.stencilColor,
        isLuminosityMask: _paintingLuminosityMask,
      ));
      return;
    }
    if (name != 'Form' || formDepth >= _maxFormDepth) return;

    // a transparency group composites as one object: the alpha AND blend mode
    // in effect at Do apply to the group's result, and reset inside (§11.6.6) -
    // otherwise an inner `gs` back to ca 1.0 / BM Normal would erase them
    final groupAlpha = _state.fillAlpha;
    final groupBlend = _state.blendMode;
    final groupDict = cos.resolve(xobject.dictionary['Group']);
    final isGroup = groupDict is CosDictionary;
    final isolated =
        isGroup && cos.resolve(groupDict['I']) == const CosBoolean(true);
    // A knockout group (/K true, §11.4.5) needs its own layer so each
    // element can composite against the group's initial backdrop, even when
    // the group itself paints at full alpha.
    final knockout =
        isGroup && cos.resolve(groupDict['K']) == const CosBoolean(true);
    // A non-Normal blend mode applies to the group's *composite* result, not
    // element-by-element - so the group must render into its own layer that
    // then blends onto the backdrop as one object. Without a layer the inner
    // content's own `gs` (typically /BM Normal) overwrites the blend mode and
    // the outer blend is lost: an opaque white flourish drawn under /Multiply
    // then paints as a solid white box instead of multiplying into the page.
    final blended = groupBlend != PdfBlendMode.normal;
    final groupLayer =
        isGroup && (groupAlpha < 1 || knockout || isolated || blended);

    final matrix = cos.resolve(xobject.dictionary['Matrix']);
    final formCtm = matrix is CosArray && matrix.length >= 6
        ? _matrixFrom(matrix.items).concat(_state.ctm)
        : _state.ctm;
    final bbox = cos.resolve(xobject.dictionary['BBox']);
    PdfPath? groupPath;
    PdfRect? groupBounds;
    if (bbox is CosArray && bbox.length >= 4) {
      final values = [for (var i = 0; i < 4; i++) _numOf(cos.resolve(bbox[i]))];
      groupPath = PdfPath([
        PdfMoveTo(formCtm.transformX(values[0], values[1]),
            formCtm.transformY(values[0], values[1])),
        PdfLineTo(formCtm.transformX(values[2], values[1]),
            formCtm.transformY(values[2], values[1])),
        PdfLineTo(formCtm.transformX(values[2], values[3]),
            formCtm.transformY(values[2], values[3])),
        PdfLineTo(formCtm.transformX(values[0], values[3]),
            formCtm.transformY(values[0], values[3])),
        const PdfClosePath(),
      ]);
      groupBounds = _pathBounds(groupPath);
    }
    final groupBackdrop = !isolated && groupPath != null
        ? _overprint?.uniformBackdrop(groupPath)
        : null;
    final outerMask = _state.softMask;
    final colorantPrecomposited = isGroup &&
        (_overprint?.beginTransparencyGroup(
              blendMode: groupBlend,
              isolated: isolated,
              knockout: knockout,
              opaque: groupAlpha >= 1 && outerMask == null,
            ) ??
            false);

    _stateStack.add(_GraphicsState.from(_state));
    _overprint?.save();
    device.save();
    final deviceGroupLayer = groupLayer && !colorantPrecomposited;
    if (deviceGroupLayer) {
      // device.beginGroup snapshots the current blend mode into the layer's
      // compositing paint, so the blend must already be set (the `gs` that
      // selected it ran before this Do).
      if (device case PdfTransparencyGroupDevice advanced) {
        advanced.beginTransparencyGroup(
          groupAlpha,
          knockout: knockout,
          isolated: isolated,
          bounds: groupBounds,
          backdropColor: groupBackdrop,
        );
      } else {
        device.beginGroup(groupAlpha, knockout: knockout);
      }
    }
    if (groupLayer) {
      _state.fillAlpha = 1;
      _state.strokeAlpha = 1;
      if (blended) {
        _state.blendMode = PdfBlendMode.normal;
        device.setBlendMode(PdfBlendMode.normal);
      }
    }
    try {
      if (matrix is CosArray && matrix.length >= 6) {
        _state.ctm = _matrixFrom(matrix.items).concat(_state.ctm);
      }
      if (bbox is CosArray && bbox.length >= 4) {
        _clipToBox([for (var i = 0; i < 4; i++) _numOf(cos.resolve(bbox[i]))]);
      }
      final innerResources = cos.resolve(xobject.dictionary['Resources']);
      final ops = _parsedOps(xobject);
      if (ops == null) return;
      _run(
        ops,
        innerResources is CosDictionary ? innerResources : resources,
        formDepth + 1,
      );
    } finally {
      // masks opened inside the form must close before its device.restore
      final mask = _state.softMask;
      if (mask != null && !identical(mask, outerMask)) {
        _finalizeSoftMask(mask);
      }
      if (deviceGroupLayer) {
        device.endGroup();
      }
      if (isGroup) _overprint?.endTransparencyGroup();
      final restored = _stateStack.removeLast();
      _restoreDeviceBlend(restored);
      _state = restored;
      _overprint?.restore();
      device.restore();
    }
  }

  /// Re-issues the blend mode when leaving a form / appearance / transparency
  /// group / tiling-pattern scope, mirroring the `q`/`Q` handler.
  ///
  /// `device.restore()` pops the canvas graphics stack, but a device's blend
  /// mode is not part of that stack (e.g. `CanvasPdfDevice` holds it in a plain
  /// field), so a non-Normal blend set inside the scope leaks out and applies
  /// to whatever is painted next - an opaque object after a Multiply one would
  /// render multiplied against the backdrop. Restoring [restored]'s blend on
  /// the way out prevents the leak (issue #462).
  void _restoreDeviceBlend(_GraphicsState restored) {
    if (_state.blendMode != restored.blendMode) {
      device.setBlendMode(restored.blendMode);
    }
  }

  void _clipToBox(List<double> box) {
    final m = _state.ctm;
    final corners = [
      (box[0], box[1]),
      (box[2], box[1]),
      (box[2], box[3]),
      (box[0], box[3]),
    ];
    final segments = <PdfPathSegment>[
      for (var i = 0; i < corners.length; i++)
        i == 0
            ? PdfMoveTo(m.transformX(corners[i].$1, corners[i].$2),
                m.transformY(corners[i].$1, corners[i].$2))
            : PdfLineTo(m.transformX(corners[i].$1, corners[i].$2),
                m.transformY(corners[i].$1, corners[i].$2)),
      const PdfClosePath(),
    ];
    device.clipPath(PdfPath(segments), PdfFillRule.nonzero);
  }

  /// Appends [path]'s segments, mapped through [m], onto [out] - used to bake
  /// glyph outlines (em space) into the page-space text clipping path.
  static void _appendTransformedPath(
      List<PdfPathSegment> out, PdfPath path, PdfMatrix m) {
    for (final s in path.segments) {
      out.add(switch (s) {
        PdfMoveTo(:final x, :final y) =>
          PdfMoveTo(m.transformX(x, y), m.transformY(x, y)),
        PdfLineTo(:final x, :final y) =>
          PdfLineTo(m.transformX(x, y), m.transformY(x, y)),
        PdfCubicTo(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x3,
          :final y3
        ) =>
          PdfCubicTo(
              m.transformX(x1, y1),
              m.transformY(x1, y1),
              m.transformX(x2, y2),
              m.transformY(x2, y2),
              m.transformX(x3, y3),
              m.transformY(x3, y3)),
        PdfClosePath() => const PdfClosePath(),
      });
    }
  }

  void _drawInlineImage(CosDictionary resources, List<CosObject> o) {
    if (o.length < 2 || o[0] is! CosDictionary || o[1] is! CosString) return;
    final abbreviated = o[0] as CosDictionary;
    // inline image dictionaries use abbreviated keys (§8.9.7, table 91)
    const expansions = {
      'W': 'Width',
      'H': 'Height',
      'BPC': 'BitsPerComponent',
      'CS': 'ColorSpace',
      'F': 'Filter',
      'D': 'Decode',
      'DP': 'DecodeParms',
      'IM': 'ImageMask',
      'I': 'Interpolate',
    };
    final dict = CosDictionary();
    abbreviated.entries.forEach((key, value) {
      dict[expansions[key] ?? key] = value;
    });
    final isStencil = dict['ImageMask'] == const CosBoolean(true);
    // An inline image's stream is synthesized fresh on every pass, so consumers
    // key it by value - which a substitute (also fresh each pass) satisfies
    // exactly as the original does.
    final draw = _imageDrawFor(
        CosStream(dict, (o[1] as CosString).bytes), resources, isStencil);
    _deliverOverprint(
        draw.overprint, _state.strokeOverprint, _state.overprintMode);
    device.drawImage(PdfImageRequest(
      stream: draw.stream,
      transform: _state.ctm,
      alpha: _state.fillAlpha,
      isStencil: isStencil,
      stencilColor: draw.stencilColor,
      isInline: true,
      isLuminosityMask: _paintingLuminosityMask,
    ));
  }

  // ---------- helpers ----------

  static double _numOf(CosObject? value) {
    if (value is CosInteger) return value.value.toDouble();
    if (value is CosReal) return value.value;
    return 0;
  }

  // Colorants are only derived while a colorant buffer is open (see
  // [_beginOverprint]); on every other page the colour operators must stay
  // allocation-free, so each assignment below is guarded on [_overprint].
  static PdfInkColorants _grayInk(double level) =>
      PdfInkColorants.deviceGray(level.clamp(0.0, 1.0).toDouble());

  static PdfInkColorants _cmykInk(double c, double m, double y, double k) =>
      PdfInkColorants.deviceCmyk(
          c.clamp(0.0, 1.0).toDouble(),
          m.clamp(0.0, 1.0).toDouble(),
          y.clamp(0.0, 1.0).toDouble(),
          k.clamp(0.0, 1.0).toDouble());

  /// Colorant reading of bare `sc`/`scn` operands through [space], or null
  /// when the space has none.
  ///
  /// Stays in lockstep with [_resolveScn], including its leniency: content
  /// that issues `0.9 0.1 0.9 0 sc` without a matching `cs` (GWG011 does) is
  /// read as DeviceCMYK by operand count for the colour, so the colorants must
  /// come from the same reading - otherwise the paint looks colorant-less and
  /// an overprint over it falls back to the approximation.
  static PdfInkColorants? _resolveInk(
      PdfColorSpace space, List<CosObject> operands, PdfInkColorants? current) {
    final values = [
      for (final item in operands)
        if (item is CosInteger || item is CosReal) _numOf(item),
    ];
    if (space.channels > 0 && values.length == space.channels) {
      return space.inkColorants(values);
    }
    return switch (values.length) {
      1 => PdfInkColorants.deviceGray(values[0].clamp(0.0, 1.0).toDouble()),
      3 => null, // an RGB reading has no colorant decomposition
      4 => PdfInkColorants.deviceCmyk(
          values[0].clamp(0.0, 1.0).toDouble(),
          values[1].clamp(0.0, 1.0).toDouble(),
          values[2].clamp(0.0, 1.0).toDouble(),
          values[3].clamp(0.0, 1.0).toDouble()),
      // _colorFromValues keeps the previous colour here, so keep its ink too.
      _ => current,
    };
  }

  /// Re-evaluates generic source colours after `ri` changes.
  ///
  /// Device colours have null operand snapshots because rendering intent does
  /// not alter native device components. CIE-based, Indexed and tint spaces
  /// retain their numeric source values and are converted with the intent in
  /// force when the eventual paint occurs (§10.3 and §11.7.5.3).
  void _refreshColorsForIntent() {
    final fill = _state.fillOperands;
    if (fill != null && _state.fillPattern == null) {
      _state.fillColor = _resolveScn(_state.fillSpace, fill, _state.fillColor);
      _state.fillInk = _overprint == null
          ? null
          : _resolveInk(_state.fillSpace, fill, _state.fillInk);
      _state.fillBlendInk = _overprint == null
          ? null
          : _resolveBlendInk(_state.fillSpace, fill, _state.fillBlendInk);
    }
    final stroke = _state.strokeOperands;
    if (stroke != null) {
      _state.strokeColor =
          _resolveScn(_state.strokeSpace, stroke, _state.strokeColor);
      _state.strokeInk = _overprint == null
          ? null
          : _resolveInk(_state.strokeSpace, stroke, _state.strokeInk);
      _state.strokeBlendInk = _overprint == null
          ? null
          : _resolveBlendInk(_state.strokeSpace, stroke, _state.strokeBlendInk);
    }
  }

  /// Transparency-blending-space counterpart of [_resolveInk]. ICCBased
  /// colours can have a destination-process reading here without becoming
  /// overprinting source inks.
  PdfInkColorants? _resolveBlendInk(
      PdfColorSpace space, List<CosObject> operands, PdfInkColorants? current) {
    final values = [
      for (final item in operands)
        if (item is CosInteger || item is CosReal) _numOf(item),
    ];
    if (space.channels > 0 && values.length == space.channels) {
      return space.blendColorants(values, intent: _state.renderingIntent);
    }
    return switch (values.length) {
      1 => PdfInkColorants.deviceGray(values[0].clamp(0.0, 1.0).toDouble()),
      3 => null,
      4 => PdfInkColorants.deviceCmyk(
          values[0].clamp(0.0, 1.0).toDouble(),
          values[1].clamp(0.0, 1.0).toDouble(),
          values[2].clamp(0.0, 1.0).toDouble(),
          values[3].clamp(0.0, 1.0).toDouble()),
      _ => current,
    };
  }

  /// Resolves bare `sc`/`scn` (or `SC`/`SCN`) numeric operands through
  /// [space]. When the operand count matches the space's channels the space
  /// converts them; a mismatch (or a Pattern space with no colorants) falls
  /// back to a device reading by count, keeping [current] for anything
  /// unsupported - matching the historical leniency on malformed content.
  PdfColor _resolveScn(
      PdfColorSpace space, List<CosObject> operands, PdfColor current) {
    final values = [
      for (final item in operands)
        if (item is CosInteger || item is CosReal) _numOf(item),
    ];
    if (space.channels > 0 && values.length == space.channels) {
      final color = space.toSrgbIntent(values, _state.renderingIntent);
      return _maskColorFromValues(values, color);
    }
    final color = _colorFromValues(
        values, current, _colorContext, _state.renderingIntent);
    return _maskColorFromValues(values, color);
  }

  PdfColor _maskColorFromValues(List<double> values, PdfColor color) {
    if (!_paintingLuminosityMask) return color;
    final normalized = values.every((value) => value >= 0 && value <= 1);
    final luminance = normalized
        ? switch (values.length) {
            1 => values[0],
            3 => 0.3 * values[0] + 0.59 * values[1] + 0.11 * values[2],
            4 => 1 -
                math.min(
                    1,
                    0.3 * values[0] +
                        0.59 * values[1] +
                        0.11 * values[2] +
                        values[3]),
            _ => 0.3 * color.red + 0.59 * color.green + 0.11 * color.blue,
          }
        : 0.3 * color.red + 0.59 * color.green + 0.11 * color.blue;
    return PdfColor.gray(luminance.clamp(0.0, 1.0).toDouble());
  }

  static double _num(List<CosObject> operands, int index) =>
      index < operands.length ? _numOf(operands[index]) : 0;

  static double _number(List<num> operands, int index) =>
      index < operands.length ? operands[index].toDouble() : 0;

  static PdfMatrix _matrixFrom(List<CosObject> o) => PdfMatrix(
      _num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3), _num(o, 4), _num(o, 5));
}

/// Whether [s] is empty or entirely whitespace - a non-allocating equivalent of
/// `s.trim().isEmpty` using Dart's own trim whitespace set (Unicode White_Space
/// plus U+FEFF), so it matches the `String.trim()` a device applies to the run.
bool _isBlankText(String s) {
  for (var i = 0; i < s.length; i++) {
    if (!_isTrimWhitespace(s.codeUnitAt(i))) return false;
  }
  return true;
}

bool _isTrimWhitespace(int c) =>
    c == 0x20 ||
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x85 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

/// A resumable walk of one page's content stream, from
/// [PdfInterpreter.beginPageContent].
///
/// [advance] records a bounded number of operations and can be called again to
/// continue from where it stopped - the cursor holds the parse position and the
/// interpreter holds the graphics state, so nothing is re-walked and nothing is
/// re-emitted. That is what lets a heavy page be recorded in visible increments,
/// and lets a cancelled record keep the work it already did instead of starting
/// over.
///
/// The caller must finish the walk exactly one of two ways: run it until
/// [advance] returns true, or call [abandon]. Either way the balancing
/// `device.restore()` runs once. A throwing [advance] (including
/// [PdfCancelledException]) finishes the walk itself, so a cancelled walk needs
/// no cleanup - but [abandon] is idempotent, so calling it anyway is safe.
class PdfPageContentWalk {
  PdfPageContentWalk._(
    this._interpreter,
    this._cursor,
    this._resources,
    this._previousFormDepth,
    this._previousVisibilityDepth,
  );

  final PdfInterpreter _interpreter;
  final ContentOperationCursor _cursor;
  final CosDictionary _resources;
  final int _previousFormDepth;
  final int _previousVisibilityDepth;

  bool _complete = false;
  bool _finished = false;

  /// True once the content stream has been walked to the end.
  bool get isComplete => _complete;

  /// True once the walk has released the device, by completion or [abandon].
  bool get isFinished => _finished;

  /// Records up to [operations] more operations (null runs to completion),
  /// returning true when the page is complete.
  ///
  /// Calling this after the walk has finished is a no-op that returns
  /// [isComplete].
  Future<bool> advance({
    int? operations,
    int yieldInterval = PdfInterpreter._yieldInterval,
  }) async {
    if (yieldInterval <= 0) {
      throw ArgumentError.value(yieldInterval, 'yieldInterval', 'must be > 0');
    }
    if (_finished) return _complete;
    try {
      _complete = await _interpreter._advanceCursorAsync(
        _cursor,
        _resources,
        0,
        yieldInterval,
        operations,
      );
    } catch (_) {
      // A cancelled or failed chunk still has to unwind the device stack; the
      // walk is not complete, so the soft mask is deliberately not finalized.
      _finish();
      rethrow;
    }
    if (_complete) _finish();
    return _complete;
  }

  /// Ends the walk without completing it - the cancelled-render path.
  /// Idempotent.
  void abandon() => _finish();

  void _finish() {
    if (_finished) return;
    _finished = true;
    _interpreter._endPageContent(
        _previousFormDepth, _previousVisibilityDepth, _complete);
  }
}

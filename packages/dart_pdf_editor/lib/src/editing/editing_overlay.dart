import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import '../debug_overlays.dart';
import '../l10n/pdf_l10n.dart';
import '../page_geometry.dart';
import '../renderer.dart';
import '../theme.dart';
import 'editing_color_pick.dart';
import 'editing_controller.dart';
import 'editing_fonts.dart';
import 'editing_interaction.dart';
import 'editing_measure.dart';
import 'editing_tool_behavior.dart';
import 'handle_layout.dart';
import 'stroke_prediction.dart';
import 'text_prompt.dart';

TextDirection _flutterTextDirection(String text) =>
    pdfTextLooksRtl(text) ? TextDirection.rtl : TextDirection.ltr;

TextAlign _flutterTextAlign(PdfTextAlign align) => switch (align) {
      PdfTextAlign.left => TextAlign.left,
      PdfTextAlign.center => TextAlign.center,
      PdfTextAlign.right => TextAlign.right,
    };

String? _textEditUiFamily(PdfTextFont font) {
  if (font is PdfStandardFont) {
    return switch (font.family) {
      PdfStandardFontFamily.sans => 'Helvetica',
      PdfStandardFontFamily.serif => 'Times New Roman',
      PdfStandardFontFamily.mono => 'Courier',
    };
  }
  // An embedded/bundled font has no platform family the way base-14 does;
  // the editor registers its outline bytes (see _ensureEmbeddedFontPreview)
  // under a synthetic family so the live preview matches what commits.
  // Null until that async registration lands, then it falls back gracefully.
  if (font is PdfEmbeddedFont) {
    return _embeddedPreviewFamilies[_embeddedFontKey(font)];
  }
  return null;
}

/// Synthetic Flutter font families an embedded font's bytes have been
/// registered under (via `ui.loadFontFromList`), keyed by
/// [_embeddedFontKey]. Module-level so [_textEditUiFamily] (a free
/// function the rich controller calls) and the overlay state share it.
final Map<String, String> _embeddedPreviewFamilies = {};

/// A stable key for an embedded font's outline data - its PostScript name
/// plus byte length, enough to dedupe registrations without holding the
/// bytes. The registered family is `'pdfedit-<key>'`.
String _embeddedFontKey(PdfEmbeddedFont font) =>
    '${font.postScriptName}:${font.fontBytes.length}';

FontWeight _textEditWeight(PdfTextFont font) =>
    font is PdfStandardFont && font.isBold
        ? FontWeight.bold
        : FontWeight.normal;

FontStyle _textEditSlant(PdfTextFont font) =>
    font is PdfStandardFont && font.isItalic
        ? FontStyle.italic
        : FontStyle.normal;

class _TextEditStyle {
  const _TextEditStyle(
      {required this.font,
      required this.size,
      required this.color,
      this.underline = false});

  final PdfTextFont font;
  final double size;
  final Color color;
  final bool underline;

  _TextEditStyle merge(
          {PdfTextFont? font, double? size, int? color, bool? underline}) =>
      _TextEditStyle(
        font: font ?? this.font,
        size: size ?? this.size,
        color: color == null ? this.color : Color(0xFF000000 | color),
        underline: underline ?? this.underline,
      );

  TextStyle toTextStyle(double scale, {double height = 1.2, double? letterSpacing}) =>
      TextStyle(
        color: color,
        fontSize: size * scale,
        height: height,
        letterSpacing: letterSpacing,
        fontFamily: _textEditUiFamily(font),
        fontWeight: _textEditWeight(font),
        fontStyle: _textEditSlant(font),
        decoration: underline ? TextDecoration.underline : null,
        decorationColor: underline ? color : null,
      );

  PdfFreeTextRun toRun(String text) => PdfFreeTextRun(text,
      font: font,
      fontSize: size,
      color: color.toARGB32() & 0xFFFFFF,
      underline: underline);
}

class _TextEditStyleRange {
  const _TextEditStyleRange(this.start, this.end, this.style);

  final int start;
  final int end;
  final _TextEditStyle style;
}

class _RichTextEditingController extends TextEditingController {
  _RichTextEditingController();

  _TextEditStyle defaultStyle = const _TextEditStyle(
      font: PdfStandardFont.helvetica, size: 14, color: Color(0xFF000000));
  double scale = 1;

  /// The box-level line-height multiplier and character spacing (already in
  /// view pixels) the styled span previews, so the live text matches the
  /// committed appearance's leading and Tc.
  double previewLineHeight = 1.2;
  double previewLetterSpacing = 0;
  final List<_TextEditStyleRange> _ranges = [];

  /// The text the style ranges are indexed against. Every edit (typing,
  /// backspace, paste) shifts the ranges so a run keeps following its own
  /// characters instead of the absolute offsets sliding under it.
  String _rangeText = '';

  /// Suppresses range remapping while [seedRuns] assigns text and ranges
  /// together (the ranges are already correct for the new text).
  bool _remapRanges = true;

  @override
  set value(TextEditingValue newValue) {
    if (_remapRanges && _ranges.isNotEmpty && newValue.text != _rangeText) {
      _shiftRanges(_rangeText, newValue.text);
    }
    _rangeText = newValue.text;
    super.value = newValue;
  }

  /// Re-maps every style range across the edit that turned [before] into
  /// [after], so a run stays glued to its characters. The changed span is
  /// the region between the common prefix and common suffix; text before it
  /// is untouched, text after it shifts by the length delta, and text
  /// inserted inside a run extends that run.
  void _shiftRanges(String before, String after) {
    var prefix = 0;
    final minLen = math.min(before.length, after.length);
    while (prefix < minLen && before[prefix] == after[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLen - prefix &&
        before[before.length - 1 - suffix] ==
            after[after.length - 1 - suffix]) {
      suffix++;
    }
    final changeStart = prefix;
    final oldChangeEnd = before.length - suffix;
    final delta = after.length - before.length;
    int mapOffset(int o) {
      if (o <= changeStart) return o;
      if (o >= oldChangeEnd) return o + delta;
      return changeStart; // inside a replaced span - collapse to its start
    }

    final next = <_TextEditStyleRange>[];
    for (final range in _ranges) {
      final start = mapOffset(range.start);
      final end = mapOffset(range.end);
      if (start < end) {
        next.add(_TextEditStyleRange(start, end, range.style));
      }
    }
    _ranges
      ..clear()
      ..addAll(_mergeRanges(next));
  }

  void resetStyles(_TextEditStyle style) {
    defaultStyle = style;
    _ranges.clear();
  }

  /// Seeds the editor from a box's persisted per-run styling (its /RC):
  /// sets [text] and a style range per run so reopening a mixed-format
  /// box shows its bold/italic/colour, not a flattened single style.
  /// [fallback] is the typing default (the box's flat /DA) for text added
  /// afterwards. Runs with non-base-14 fonts keep their [PdfTextFont].
  void seedRuns(List<PdfFreeTextRun> runs, _TextEditStyle fallback) {
    defaultStyle = fallback;
    final buffer = StringBuffer();
    final ranges = <_TextEditStyleRange>[];
    var offset = 0;
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      final start = offset;
      buffer.write(run.text);
      offset += run.text.length;
      ranges.add(_TextEditStyleRange(
          start,
          offset,
          _TextEditStyle(
              font: run.font,
              size: run.fontSize,
              color: Color(0xFF000000 | (run.color & 0xFFFFFF)),
              underline: run.underline)));
    }
    _ranges
      ..clear()
      ..addAll(_mergeRanges(ranges));
    // assigning text notifies listeners and rebuilds the styled span; the
    // ranges are already correct for the new text, so skip the edit remap
    _remapRanges = false;
    text = buffer.toString();
    _remapRanges = true;
  }

  bool get hasRichStyles => _ranges.isNotEmpty;

  /// The largest font size across the default style and every run - the
  /// strut size the inline editor pins line height to, so line spacing
  /// stays font-independent (matching the committed appearance's leading)
  /// instead of jumping when a run's font changes.
  double get maxStyleSize {
    var largest = defaultStyle.size;
    for (final range in _ranges) {
      if (range.style.size > largest) largest = range.style.size;
    }
    return largest;
  }

  void applyStyle(TextSelection selection,
      {PdfTextFont? font, double? size, int? color, bool? underline}) {
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.max(0, math.min(selection.start, selection.end));
    final end = math.min(text.length, math.max(selection.start, selection.end));
    if (start >= end) return;
    final next = <_TextEditStyleRange>[];
    for (final range in _ranges) {
      if (range.end <= start || range.start >= end) {
        next.add(range);
        continue;
      }
      if (range.start < start) {
        next.add(_TextEditStyleRange(range.start, start, range.style));
      }
      if (range.end > end) {
        next.add(_TextEditStyleRange(end, range.end, range.style));
      }
    }
    // split the selection into runs of already-uniform style so underlining
    // (or any per-char toggle) keeps each character's own font/size/colour
    var cursor = start;
    while (cursor < end) {
      final runStyle = _styleAt(cursor);
      var runEnd = cursor + 1;
      while (runEnd < end && _sameStyle(_styleAt(runEnd), runStyle)) {
        runEnd++;
      }
      next.add(_TextEditStyleRange(cursor, runEnd,
          runStyle.merge(font: font, size: size, color: color, underline: underline)));
      cursor = runEnd;
    }
    _ranges
      ..clear()
      ..addAll(_mergeRanges(next));
    notifyListeners();
  }

  static bool _sameStyle(_TextEditStyle a, _TextEditStyle b) =>
      identical(a.font, b.font) &&
      a.size == b.size &&
      a.color == b.color &&
      a.underline == b.underline;

  List<PdfFreeTextRun> toPdfRuns() {
    final value = text;
    if (value.isEmpty) return const [];
    final ranges = _mergeRanges([
      for (final range in _ranges)
        if (range.start < value.length && range.end > 0)
          _TextEditStyleRange(range.start.clamp(0, value.length),
              range.end.clamp(0, value.length), range.style)
    ]);
    final result = <PdfFreeTextRun>[];
    var offset = 0;
    for (final range in ranges) {
      if (offset < range.start) {
        result.add(defaultStyle.toRun(value.substring(offset, range.start)));
      }
      result.add(range.style.toRun(value.substring(range.start, range.end)));
      offset = range.end;
    }
    if (offset < value.length) {
      result.add(defaultStyle.toRun(value.substring(offset)));
    }
    return result;
  }

  _TextEditStyle _styleAt(int offset) {
    for (final range in _ranges.reversed) {
      if (offset >= range.start && offset < range.end) return range.style;
    }
    return defaultStyle;
  }

  static List<_TextEditStyleRange> _mergeRanges(
      List<_TextEditStyleRange> ranges) {
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final out = <_TextEditStyleRange>[];
    for (final range in ranges) {
      if (range.start >= range.end) continue;
      if (out.isNotEmpty &&
          out.last.end == range.start &&
          identical(out.last.style.font, range.style.font) &&
          out.last.style.size == range.style.size &&
          out.last.style.color == range.style.color &&
          out.last.style.underline == range.style.underline) {
        final last = out.removeLast();
        out.add(_TextEditStyleRange(last.start, range.end, last.style));
      } else {
        out.add(range);
      }
    }
    return out;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final value = text;
    if (value.isEmpty || _ranges.isEmpty) {
      return TextSpan(text: value, style: style);
    }
    final children = <InlineSpan>[];
    var offset = 0;
    for (final range in _mergeRanges(List.of(_ranges))) {
      if (range.start >= value.length) continue;
      final start = range.start.clamp(0, value.length);
      final end = range.end.clamp(0, value.length);
      if (offset < start) {
        children.add(TextSpan(text: value.substring(offset, start)));
      }
      children.add(TextSpan(
          text: value.substring(start, end),
          style: range.style.toTextStyle(scale,
              height: previewLineHeight,
              letterSpacing: previewLetterSpacing)));
      offset = end;
    }
    if (offset < value.length) {
      children.add(TextSpan(text: value.substring(offset)));
    }
    return TextSpan(style: style, children: children);
  }
}

class _ScaledTextSelectionControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  _ScaledTextSelectionControls(this.scale, this.color);

  final double scale;
  final Color color;

  double get _s => scale.isFinite && scale > 0 ? scale : 1.0;

  @override
  Widget buildHandle(
      BuildContext context, TextSelectionHandleType type, double textLineHeight,
      [VoidCallback? onTap]) {
    // The collapsed handle is the touch caret's draggable dot. In an
    // expanded text box it floats well below the caret (a stray dot near
    // the box's bottom edge), so suppress it - the blinking caret already
    // marks the insertion point. Range-selection handles stay.
    if (type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    return SizedBox.fromSize(
      size: getHandleSize(textLineHeight),
      child: CustomPaint(
        painter: _InlineTextHandlePainter(
          color: color,
          scale: _s,
          type: type,
        ),
      ),
    );
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final size = getHandleSize(textLineHeight);
    return switch (type) {
      TextSelectionHandleType.left => Offset(size.width / 2, size.height),
      TextSelectionHandleType.right ||
      TextSelectionHandleType.collapsed =>
        Offset(size.width / 2, 0),
    };
  }

  @override
  Size getHandleSize(double textLineHeight) => Size(36 * _s, 34 * _s);
}

class _InlineTextHandlePainter extends CustomPainter {
  _InlineTextHandlePainter({
    required this.color,
    required this.scale,
    required this.type,
  });

  final Color color;
  final double scale;
  final TextSelectionHandleType type;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    final cx = size.width / 2;
    final radius = 7 * s;
    final gap = 2 * s;
    if (type == TextSelectionHandleType.left) {
      canvas.drawLine(
          Offset(cx, 2 * radius + gap), Offset(cx, size.height), paint);
      canvas.drawCircle(Offset(cx, radius), radius, fill);
      return;
    }
    canvas.drawLine(
        Offset(cx, 0), Offset(cx, size.height - 2 * radius - gap), paint);
    canvas.drawCircle(Offset(cx, size.height - radius), radius, fill);
  }

  @override
  bool shouldRepaint(_InlineTextHandlePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.scale != scale ||
      oldDelegate.type != type;
}

Color _inlineTextHandleColor(BuildContext context) {
  final theme = PdfViewerTheme.of(context);
  return theme.selectionHandleColor ??
      theme.annotationChromeColor ??
      const Color(0xFF2196F3);
}

/// One page's editing layer: captures the armed tool's gestures in page
/// space, previews them, and commits them through the controller.
///
/// Instantiated by [PdfViewer] for every page while
/// [PdfEditingController.tool] is armed. It sits innermost in the page
/// overlay stack, so its recognizers win the arena over the viewer's
/// text-selection drag.
class EditingPageOverlay extends StatefulWidget {
  const EditingPageOverlay({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.geometry,
    required this.textPrompt,
    this.pageColor = const Color(0xFFFFFFFF),
    this.showAnnotations = true,
    this.interactionHost,
    this.interactionSession,
    this.onPanViewport,
    this.onPanViewportEnd,
    this.edgeAutoScroll,
    this.rasterCurrent = true,
    this.zoom = 1,
    this.predictStrokes = true,
    this.formImagePicker,
    this.imagePicker,
    this.onSnapshot,
    this.onPlaceSignature,
    this.onShowAnnotationMenu,
    this.onShowFormFieldMenu,
    this.onResolvePagePoint,
    this.onMoveDragPreview,
    this.onTextEditClosed,
    this.contextMenuEnabled = true,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final PdfPageGeometry geometry;
  final PdfTextPrompt textPrompt;

  /// How the form tool asks for a push-button field's image. With none,
  /// tapping a push button does nothing.
  final PdfFormImagePicker? formImagePicker;

  /// How the image tool ([PdfEditTool.image]) asks for the picture to
  /// insert. With none, the image tool does nothing.
  final PdfImagePicker? imagePicker;

  /// Receives a region captured by the snapshot tool
  /// ([PdfEditTool.snapshot]). With none, the snapshot tool does nothing.
  final PdfSnapshotHandler? onSnapshot;

  /// Receives the box drawn by the signature-box tool
  /// ([PdfEditTool.signatureBox]) so the host can sign into it. With none,
  /// the signature-box tool does nothing.
  final PdfSignaturePlacer? onPlaceSignature;

  /// The paper color the page is displayed with - the eyedropper's
  /// raster must match what's on screen.
  final Color pageColor;

  /// Whether the page is displayed with its annotations - same
  /// requirement as [pageColor]: the eyedropper samples what's visible.
  final bool showAnnotations;

  /// Viewer-owned services used by this page's interaction session.
  final PdfEditingInteractionHost? interactionHost;

  /// Optional stable state/effect surface. When omitted the overlay owns a
  /// private session; [PdfViewer.interactionSession] exposes one to hosts and
  /// tests without coupling them to the preview painter.
  final PdfEditingInteractionSession? interactionSession;

  /// Legacy callback parameters retained for source compatibility. New
  /// integrations should provide one [interactionHost].
  final void Function(Offset delta)? onPanViewport;
  final void Function(Velocity velocity)? onPanViewportEnd;
  final Offset Function(Offset globalPosition)? edgeAutoScroll;
  final void Function(Offset globalPosition, int pageIndex,
      {(double, double)? pagePoint})? onShowAnnotationMenu;
  final void Function(Offset globalPosition, String fieldName,
      {int? widgetIndex})? onShowFormFieldMenu;
  final (int, double, double)? Function(Offset globalPosition)?
      onResolvePagePoint;
  final PdfMoveDragPreviewCallback? onMoveDragPreview;
  final VoidCallback? onTextEditClosed;

  /// Whether the touch long-press annotation menu and the floating selection
  /// chip's "More" button are allowed to show. Mirrors [PdfViewer.contextMenuEnabled];
  /// see that property for the semantics. Has no effect without an editing
  /// controller (the menu path is reader-mode only). Defaults to true.
  final bool contextMenuEnabled;

  /// Whether the page raster on screen already shows the controller's
  /// current revision. While false (an edit just committed and the
  /// re-render is in flight), the overlay keeps painting the committed
  /// edit's preview - its afterimage - so the edit never blinks out.
  final bool rasterCurrent;

  /// Screen pixels per overlay pixel - the viewer's transform zoom. The
  /// overlay paints inside that transform, so selection chrome (outline,
  /// handles, the rotate knob) divides its sizes and hit radii by this
  /// to stay constant-size on screen at any zoom. Page-content previews
  /// (ink, shapes, the drag ghost) scale with the page on purpose.
  final double zoom;

  /// See [PdfViewer.predictStrokes]. When true the in-progress ink layer
  /// draws a forward-extrapolated lead so the painted line keeps up with
  /// the pen tip.
  final bool predictStrokes;

  @override
  State<EditingPageOverlay> createState() => _EditingPageOverlayState();
}

/// A set of strokes the preview painter draws beyond the pending ink:
/// committed-ink afterimages and the signature tool's live preview.
/// Strokes are page-space; [strokeWidth] is view pixels.
typedef _InkPaint = ({
  List<List<(double, double)>> strokes,
  List<List<double>?> pressures,
  Color color,
  double strokeWidth,
});

typedef _AfterGhost = ({
  ui.Picture picture,
  Rect from,
  Rect to,
  Rect? source,
  ui.Picture? sourceClean,
  Color? sourceWash,
  double rotation,
  double localAngle,
  bool flipX,
  bool flipY,
});

/// A just-placed text/check stamp painted while the full page raster catches
/// up. [rect] is view-space; this preview is intentionally lightweight but
/// follows the PDF appearance geometry closely enough to avoid a blank gap.
typedef _StampAfterimage = ({
  Rect rect,
  String? text,
  PdfStampTemplate? template,
  bool check,
  Color color,
  double opacity,
});

/// A Square/Circle drawn for a resize preview (or its committed
/// afterimage). The editor *regenerates* a shape's appearance at the new
/// rect with a constant stroke width rather than stretching the old one,
/// so a stretched ghost would thicken the line during the drag and snap
/// back on commit - this draws the shape the way the commit will, line
/// width and all. [strokeWidth] is view space; [rotation] view radians.
typedef _ShapeResize = ({
  Rect rect,
  bool ellipse,
  Color? stroke,
  double strokeWidth,
  Color? fill,
  List<double>? dashPattern,
  double rotation,
  double opacity,
});

/// Which sides of the selection a resize handle moves: -1 left/top edge,
/// +1 right/bottom edge, 0 leaves that axis alone. (View space, y down.)
// Resize-handle geometry lives in handle_layout.dart as a pure, unit-testable
// value type ([HandleLayout]); these aliases keep the overlay's existing names.
typedef _Handle = SelectionHandle;

const List<_Handle> _handles = selectionHandles;

const double _handleSize = 8;
const double _handleHitRadius = HandleLayout.defaultHitRadius;
const double _minSizeView = 12;

/// How far the rotation knob floats above the selection's top edge.
const double _rotateHandleDistance = HandleLayout.defaultRotateHandleDistance;

/// Rotation drags snap to 45° multiples when within this margin.
const double _rotateSnapRadians = 3 * math.pi / 180;

class _PointerInteractionSession {
  int? rawPointer;
  bool rawErasing = false;

  int? panPointer;
  Offset? panLast;
  VelocityTracker? panVelocity;

  final Set<int> touchPointers = {};
  bool gestureBailed = false;

  void clearRaw() {
    rawPointer = null;
    rawErasing = false;
  }

  void clearPan() {
    panPointer = null;
    panLast = null;
    panVelocity = null;
  }

  void clearTouches() {
    touchPointers.clear();
    gestureBailed = false;
  }
}

class _EditingPageOverlayState extends State<EditingPageOverlay>
    with TickerProviderStateMixin {
  // shape/text/stamp drag
  Offset? _dragStart;
  Offset? _dragCurrent;
  List<Offset>? _polyPoints;
  Offset? _polyHover;
  Offset? _polyDoubleTapPosition;
  // the form tool's double-tap fills the field under the down position
  TapDownDetails? _doubleTapDownDetails;

  // eyedropper: one page raster serves every preview sample
  PdfPageColorSampler? _sampler;
  PdfDocument? _samplerDocument;
  Color? _samplerPageColor;
  bool? _samplerAnnotations;
  Future<PdfPageColorSampler>? _samplerFuture;
  Offset? _pickPosition;
  Color? _pickPreview;

  // ink
  List<(double, double)>? _activeStroke;
  List<double>? _activeStrokePressures;

  /// Repaint signal for the in-progress stroke. Appending a point during a
  /// pencil/mouse stroke bumps this instead of calling setState, so the
  /// dedicated active-stroke layer (its own RepaintBoundary) re-rasterizes
  /// without rebuilding the overlay subtree or the heavy preview painter -
  /// the difference between a per-point widget rebuild and a per-point
  /// repaint, which is what the pen latency was paying for. Every mutation
  /// of [_activeStroke]/[_activeStrokePressures] must call [_bumpActiveStroke]
  /// (the painter's shouldRepaint stays false - this Listenable is the only
  /// thing that drives it, including the clear on commit/bail).
  final ValueNotifier<int> _activeStrokeRepaint = ValueNotifier<int>(0);

  void _bumpActiveStroke() => _activeStrokeRepaint.value++;

  /// The latest normalized pressure of the pointer being tracked, or null
  /// for devices that don't report pressure (finger, mouse).
  double? _pointerPressure;

  // raw-driven drawing: with ink or the eraser armed, stylus pointers
  // (and touch, when fingers draw) skip the gesture arena entirely - a
  // pan recognizer only wins after ~36px of motion, which swallowed the
  // start of every pencil stroke and dropped quick dots as taps. The
  // pointer id claims the gesture; moves append, up commits.
  final _PointerInteractionSession _pointers = _PointerInteractionSession();

  // raw-driven finger pan: with the ink/eraser tool armed and finger
  // drawing OFF (Apple Pencil mode), a finger must still scroll the
  // document. The list's physics are NeverScrollable while a tool is
  // armed and touch is excluded from the overlay's gesture arena, so a
  // single finger reaches neither - it would do nothing. This raw path
  // pans the viewer instead (the pen keeps drawing through [_pointers], so the
  // two never collide). A touch landing during an active pen stroke is a palm
  // and is ignored; a second finger bails to the viewer's pinch-zoom
  // recognizer.
  /// Raw-pointer, touch-bail, and finger-pan bookkeeping lives in
  /// [_pointers]; the overlay keeps the actual preview/commit state.

  /// The device kind of the latest pointer down on this page - the
  /// selection action chip only shows for touch and stylus input.
  PointerDeviceKind? _lastPointerKind;

  // circle eraser: the swipe's swept path (page space), the live-sliced
  // remainder per touched /Annots slot (painted over the faded
  // original, so the preview shows exactly what the commit keeps), the
  // original strokes of each touched sliceable annotation (washed over
  // so the baked-in ink fades without obscuring the page content around
  // it - the wash follows the strokes, not the bounding box), inkless
  // slots that can only be deleted whole (washed by their rect), and the
  // ring cursor's view position (drag for any pointer, hover for a mouse)
  final List<(double, double)> _erasePath = [];
  final Map<int, _InkPaint> _eraseSliced = {};
  final Map<int, _InkPaint> _eraseFade = {};
  final Map<int, Rect> _eraseRects = {};
  final Set<int> _eraseWholeSlots = {};
  Offset? _eraserCursor;
  bool _panErasing = false; // a mouse drag is erasing (arena path)

  /// The ink tool's pen-preview cursor: a dot the size of the pen width,
  /// in the pen colour, painted in place of the system cursor so the
  /// drawn colour and width are visible before a stroke is started.
  Offset? _penCursor;

  /// The count tool's check-mark cursor: the mark that will be placed by a
  /// click, centered on the mouse and clamped the same way the commit is.
  Offset? _countCursor;

  /// The stamp tool's hover preview position: the active custom stamp that a
  /// click will place, centered and clamped exactly like the tap commit.
  Offset? _stampPreview;

  /// The rotate knob's cursor position (hover over the knob, or live
  /// through a rotate drag): Flutter has no rotation cursor, so the
  /// system cursor is hidden here and a small curved-arrow glyph is
  /// painted to track the pointer instead.
  Offset? _rotateCursor;

  /// Erase results kept painted until the new revision's raster lands -
  /// without them the old strokes pop back at full strength for a frame.
  List<Rect>? _afterEraseRects;
  List<_InkPaint>? _afterEraseFade;
  List<_InkPaint>? _afterEraseInk;

  // in-place text editor: open after a free-text drag-out (new) or a
  // tap on the already-selected free text annotation (existing)
  Rect? _textEditRect; // view space; null = closed; derived per build
  // page space is the source of truth: a zoom that re-lays-out the page
  // (the _layoutZoom regime changes _geometry.scale) would leave a cached
  // view rect stale, so the box would drift across the page - build
  // refreshes _textEditRect from this through the live geometry
  PdfRect? _textEditPageRect;
  bool _textEditExisting = false;
  PdfEditTool? _textEditTool;
  // when non-null the open editor is a callout: this is the page-space point
  // (the terminus) the committed box's leader line will point at
  (double, double)? _textEditCalloutTarget;
  late final _RichTextEditingController _textEditText =
      _RichTextEditingController()..addListener(_onTextEditChanged);
  late final FocusNode _textEditFocus = FocusNode(onKeyEvent: _onTextEditKey)
    ..addListener(_onTextEditFocus);
  PdfStandardFont _textEditFont = PdfStandardFont.helvetica;
  // embedded-font keys whose preview registration is in flight, so a
  // repeated restyle doesn't kick off a second load (see [_embeddedFontKey])
  final Set<String> _embeddedFontsLoading = {};
  double _textEditSize = 14; // pt
  Color _textEditColor = const Color(0xFF000000);
  Color? _textEditFill; // the box background the commit will paint
  // box-level layout the inline editor previews so the live text matches
  // what commits: alignment (/Q), line height, character spacing, and
  // horizontal glyph scaling
  // null means "follow the text direction" (left for LTR, right for RTL) -
  // a box with no explicit /Q, matching TextField's TextAlign.start
  PdfTextAlign? _textEditAlign;
  double _textEditLineSpacing = kPdfFreeTextDefaultLineSpacing;
  double _textEditCharSpacing = 0;
  bool _textEditStyleMenuOpen = false;
  // holds the editor's keyboard focus while a pointer is down on the inline
  // style chip, so tapping a chip button (underline, size, …) on mobile
  // doesn't blur the field and commit/deselect the box under it
  bool _chipFocusHeld = false;
  // resting view-space rotation of the box being edited (radians,
  // clockwise positive): nonzero only when editing already-rotated text,
  // so the inline editor and afterimage sit on the artwork instead of
  // snapping back to horizontal
  double _textEditRotation = 0;
  int _textEditStyleRevision = 0;
  int _editSelectedTextRevision = 0;
  int _textEditFocusHoldRevision = 0;

  // form-tool text fill: when set, the inline editor commits into this
  // field's /V instead of creating a free-text annotation
  String? _textEditFieldName;
  bool _textEditMultiline = true;

  // select-tool drags. A rotated selection resizes in its local frame:
  // _resizeFrom/_resizeRect are then the chrome's local box (the rect
  // the painter spins by _resizeAngle), not page-axis view rects.
  Offset? _moveStart;
  Offset? _moveCurrent;

  /// The global position of [_moveCurrent] - captured during a move drag
  /// so a drop over another page can be resolved to a page point (drag-end
  /// details carry no position).
  Offset? _moveCurrentGlobal;

  // Edge auto-scroll: while a region/selection drag is in flight the ticker
  // runs every frame, scrolling the viewer when the pointer rests against a
  // viewport edge and re-tracking the held pointer onto the content scrolled
  // under it (so the drag keeps growing during auto-scroll or a manual
  // shift-scroll). [_autoScrollGlobal] is the latest pointer global position;
  // [_autoScrollLastLocal] guards against redundant re-tracks.
  late final Ticker _autoScrollTicker = createTicker(_onAutoScrollTick);
  Offset? _autoScrollGlobal;
  Offset? _autoScrollLastLocal;

  _Handle? _resizeHandle;
  Rect? _resizeFrom;
  Rect? _resizeRect;
  double _resizeAngle = 0;
  // a resize drag that pulled a handle past the opposite edge mirrors the
  // annotation; _resizeRect stays normalized (positive) so the chrome and
  // ghost layout are unaffected, and these carry the flip to the commit
  bool _resizeFlipX = false;
  bool _resizeFlipY = false;
  int? _vertexHandle;
  List<Offset>? _vertexPoints;

  // the "lift" model behind a free-text resize: the page rendered WITHOUT
  // the dragged annotation, drawn clipped to the resting box so the
  // original reads as gone (the page content behind shows through) while
  // the re-wrapped preview floats on top. Rendered async on resize start;
  // until it lands, an opaque-paper wash stands in so the original never
  // flashes. [_resizeCleanFor] is the lifted annotation's identity, so a
  // stale render from an earlier drag is discarded.
  ui.Picture? _resizeCleanPicture;
  Object? _resizeCleanFor;

  // The embedded/bundled face a free-text resize preview re-wraps with,
  // reparsed from the box's appearance program once per selection. Recovering
  // the program isn't free, so it's cached against the annotation instance
  // (stable within a revision) rather than decoded on every drag frame.
  PdfEmbeddedFont? _resizeEmbeddedFont;
  PdfAnnotation? _resizeEmbeddedFontFor;

  // Clean page for a selected annotation's original footprint. Move commits
  // clip this into the source rect so the annotation disappears without
  // covering underlying page content with a paper-colored box.
  ui.Picture? _sourceCleanPicture;
  Object? _sourceCleanFor;

  // rubber-band selection (mouse drags on empty page area)
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  bool _marqueeAdd = false;

  // touch drags on empty page area pan the viewer instead
  bool _viewportPanning = false;

  // rotate drag: the pointer's start angle about the selection center,
  // the annotation's resting rotation when the drag started, and the
  // current delta (view space, clockwise positive - y is down)
  double? _rotateStartAngle;
  double _rotateResting = 0;
  double _rotateDelta = 0;

  // signature tool: the pointer position the live preview rides (hover
  // for a mouse, press-and-drag for touch), and whether a drag-place is
  // in flight
  Offset? _signaturePreview;
  bool _signatureDrag = false;

  // afterimage of the last commit, painted until the new revision's
  // raster lands ([widget.rasterCurrent]) - without it the preview
  // clears frames before the page re-renders and the edit blinks out
  PdfDocument? _afterDocument;
  ui.Picture? _afterGhost;
  Rect? _afterGhostFrom;
  Rect? _afterGhostTo;
  Rect? _afterGhostSourceRect;
  ui.Picture? _afterGhostSourceClean;
  double _afterGhostRotation = 0;
  double _afterGhostLocalAngle = 0;
  bool _afterGhostFlipX = false;
  bool _afterGhostFlipY = false;
  ({Rect rect, PdfEditTool tool, Color color, double strokeWidth})? _afterShape;
  _StampAfterimage? _afterStamp;
  // a just-committed Square/Circle resize, held (constant stroke width)
  // until the new revision's raster lands - see [_shapeResizeStyle]
  _ShapeResize? _afterShapeResize;
  ({
    List<Offset> points,
    PdfEditTool tool,
    Color color,
    Color? fillColor,
    double strokeWidth,
    bool dashed,
  })? _afterPath;
  ({
    Rect rect,
    String text,
    PdfTextFont font,
    double size,
    Color color,
    Color? fill,
    bool washed,
    double rotation,
    PdfTextAlign? align,
    bool underline,
    double lineSpacing,
  })? _afterText;
  // the lifted clean page (the page rendered without the resized text box)
  // kept alive past the drag so a transparent box's commit afterimage shows
  // the real page content behind it instead of an opaque-paper flash. Null
  // when the lift wasn't ready - then [_afterText.washed] paints the paper
  // fallback. Hides the old footprint [_afterTextHideRect] (view space).
  ui.Picture? _afterTextClean;
  Rect? _afterTextHideRect;
  double _afterTextHideAngle = 0;
  _InkPaint? _afterSignature;

  // live drag preview: the selected annotation's appearance, rendered
  // once per (revision, selection) and drawn stretched while dragging
  ui.Picture? _ghost;
  (PdfDocument, int, int)? _ghostKey;

  // attention flash (the annotation sidebar's zoom-to): an amber pulse
  // closing in on the annotation, driven by its own short animation
  late final AnimationController _flashController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..addListener(_onFlashTick)
    ..addStatusListener(_onFlashStatus);
  int _flashSequence = 0;
  PdfRect? _flashRect; // page space - view rect derives per build

  void _onFlashTick() => setState(() {});

  void _onFlashStatus(AnimationStatus status) {
    // pulse done: retire the pending flash so the overlay can unmount
    if (status == AnimationStatus.completed) {
      _controller.expireFlash(_flashSequence);
    }
  }

  MouseCursor _cursor = MouseCursor.defer;

  late PdfEditingInteractionSession _interaction;
  late bool _ownsInteraction;
  late PdfEditingInteractionHost _host;
  bool _rasterReadyScheduled = false;

  PdfEditingController get _controller => widget.controller;
  PdfPageGeometry get _geometry => widget.geometry;

  /// Overlay pixels per intended screen pixel for chrome metrics - the
  /// inverse of the viewer's transform zoom (see [EditingPageOverlay.zoom]).
  double get _chromeScale {
    final zoom = widget.zoom;
    return zoom.isFinite && zoom > 0 ? 1 / zoom : 1.0;
  }

  /// Null while the eyedropper is armed without a tool, or while a
  /// default-mode (mouse click) selection exists without one.
  PdfEditTool? get _tool => _controller.tool;

  /// Select-tool behavior applies: the tool is armed, or an annotation
  /// was selected in default mode (no tool) by a mouse click - the
  /// selection needs its move/resize/marquee interactions either way.
  bool get _selectMode =>
      _tool == PdfEditTool.select ||
      (_tool == null && _controller.hasAnnotationSelection);

  @override
  void initState() {
    super.initState();
    _adoptInteraction();
    _adoptHost();
    _controller.addListener(_onControllerChanged);
  }

  void _adoptInteraction() {
    _ownsInteraction = widget.interactionSession == null;
    _interaction =
        widget.interactionSession ?? PdfEditingInteractionSession();
  }

  void _adoptHost() {
    _host = widget.interactionHost ??
        PdfEditingInteractionHost(
          panViewport: widget.onPanViewport,
          endViewportPan: widget.onPanViewportEnd,
          edgeAutoScroll: widget.edgeAutoScroll,
          showAnnotationMenu: widget.onShowAnnotationMenu,
          showFormFieldMenu: widget.onShowFormFieldMenu,
          resolvePagePoint: widget.onResolvePagePoint,
          moveDragPreview: widget.onMoveDragPreview,
          textEditClosed: widget.onTextEditClosed,
        );
  }

  @override
  void didUpdateWidget(covariant EditingPageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
    }
    if (!identical(oldWidget.interactionSession, widget.interactionSession)) {
      if (_interaction.isActive) _interaction.cancel();
      if (_ownsInteraction) _interaction.dispose();
      _adoptInteraction();
    }
    if (!identical(oldWidget.interactionHost, widget.interactionHost) ||
        !identical(oldWidget.onPanViewport, widget.onPanViewport) ||
        !identical(oldWidget.onPanViewportEnd, widget.onPanViewportEnd) ||
        !identical(oldWidget.edgeAutoScroll, widget.edgeAutoScroll) ||
        !identical(
            oldWidget.onShowAnnotationMenu, widget.onShowAnnotationMenu) ||
        !identical(oldWidget.onShowFormFieldMenu, widget.onShowFormFieldMenu) ||
        !identical(oldWidget.onResolvePagePoint, widget.onResolvePagePoint) ||
        !identical(oldWidget.onMoveDragPreview, widget.onMoveDragPreview) ||
        !identical(oldWidget.onTextEditClosed, widget.onTextEditClosed)) {
      _adoptHost();
    }
  }

  /// Shift/⌘/Ctrl held - a click toggles membership, a marquee adds.
  static bool get _additiveModifier {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isMetaPressed ||
        keyboard.isControlPressed;
  }

  static double? _normalizedPressure(PointerEvent event) =>
      event.pressureMax > event.pressureMin
          ? ((event.pressure - event.pressureMin) /
                  (event.pressureMax - event.pressureMin))
              .clamp(0.0, 1.0)
          : null;

  /// The armed tool's behaviour - the single source of tool identity the
  /// gesture phases dispatch on - or null when nothing is armed.
  PdfEditToolBehavior? get _behavior => PdfEditToolBehavior.maybeOf(_tool);

  bool get _inkTool => _behavior?.isInk ?? false;
  bool get _drawTool => _behavior?.isDraw ?? false;

  /// A finger should pan the viewer (not draw): the draw tool is armed
  /// but finger-drawing is off, so touch is reserved for scrolling.
  bool get _fingerPansViewport =>
      _drawTool &&
      !_controller.preferences.fingerDrawsInk &&
      _host.panViewport != null;
  bool get _polyTool => _behavior?.isPoly ?? false;

  /// The cloud tool is a hybrid: a drag rubber-bands a rectangle, but a
  /// tap starts (and each further tap extends) a free-form vertex list -
  /// finished by a double-tap. This is true once at least one vertex has
  /// been placed, so a drag no longer restarts the shape as a rectangle.
  bool get _cloudPolyInProgress =>
      _tool == PdfEditTool.cloudPolygon && (_polyPoints?.isNotEmpty ?? false);

  /// The number of clicks a fixed-arity poly tool takes before it
  /// auto-finishes - three for the angle and arc takeoffs - or null for an
  /// open-ended poly tool (finished by a double-tap).
  int? get _fixedPolyCount => _behavior?.fixedPolyCount;

  /// A tool placed by dragging a single straight segment (a /Line or a
  /// distance/slope measurement).
  bool get _lineDragTool => _behavior?.isLineDrag ?? false;

  /// The measurement kind the armed tool creates, or null for a
  /// non-measurement tool.
  PdfMeasurementKind? get _measureKind => _behavior?.measureKind;

  /// Whether a pointer of [kind] draws (or erases) through the raw
  /// event stream instead of the gesture arena. Pan recognizers only
  /// win the arena after ~36px of motion, which swallowed the start of
  /// every pencil stroke and dropped quick dots as taps - so with ink
  /// or the eraser armed, stylus input (and touch, when fingers draw)
  /// starts on pointer-down. Mouse and trackpad keep the arena path:
  /// they have no latency problem and hover/click semantics to honor.
  bool _rawDrives(PointerDeviceKind? kind) {
    if (!_drawTool) return false;
    return switch (kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.touch => _controller.preferences.fingerDrawsInk,
      _ => false,
    };
  }

  void _beginInteraction(
      PdfEditingInteractionIntent intent, PointerDeviceKind? pointerKind) {
    _interaction.begin(intent,
        pageIndex: widget.pageIndex, pointerKind: pointerKind);
  }

  void _finishInteraction(PdfDocument before, int transition,
      {bool canceled = false}) {
    final state = _interaction.state;
    // The completed gesture may have opened a new interaction (a dragged
    // FreeText box opens the text session). Never finish that successor.
    if (state.transition != transition || !_interaction.isActive) return;
    if (canceled) {
      _interaction.cancel();
    } else if (!identical(before, _controller.document)) {
      _interaction.commit();
    } else {
      _interaction.complete();
    }
  }

  void _scheduleRasterReady() {
    if (_rasterReadyScheduled) return;
    final state = _interaction.state;
    if (!widget.rasterCurrent ||
        state.phase != PdfEditingInteractionPhase.awaitingRaster ||
        state.pageIndex != widget.pageIndex) {
      return;
    }
    _rasterReadyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rasterReadyScheduled = false;
      if (mounted && widget.rasterCurrent) _interaction.rasterReady();
    });
  }

  /// Raw-pointer bookkeeping the pan callbacks can't see: the pressure
  /// stream, stylus detection for palm rejection, multi-touch bail, and
  /// - with ink or the eraser armed - the stroke itself.
  void _onPointerDown(PointerDownEvent event) {
    _pointerPressure = _normalizedPressure(event);
    if (_lastPointerKind != event.kind) {
      // the selection action chip shows for touch/stylus input only
      setState(() => _lastPointerKind = event.kind);
    }
    if (event.kind == PointerDeviceKind.touch) {
      _pointers.touchPointers.add(event.pointer);
      if (_pointers.touchPointers.length >= 2) {
        // a stylus stroke survives stray touches - that second contact
        // is the palm resting on the screen, not a gesture
        if (_pointers.rawPointer != null &&
            !_pointers.touchPointers.contains(_pointers.rawPointer)) {
          return;
        }
        _bailActiveGesture();
        return;
      }
    }
    if (_controller.isPickingColor) {
      _updatePickPreview(event.localPosition);
      return;
    }
    if (_pointers.gestureBailed) return;
    if (_polyTool) {
      _addPolyPoint(event.localPosition);
      return;
    }
    if (_drawTool &&
        _controller.preferences.fingerDrawsInk &&
        (event.kind == PointerDeviceKind.stylus ||
            event.kind == PointerDeviceKind.invertedStylus)) {
      // an Apple Pencil (or other stylus) is in play: from now on the
      // pen draws and fingers scroll, until the user toggles it back
      _controller.preferences.fingerDrawsInk = false;
    }
    if (_pointers.rawPointer == null && _rawDrives(event.kind)) {
      _pointers.rawPointer = event.pointer;
      // a flipped pencil erases even while the ink tool is armed -
      // that's what the flip is for
      _pointers.rawErasing = _tool == PdfEditTool.eraser ||
          event.kind == PointerDeviceKind.invertedStylus;
      _beginInteraction(
          _pointers.rawErasing
              ? PdfEditingInteractionIntent.erase
              : PdfEditingInteractionIntent.ink,
          event.kind);
      if (_pointers.rawErasing) {
        _eraseAt(event.localPosition);
      } else {
        // hold the auto-commit while this stroke is on the page
        _controller.beginInkStroke();
        final pressure = _pointerPressure;
        _penCursor = event.localPosition;
        // no setState: the active stroke lives on its own repaint layer
        _activeStroke = [_geometry.toPagePoint(event.localPosition)];
        _activeStrokePressures = pressure == null ? null : [pressure];
        _bumpActiveStroke();
      }
    } else if (_pointers.panPointer == null &&
        _pointers.rawPointer == null &&
        event.kind == PointerDeviceKind.touch &&
        _fingerPansViewport) {
      // pencil mode, single finger, no pen stroke in flight: pan the
      // viewer. A move drives [onPanViewport]; lift hands the velocity
      // to [onPanViewportEnd] for a fling, exactly like a select-mode
      // empty-area touch drag.
      _pointers.panPointer = event.pointer;
      _pointers.panLast = event.localPosition;
      _pointers.panVelocity = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.localPosition);
      _beginInteraction(PdfEditingInteractionIntent.viewportPan, event.kind);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final pressure = _normalizedPressure(event);
    if (pressure != null) _pointerPressure = pressure;
    if (_controller.isPickingColor) {
      _updatePickPreview(event.localPosition);
      return;
    }
    if (event.pointer == _pointers.panPointer) {
      _interaction.sample();
      final last = _pointers.panLast;
      if (last != null) {
        _host.panViewport?.call(event.localPosition - last);
      }
      _pointers.panLast = event.localPosition;
      _pointers.panVelocity?.addPosition(event.timeStamp, event.localPosition);
      return;
    }
    if (event.pointer != _pointers.rawPointer) return;
    _interaction.sample();
    if (_pointers.rawErasing) {
      _eraseAt(event.localPosition);
    } else if (_activeStroke != null) {
      // hot path: append + repaint the stroke layer only, no rebuild
      _penCursor = event.localPosition;
      _activeStroke!.add(_geometry.toPagePoint(event.localPosition));
      _activeStrokePressures
          ?.add(_pointerPressure ?? _activeStrokePressures!.last);
      _bumpActiveStroke();
    }
  }

  /// Aborts whatever gesture is in flight - a second finger landed, so
  /// the first one wasn't drawing or dragging after all (it's a pinch,
  /// or just a clumsy grip). Nothing commits; the rest of the gesture
  /// is dead air until every touch pointer lifts.
  void _bailActiveGesture() {
    if (_interaction.isActive) _interaction.cancel();
    _pointers.gestureBailed = true;
    _pointers.clearRaw();
    // a second finger landed: stop panning so the viewer's pinch-zoom
    // recognizer takes both touches (no fling - the gesture isn't a pan)
    _pointers.clearPan();
    setState(() {
      _activeStroke = null;
      _activeStrokePressures = null;
      _resetErase();
      _panErasing = false;
      _dragStart = null;
      _dragCurrent = null;
      _moveStart = null;
      _moveCurrent = null;
      _moveCurrentGlobal = null;
      _resizeHandle = null;
      _resizeFrom = null;
      _resizeRect = null;
      _resizeAngle = 0;
      _resizeFlipX = false;
      _resizeFlipY = false;
      _rotateStartAngle = null;
      _rotateDelta = 0;
      _marqueeStart = null;
      _marqueeCurrent = null;
      _marqueeAdd = false;
      _viewportPanning = false;
      _signatureDrag = false;
      _signaturePreview = null;
    });
    _stopAutoScroll();
    _clearResizeClean();
    _host.moveDragPreview?.call(null);
    _bumpActiveStroke();
    // earlier strokes waiting in the buffer get their auto-commit back
    _controller.cancelInkStroke();
  }

  /// Touch bookkeeping and the raw gesture's commit, shared by
  /// pointer-up and pointer-cancel.
  void _endRawPointer(PointerEvent event, {required bool canceled}) {
    final tracked = event.pointer == _pointers.rawPointer ||
        event.pointer == _pointers.panPointer;
    final before = _controller.document;
    final transition = _interaction.state.transition;
    _finishRawPointer(event, canceled: canceled);
    if (tracked) {
      _finishInteraction(before, transition, canceled: canceled);
    }
  }

  void _finishRawPointer(PointerEvent event, {required bool canceled}) {
    if (event.kind == PointerDeviceKind.touch) {
      _pointers.touchPointers.remove(event.pointer);
      if (_pointers.touchPointers.isEmpty) _pointers.gestureBailed = false;
    }
    if (event.pointer == _pointers.panPointer) {
      final velocity = canceled
          ? Velocity.zero
          : (_pointers.panVelocity?.getVelocity() ?? Velocity.zero);
      _pointers.clearPan();
      if (!canceled) _host.endViewportPan?.call(velocity);
      return;
    }
    if (event.pointer != _pointers.rawPointer) {
      if (_panErasing && !canceled) _eraseAt(event.localPosition);
      return;
    }
    final erasing = _pointers.rawErasing;
    if (erasing) {
      if (canceled) {
        _pointers.clearRaw();
        setState(_resetErase);
      } else {
        // Fast pen swipes can land their final contact only on pointer-up.
        // Stamp it into the path before committing so the tail erases too.
        _eraseAt(event.localPosition);
        _pointers.clearRaw();
        _commitErase();
      }
      return;
    }
    _pointers.clearRaw();
    final stroke = _activeStroke;
    final pressures = _activeStrokePressures;
    setState(() {
      _activeStroke = null;
      _activeStrokePressures = null;
    });
    _bumpActiveStroke();
    if (canceled || stroke == null || stroke.isEmpty) {
      _controller.cancelInkStroke();
      return;
    }
    if (stroke.length == 1) {
      // a dot (the i's, mostly): a zero-length segment renders as a
      // filled circle under the round line cap (PDF §8.5.3.2)
      stroke.add(stroke.single);
      pressures?.add(pressures.single);
    }
    _controller.addInkStroke(widget.pageIndex, stroke, pressures: pressures);
  }

  /// Sweeps the circle eraser to the view-space [position]: extends the
  /// swipe's path by one capsule and re-slices every ink annotation it
  /// touches, so the live preview (faded original + remainder strokes)
  /// shows exactly what the commit will keep. Ink annotations without a
  /// usable /InkList can't be sliced - they fade whole and the commit
  /// deletes them.
  void _eraseAt(Offset position) {
    final point = _geometry.toPagePoint(position);
    final radius = _controller.preferences.eraserRadius;
    final from = _erasePath.isEmpty ? point : _erasePath.last;
    setState(() {
      _eraserCursor = position;
      _erasePath.add(point);
      final annotations = _controller.pageAt(widget.pageIndex).annotations;
      for (var slot = 0; slot < annotations.length; slot++) {
        final annotation = annotations[slot];
        if (annotation.subtype != 'Ink' ||
            annotation.isHidden ||
            !_controller.isAnnotationEditable(annotation)) {
          continue;
        }
        final tracked = _eraseSliced[slot];
        final strokes = tracked?.strokes ?? annotation.inkList;
        if (strokes == null) {
          if (!_eraseWholeSlots.contains(slot) &&
              _hitsRect(point, annotation.rect, radius)) {
            _eraseWholeSlots.add(slot);
            _eraseRects[slot] = _geometry.toViewRect(annotation.rect);
          }
          continue;
        }
        final sliced = pdfSliceInkStrokes(strokes, null, from, point, radius);
        if (sliced == null) continue;
        // wash the original ink along its own strokes (padded for the
        // baked-in pressure width + caps) rather than the whole bounding
        // box, so surrounding page content isn't dimmed and the wash
        // never spills off the page
        _eraseFade.putIfAbsent(
            slot,
            () => (
                  strokes: strokes,
                  pressures: List<List<double>?>.filled(strokes.length, null),
                  color: const Color(0xFF000000),
                  strokeWidth:
                      (annotation.borderWidth ?? 1) * _geometry.scale * 1.7 + 4,
                ));
        _eraseSliced[slot] = (
          strokes: sliced.strokes,
          pressures: List<List<double>?>.filled(sliced.strokes.length, null),
          color: Color(0xFF000000 | (annotation.color ?? 0xD02020)),
          strokeWidth: (annotation.borderWidth ?? 1) * _geometry.scale,
        );
      }
    });
  }

  static bool _hitsRect((double, double) p, PdfRect rect, double radius) =>
      p.$1 >= rect.left - radius &&
      p.$1 <= rect.right + radius &&
      p.$2 >= rect.bottom - radius &&
      p.$2 <= rect.top + radius;

  void _resetErase() {
    _erasePath.clear();
    _eraseSliced.clear();
    _eraseFade.clear();
    _eraseWholeSlots.clear();
    _eraseRects.clear();
    _eraserCursor = null;
  }

  /// Commits the swipe's slicing in one apply (one undo) and keeps the
  /// washed rects plus the sliced remainders painted until the new
  /// revision's raster lands.
  void _commitErase() {
    final path = List.of(_erasePath);
    final rects = List.of(_eraseRects.values);
    final fade = List.of(_eraseFade.values);
    final ink = List.of(_eraseSliced.values);
    final touched = _eraseSliced.isNotEmpty || _eraseWholeSlots.isNotEmpty;
    setState(_resetErase);
    if (path.isEmpty || !touched) return;
    final before = _controller.document;
    _controller.sliceErase(widget.pageIndex, path);
    if (identical(before, _controller.document)) return;
    _clearAfterimage();
    _afterEraseRects = rects;
    _afterEraseFade = fade;
    _afterEraseInk = ink;
    _afterDocument = _controller.document;
  }

  /// The primary selected annotation's view rect when it lives on this
  /// page - the one that gets resize/rotate handles (single selection).
  Rect? get _selectedViewRect {
    if (_controller.selectedPage != widget.pageIndex) return null;
    final annotation = _controller.selectedAnnotation;
    if (annotation == null) return null;
    // a callout's chrome hugs the text box, not the /Rect that also
    // encloses the leader + arrow, so resize handles size the box alone
    return _geometry.toViewRect(annotation.calloutBox ?? annotation.rect);
  }

  /// View rects of the marked (unburned) /Redact annotations on this page,
  /// for the hatched preview. Empty when the document has no redactions.
  List<Rect> get _redactionViewRects {
    final page = _controller.pageAt(widget.pageIndex);
    return [
      for (final annotation in page.annotations)
        if (annotation.subtype == 'Redact')
          _geometry.toViewRect(annotation.rect),
    ];
  }

  /// Every selected annotation's view rect on this page, in selection
  /// order (so the primary is last).
  List<Rect> get _selectedViewRects => [
        for (final slot in _controller.selectedAnnotationSlots)
          if (slot.$1 == widget.pageIndex)
            if (_controller.annotationAt(slot.$1, slot.$2)
                case final annotation?)
              _geometry.toViewRect(annotation.rect)
      ];

  /// The primary selection's appearance quad in view space (BBox corner
  /// order: ll, lr, ur, ul), or null without an appearance stream.
  List<Offset>? get _selectedViewQuad {
    if (_controller.selectedPage != widget.pageIndex) return null;
    final quad = _controller.selectedAnnotation?.appearanceQuad;
    if (quad == null) return null;
    return [for (final (x, y) in quad) _geometry.toViewOffset(x, y)];
  }

  bool get _selectedLineFamily {
    return _controller.selectedAnnotation?.behavior.lineFamily == true;
  }

  PdfEditTool? get _selectedLineTool {
    final annotation = _controller.selectedAnnotation;
    switch (annotation?.subtype) {
      case 'Line':
        final cos = annotation!.document.cos;
        final le = cos.resolve(annotation.dict['LE']);
        if (le is CosArray && le.length >= 2) {
          final end = cos.resolve(le[1]);
          if (end is CosName && end.value == 'ClosedArrow') {
            return PdfEditTool.arrow;
          }
        }
        return PdfEditTool.line;
      case 'PolyLine':
        return PdfEditTool.polyline;
      case 'Polygon':
        return annotation!.hasCloudyBorder
            ? PdfEditTool.cloudPolygon
            : PdfEditTool.polygon;
      default:
        return null;
    }
  }

  /// The selected line-family annotation's defining points in view space:
  /// /L endpoints for Line, /Vertices for PolyLine and Polygon.
  List<Offset>? get _selectedVertexPoints {
    if (_controller.selectedPage != widget.pageIndex) return null;
    final annotation = _controller.selectedAnnotation;
    if (annotation == null) return null;
    // a callout exposes two handles: the terminus (arrow tip, index 0) and
    // the base where the leader meets the box (index 1), so each can be
    // dragged without disturbing the other or the text box
    if (annotation.calloutLine case final line?) {
      return [
        _geometry.toViewOffset(line.first.$1, line.first.$2),
        _geometry.toViewOffset(line.last.$1, line.last.$2),
      ];
    }
    if (annotation.line case final line?) {
      return [
        _geometry.toViewOffset(line.$1.$1, line.$1.$2),
        _geometry.toViewOffset(line.$2.$1, line.$2.$2),
      ];
    }
    final vertices = annotation.vertices;
    if (vertices == null) return null;
    return [for (final (x, y) in vertices) _geometry.toViewOffset(x, y)];
  }

  /// The view-space rotation of [quad]'s bottom edge - the angle the
  /// selection chrome spins by (canvas.rotate convention: clockwise
  /// positive). Numeric noise within ~0.3° reads as unrotated.
  static double _quadAngle(List<Offset> quad) {
    final edge = quad[1] - quad[0];
    if (edge.distance <= 0) return 0;
    final angle = edge.direction;
    return angle.abs() < 0.005 ? 0 : angle;
  }

  /// The selection chrome's box and resting rotation: the axis-aligned
  /// view rect for an unrotated appearance, otherwise the quad's own
  /// (pre-rotation) rectangle - the painter spins it back into place,
  /// so the chrome hugs the rotated artwork instead of boxing its
  /// axis-aligned bounds.
  (Rect, double)? get _selectionChrome {
    final selected = _selectedViewRect;
    if (selected == null) return null;
    final quad = _selectedViewQuad;
    if (quad == null) return (selected, 0);
    final angle = _quadAngle(quad);
    if (angle == 0) return (selected, 0);
    final center =
        Offset((quad[0].dx + quad[2].dx) / 2, (quad[0].dy + quad[2].dy) / 2);
    return (
      Rect.fromCenter(
        center: center,
        width: (quad[1] - quad[0]).distance,
        height: (quad[3] - quad[0]).distance,
      ),
      angle,
    );
  }

  static Offset _rotatePoint(Offset p, Offset center, double angle) =>
      HandleLayout.rotatePoint(p, center, angle);

  /// Drops the afterimage (and its ghost picture, which the state owns).
  void _clearAfterimage() {
    _afterGhost?.dispose();
    _afterGhost = null;
    _afterGhostFrom = null;
    _afterGhostTo = null;
    _afterGhostSourceRect = null;
    _afterGhostSourceClean?.dispose();
    _afterGhostSourceClean = null;
    _afterGhostRotation = 0;
    _afterGhostLocalAngle = 0;
    _afterGhostFlipX = false;
    _afterGhostFlipY = false;
    _afterShape = null;
    _afterStamp = null;
    _afterShapeResize = null;
    _afterPath = null;
    _afterText = null;
    _afterTextClean?.dispose();
    _afterTextClean = null;
    _afterTextHideRect = null;
    _afterTextHideAngle = 0;
    _afterSignature = null;
    _afterEraseRects = null;
    _afterEraseFade = null;
    _afterEraseInk = null;
    _afterDocument = null;
  }

  /// Runs [commit] and, when it produced a new revision, keeps the
  /// current ghost painted at [to] (spun by [rotation]) as the
  /// afterimage - the move/resize/rotate result stays visible while the
  /// page re-renders. The ghost's ownership transfers to the afterimage;
  /// [_ensureGhost] re-renders a fresh one for the new revision.
  ///
  /// For a rotated selection's resize, [localAngle] is its resting
  /// rotation and [to] the dragged *local* box - the afterimage then
  /// scales along the local axes, exactly like the live preview did.
  ///
  /// [flipX]/[flipY] mirror the afterimage so a resize that inverted the
  /// annotation stays inverted while the page re-renders.
  ///
  /// [washSource] paints the old on-raster footprint over with paper before
  /// the new raster lands, so the stale raster does not keep showing the
  /// annotation at its previous position during the commit gap.
  void _commitWithGhost(VoidCallback commit,
      {Rect? to,
      double rotation = 0,
      double localAngle = 0,
      bool flipX = false,
      bool flipY = false,
      bool washSource = true}) {
    final from = localAngle == 0 ? _selectedViewRect : _selectionChrome?.$1;
    final source = _selectedViewRect;
    final ghost = _ghost;
    final sourceAnnotation = washSource ? _controller.selectedAnnotation : null;
    final before = _controller.document;
    commit();
    if (identical(before, _controller.document)) return;
    if (ghost == null || from == null || to == null) return;
    final afterDocument = _controller.document;
    _clearAfterimage();
    _ghost = null;
    _ghostKey = null;
    _afterGhost = ghost;
    _afterGhostFrom = from;
    _afterGhostTo = to;
    _afterGhostSourceRect = washSource ? source : null;
    final sourceCleanKey = washSource && sourceAnnotation != null
        ? (
            document: before,
            page: widget.pageIndex,
            annotation: sourceAnnotation.dict,
            color: widget.pageColor,
            showAnnotations: widget.showAnnotations,
          )
        : null;
    if (washSource &&
        _sourceCleanPicture != null &&
        _sourceCleanFor == sourceCleanKey) {
      _afterGhostSourceClean = _sourceCleanPicture;
      _sourceCleanPicture = null;
      _sourceCleanFor = null;
    } else {
      if (_sourceCleanPicture != null) {
        _sourceCleanPicture!.dispose();
        _sourceCleanPicture = null;
        _sourceCleanFor = null;
      }
      if (washSource &&
          sourceAnnotation != null &&
          sourceAnnotation.subtype != 'Stamp') {
        unawaited(_renderAfterGhostSourceClean(
          document: before,
          pageIndex: widget.pageIndex,
          annotation: sourceAnnotation,
          ghost: ghost,
          afterDocument: afterDocument,
        ));
      }
    }
    _afterGhostRotation = rotation;
    _afterGhostLocalAngle = localAngle;
    _afterGhostFlipX = flipX;
    _afterGhostFlipY = flipY;
    _afterDocument = afterDocument;
  }

  Future<void> _renderAfterGhostSourceClean({
    required PdfDocument document,
    required int pageIndex,
    required PdfAnnotation annotation,
    required ui.Picture ghost,
    required PdfDocument afterDocument,
  }) async {
    // The drag/release feedback must hit the screen first. Rendering a clean
    // page can parse and interpret a large CAD page synchronously before its
    // first await, so defer it until the current frame is delivered.
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted ||
        _afterGhost != ghost ||
        !identical(_afterDocument, afterDocument)) {
      return;
    }
    final name = annotation.name;
    try {
      final picture = await PdfPageRenderer.renderPicture(
        document.page(pageIndex),
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations,
        skipAnnotation: (a) =>
            identical(a.dict, annotation.dict) ||
            (name != null && a.name == name),
      );
      if (!mounted ||
          _afterGhost != ghost ||
          !identical(_afterDocument, afterDocument)) {
        picture.dispose();
        return;
      }
      setState(() {
        _afterGhostSourceClean?.dispose();
        _afterGhostSourceClean = picture;
      });
    } catch (_) {
      // A clean-page failure leaves the existing afterimage in place. The
      // normal page raster will still replace it when rendering completes.
    }
  }

  void _captureLastStampAfterimage(PdfDocument before,
      {required bool check, required String? text, required Color color}) {
    if (identical(before, _controller.document)) return;
    final annotations = _controller.document.page(widget.pageIndex).annotations;
    if (annotations.isEmpty) return;
    _setStampAfterimage(
      (
        rect: _geometry.toViewRect(annotations.last.rect),
        text: text,
        template: null,
        check: check,
        color: color,
        opacity: _controller.preferences.opacity.clamp(0.0, 1.0).toDouble(),
      ),
      document: _controller.document,
    );
  }

  void _setStampAfterimage(_StampAfterimage stamp, {PdfDocument? document}) {
    _clearAfterimage();
    _afterStamp = stamp;
    _afterDocument = document;
    if (mounted) setState(() {});
  }

  Future<void> _commitStampWithAfterimage(
      _StampAfterimage preview, VoidCallback commit) async {
    // Paint first, then do the synchronous PDF edit after the frame. Without
    // this, a large save/appearance update can leave the page visually
    // unchanged for a few hundred milliseconds after the click.
    _setStampAfterimage(preview);
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return;
    final before = _controller.document;
    commit();
    if (!mounted) return;
    if (identical(before, _controller.document)) {
      _clearAfterimage();
      setState(() {});
      return;
    }
    final annotations = _controller.document.page(widget.pageIndex).annotations;
    _afterStamp = annotations.isEmpty
        ? preview
        : (
            rect: _geometry.toViewRect(annotations.last.rect),
            text: preview.text,
            template: preview.template,
            check: preview.check,
            color: preview.color,
            opacity: preview.opacity,
          );
    _afterDocument = _controller.document;
    setState(() {});
  }

  _StampAfterimage _stampAfterimage(Rect rect,
          {required String? text,
          required Color color,
          PdfStampTemplate? template,
          bool check = false}) =>
      (
        rect: rect,
        text: text,
        template: template,
        check: check,
        color: color,
        opacity: _controller.preferences.opacity.clamp(0.0, 1.0).toDouble(),
      );

  _StampAfterimage? _activeStampAfterimageAt(Offset position) {
    final stamp = _controller.activeStamp;
    if (stamp == null) return null;
    final (x, y) = _geometry.toPagePoint(position);
    final rect = _controller.stampPlacement(widget.pageIndex, x, y);
    if (rect == null) return null;
    final values = _controller.resolvedStampTemplateValues;
    return _stampAfterimage(
      _geometry.toViewRect(rect),
      text: pdfResolveStampTemplateText(stamp.text, values),
      template: stamp.template?.resolveText(values),
      color: Color(0xFF000000 | stamp.color),
    );
  }

  _StampAfterimage _textStampAfterimageAt(
      Offset position, String text, Color color) {
    final (x, y) = _geometry.toPagePoint(position);
    return _stampAfterimage(
      _geometry.toViewRect(
          _controller.textStampPlacement(widget.pageIndex, x, y, text)),
      text: text,
      color: color,
    );
  }

  /// Placeholder caption previewed while hovering the text-stamp tool before
  /// a click prompts for the real text.
  static const String _textStampPreviewLabel = 'TEXT';

  /// The stamp tool's hover preview: an active custom stamp when one is
  /// selected, otherwise the plain text-stamp fallback shown as a
  /// [_textStampPreviewLabel] placeholder so the click target is visible.
  _StampAfterimage? _stampHoverAfterimageAt(Offset position) {
    if (_controller.activeStamp != null) {
      return _activeStampAfterimageAt(position);
    }
    return _textStampAfterimageAt(
        position, _textStampPreviewLabel, _controller.color);
  }

  _StampAfterimage _countPreviewAt(Offset position) {
    final (x, y) = _geometry.toPagePoint(position);
    final box = _controller.pageAt(widget.pageIndex).cropBox;
    final s = PdfEditingController.checkMarkSize
        .clamp(4.0, math.min(box.width, box.height) * 0.9)
        .toDouble();
    final cx = x.clamp(box.left + s / 2, box.right - s / 2).toDouble();
    final cy = y.clamp(box.bottom + s / 2, box.top - s / 2).toDouble();
    return (
      rect: _geometry.toViewRect(PdfRect(
        cx - s / 2,
        cy - s / 2,
        cx + s / 2,
        cy + s / 2,
      )),
      text: null,
      template: null,
      check: true,
      color: _controller.color,
      opacity: _controller.preferences.opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// The embedded (Type0-with-program) face a free-text [annotation] names in
  /// its /DA, reparsed from its appearance program so a resize preview can
  /// re-wrap in the real font. Cached against the annotation instance (stable
  /// within a revision) because decoding the program isn't cheap. Null when
  /// the box has no embedded program or it can't be recovered.
  PdfEmbeddedFont? _resizeEmbeddedFontOf(PdfAnnotation annotation) {
    if (!identical(annotation, _resizeEmbeddedFontFor)) {
      _resizeEmbeddedFontFor = annotation;
      _resizeEmbeddedFont = annotation.behavior.hasEmbeddedTextFont
          ? PdfEmbeddedFont.fromFreeText(annotation)
          : null;
    }
    return _resizeEmbeddedFont;
  }

  /// The selection's text style when a resize commit will RE-WRAP it at
  /// a constant font size - the editor's FreeText regenerate path:
  /// an /AP to replace and a /DA naming the box's font. Null means the
  /// commit stretches the appearance and the ghost previews faithfully.
  ({
    String text,
    PdfTextFont font,
    double size,
    Color color,
    Color? fill,
    PdfTextAlign align,
    bool underline,
    double lineSpacing,
  })? get _textResizeStyle {
    final annotation = _controller.selectedAnnotation;
    if (annotation == null ||
        annotation.behavior.resizeBehavior !=
            PdfAnnotationResizeBehavior.reflowText) {
      return null;
    }
    // Base-14 boxes preview in the matching platform face; an embedded/bundled
    // box previews in its own outline bytes, registered with the engine under
    // a synthetic family ([_wrappedTextBox] kicks that off) exactly like the
    // inline editor - so the drag wraps in the real font instead of stretching
    // baked glyphs. Only when neither is recoverable does the stretch ghost
    // still stand in (the commit re-wraps correctly regardless).
    final PdfTextFont? font = annotation.behavior.standardTextFont ??
        _resizeEmbeddedFontOf(annotation);
    if (font == null) return null;
    final parsed = annotation.behavior.style.freeText!;
    return (
      text: annotation.contents ?? '',
      font: font,
      size: parsed.fontSize,
      color: Color(0xFF000000 | parsed.color),
      fill: parsed.fillColor != null
          ? Color(0xFF000000 | parsed.fillColor!)
          : null,
      align: parsed.alignment,
      underline: parsed.underline,
      lineSpacing: parsed.lineSpacing,
    );
  }

  /// The selected annotation's style when a resize commit will
  /// REGENERATE it (Square/Circle) at a constant stroke width - the
  /// editor's shape regenerate path: an /AP to replace, no cloudy /BE,
  /// and a stroke or fill to draw. Dashed borders carry their exact /BS /D
  /// pattern into the preview. [strokeWidth] is in
  /// view pixels (the page-space border width scaled), so the preview
  /// reads at the same weight the commit will, instead of the ghost's
  /// stretched line. Null leaves the drag on the stretch ghost.
  ///
  /// Mirrors `_regenerateResizedAppearance`'s Square/Circle gate exactly,
  /// so the preview never disagrees with the commit.
  _ShapeResize? _shapeResizeStyle(Rect rect, double rotation) {
    final annotation = _controller.selectedAnnotation;
    if (annotation == null ||
        annotation.behavior.resizeBehavior !=
            PdfAnnotationResizeBehavior.regenerateShape) {
      return null;
    }
    final style = annotation.behavior.style;
    final width = style.strokeWidth ?? 1;
    final stroke = width > 0 ? style.color : null;
    final fill = style.fillColor;
    return (
      rect: rect,
      ellipse: annotation.subtype == 'Circle',
      stroke: stroke == null ? null : Color(0xFF000000 | stroke),
      strokeWidth: width * _geometry.scale,
      fill: fill == null ? null : Color(0xFF000000 | fill),
      dashPattern: annotation.borderDash == null
          ? null
          : [
              for (final length in annotation.borderDash!)
                length * _geometry.scale,
            ],
      rotation: rotation,
      opacity: style.opacity,
    );
  }

  /// The selected content element's view rect when it lives on this page.
  Rect? get _selectedElementViewRect {
    if (_controller.selectedElementPage != widget.pageIndex) return null;
    final bounds = _controller.selectedElement?.bounds;
    return bounds == null ? null : _geometry.toViewRect(bounds);
  }

  /// Keeps [_ghost] current: the selected annotation's appearance as a
  /// page-space picture, so a move/resize drag can show the artwork at
  /// its new place instead of just the chrome. Re-renders only when the
  /// revision or the selection changes; called from [build] so the
  /// picture is usually ready before a drag starts.
  void _ensureGhost() {
    // only a single selection drags with its artwork; a multi-selection
    // moves as plain chrome boxes
    final slot = _controller.selectedAnnotationSlots.length == 1
        ? _controller.selectedAnnotationSlot
        : null;
    final document = _controller.document;
    if (slot == null || slot.$1 != widget.pageIndex) {
      _ghost?.dispose();
      _ghost = null;
      _ghostKey = null;
      return;
    }
    final key = (document, slot.$1, slot.$2);
    if (key == _ghostKey) return;
    _ghostKey = key;
    _ghost?.dispose();
    _ghost = null;
    final annotation = _controller.selectedAnnotation;
    if (annotation == null) return;
    unawaited(PdfPageRenderer.renderAnnotationPicture(
            document.page(widget.pageIndex), annotation,
            rotation: widget.geometry.rotation)
        .then((picture) {
      if (!mounted || _ghostKey != key) {
        picture?.dispose();
        return;
      }
      setState(() => _ghost = picture);
      // a select-and-drag in one motion starts before the ghost renders;
      // once it lands mid-move, float it immediately (the pan updates
      // alone would leave it blank until the next pointer move)
      if (_moveStart != null) _reportMovePreview();
    }));
  }

  /// Pushes the current single-selection move drag's floating preview up
  /// to the viewer, which paints it above the page below - this overlay
  /// clips its own ghost at the page edge, so the part dragged past the
  /// boundary would otherwise vanish behind the next page.
  ///
  /// Only fires once the dragged rect actually leaves this page; a move
  /// that stays on the page keeps the overlay's own ghost (no floating
  /// layer, so no double exposure). Reports null otherwise - the ghost
  /// isn't ready, it's a resize/rotate, or it's not a single selection.
  void _reportMovePreview() {
    final report = _host.moveDragPreview;
    if (report == null) return;
    final picture = _ghost;
    final from = _selectedViewRect;
    final start = _moveStart;
    final current = _moveCurrent;
    if (picture == null ||
        from == null ||
        start == null ||
        current == null ||
        _resizeHandle != null ||
        _rotateStartAngle != null ||
        _controller.selectedAnnotationSlots.length != 1) {
      report(null);
      return;
    }
    final to = from.shift(current - start);
    // still wholly on this page: the overlay's own ghost shows it, no need
    // to float (and floating it too would double-expose the artwork)
    final page = Offset.zero & _geometry.viewSize;
    if (page.contains(to.topLeft) && page.contains(to.bottomRight)) {
      report(null);
      return;
    }
    report(PdfMoveDragPreview(
      pageIndex: widget.pageIndex,
      picture: picture,
      from: from,
      to: to,
      scale: _geometry.scale,
    ));
  }

  /// Renders the page WITHOUT the annotation being resized, so a free-text
  /// resize can show the page content behind it (the "lift" model) rather
  /// than wash an opaque rectangle over the original. Kicked off once per
  /// resize-drag start; the result is reused for the whole drag (the page
  /// behind doesn't change). Until it lands [_resizeCleanPicture] is null
  /// and the painter falls back to an opaque-paper wash, so the original
  /// never flashes through.
  Future<void> _renderResizeClean() async {
    final annotation = _controller.selectedAnnotation;
    if (annotation == null) return;
    final key = annotation.dict; // stable CosDictionary identity this revision
    final name = annotation.name;
    _resizeCleanFor = key;
    final document = _controller.document;
    try {
      final picture = await PdfPageRenderer.renderPicture(
        _controller.pageAt(widget.pageIndex),
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations,
        skipAnnotation: (a) =>
            identical(a.dict, key) || (name != null && a.name == name),
      );
      // discard if the drag ended, the selection changed, or the document
      // moved under us - a stale clean page would hide the wrong thing
      if (!mounted ||
          !identical(_resizeCleanFor, key) ||
          !identical(_controller.document, document)) {
        picture.dispose();
        return;
      }
      setState(() {
        _resizeCleanPicture?.dispose();
        _resizeCleanPicture = picture;
      });
    } catch (_) {
      // any render failure just leaves the opaque-paper wash fallback up
    }
  }

  /// Keeps a clean page (without the selected annotation) ready for move
  /// commits, so the old location can be erased by restoring the real page
  /// content instead of painting a white/paper rectangle over it.
  Future<void> _ensureSourceClean() async {
    // Do not start a clean-page render while the annotation is being moved.
    // That render may synchronously parse/interpret a complex page before its
    // first await, which competes directly with drag frames. If no clean page
    // is ready on release, [_renderAfterGhostSourceClean] fills it in after
    // the committed preview has already painted.
    if (_moveStart != null) return;
    final slots = _controller.selectedAnnotationSlots;
    if (slots.length != 1 || slots.single.$1 != widget.pageIndex) {
      _sourceCleanPicture?.dispose();
      _sourceCleanPicture = null;
      _sourceCleanFor = null;
      return;
    }
    final annotation =
        _controller.annotationAt(widget.pageIndex, slots.single.$2);
    if (annotation == null) return;
    final key = (
      document: _controller.document,
      page: widget.pageIndex,
      annotation: annotation.dict,
      color: widget.pageColor,
      showAnnotations: widget.showAnnotations,
    );
    if (_sourceCleanFor == key) return;
    _sourceCleanPicture?.dispose();
    _sourceCleanPicture = null;
    _sourceCleanFor = key;
    // Moving stamps is a hot path: pre-rendering the entire page without the
    // stamp can synchronously parse a complex CAD page and make the drag feel
    // sticky. Use the committed source wash until the normal page raster lands.
    if (annotation.subtype == 'Stamp') return;
    final name = annotation.name;
    try {
      final picture = await PdfPageRenderer.renderPicture(
        _controller.pageAt(widget.pageIndex),
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations,
        skipAnnotation: (a) =>
            identical(a.dict, annotation.dict) ||
            (name != null && a.name == name),
      );
      if (!mounted || _sourceCleanFor != key) {
        picture.dispose();
        return;
      }
      if (_moveStart != null) {
        _sourceCleanPicture?.dispose();
        _sourceCleanPicture = picture;
        return;
      }
      setState(() {
        _sourceCleanPicture?.dispose();
        _sourceCleanPicture = picture;
      });
    } catch (_) {
      // If the clean render fails, leave the stale raster alone rather than
      // painting an opaque box over the page content.
    }
  }

  /// Drops the lifted clean-page picture once a resize drag ends.
  void _clearResizeClean() {
    _resizeCleanPicture?.dispose();
    _resizeCleanPicture = null;
    _resizeCleanFor = null;
  }

  void _clearSourceClean() {
    _sourceCleanPicture?.dispose();
    _sourceCleanPicture = null;
    _sourceCleanFor = null;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_textEditRect != null) _controller.setEditingText(false);
    // if THIS overlay was mid-move, drop the shared cross-page preview
    // before disposing [_ghost] so a neighbour page can't paint freed
    // pixels. Guarded by _moveStart so disposing some other (off-screen)
    // page's overlay never clears a preview the dragging page still owns.
    if (_moveStart != null) _host.moveDragPreview?.call(null);
    if (_chipFocusHeld) {
      _chipFocusHeld = false;
      _controller.endEditingTextFocusHold();
    }
    _textEditFocus
      ..removeListener(_onTextEditFocus)
      ..dispose();
    _textEditText.dispose();
    _ghost?.dispose();
    _clearAfterimage();
    _resizeCleanPicture?.dispose();
    _clearSourceClean();
    _flashController.dispose();
    _activeStrokeRepaint.dispose();
    _autoScrollTicker.dispose();
    if (_interaction.isActive &&
        _interaction.state.pageIndex == widget.pageIndex) {
      _interaction.cancel();
    }
    if (_ownsInteraction) _interaction.dispose();
    super.dispose();
  }

  void _onTextEditChanged() {
    if (_textEditRect == null) return;
    _controller.setEditingTextSelection(_textEditText.selection);
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    final holdRevision = _controller.editingTextFocusHoldRevision;
    if (holdRevision != _textEditFocusHoldRevision) {
      _textEditFocusHoldRevision = holdRevision;
      if (_textEditRect != null &&
          !_controller.isEditingTextFocusCommitHeld &&
          !_textEditFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _textEditRect != null) _textEditFocus.requestFocus();
        });
      }
    }
    final editRevision = _controller.editSelectedTextRevision;
    if (editRevision != _editSelectedTextRevision) {
      _editSelectedTextRevision = editRevision;
      if (_textEditRect == null &&
          _controller.selectedAnnotationSlot?.$1 == widget.pageIndex &&
          _controller.selectedAnnotation?.subtype == 'FreeText') {
        final rect = _selectedViewRect;
        if (rect != null) _openTextEditor(rect, existing: true);
      }
    }
    if (_textEditRect == null) return;
    // a new box in flight follows the tune popup's box-level defaults live
    // (alignment, spacing, underline) instead of only picking them up on open
    if (!_textEditExisting && _textEditFieldName == null) {
      final align = _controller.preferences.textAlign;
      final ls = _controller.lineSpacing;
      final cs = _controller.charSpacing;
      final ul = _controller.textUnderline;
      final defaultUnderline = _textEditText.defaultStyle.underline;
      if (align != _textEditAlign ||
          ls != _textEditLineSpacing ||
          cs != _textEditCharSpacing ||
          (ul != defaultUnderline && !_textEditText.hasRichStyles)) {
        setState(() {
          _textEditAlign = align;
          _textEditLineSpacing = ls;
          _textEditCharSpacing = cs;
          if (ul != defaultUnderline && !_textEditText.hasRichStyles) {
            _textEditText.resetStyles(
                _textEditText.defaultStyle.merge(underline: ul));
          }
        });
      }
    }
    final revision = _controller.editingTextStyleRevision;
    if (revision == _textEditStyleRevision) return;
    _textEditStyleRevision = revision;
    final request = _controller.editingTextStyleRequest;
    if (request == null) return;
    // register an embedded font's bytes so the styled run previews in its
    // real face, not the fallback - covers the inline menu and a host that
    // drives restyleEditingTextSelection directly
    if (request.font is PdfEmbeddedFont) {
      _ensureEmbeddedFontPreview(request.font as PdfEmbeddedFont);
    }
    _textEditText.applyStyle(_textEditText.selection,
        font: request.font,
        size: request.size,
        color: request.color,
        underline: request.underline);
  }

  /// The chrome-handle geometry for a selection [rect] at the current
  /// [_chromeScale], carrying the resting [rotation] for the rotate knob.
  HandleLayout _handleLayout(Rect rect, [double rotation = 0]) => HandleLayout(
        rect: rect,
        rotation: rotation,
        chromeScale: _chromeScale,
        hitRadius: _handleHitRadius,
        rotateHandleDistance: _rotateHandleDistance,
      );

  /// The resize cursor for a handle by its corner/edge: orthogonal edges
  /// get the straight resize cursors, corners the matching diagonal.
  static MouseCursor _resizeCursorFor(_Handle handle) =>
      switch ((handle.dx, handle.dy)) {
        (0, _) => SystemMouseCursors.resizeUpDown,
        (_, 0) => SystemMouseCursors.resizeLeftRight,
        (-1, -1) || (1, 1) => SystemMouseCursors.resizeUpLeftDownRight,
        _ => SystemMouseCursors.resizeUpRightDownLeft,
      };

  _Handle? _handleAt(Rect rect, Offset position) {
    if (!_controller.canResizeSelected) return null;
    return _handleLayout(rect).handleAt(position);
  }

  int? _vertexHandleAt(List<Offset> points, Offset position) {
    if (!_controller.canResizeSelected) return null;
    for (var i = points.length - 1; i >= 0; i--) {
      if ((position - points[i]).distance <= _handleHitRadius * _chromeScale) {
        return i;
      }
    }
    return null;
  }

  /// Resize handles get first claim (the top-center knob sits close),
  /// so this is only consulted after [_handleAt] misses.
  bool _hitsRotateHandle(Rect rect, double rotation, Offset position) =>
      _controller.canRotateSelected &&
      _handleLayout(rect, rotation).hitsRotateHandle(position);

  /// The drag's rotation delta for the pointer at [position]: the angle
  /// swept about the selection center. The *total* rotation (resting +
  /// delta) snaps near 45° multiples, so a rotated annotation can snap
  /// back to square.
  double _rotationDelta(Rect selected, Offset position) {
    var delta = (position - selected.center).direction - _rotateStartAngle!;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta <= -math.pi) {
      delta += 2 * math.pi;
    }
    final total = _rotateResting + delta;
    final snapped = (total / (math.pi / 4)).round() * (math.pi / 4);
    return (total - snapped).abs() <= _rotateSnapRadians
        ? snapped - _rotateResting
        : delta;
  }

  /// The committed annotation re-rotates about the *new* local box's
  /// center, so a resize that moves the center would translate every
  /// un-dragged point by Δ − R(Δ). Shifting the local box by R(Δ) − Δ
  /// cancels that: the geometry opposite the drag stays anchored on
  /// screen and the dragged handle rides the pointer.
  Rect _anchorResized(Rect resized) {
    if (_resizeAngle == 0) return resized;
    final delta = resized.center - _resizeFrom!.center;
    return resized
        .shift(_rotatePoint(delta, Offset.zero, _resizeAngle) - delta);
  }

  /// The resized box, plus whether the drag inverted it horizontally /
  /// vertically. The returned rect is always normalized (positive
  /// width/height); a flip rides the booleans, so chrome and ghost layout
  /// stay simple. A handle dragged past the opposite edge crosses the 0
  /// point and the box flips out the other side (with the minimum size
  /// kept on the far side); aspect-locked drags (Shift) keep the old
  /// clamp-at-minimum and never flip.
  (Rect, bool, bool) _resizedRect(Rect from, _Handle handle, Offset delta,
      {double? aspectRatio}) {
    final minSize = _minSizeView * _chromeScale;
    var left = from.left, top = from.top;
    var right = from.right, bottom = from.bottom;
    if (handle.dx < 0) left += delta.dx;
    if (handle.dx > 0) right += delta.dx;
    if (handle.dy < 0) top += delta.dy;
    if (handle.dy > 0) bottom += delta.dy;

    if (aspectRatio != null && aspectRatio > 0) {
      // aspect-locked: keep the original clamp-at-minimum, never invert
      if (right - left < minSize) {
        if (handle.dx < 0) {
          left = right - minSize;
        } else {
          right = left + minSize;
        }
      }
      if (bottom - top < minSize) {
        if (handle.dy < 0) {
          top = bottom - minSize;
        } else {
          bottom = top + minSize;
        }
      }
      var width = right - left;
      var height = bottom - top;
      if (handle.dx != 0 && handle.dy != 0) {
        // corner: lock the off-axis to whichever side the pointer pushed
        // harder (relative to the original size), then re-anchor at the
        // fixed corner so the dragged corner tracks the pointer
        if (width / from.width >= height / from.height) {
          height = width / aspectRatio;
        } else {
          width = height * aspectRatio;
        }
        if (height < minSize) {
          height = minSize;
          width = height * aspectRatio;
        }
        if (width < minSize) {
          width = minSize;
          height = width / aspectRatio;
        }
        if (handle.dx < 0) {
          left = right - width;
        } else {
          right = left + width;
        }
        if (handle.dy < 0) {
          top = bottom - height;
        } else {
          bottom = top + height;
        }
      } else if (handle.dy == 0) {
        // vertical edge: width drives, height follows about the center
        height = math.max(width / aspectRatio, minSize);
        final cy = from.center.dy;
        top = cy - height / 2;
        bottom = cy + height / 2;
      } else {
        // horizontal edge: height drives, width follows about the center
        width = math.max(height * aspectRatio, minSize);
        final cx = from.center.dx;
        left = cx - width / 2;
        right = cx + width / 2;
      }
      return (Rect.fromLTRB(left, top, right, bottom), false, false);
    }

    // free resize: let the dragged edge cross its anchor and invert the
    // box. Keep |size| ≥ minSize on whichever side of 0 it currently sits
    // so it never collapses to a line.
    var flipX = false, flipY = false;
    if (handle.dx != 0) {
      var width = right - left;
      if (width.abs() < minSize) {
        width = width < 0 ? -minSize : minSize;
        if (handle.dx < 0) {
          left = right - width;
        } else {
          right = left + width;
        }
      }
      flipX = width < 0;
    }
    if (handle.dy != 0) {
      var height = bottom - top;
      if (height.abs() < minSize) {
        height = height < 0 ? -minSize : minSize;
        if (handle.dy < 0) {
          top = bottom - height;
        } else {
          bottom = top + height;
        }
      }
      flipY = height < 0;
    }
    return (
      Rect.fromLTRB(
        math.min(left, right),
        math.min(top, bottom),
        math.max(left, right),
        math.max(top, bottom),
      ),
      flipX,
      flipY,
    );
  }

  // -----------------------------------------------------------------
  // in-place text editing

  /// A default-sized view rect for a tap-to-place annotation, with its
  /// top-left at [tap]: ~200pt wide and one line of the current font tall
  /// (in page points, mapped through the zoom). Nudged back onto the page
  /// when the tap is near the right or bottom edge so the whole box fits.
  Rect _defaultPlacementRect(Offset tap) {
    final scale = _geometry.scale;
    final w = 200.0 * scale;
    final h = (_controller.preferences.fontSize * 1.6 + 8) * scale;
    final size = _geometry.viewSize;
    final left = tap.dx.clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    final top = tap.dy.clamp(0.0, math.max(0.0, size.height - h)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Opens the inline text editor over [viewRect] - empty for a fresh
  /// free-text box, prefilled from the selected annotation when
  /// [existing]. The editor renders with the same font, size, and color
  /// the committed annotation will use.
  void _openTextEditor(Rect viewRect, {required bool existing}) {
    final style = existing ? _controller.selectedTextStyle : null;
    // /DA carries the text color; /C is the box background for free text
    final annotation = existing ? _controller.selectedAnnotation : null;
    final parsed = annotation?.behavior.style.freeText;
    final annotationColor = annotation?.behavior.style.color;
    // an already-rotated box edits in its rotated frame: take the chrome's
    // un-rotated box + resting angle so the editor (and the committed
    // afterimage) ride the artwork, not its axis-aligned bounds
    var rect = viewRect;
    var rotation = 0.0;
    if (existing) {
      final chrome = _selectionChrome;
      if (chrome != null && chrome.$2 != 0) {
        rect = chrome.$1;
        rotation = chrome.$2;
      }
    }
    final defaultFont = existing
        ? (style?.font ?? _controller.fontFamily)
        : (_controller.activeFont ?? _controller.fontFamily);
    final defaultSize = style?.size ?? _controller.preferences.fontSize;
    final defaultColor = annotationColor != null
        ? Color(0xFF000000 | annotationColor)
        : _controller.color;
    final defaultUnderline =
        existing ? (parsed?.underline ?? false) : _controller.textUnderline;
    final fallbackStyle = _TextEditStyle(
        font: defaultFont,
        size: defaultSize,
        color: defaultColor,
        underline: defaultUnderline);
    // a box saved with mixed styling carries /RC: reseed its per-run fonts
    // so reopening shows the bold/italic/colour, not a flattened style
    final richRuns = existing ? _controller.selectedRichRuns : null;
    if (richRuns != null && richRuns.isNotEmpty) {
      _textEditText.seedRuns(richRuns, fallbackStyle);
    } else {
      _textEditText.resetStyles(fallbackStyle);
      _textEditText.text = existing ? (_controller.selectedText ?? '') : '';
    }
    setState(() {
      _textEditRect = rect;
      _textEditPageRect = _geometry.toPageRect(rect);
      _textEditRotation = rotation;
      _textEditExisting = existing;
      _textEditTool = _tool;
      _textEditFont =
          defaultFont is PdfStandardFont ? defaultFont : _controller.fontFamily;
      _textEditSize = defaultSize;
      _textEditColor = defaultColor;
      _textEditAlign = existing ? parsed?.alignment : _controller.preferences.textAlign;
      _textEditLineSpacing = existing
          ? (parsed?.lineSpacing ?? kPdfFreeTextDefaultLineSpacing)
          : _controller.lineSpacing;
      _textEditCharSpacing =
          existing ? (parsed?.charSpacing ?? 0) : _controller.charSpacing;
      _textEditFill = existing
          ? (parsed?.fillColor != null
              ? Color(0xFF000000 | parsed!.fillColor!)
              : null)
          : _controller.preferences.textFillColor;
    });
    _beginInteraction(PdfEditingInteractionIntent.text, _lastPointerKind);
    _controller.setEditingText(true);
    // the field's autofocus is ignored: the creating gesture's
    // pointer-down put primary focus on the viewer's own node, and
    // autofocus only fires into an unfocused scope - claim it so typing
    // lands in the fresh box without clicking into it first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _textEditRect != null) _textEditFocus.requestFocus();
    });
  }

  /// Opens the inline text editor for a callout: the same box editor as
  /// free text, but remembering the page-space [target] the leader line will
  /// point at so the commit builds a callout instead of a plain box.
  void _openCalloutEditor(Rect viewRect, Offset terminus) {
    _textEditCalloutTarget = _geometry.toPagePoint(terminus);
    _openTextEditor(viewRect, existing: false);
  }

  /// The nearest point on [box]'s perimeter to [p] (view space, y-down) -
  /// where the leader meets the box before the base is pinned.
  static Offset _nearestBoxEdge(Rect box, Offset p) {
    if (p.dx < box.left) {
      return Offset(box.left, p.dy.clamp(box.top, box.bottom));
    }
    if (p.dx > box.right) {
      return Offset(box.right, p.dy.clamp(box.top, box.bottom));
    }
    if (p.dy < box.top) return Offset(p.dx.clamp(box.left, box.right), box.top);
    if (p.dy > box.bottom) {
      return Offset(p.dx.clamp(box.left, box.right), box.bottom);
    }
    return box.center;
  }

  /// The leader (terminus, base, color, width) to keep painted so a callout's
  /// arrow stays visible: while a terminus/base handle is being dragged, and
  /// while the box editor is open placing a new one. Null otherwise.
  (Offset, Offset, Color, double)? _calloutLeaderPreview() {
    if (_vertexHandle != null && _vertexPoints != null) {
      final annotation = _controller.selectedAnnotation;
      final box = _selectedViewRect;
      if (annotation != null &&
          annotation.isCallout &&
          box != null &&
          _vertexPoints!.isNotEmpty) {
        final style = annotation.freeTextStyle;
        final rgb = style?.borderColor ?? style?.color ?? 0x000000;
        final width = (style?.borderWidth ?? 1) * _geometry.scale;
        final terminus = _vertexPoints!.first;
        final base = _vertexPoints!.length > 1
            ? _vertexPoints![1]
            : _nearestBoxEdge(box, terminus);
        return (
          terminus,
          base,
          Color(0xFF000000 | rgb),
          width > 0 ? width : _geometry.scale,
        );
      }
    }
    if (_textEditCalloutTarget != null && _textEditRect != null) {
      final terminus = _geometry.toViewOffset(
          _textEditCalloutTarget!.$1, _textEditCalloutTarget!.$2);
      return (
        terminus,
        _nearestBoxEdge(_textEditRect!, terminus),
        _controller.preferences.textBorderColor ?? _controller.color,
        _controller.preferences.strokeWidth * _geometry.scale,
      );
    }
    return null;
  }

  /// Opens the inline editor over a text field's widget, prefilled with
  /// its value - the form tool's tap-to-fill. The commit goes into the
  /// field's /V instead of creating an annotation.
  void _openFormTextEditor(PdfFormField field, int widgetIndex) {
    final rect = field.widgetRect(widgetIndex);
    if (rect == null) return;
    final tf = RegExp(r'/(\S+)\s+(\d+(?:\.\d+)?)\s+Tf')
        .firstMatch(field.defaultAppearance ?? '');
    final size = double.tryParse(tf?.group(2) ?? '') ?? 0;
    final formFont = tf == null
        ? PdfStandardFont.helvetica
        : PdfStandardFont.fromName(tf.group(1)!);
    final formSize = size > 0 ? size : 12.0;
    _textEditText.resetStyles(_TextEditStyle(
        font: formFont, size: formSize, color: const Color(0xFF000000)));
    _textEditText.text = field.value ?? '';
    setState(() {
      _textEditRect = _geometry.toViewRect(rect);
      _textEditPageRect = rect;
      _textEditRotation = 0;
      _textEditExisting = false;
      _textEditTool = _tool;
      _textEditFieldName = field.name;
      _textEditMultiline = field.isMultiline;
      _textEditFont = formFont;
      // an auto-size /DA (0 Tf) edits at a readable default; the
      // committed appearance derives its own size as usual
      _textEditSize = formSize;
      _textEditColor = const Color(0xFF000000);
      _textEditFill = null;
    });
    _beginInteraction(PdfEditingInteractionIntent.text, _lastPointerKind);
    _controller.setEditingText(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _textEditRect != null) _textEditFocus.requestFocus();
    });
  }

  /// Commits the editor's text: a new free-text annotation, the
  /// selected one rewritten, or - for the form tool - the field's new
  /// value. Empty text adds nothing / changes nothing.
  void _commitTextEdit() {
    if (_textEditRect == null) return;
    final before = _controller.document;
    final transition = _interaction.state.transition;
    _finishTextEdit();
    _finishInteraction(before, transition);
  }

  void _finishTextEdit() {
    final rect = _textEditRect;
    if (rect == null) return;
    final fieldName = _textEditFieldName;
    if (fieldName != null) {
      // form fields: empty is a legitimate value (clearing the field)
      final value = _textEditText.text;
      final font = _textEditFont;
      final size = _textEditSize;
      _closeTextEditor();
      final before = _controller.document;
      _controller.setFormFieldText(fieldName, value);
      if (identical(before, _controller.document)) return;
      _clearAfterimage();
      _afterText = (
        rect: rect,
        text: value,
        font: font,
        size: size,
        color: const Color(0xFF000000),
        fill: null,
        washed: true, // cover the old value until the raster lands
        rotation: 0,
        align: PdfTextAlign.left,
        underline: false,
        lineSpacing: kPdfFreeTextDefaultLineSpacing,
      );
      _afterDocument = _controller.document;
      return;
    }
    final text = _textEditText.text.trimRight();
    final existing = _textEditExisting;
    final richRuns =
        _textEditText.hasRichStyles ? _textEditText.toPdfRuns() : null;
    final font = _textEditFont;
    final size = _textEditSize;
    final color = _textEditColor;
    final fill = _textEditFill;
    final rotation = _textEditRotation;
    final calloutTarget = _textEditCalloutTarget;
    _closeTextEditor();
    final before = _controller.document;
    if (existing) {
      if (text.isNotEmpty && richRuns != null) {
        _controller.setSelectedRichText(richRuns);
      } else if (text.isNotEmpty && text != _controller.selectedText) {
        _controller.setSelectedText(text);
      }
    } else if (text.isNotEmpty) {
      if (calloutTarget != null) {
        _controller.addCallout(
            widget.pageIndex, _geometry.toPageRect(rect), text, calloutTarget);
      } else if (richRuns != null) {
        _controller.addFreeTextRich(
            widget.pageIndex, _geometry.toPageRect(rect), richRuns);
      } else {
        _controller.addFreeText(
            widget.pageIndex, _geometry.toPageRect(rect), text);
      }
    }
    if (identical(before, _controller.document)) return;
    // the editor's rendering, frozen until the new revision's raster
    // lands - otherwise the text vanishes for the render's duration
    _clearAfterimage();
    _afterText = (
      rect: rect,
      text: text,
      font: font,
      size: size,
      color: color,
      fill: fill,
      washed: existing,
      rotation: rotation,
      align: _textEditAlign,
      underline: _textEditText.defaultStyle.underline,
      lineSpacing: _textEditLineSpacing,
    );
    _afterDocument = _controller.document;
  }

  void _cancelTextEdit() {
    final transition = _interaction.state.transition;
    _closeTextEditor();
    final state = _interaction.state;
    if (state.transition == transition && _interaction.isActive) {
      _interaction.cancel();
    }
  }

  /// What Escape does to the open editor. It must never destroy a box: a
  /// brand-new free-text box keeps what was typed (an empty one just adds
  /// nothing on close), matching the desktop convention where Escape
  /// *finishes* the box rather than throwing it away - discarding it read
  /// as Escape "deleting" the annotation you'd just placed. An existing box
  /// or a form field reverts to its saved value instead (a real cancel,
  /// and still non-destructive - the box stays).
  void _onEscapeTextEdit() {
    if (_textEditExisting || _textEditFieldName != null) {
      _cancelTextEdit();
    } else {
      _commitTextEdit();
    }
  }

  /// Escape ends the inline editor straight from the field's focus node, so
  /// it fires even on platforms/states where the ancestor
  /// `CallbackShortcuts` never sees the key (e.g. the field's own editing
  /// actions swallow it). Returning `handled` stops the duplicate
  /// `CallbackShortcuts` binding from also running; every other key falls
  /// through to normal text input.
  KeyEventResult _onTextEditKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _textEditRect != null) {
      _onEscapeTextEdit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _closeTextEditor() {
    if (_textEditRect == null) return;
    // whether the editor still owned the keyboard: a close driven by Escape,
    // ⌘Enter, or a tap on the page arrives with focus still on the field; a
    // close because the user clicked another widget (e.g. a toolbar field)
    // does not - that new focus must be left alone
    final ownedFocus = _textEditFocus.hasFocus;
    _textEditCalloutTarget = null;
    if (mounted) {
      setState(() {
        _textEditRect = null;
        _textEditPageRect = null;
        _textEditFieldName = null;
      });
    } else {
      _textEditRect = null;
      _textEditPageRect = null;
      _textEditFieldName = null;
    }
    _controller.setEditingText(false);
    // hand the keyboard back so the viewer's shortcuts work again right away
    // (Escape → back out the tool, V/P/R tool keys, delete): the removed
    // field's focus node otherwise leaves focus in limbo and the next key
    // reaches nothing. Prefer the viewer's own node (via onTextEditClosed)
    // so a *second* Escape lands on its handler; fall back to a plain
    // unfocus in hosts that supply no hook. rect is already null, so the
    // focus-loss listener's commit is a no-op.
    if (ownedFocus) {
      if (_host.textEditClosed != null) {
        _host.textEditClosed!();
      } else if (_textEditFocus.hasFocus) {
        _textEditFocus.unfocus();
      }
    }
  }

  /// Losing focus commits - tapping another widget, switching panes.
  /// (Escape cancels first, so by the time the unfocus arrives the
  /// session is already gone and this is a no-op.)
  void _onTextEditFocus() {
    if (!_textEditFocus.hasFocus &&
        !_textEditStyleMenuOpen &&
        !_controller.isEditingTextFocusCommitHeld) {
      _commitTextEdit();
    }
  }

  /// Holds the inline editor's focus while a pointer is down on the style
  /// chip, so a chip tap on mobile (which blurs the field) can't trip the
  /// focus-loss commit and deselect the box before the button runs.
  void _holdChipFocus() {
    if (_chipFocusHeld || _textEditRect == null) return;
    _chipFocusHeld = true;
    _controller.beginEditingTextFocusHold();
  }

  void _releaseChipFocus() {
    if (!_chipFocusHeld) return;
    // pointer-up fires before the button's onPressed, so defer to the next
    // frame: by then the button's style change has run against the live
    // selection. Restore the keyboard to the field (unless a colour/font
    // menu now owns it) and drop the hold so a later real blur commits.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chipFocusHeld) return;
      _chipFocusHeld = false;
      if (mounted && _textEditRect != null && !_textEditStyleMenuOpen) {
        _textEditFocus.requestFocus();
      }
      _controller.endEditingTextFocusHold();
    });
  }

  void _panStart(DragStartDetails details) {
    // raw-driven pointers own their gesture: the pan recognizer still
    // claims the arena (keeping the viewer's pan/zoom from fighting the
    // stroke) but its callbacks must not double-drive it
    if (_pointers.gestureBailed || _rawDrives(details.kind)) return;
    final position = details.localPosition;
    if (_textEditRect != null) {
      // a drag outside the open editor commits it, like a tap
      _commitTextEdit();
      return;
    }
    if (_stampPreview != null) {
      setState(() => _stampPreview = null);
    }
    if (_selectMode) {
      _selectPanStart(details);
      return;
    }
    if (_cloudPolyInProgress) {
      // committing a cloud by clicks: a stray drag must not rubber-band a
      // rectangle over the vertices already placed
      return;
    }
    switch (_tool) {
      case null:
        break; // eyedropper only - taps, no drags
      case PdfEditTool.select:
        break; // handled by _selectPanStart above
      case PdfEditTool.eraser:
        // mouse/trackpad erase through the arena like any drag
        _beginInteraction(PdfEditingInteractionIntent.erase, details.kind);
        _panErasing = true;
        _eraseAt(position);
      case PdfEditTool.ink || PdfEditTool.highlight:
        _beginInteraction(PdfEditingInteractionIntent.ink, details.kind);
        // hold the auto-commit while this stroke is on the page
        _controller.beginInkStroke();
        final pressure = _pointerPressure;
        // While the mouse is pressed, hover events stop. Keep the painted
        // pen cursor's stored position moving with the drag so it reappears
        // at the stroke end, not where the stroke started.
        _penCursor = position;
        // no setState: the active stroke lives on its own repaint layer
        _activeStroke = [_geometry.toPagePoint(position)];
        // the first event decides: a pressure device varies the whole
        // stroke, anything else stays uniform
        _activeStrokePressures = pressure == null ? null : [pressure];
        _bumpActiveStroke();
      case PdfEditTool.rectangle ||
            PdfEditTool.ellipse ||
            PdfEditTool.cloudPolygon ||
            PdfEditTool.line ||
            PdfEditTool.arrow ||
            PdfEditTool.measureDistance ||
            PdfEditTool.measureSlope ||
            PdfEditTool.calibrate ||
            PdfEditTool.freeText ||
            PdfEditTool.callout ||
            PdfEditTool.stamp ||
            PdfEditTool.image ||
            PdfEditTool.redact ||
            PdfEditTool.snapshot ||
            PdfEditTool.signatureBox:
        _beginInteraction(PdfEditingInteractionIntent.create, details.kind);
        setState(() {
          _dragStart = position;
          _dragCurrent = position;
        });
      case PdfEditTool.form:
        // a resize handle or the body of the selected widget manipulates
        // it; a press on another widget grabs it (select + move in one
        // drag); empty page area drags out a new field
        final (x, y) = _geometry.toPagePoint(position);
        final selectedRect = _selectedViewRect;
        final onHandle = selectedRect != null &&
            _controller.canResizeSelected &&
            _handleAt(selectedRect, position) != null;
        if (onHandle || (selectedRect?.contains(position) ?? false)) {
          _selectPanStart(details);
          return;
        }
        final hit = _controller.selectableWidgetAt(widget.pageIndex, x, y);
        if (hit != null) {
          if (!_controller.isAnnotationSelected(widget.pageIndex, hit.$1)) {
            _controller.selectFormWidgetAt(widget.pageIndex, x, y);
          }
          setState(() {
            _moveStart = position;
            _moveCurrent = position;
          });
          _beginInteraction(PdfEditingInteractionIntent.move, details.kind);
          return;
        }
        if (_controller.formFieldAt(widget.pageIndex, x, y) == null) {
          _beginInteraction(PdfEditingInteractionIntent.create, details.kind);
          setState(() {
            _dragStart = position;
            _dragCurrent = position;
          });
        }
      case PdfEditTool.signature:
        // press-drag-release placement: the preview rides the pointer
        // (touch has no hover), release commits where it landed
        if (_controller.preferences.signature != null) {
          _beginInteraction(
              PdfEditingInteractionIntent.signature, details.kind);
          setState(() {
            _signatureDrag = true;
            _signaturePreview = position;
          });
        }
      case PdfEditTool.polyline ||
            PdfEditTool.polygon ||
            PdfEditTool.measurePerimeter ||
            PdfEditTool.measureArea ||
            PdfEditTool.measureAngle ||
            PdfEditTool.measureArc ||
            PdfEditTool.measureVolume:
        break; // taps add vertices; double-tap finishes
      case PdfEditTool.note || PdfEditTool.content || PdfEditTool.count:
        break; // driven by taps
    }
  }

  /// Select-mode drags, by what's under the press: a handle resizes, the
  /// rotate knob spins, a selected annotation moves the whole selection,
  /// an unselected one is selected and moved in the same drag. Empty
  /// page area drags a rubber band with a mouse and pans the viewer with
  /// touch (so the document stays scrollable while selecting).
  void _selectPanStart(DragStartDetails details) {
    final position = details.localPosition;
    final selected = _selectedViewRect;
    final chrome = _selectionChrome;
    final resting = chrome?.$2 ?? 0;
    if (selected != null) {
      final vertexPoints = _selectedVertexPoints;
      final vertex =
          vertexPoints == null ? null : _vertexHandleAt(vertexPoints, position);
      if (vertex != null) {
        _beginInteraction(PdfEditingInteractionIntent.reshape, details.kind);
        setState(() {
          _vertexHandle = vertex;
          _vertexPoints = List<Offset>.of(vertexPoints!);
        });
        return;
      }
      // a rotated selection resizes in its local frame: hit-test the
      // handles where they're drawn (on the spun chrome box) by
      // unrotating the pointer about the chrome center
      final handle = _selectedLineFamily
          ? null
          : resting == 0 || chrome == null
              ? _handleAt(selected, position)
              : _handleAt(chrome.$1,
                  _rotatePoint(position, chrome.$1.center, -resting));
      if (handle != null) {
        _beginInteraction(PdfEditingInteractionIntent.resize, details.kind);
        setState(() {
          _resizeHandle = handle;
          _resizeFrom = resting == 0 ? selected : chrome!.$1;
          _resizeRect = _resizeFrom;
          _resizeAngle = resting;
          _resizeFlipX = false;
          _resizeFlipY = false;
          _moveStart = position;
          _moveCurrent = position;
          // hold the matching resize cursor through the drag (hover stops
          // firing once the pointer is down)
          _cursor = _resizeCursorFor(handle);
        });
        // lift the box off the page for a re-wrapping (free-text) resize:
        // render the page without it so the preview floats over the real
        // content behind, not an opaque wash
        if (_textResizeStyle != null) _renderResizeClean();
        return;
      }
      if (chrome != null && _hitsRotateHandle(chrome.$1, resting, position)) {
        _beginInteraction(PdfEditingInteractionIntent.rotate, details.kind);
        setState(() {
          _rotateStartAngle = (position - selected.center).direction;
          _rotateResting = resting;
          _rotateDelta = 0;
          // keep the painted rotation glyph riding the pointer mid-drag
          _rotateCursor = position;
          _cursor = SystemMouseCursors.none;
        });
        return;
      }
    }
    // dragging any selected annotation moves the whole selection
    for (final rect in _selectedViewRects) {
      if (rect.contains(position)) {
        _beginInteraction(PdfEditingInteractionIntent.move, details.kind);
        setState(() {
          _moveStart = position;
          _moveCurrent = position;
          _cursor = SystemMouseCursors.move; // 4-arrow while dragging
        });
        _ensureSourceClean();
        return;
      }
    }
    final (x, y) = _geometry.toPagePoint(position);
    if (_controller.selectableAnnotationAt(widget.pageIndex, x, y) != null) {
      // grab an unselected annotation: select it and move it in one drag
      _controller.selectAnnotationAt(widget.pageIndex, x, y);
      _beginInteraction(PdfEditingInteractionIntent.move, details.kind);
      setState(() {
        _moveStart = position;
        _moveCurrent = position;
        _cursor = SystemMouseCursors.move;
      });
      _ensureSourceClean();
      return;
    }
    final mouseLike = details.kind == null ||
        details.kind == PointerDeviceKind.mouse ||
        details.kind == PointerDeviceKind.trackpad;
    if (mouseLike) {
      _beginInteraction(PdfEditingInteractionIntent.marquee, details.kind);
      setState(() {
        _marqueeStart = position;
        _marqueeCurrent = position;
        _marqueeAdd = _additiveModifier;
      });
    } else if (_host.panViewport != null) {
      pdfLogGesture('overlay viewport-pan START',
          () => 'page=${widget.pageIndex} kind=${details.kind?.name}');
      _beginInteraction(
          PdfEditingInteractionIntent.viewportPan, details.kind);
      _viewportPanning = true;
    }
  }

  /// Whether a touch/stylus long-press at [position] would open an
  /// annotation context menu - checked on pointer DOWN (the recognizer only
  /// joins the arena when this is true), so a long-press that has nothing to
  /// offer never steals the gesture from text selection or the viewer. Form
  /// fields use selection + toolbar controls instead of a long-press menu.
  ///
  /// Note: the host's [contextMenuEnabled] gate lives in [_onMenuLongPress]
  /// itself, not here - this predicate decides *gesture ownership*, so it
  /// must mirror the no-op case (nothing to select, no clipboard) regardless
  /// of the menu toggle, otherwise long-press selection silently dies when
  /// the menu is suppressed.
  bool _menuLongPressClaims(Offset position) {
    if (_pointers.gestureBailed) return false;
    final (x, y) = _geometry.toPagePoint(position);
    if (_tool == PdfEditTool.form) return false;
    if (!_selectMode || _host.showAnnotationMenu == null) {
      return false;
    }
    return _controller.selectableAnnotationAt(widget.pageIndex, x, y) != null ||
        _controller.hasAnnotationClipboard;
  }

  /// Touch/stylus long-press: the context menu mice reach by
  /// right-clicking. A pressed annotation joins the selection first
  /// (an already-selected one keeps a multi-selection intact); empty
  /// page area opens the paste menu when the clipboard has content.
  ///
  /// When [contextMenuEnabled] is false the press still selects the
  /// annotation (or, with a clipboard, still bails out the same way) -
  /// only the popup is suppressed.
  void _onMenuLongPress(LongPressStartDetails details) {
    final position = details.localPosition;
    final (x, y) = _geometry.toPagePoint(position);
    final hit = _controller.selectableAnnotationAt(widget.pageIndex, x, y);
    if (hit != null) {
      if (!_controller.isAnnotationSelected(widget.pageIndex, hit.$1)) {
        _controller.selectAnnotationAt(widget.pageIndex, x, y);
      }
    } else if (!_controller.hasAnnotationClipboard) {
      return;
    }
    HapticFeedback.selectionClick();
    if (!widget.contextMenuEnabled) return;
    _host.showAnnotationMenu
        ?.call(details.globalPosition, widget.pageIndex, pagePoint: (x, y));
  }

  void _panUpdate(DragUpdateDetails details) {
    if (_pointers.gestureBailed || _pointers.rawPointer != null) return;
    final position = details.localPosition;
    _interaction.sample();
    if (_panErasing) {
      _eraseAt(position);
      return;
    }
    if (_viewportPanning) {
      _host.panViewport?.call(details.delta);
      return;
    }
    if (_signatureDrag) {
      setState(() => _signaturePreview = position);
      return;
    }
    if (_activeStroke != null) {
      // hot path: append + repaint the stroke layer only, no rebuild
      _penCursor = position;
      _activeStroke!.add(_geometry.toPagePoint(position));
      _activeStrokePressures
          ?.add(_pointerPressure ?? _activeStrokePressures!.last);
      _bumpActiveStroke();
      return;
    }
    // region/selection drags (marquee, move, resize, vertex, shape/snapshot
    // rect, rotate) track their current point in view space. Record the
    // pointer's global position too: an edge auto-scroll tick re-derives the
    // view-space point from it as the page scrolls under a held pointer.
    _autoScrollGlobal = details.globalPosition;
    _autoScrollLastLocal = position;
    _applyDragPosition(position);
    _maybeAutoScroll();
  }

  /// Applies a region drag's current pointer (view space) to whichever drag
  /// is in flight - shared by [_panUpdate] and the edge auto-scroll tick so a
  /// held pointer keeps tracking the page as it scrolls underneath.
  void _applyDragPosition(Offset position) {
    if (_marqueeStart != null) {
      setState(() => _marqueeCurrent = position);
    } else if (_rotateStartAngle != null) {
      final selected = _selectedViewRect;
      if (selected == null) return;
      setState(() {
        _rotateDelta = _rotationDelta(selected, position);
        _rotateCursor = position; // the glyph follows the pointer
      });
    } else if (_vertexHandle != null) {
      setState(() {
        final points = List<Offset>.of(_vertexPoints!);
        points[_vertexHandle!] = position;
        _vertexPoints = points;
      });
    } else if (_resizeHandle != null) {
      setState(() {
        _moveCurrent = position;
        // a rotated selection's handles move along its own axes, so the
        // pointer delta rotates into the local frame
        final delta = position - _moveStart!;
        // holding Shift locks the original aspect ratio
        final aspectRatio =
            HardwareKeyboard.instance.isShiftPressed && _resizeFrom!.height > 0
                ? _resizeFrom!.width / _resizeFrom!.height
                : null;
        final (resized, flipX, flipY) = _resizedRect(
            _resizeFrom!,
            _resizeHandle!,
            _resizeAngle == 0
                ? delta
                : _rotatePoint(delta, Offset.zero, -_resizeAngle),
            aspectRatio: aspectRatio);
        _resizeFlipX = flipX;
        _resizeFlipY = flipY;
        _resizeRect = _anchorResized(resized);
      });
    } else if (_moveStart != null) {
      _moveCurrentGlobal = _autoScrollGlobal;
      setState(() => _moveCurrent = position);
      // float the artwork above every page so a move dragged onto the
      // page below isn't clipped behind it (this overlay can't paint
      // over a sibling list item)
      _reportMovePreview();
    } else if (_dragStart != null) {
      setState(() => _dragCurrent = position);
    }
  }

  /// Drags whose region keeps growing while the pointer sits against the
  /// viewport edge (and the viewer auto-scrolls under it).
  bool get _autoScrollDragActive =>
      _marqueeStart != null ||
      _moveStart != null ||
      _resizeHandle != null ||
      _vertexHandle != null ||
      _dragStart != null;

  /// Runs the edge auto-scroll ticker for an in-flight region drag. The
  /// ticker runs for the whole drag (not only at the edge) so a manual
  /// shift-scroll mid-drag also re-tracks the held pointer onto the
  /// newly revealed content.
  void _maybeAutoScroll() {
    if (_host.edgeAutoScroll == null ||
        _host.panViewport == null) {
      return;
    }
    if (!_autoScrollDragActive) return;
    if (!_autoScrollTicker.isActive) _autoScrollTicker.start();
  }

  void _stopAutoScroll() {
    if (_autoScrollTicker.isActive) _autoScrollTicker.stop();
    _autoScrollGlobal = null;
    _autoScrollLastLocal = null;
  }

  void _onAutoScrollTick(Duration _) {
    final global = _autoScrollGlobal;
    if (global == null || !_autoScrollDragActive) {
      _stopAutoScroll();
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // Re-derive the view-space pointer: the page may have scrolled under a
    // held pointer (the edge auto-scroll below, or a manual shift-scroll), so
    // the same global point now lands on different content - grow the drag to
    // it. The guard skips redundant rebuilds when nothing moved.
    final local = box.globalToLocal(global);
    if (local != _autoScrollLastLocal) {
      _autoScrollLastLocal = local;
      _interaction.sample();
      _applyDragPosition(local);
    }
    // Keep scrolling while the pointer rests in the viewport's edge band.
    final delta = _host.edgeAutoScroll!(global);
    if (delta != Offset.zero) _host.panViewport!(delta);
  }

  void _panEnd(DragEndDetails details) {
    if (_pointers.rawPointer != null) return; // the raw pointer-up commits
    final before = _controller.document;
    final transition = _interaction.state.transition;
    _finishPan(details);
    _finishInteraction(before, transition);
  }

  void _finishPan(DragEndDetails details) {
    if (_panErasing) {
      _panErasing = false;
      _commitErase();
      return;
    }
    final stroke = _activeStroke;
    final strokePressures = _activeStrokePressures;
    final dragStart = _dragStart;
    final dragCurrent = _dragCurrent;
    final moveStart = _moveStart;
    final moveCurrent = _moveCurrent;
    final moveCurrentGlobal = _moveCurrentGlobal;
    final resizeRect = _resizeHandle != null ? _resizeRect : null;
    final resizeAngle = _resizeAngle;
    final resizeFlipX = _resizeFlipX;
    final resizeFlipY = _resizeFlipY;
    final vertexPoints = _vertexHandle != null ? _vertexPoints : null;
    final vertexHandle = _vertexHandle;
    final rotating = _rotateStartAngle != null;
    final rotateDelta = _rotateDelta;
    final marquee = _marqueeStart != null && _marqueeCurrent != null
        ? Rect.fromPoints(_marqueeStart!, _marqueeCurrent!)
        : null;
    final marqueeAdd = _marqueeAdd;
    final panned = _viewportPanning;
    final signaturePlace = _signatureDrag ? _signaturePreview : null;
    // a free-text resize lifts the original box out of the page so the drag
    // shows real content behind a transparent box; detach that lift (taking
    // ownership from [_clearResizeClean]) so the commit afterimage can keep
    // it up until the new raster lands - without it a transparent box
    // flashes opaque paper on release
    final textResizing = resizeRect != null && _textResizeStyle != null;
    final liftClean = textResizing ? _resizeCleanPicture : null;
    final liftHideRect = textResizing ? _resizeFrom : null;
    final liftHideAngle = _resizeAngle;
    if (liftClean != null) {
      _resizeCleanPicture = null; // ownership transferred; don't dispose it
      _resizeCleanFor = null;
    }
    setState(() {
      _activeStroke = null;
      _activeStrokePressures = null;
      _dragStart = null;
      _dragCurrent = null;
      _moveStart = null;
      _moveCurrent = null;
      _moveCurrentGlobal = null;
      _resizeHandle = null;
      _resizeFrom = null;
      _resizeRect = null;
      _resizeAngle = 0;
      _resizeFlipX = false;
      _resizeFlipY = false;
      _vertexHandle = null;
      _vertexPoints = null;
      _rotateStartAngle = null;
      _rotateDelta = 0;
      _rotateCursor = null;
      _marqueeStart = null;
      _marqueeCurrent = null;
      _marqueeAdd = false;
      _viewportPanning = false;
      _signatureDrag = false;
      // drop any drag cursor; the next hover recomputes it
      _cursor = MouseCursor.defer;
    });
    _stopAutoScroll();
    // the in-flight lift is done; the afterimage covers the commit gap
    _clearResizeClean();
    // the floating move preview hands off to the commit's afterimage (or
    // the new page's raster for a cross-page drop)
    _host.moveDragPreview?.call(null);
    _bumpActiveStroke();

    if (panned) {
      // momentum: the fling continues in the viewer, which owns the
      // scroll position and zoom window this pan was feeding
      _host.endViewportPan?.call(details.velocity);
      return;
    }
    if (signaturePlace != null) {
      _placeSignature(signaturePlace);
      return;
    }
    if (marquee != null) {
      if (marquee.width < 4 && marquee.height < 4) return; // a click
      _controller.selectAnnotationsIn(
          widget.pageIndex, _geometry.toPageRect(marquee),
          add: marqueeAdd);
      return;
    }
    if (rotating) {
      // view-space clockwise (y down) is page-space clockwise, and PDF
      // rotation is counterclockwise-positive - hence the sign flip
      _commitWithGhost(
          () => _controller.rotateSelected(-rotateDelta * 180 / math.pi),
          to: _selectedViewRect,
          rotation: rotateDelta);
    } else if (vertexPoints != null) {
      _commitVertexDrag(vertexPoints, handle: vertexHandle);
    } else if (resizeRect != null) {
      final wrapStyle = _textResizeStyle;
      // captured before the commit: a Square/Circle regenerates at a
      // constant stroke width, so its afterimage must too (the stretch
      // ghost would thicken the line until the raster lands)
      final shapeStyle = _shapeResizeStyle(resizeRect, resizeAngle);
      void commit() => resizeAngle == 0
          ? _controller.resizeSelected(_geometry.toPageRect(resizeRect),
              flipX: resizeFlipX, flipY: resizeFlipY)
          : _controller.resizeSelectedLocal(_geometry.toPageRect(resizeRect),
              flipX: resizeFlipX, flipY: resizeFlipY);
      if (wrapStyle != null) {
        // the commit re-wraps the text at constant size - a stretched
        // ghost afterimage would show scaled glyphs, so freeze the same
        // wrapped-text preview the drag showed instead
        final before = _controller.document;
        commit();
        if (!identical(before, _controller.document)) {
          _clearAfterimage();
          _afterText = (
            rect: resizeRect,
            text: wrapStyle.text,
            font: wrapStyle.font,
            size: wrapStyle.size,
            color: wrapStyle.color,
            fill: wrapStyle.fill,
            // with the lift up the box keeps its true (maybe transparent)
            // fill and the lift hides the old footprint; only without a
            // lift does it fall back to the opaque-paper wash
            washed: liftClean == null,
            rotation: resizeAngle,
            align: wrapStyle.align,
            underline: wrapStyle.underline,
            lineSpacing: wrapStyle.lineSpacing,
          );
          _afterTextClean = liftClean;
          _afterTextHideRect = liftHideRect;
          _afterTextHideAngle = liftHideAngle;
          _afterDocument = _controller.document;
        } else {
          liftClean?.dispose(); // no commit: don't leak the detached lift
        }
      } else if (shapeStyle != null) {
        // the commit regenerates the shape at a constant stroke width -
        // freeze the same constant-width preview the drag showed
        final before = _controller.document;
        commit();
        if (!identical(before, _controller.document)) {
          _clearAfterimage();
          _afterShapeResize = shapeStyle;
          _afterDocument = _controller.document;
        }
      } else if (resizeAngle == 0) {
        _commitWithGhost(commit,
            to: resizeRect, flipX: resizeFlipX, flipY: resizeFlipY);
      } else {
        // the dragged rect is the local box; the editor re-applies the
        // resting rotation about its center
        _commitWithGhost(commit,
            to: resizeRect,
            localAngle: resizeAngle,
            flipX: resizeFlipX,
            flipY: resizeFlipY);
      }
    } else if (moveStart != null && moveCurrent != null) {
      if ((moveCurrent - moveStart).distance < 2) return; // a click
      // mapping both endpoints keeps the delta correct on rotated pages
      final (x0, y0) = _geometry.toPagePoint(moveStart);
      // a single-annotation move dropped over a *different* page re-homes
      // it there (drawn on top) instead of leaving it off this page's crop
      // box, behind the neighbour
      final resolve = _host.resolvePagePoint;
      if (resolve != null &&
          moveCurrentGlobal != null &&
          _controller.selectedAnnotationSlots.length == 1) {
        final drop = resolve(moveCurrentGlobal);
        if (drop != null && drop.$1 != widget.pageIndex) {
          _controller.moveSelectedToPage(drop.$1, drop.$2 - x0, drop.$3 - y0);
          return;
        }
      }
      final (x1, y1) = _geometry.toPagePoint(moveCurrent);
      // Wash the old spot so the stale raster does not leave a second copy
      // behind while the committed revision re-renders.
      _commitWithGhost(() => _controller.moveSelected(x1 - x0, y1 - y0),
          to: _selectedViewRect?.shift(moveCurrent - moveStart));
    } else if (stroke != null && stroke.isNotEmpty) {
      _controller.addInkStroke(widget.pageIndex, stroke,
          pressures: strokePressures);
    } else if (dragStart != null && dragCurrent != null) {
      final viewRect = Rect.fromPoints(dragStart, dragCurrent);
      if (_lineDragTool) {
        if ((dragCurrent - dragStart).distance < 4) return; // a click
        _commitLineDrag(dragStart, dragCurrent);
        return;
      }
      if (_tool == PdfEditTool.callout) {
        // the drag draws the leader: press at the terminus, release where
        // the box goes. A too-short drag drops a default-offset box.
        final short = (dragCurrent - dragStart).distance < 8;
        final anchor = short ? dragStart + const Offset(28, -28) : dragCurrent;
        _openCalloutEditor(_defaultPlacementRect(anchor), dragStart);
        return;
      }
      if (viewRect.width < 4 || viewRect.height < 4) return; // a click
      if (_tool == PdfEditTool.freeText) {
        // type into the box just dragged out, instead of a dialog
        _openTextEditor(viewRect, existing: false);
      } else {
        _commitRect(viewRect);
      }
    }
  }

  /// Places the saved signature at the view-space [position] and keeps
  /// its preview painted as the afterimage while the page re-renders.
  void _placeSignature(Offset position) {
    final (x, y) = _geometry.toPagePoint(position);
    final placement = _controller.signaturePlacement(widget.pageIndex, x, y);
    if (placement == null) return;
    final before = _controller.document;
    _controller.placeSignature(widget.pageIndex, x, y);
    if (identical(before, _controller.document)) return;
    _clearAfterimage();
    _afterSignature = (
      strokes: placement.strokes,
      pressures: placement.pressures,
      color: Color(0xFF000000 | placement.color),
      strokeWidth: placement.strokeWidth * _geometry.scale,
    );
    _afterDocument = _controller.document;
    // the next hover re-arms the preview; touch shouldn't keep a stale one
    _signaturePreview = null;
  }

  void _commitLineDrag(Offset start, Offset end) {
    if (_tool == PdfEditTool.calibrate) {
      unawaited(_commitCalibration(start, end));
      return;
    }
    final before = _controller.document;
    _behavior!.commitLineDrag(_controller, widget.pageIndex,
        _geometry.toPagePoint(start), _geometry.toPagePoint(end));
    if (identical(before, _controller.document)) return;
    _clearAfterimage();
    _afterPath = (
      points: [start, end],
      tool: _tool!,
      color: _controller.color
          .withValues(alpha: _controller.preferences.opacity.clamp(0.0, 1.0)),
      fillColor: null,
      strokeWidth: _controller.preferences.strokeWidth * _geometry.scale,
      dashed: _controller.dashedStroke,
    );
    _afterDocument = _controller.document;
  }

  /// Finishes the calibration drag: asks how long the drawn segment is in
  /// the real world, then derives [PdfEditingController.measurementScale]
  /// from it and disarms the tool. Nothing is stamped on the page.
  Future<void> _commitCalibration(Offset start, Offset end) async {
    final existing = _controller.preferences.measurementScale;
    final result = await showPdfCalibrationLengthDialog(
      context,
      initialUnit: existing?.unitLabel,
    );
    if (!mounted || result == null) return;
    final (length, unit) = result;
    _controller.calibrateScale(
      _geometry.toPagePoint(start),
      _geometry.toPagePoint(end),
      length,
      unit,
      pageUnitLabel: existing?.pageUnitLabel ?? pdfDefaultPageUnit(),
    );
    _controller.tool = PdfEditTool.select;
  }

  /// Finishes a volume measurement: asks for the extrusion depth (in the
  /// scale's unit), then stamps a /Polygon takeoff carrying it. Cancelling
  /// the dialog drops the in-progress polygon without stamping anything.
  Future<void> _commitVolume(List<(double, double)> pagePoints) async {
    final depth = await showPdfDepthDialog(
      context,
      unitLabel: _controller.preferences.measurementScale?.unitLabel,
    );
    if (!mounted || depth == null) return;
    _controller.addMeasurement(
        widget.pageIndex, PdfMeasurementKind.volume, pagePoints,
        depth: depth);
  }

  void _commitVertexDrag(List<Offset> points, {int? handle}) {
    final annotation = _controller.selectedAnnotation;
    if (annotation != null && annotation.isCallout && points.isNotEmpty) {
      // handle 0 is the terminus (re-aim the arrow), handle 1 is the base
      // (slide where the leader meets the box); both leave the box in place
      final idx = (handle ?? 0).clamp(0, points.length - 1);
      final page = _geometry.toPagePoint(points[idx]);
      if (idx == 1) {
        _controller.reshapeSelectedCalloutBase(page);
      } else {
        _controller.reshapeSelectedCalloutTarget(page);
      }
      return;
    }
    final tool = _selectedLineTool;
    if (tool == null) return;
    final style = _controller.selectedAnnotationStyle;
    final opacity = style?.opacity ?? 1;
    final before = _controller.document;
    _controller.reshapeSelectedLine(
        [for (final point in points) _geometry.toPagePoint(point)]);
    if (identical(before, _controller.document)) return;
    _clearAfterimage();
    _afterPath = (
      points: points,
      tool: tool,
      color: style?.color.withValues(alpha: opacity) ?? _controller.color,
      fillColor: annotation?.behavior.style.fillColor == null
          ? null
          : Color(0xFF000000 | annotation!.behavior.style.fillColor!)
              .withValues(alpha: opacity),
      strokeWidth:
          (style?.strokeWidth ?? _controller.preferences.strokeWidth) * _geometry.scale,
      dashed: annotation?.borderDash != null,
    );
    _afterDocument = _controller.document;
  }

  ({
    List<Offset> points,
    PdfEditTool tool,
    Color color,
    Color? fillColor,
    double strokeWidth,
    bool dashed,
  })? _linePreviewPath(List<Offset> points) {
    final tool = _selectedLineTool;
    final style = _controller.selectedAnnotationStyle;
    final annotation = _controller.selectedAnnotation;
    if (tool == null || style == null || annotation == null) return null;
    final opacity = style.opacity;
    return (
      points: points,
      tool: tool,
      color: style.color.withValues(alpha: opacity),
      fillColor: annotation.behavior.style.fillColor == null
          ? null
          : Color(0xFF000000 | annotation.behavior.style.fillColor!)
              .withValues(alpha: opacity),
      strokeWidth:
          (style.strokeWidth ?? _controller.preferences.strokeWidth) * _geometry.scale,
      dashed: annotation.borderDash != null,
    );
  }

  void _addPolyPoint(Offset point) {
    var reachedFixed = false;
    setState(() {
      final points = _polyPoints ?? <Offset>[];
      if (points.isEmpty || (point - points.last).distance >= 2) {
        _polyPoints = [...points, point];
      }
      _polyHover = null;
      final fixed = _fixedPolyCount;
      reachedFixed = fixed != null && (_polyPoints?.length ?? 0) >= fixed;
    });
    // angle/arc take exactly three clicks, then commit themselves.
    if (reachedFixed) _finishPolyPath();
  }

  void _finishPolyPath([Offset? finalPoint]) {
    final existing = _polyPoints;
    if (existing == null) return;
    final points = List<Offset>.of(existing);
    if (finalPoint != null &&
        (points.isEmpty || (finalPoint - points.last).distance >= 2)) {
      points.add(finalPoint);
    }
    final closed = _tool == PdfEditTool.polygon ||
        _tool == PdfEditTool.cloudPolygon ||
        _tool == PdfEditTool.measureArea ||
        _tool == PdfEditTool.measureVolume;
    final minPoints = _fixedPolyCount ?? (closed ? 3 : 2);
    if (points.length < minPoints) return;
    final simplified = <Offset>[];
    for (final point in points) {
      if (simplified.isEmpty || (point - simplified.last).distance >= 2) {
        simplified.add(point);
      }
    }
    if (simplified.length < minPoints) return;
    final pagePoints = [for (final p in simplified) _geometry.toPagePoint(p)];
    final before = _controller.document;
    // Volume needs a depth: its behaviour declines the synchronous commit,
    // so prompt for the depth and commit asynchronously here.
    if (_measureKind == PdfMeasurementKind.volume) {
      unawaited(_commitVolume(pagePoints));
      _clearAfterimage();
      setState(() {
        _polyPoints = null;
        _polyHover = null;
      });
      return;
    }
    // The cloud tool's click path builds a free-form footprint (its drag
    // path rubber-bands a rectangle instead), so it isn't a poly behaviour;
    // every other poly/measure-poly tool commits through its behaviour.
    if (_tool == PdfEditTool.cloudPolygon) {
      _controller.addCloudPolygonPoints(widget.pageIndex, pagePoints);
    } else {
      _behavior!.commitPoly(_controller, widget.pageIndex, pagePoints);
    }
    if (identical(before, _controller.document)) return;
    _clearAfterimage();
    setState(() {
      _polyPoints = null;
      _polyHover = null;
    });
    final opacity = _controller.preferences.opacity.clamp(0.0, 1.0);
    final fill = _controller.preferences.shapeFillColor;
    _afterPath = (
      points: simplified,
      tool: _tool!,
      color: _controller.color.withValues(alpha: opacity),
      // a polygon's interior fill (so the commit afterimage matches the
      // filled appearance, not just its outline); the cloud fills its
      // straight footprint the same way
      fillColor: (_tool == PdfEditTool.polygon ||
                  _tool == PdfEditTool.cloudPolygon) &&
              fill != null
          ? fill.withValues(alpha: opacity)
          : null,
      strokeWidth: _controller.preferences.strokeWidth * _geometry.scale,
      dashed: _controller.dashedStroke,
    );
    _afterDocument = _controller.document;
  }

  Future<void> _commitRect(Rect viewRect) async {
    final rect = _geometry.toPageRect(viewRect);
    switch (_tool) {
      case PdfEditTool.rectangle ||
            PdfEditTool.ellipse ||
            PdfEditTool.cloudPolygon:
        final tool = _tool!;
        final before = _controller.document;
        _behavior!.commitShapeRect(_controller, widget.pageIndex, rect);
        if (identical(before, _controller.document)) return;
        // the drag preview, frozen until the new revision renders
        _clearAfterimage();
        _afterShape = (
          rect: viewRect,
          tool: tool,
          color: _controller.color
              .withValues(alpha: _controller.preferences.opacity.clamp(0.0, 1.0)),
          strokeWidth: _controller.preferences.strokeWidth * _geometry.scale,
        );
        _afterDocument = _controller.document;
      case PdfEditTool.stamp:
        final stamp = _controller.activeStamp;
        if (stamp != null) {
          final values = _controller.resolvedStampTemplateValues;
          await _commitStampWithAfterimage(
              _stampAfterimage(viewRect,
                  text: pdfResolveStampTemplateText(stamp.text, values),
                  template: stamp.template?.resolveText(values),
                  color: Color(0xFF000000 | stamp.color)),
              () => _controller.addCustomStamp(widget.pageIndex, rect, stamp));
          return;
        }
        final text = await widget.textPrompt(context,
            title: pdfL10n(context).overlayStampText, initial: 'APPROVED');
        if (text == null || text.isEmpty) return;
        await _commitStampWithAfterimage(
            _stampAfterimage(viewRect, text: text, color: _controller.color),
            () => _controller.addStamp(widget.pageIndex, rect, text));
      case PdfEditTool.image:
        final picker = widget.imagePicker;
        if (picker == null) return;
        final bytes = await picker(context);
        if (bytes == null) return;
        await _controller.addImageInRectAsync(widget.pageIndex, rect, bytes);
      case PdfEditTool.form:
        _controller.addFormField(
            _controller.newFormFieldKind, widget.pageIndex, rect);
      case PdfEditTool.redact:
        _controller.addRedaction(widget.pageIndex, rect);
      case PdfEditTool.signatureBox:
        final placer = widget.onPlaceSignature;
        if (placer == null) return;
        await placer(context, pageIndex: widget.pageIndex, pageRect: rect);
      case PdfEditTool.snapshot:
        // always keep a vector copy on the clipboard so it can paste back
        // into the PDF (⌘V / the paste menu), Bluebeam-style; the host
        // callback is an optional export of the raster image on top
        final vector = _controller.copyVectorSnapshot(widget.pageIndex, rect);
        final handler = widget.onSnapshot;
        if (handler == null) return;
        // page raster space (post-/Rotate, y down) = view space / scale -
        // the same mapping the eyedropper's sampler uses
        final s = _geometry.scale;
        final region = Rect.fromLTRB(viewRect.left / s, viewRect.top / s,
            viewRect.right / s, viewRect.bottom / s);
        final bytes = await _controller.captureSnapshot(
            widget.pageIndex, region,
            pageColor: widget.pageColor, annotations: widget.showAnnotations);
        if (bytes == null || !mounted) return;
        await handler(
            context,
            PdfSnapshot(
              pageIndex: widget.pageIndex,
              pageRect: rect,
              pngBytes: bytes,
              vector: vector,
            ));
      default:
        break;
    }
  }

  /// The form tool's double-tap (and read mode's tap): routes the hit
  /// field at [local] to its fill interaction. [globalPosition] anchors
  /// the choice menu.
  Future<void> _fillFormFieldAt(Offset local, Offset globalPosition) async {
    final (x, y) = _geometry.toPagePoint(local);
    final hit = _controller.formFieldAt(widget.pageIndex, x, y);
    if (hit == null) return;
    final (field, widgetIndex) = hit;
    if (field.isReadOnly) return;
    switch (field.type) {
      case PdfFieldType.text:
        _openFormTextEditor(field, widgetIndex);
      case PdfFieldType.checkBox:
        _controller.toggleFormCheckBox(field.name);
      case PdfFieldType.radioGroup:
        final state = field.widgetOnState(widgetIndex);
        if (state != null) _controller.setFormRadioValue(field.name, state);
      case PdfFieldType.comboBox || PdfFieldType.listBox:
        await _pickFormChoice(field, globalPosition);
      case PdfFieldType.pushButton:
        final picker = widget.formImagePicker;
        if (picker == null) return;
        final name = field.name;
        final bytes = await picker(context, field);
        if (bytes != null) {
          await _controller.setFormButtonImageAsync(name, bytes);
        }
      case PdfFieldType.signature || PdfFieldType.unknown:
        break;
    }
  }

  /// A choice field's options as a context menu at the tap position.
  Future<void> _pickFormChoice(
      PdfFormField field, Offset globalPosition) async {
    final options = field.options;
    if (options.isEmpty) return;
    final name = field.name;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          globalPosition & Size.zero, Offset.zero & overlay.size),
      items: [
        for (final (export, display) in options)
          PopupMenuItem(
            key: ValueKey('pdf-form-option-$export'),
            value: export,
            height: 34,
            child: Text(display,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(height: 1.1)),
          ),
      ],
    );
    if (picked != null) _controller.setFormChoiceValue(name, picked);
  }

  /// Rasterizes this page once for the eyedropper, keyed on document
  /// identity (it changes every revision). The page raster at scale 1
  /// shares the view's orientation, so view → raster is just the
  /// geometry scale.
  Future<PdfPageColorSampler> _ensureSampler() {
    final document = _controller.document;
    final pageColor = widget.pageColor;
    final annotations = widget.showAnnotations;
    if (!identical(document, _samplerDocument) ||
        pageColor != _samplerPageColor ||
        annotations != _samplerAnnotations) {
      _samplerDocument = document;
      _samplerPageColor = pageColor;
      _samplerAnnotations = annotations;
      _sampler = null;
      _samplerFuture = PdfPageColorSampler.of(document.page(widget.pageIndex),
              pageColor: pageColor,
              annotations: annotations,
              rotation: widget.geometry.rotation)
          .then((s) {
        // resolve the preview that was waiting on the raster
        if (mounted &&
            identical(_samplerDocument, document) &&
            _samplerPageColor == pageColor &&
            _samplerAnnotations == annotations) {
          setState(() {
            _sampler = s;
            final position = _pickPosition;
            if (position != null) {
              _pickPreview = s.colorAt(position / _geometry.scale);
            }
          });
        }
        return s;
      });
    }
    return _samplerFuture!;
  }

  void _updatePickPreview(Offset position) {
    unawaited(_ensureSampler());
    setState(() {
      _pickPosition = position;
      _pickPreview = _sampler?.colorAt(position / _geometry.scale);
    });
  }

  /// Releasing the pointer commits the raw gesture (stroke or erase
  /// swipe) and picks the eyedropper's previewed color - so both a
  /// plain tap and press-drag-release (watching the preview) work. A
  /// raw listener, so it fires regardless of the gesture arena.
  Future<void> _onPointerUp(PointerUpEvent event) async {
    _endRawPointer(event, canceled: false);
    if (!_controller.isPickingColor) return;
    final document = _controller.document;
    final sampler = await _ensureSampler();
    if (!mounted || !identical(document, _controller.document)) return;
    setState(() {
      _pickPosition = null;
      _pickPreview = null;
    });
    final color = sampler.colorAt(event.localPosition / _geometry.scale);
    if (color != null) _controller.finishColorPick(color);
  }

  void _onPointerCancel(PointerCancelEvent event) =>
      _endRawPointer(event, canceled: true);

  Future<void> _onTapUp(TapUpDetails details) async {
    // the eyedropper commits from the raw pointer-up instead
    if (_controller.isPickingColor) return;
    if (_pointers.gestureBailed) return;
    if (_tool == PdfEditTool.eraser) {
      // a mouse/trackpad click erases what's under it; raw-driven
      // pointers already handled theirs on the way down
      if (!_rawDrives(details.kind)) {
        final before = _controller.document;
        _beginInteraction(PdfEditingInteractionIntent.erase, details.kind);
        final transition = _interaction.state.transition;
        _eraseAt(details.localPosition);
        _commitErase();
        _finishInteraction(before, transition);
      }
      return;
    }
    if (_textEditRect != null) {
      // tapping outside the open editor commits it
      _commitTextEdit();
      return;
    }
    if (_polyTool) {
      return;
    }
    if (_tool == PdfEditTool.cloudPolygon) {
      // a tap (not a drag) drops a cloud vertex; double-tap finishes it
      _addPolyPoint(details.localPosition);
      return;
    }
    final (x, y) = _geometry.toPagePoint(details.localPosition);
    if (_selectMode) {
      // tapping the already-selected free text edits it in place,
      // like clicking into a text box in any editor
      if (_controller.selectedAnnotationSlots.length == 1 &&
          _controller.selectedAnnotationSlot?.$1 == widget.pageIndex &&
          _controller.selectedAnnotation?.subtype == 'FreeText' &&
          !_additiveModifier &&
          (_selectedViewRect?.contains(details.localPosition) ?? false)) {
        _openTextEditor(_selectedViewRect!, existing: true);
        return;
      }
      // shift/⌘-click toggles membership in the selection
      _controller.selectAnnotationAt(widget.pageIndex, x, y,
          toggle: _additiveModifier);
      return;
    }
    final tapIntent = switch (_tool) {
      PdfEditTool.note ||
      PdfEditTool.count ||
      PdfEditTool.signature ||
      PdfEditTool.freeText ||
      PdfEditTool.callout ||
      PdfEditTool.stamp ||
      PdfEditTool.image =>
        PdfEditingInteractionIntent.create,
      _ => PdfEditingInteractionIntent.none,
    };
    final before = _controller.document;
    if (tapIntent != PdfEditingInteractionIntent.none) {
      _beginInteraction(tapIntent, details.kind);
    }
    final transition = _interaction.state.transition;
    try {
      switch (_tool) {
      case null:
        break;
      case PdfEditTool.select:
        break; // handled above
      case PdfEditTool.content:
        _controller.selectElementAt(widget.pageIndex, x, y);
      case PdfEditTool.note:
        final text =
            await widget.textPrompt(context,
                title: pdfL10n(context).overlayNote, multiline: true);
        if (text == null || text.isEmpty) return;
        _controller.addNote(widget.pageIndex, x, y, text);
      case PdfEditTool.count:
        // each tap drops a check-mark and bumps the running tally
        final before = _controller.document;
        _controller.placeCheckMark(widget.pageIndex, x, y);
        _captureLastStampAfterimage(before,
            check: true, text: null, color: _controller.color);
      case PdfEditTool.signature:
        _placeSignature(details.localPosition);
      case PdfEditTool.freeText:
        // tapping without dragging out a box opens a default-sized one
        _openTextEditor(_defaultPlacementRect(details.localPosition),
            existing: false);
      case PdfEditTool.callout:
        // a plain tap makes the tap the terminus and offsets the box; a drag
        // (handled in _panEnd) instead aims the box where the drag released
        _openCalloutEditor(
            _defaultPlacementRect(
                details.localPosition + const Offset(28, -28)),
            details.localPosition);
      case PdfEditTool.stamp:
        final stamp = _controller.activeStamp;
        if (stamp != null) {
          // an active custom stamp drops at its auto-size on tap
          final preview = _activeStampAfterimageAt(details.localPosition);
          if (preview == null) return;
          if (_stampPreview != null) setState(() => _stampPreview = null);
          await _commitStampWithAfterimage(
              preview, () => _controller.placeStamp(widget.pageIndex, x, y));
        } else {
          // the classic flow normally drags out a box; a plain tap places
          // a default-sized stamp after prompting for its caption
          final text = await widget.textPrompt(context,
              title: pdfL10n(context).overlayStampText, initial: 'APPROVED');
          if (text == null || text.isEmpty) return;
          await _commitStampWithAfterimage(
              _textStampAfterimageAt(
                  details.localPosition, text, _controller.color),
              () => _controller.placeTextStamp(widget.pageIndex, x, y, text));
        }
      case PdfEditTool.image:
        final picker = widget.imagePicker;
        if (picker == null) return;
        final bytes = await picker(context);
        if (bytes == null) return;
        await _controller.placeImageAsync(widget.pageIndex, x, y, bytes);
      case PdfEditTool.form:
        // single tap selects the field for move/resize/menu; double-tap
        // fills it (read mode is the no-tool path to just fill)
        _controller.selectFormWidgetAt(widget.pageIndex, x, y,
            toggle: _additiveModifier);
      default:
        break;
      }
    } finally {
      if (tapIntent != PdfEditingInteractionIntent.none) {
        _finishInteraction(before, transition);
      }
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _polyDoubleTapPosition = details.localPosition;
    _doubleTapDownDetails = details;
  }

  void _onDoubleTap() {
    if (_tool == PdfEditTool.form) {
      final details = _doubleTapDownDetails;
      if (details != null) {
        unawaited(
            _fillFormFieldAt(details.localPosition, details.globalPosition));
      }
      return;
    }
    if (!_polyTool && _tool != PdfEditTool.cloudPolygon) return;
    _finishPolyPath(_polyDoubleTapPosition);
    _polyDoubleTapPosition = null;
  }

  void _onHover(PointerHoverEvent event) {
    final MouseCursor cursor;
    if (_controller.isPickingColor) {
      _updatePickPreview(event.localPosition);
      cursor = SystemMouseCursors.precise;
    } else if (_selectMode) {
      final selected = _selectedViewRect;
      final chrome = _selectionChrome;
      final resting = chrome?.$2 ?? 0;
      final vertexPoints = _selectedVertexPoints;
      final vertex = vertexPoints == null
          ? null
          : _vertexHandleAt(vertexPoints, event.localPosition);
      final handle = selected == null || _selectedLineFamily
          ? null
          : resting == 0 || chrome == null
              ? _handleAt(selected, event.localPosition)
              : _handleAt(
                  chrome.$1,
                  _rotatePoint(
                      event.localPosition, chrome.$1.center, -resting));
      if (vertex != null) {
        cursor = SystemMouseCursors.grab;
      } else if (handle != null) {
        cursor = _resizeCursorFor(handle);
      } else if (chrome != null &&
          _hitsRotateHandle(chrome.$1, resting, event.localPosition)) {
        // no system rotation cursor: hide it and paint a curved-arrow glyph
        if (_rotateCursor != event.localPosition) {
          setState(() => _rotateCursor = event.localPosition);
        }
        cursor = SystemMouseCursors.none;
      } else if (_selectedViewRects
          .any((rect) => rect.contains(event.localPosition))) {
        // hovering a selected annotation: the 4-arrow reads as "drag me"
        cursor = SystemMouseCursors.move;
      } else {
        final (x, y) = _geometry.toPagePoint(event.localPosition);
        // a pointer over a selectable annotation, a crosshair-ish basic
        // over empty page (a drag there rubber-bands)
        cursor =
            _controller.selectableAnnotationAt(widget.pageIndex, x, y) != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic;
      }
    } else if (_tool == PdfEditTool.note) {
      cursor = SystemMouseCursors.click;
    } else if (_inkTool) {
      // the painted dot (pen colour at pen width) is the cursor, so the
      // chosen colour and stroke width are visible before drawing
      if (_penCursor != event.localPosition) {
        setState(() => _penCursor = event.localPosition);
      }
      cursor = SystemMouseCursors.none;
    } else if (_tool == PdfEditTool.eraser) {
      // the painted ring is the cursor
      if (_eraserCursor != event.localPosition) {
        setState(() => _eraserCursor = event.localPosition);
      }
      cursor = SystemMouseCursors.none;
    } else if (_tool == PdfEditTool.count) {
      // the painted check-mark is the cursor, showing exactly what a click
      // will place before the page gets a new annotation.
      if (_countCursor != event.localPosition) {
        setState(() => _countCursor = event.localPosition);
      }
      cursor = SystemMouseCursors.none;
    } else if (_tool == PdfEditTool.stamp) {
      // active custom stamps can be placed by a plain click - show the exact
      // auto-sized placement before committing it. The prompt-for-text
      // fallback has no caption yet, so it previews a 'TEXT' placeholder to
      // make the click target visible.
      final preview = _stampHoverAfterimageAt(event.localPosition);
      if (preview == null) {
        if (_stampPreview != null) setState(() => _stampPreview = null);
      } else if (_stampPreview != event.localPosition) {
        setState(() => _stampPreview = event.localPosition);
      }
      cursor = SystemMouseCursors.precise;
    } else if (_tool == PdfEditTool.signature) {
      // the live preview rides the mouse; a click commits it
      if (_controller.preferences.signature != null &&
          event.localPosition != _signaturePreview) {
        setState(() => _signaturePreview = event.localPosition);
      }
      cursor = SystemMouseCursors.precise;
    } else if (_polyTool || _tool == PdfEditTool.cloudPolygon) {
      // once a cloud vertex is down, the hover rubber-bands the next edge;
      // before that the cloud tool still rubber-bands a rectangle on drag
      if (_polyPoints != null && event.localPosition != _polyHover) {
        setState(() => _polyHover = event.localPosition);
      }
      cursor = SystemMouseCursors.precise;
    } else if (_tool == PdfEditTool.content) {
      final (x, y) = _geometry.toPagePoint(event.localPosition);
      cursor =
          _controller.elementsOn(widget.pageIndex).elementsAt(x, y).isNotEmpty
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic;
    } else if (_tool == PdfEditTool.form) {
      final (x, y) = _geometry.toPagePoint(event.localPosition);
      final selectedRect = _selectedViewRect;
      final onHandle = selectedRect != null &&
          _controller.canResizeSelected &&
          _handleAt(selectedRect, event.localPosition) != null;
      if (onHandle) {
        cursor = SystemMouseCursors.precise; // a resize handle
      } else if (selectedRect?.contains(event.localPosition) ?? false) {
        cursor = SystemMouseCursors.move; // drag the selected field
      } else if (_controller.selectableWidgetAt(widget.pageIndex, x, y) !=
          null) {
        cursor = SystemMouseCursors.click; // tap to select / double-tap fills
      } else {
        cursor = SystemMouseCursors.precise; // a drag here adds a field
      }
    } else {
      cursor = SystemMouseCursors.precise;
    }
    // retract the painted glyph cursors when the pointer leaves their zone:
    // the rotate glyph shows only over the knob (the lone `none` in select
    // mode), the pen dot only with the ink tool armed
    final overKnob = _selectMode && cursor == SystemMouseCursors.none;
    if (!overKnob && _rotateCursor != null) {
      setState(() => _rotateCursor = null);
    }
    if (!_inkTool && _penCursor != null) {
      setState(() => _penCursor = null);
    }
    if (_tool != PdfEditTool.count && _countCursor != null) {
      setState(() => _countCursor = null);
    }
    if (_tool != PdfEditTool.stamp && _stampPreview != null) {
      setState(() => _stampPreview = null);
    }
    if (cursor != _cursor) setState(() => _cursor = cursor);
  }

  /// The floating action row beside a touch/stylus selection - the
  /// affordances mice get from hover and right-click (delete, the
  /// context menu, edit-in-place). Rides above the selection, clear of
  /// the rotate knob; flips below when the selection hugs the page top.
  /// Constant size on screen at any zoom, like the rest of the chrome.
  Widget _buildSelectionChip(Rect selected) {
    final clearance = (_rotateHandleDistance + 16) * _chromeScale;
    final above = selected.top - clearance - 44 * _chromeScale >= 0;
    // keep the chip's body on the page near the side edges
    final width = _geometry.viewSize.width;
    final halfChip = 80 * _chromeScale;
    final anchor = Offset(
      width <= 2 * halfChip
          ? width / 2
          : selected.center.dx.clamp(halfChip, width - halfChip),
      above ? selected.top - clearance : selected.bottom + 12 * _chromeScale,
    );
    return Positioned(
      left: anchor.dx,
      top: anchor.dy,
      child: FractionalTranslation(
        translation: Offset(-0.5, above ? -1 : 0),
        child: Transform.scale(
          scale: _chromeScale,
          alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
          child: Material(
            key: const ValueKey('pdf-selection-chip'),
            elevation: 3,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: const ValueKey('pdf-selection-chip-delete'),
                icon: const Icon(Icons.delete_outline),
                tooltip: pdfL10n(context).delete,
                onPressed: _controller.deleteSelected,
              ),
              if (_controller.canEditSelectedText)
                IconButton(
                  key: const ValueKey('pdf-selection-chip-edit'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: pdfL10n(context).overlayEditText,
                  onPressed: () {
                    final rect = _selectedViewRect;
                    if (rect != null) _openTextEditor(rect, existing: true);
                  },
                ),
              if (_host.showAnnotationMenu != null && widget.contextMenuEnabled)
                IconButton(
                  key: const ValueKey('pdf-selection-chip-menu'),
                  icon: const Icon(Icons.more_horiz),
                  tooltip: pdfL10n(context).overlayMore,
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    _host.showAnnotationMenu!(
                        box.localToGlobal(anchor), widget.pageIndex);
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  bool get _canStyleInlineTextSelection {
    final selection = _textEditText.selection;
    return _textEditRect != null && selection.isValid && !selection.isCollapsed;
  }

  _TextEditStyle _currentInlineTextStyle() {
    final selection = _textEditText.selection;
    final offset = selection.isValid
        ? math.min(selection.baseOffset, selection.extentOffset)
        : 0;
    return _textEditText._styleAt(offset.clamp(0, _textEditText.text.length));
  }

  void _applyInlineTextStyle(
      {PdfTextFont? font, double? size, Color? color, bool? underline}) {
    if (!_canStyleInlineTextSelection) return;
    final rgb = color == null ? null : color.toARGB32() & 0xFFFFFF;
    if (font is PdfStandardFont) {
      _controller.fontFamily = font;
    } else if (font is PdfEmbeddedFont) {
      _controller.activeFont = font;
    }
    if (size != null) _controller.preferences.fontSize = size;
    if (color != null) _controller.color = Color(0xFF000000 | rgb!);
    if (underline != null) _controller.textUnderline = underline;
    _controller.setEditingTextSelection(_textEditText.selection);
    _controller.restyleEditingTextSelection(
        font: font, size: size, color: rgb, underline: underline);
  }

  /// Registers an embedded font's outline bytes with the engine under a
  /// synthetic family so the inline editor can *preview* it - base-14
  /// faces map to platform families, but an embedded/bundled font is drawn
  /// from raw bytes the page renderer turns into paths, which a Flutter
  /// `TextField` can't use until they're loaded as a font. Idempotent and
  /// fire-and-forget: once the load lands it rebuilds so the styled run
  /// switches from the fallback face to the real one.
  void _ensureEmbeddedFontPreview(PdfEmbeddedFont font) {
    final key = _embeddedFontKey(font);
    if (_embeddedPreviewFamilies.containsKey(key) ||
        _embeddedFontsLoading.contains(key)) {
      return;
    }
    _embeddedFontsLoading.add(key);
    final family = 'pdfedit-$key';
    // copy the bytes: loadFontFromList wants an owned, immutable list
    ui
        .loadFontFromList(Uint8List.fromList(font.fontBytes),
            fontFamily: family)
        .then((_) {
      _embeddedPreviewFamilies[key] = family;
      _embeddedFontsLoading.remove(key);
      if (mounted) setState(() {});
    }, onError: (_) {
      // a font the engine rejects just keeps previewing in the fallback face
      _embeddedFontsLoading.remove(key);
    });
  }

  /// Toggles bold (or [italic]) on the inline text editor - the desktop
  /// Cmd/Ctrl+B / Cmd/Ctrl+I shortcuts. Bold and italic are variants of the
  /// base-14 faces, so an embedded font is left alone. With a selection the
  /// toggle restyles it; with none it styles the whole box (or just sets the
  /// face when the box is still empty).
  void _toggleInlineTextStyle({required bool italic}) {
    // form fields carry a single /DA font - no rich styling to toggle
    if (_textEditRect == null || _textEditFieldName != null) return;

    final base = _canStyleInlineTextSelection
        ? _currentInlineTextStyle().font
        : _textEditFont;
    if (base is! PdfStandardFont) return;
    final next =
        italic ? base.withItalic(!base.isItalic) : base.withBold(!base.isBold);

    if (_canStyleInlineTextSelection) {
      _applyInlineTextStyle(font: next);
      return;
    }
    final length = _textEditText.text.length;
    if (length == 0) {
      setState(() => _textEditFont = next);
      _controller.fontFamily = next;
      _textEditText.resetStyles(_TextEditStyle(
          font: next, size: _textEditSize, color: _textEditColor));
      return;
    }
    // a bare caret: style the whole box (select-all gives visible feedback)
    _textEditText.selection =
        TextSelection(baseOffset: 0, extentOffset: length);
    _applyInlineTextStyle(font: next);
  }

  /// Toggles underline on the inline text editor - the desktop Cmd/Ctrl+U
  /// shortcut and the style-chip button. Underline is a per-character format
  /// (like bold), so with a selection it restyles that run; with none it
  /// underlines the whole box (or just sets the default when the box is
  /// still empty).
  void _toggleInlineUnderline() {
    if (_textEditRect == null || _textEditFieldName != null) return;
    final on = !_currentInlineTextStyle().underline;
    if (_canStyleInlineTextSelection) {
      _applyInlineTextStyle(underline: on);
      return;
    }
    final length = _textEditText.text.length;
    if (length == 0) {
      _controller.textUnderline = on;
      setState(() => _textEditText.resetStyles(_TextEditStyle(
          font: _textEditFont,
          size: _textEditSize,
          color: _textEditColor,
          underline: on)));
      return;
    }
    _textEditText.selection =
        TextSelection(baseOffset: 0, extentOffset: length);
    _applyInlineTextStyle(underline: on);
  }

  Future<void> _showInlineTextFontMenu(BuildContext context) async {
    if (!_canStyleInlineTextSelection) return;
    _textEditStyleMenuOpen = true;
    _textEditFocus.requestFocus();
    await showPdfFontMenu(
        context: context,
        controller: _controller,
        currentFont: _currentInlineTextStyle().font,
        onSelected: (font) {
          if (!mounted || !_canStyleInlineTextSelection) return;
          _applyInlineTextStyle(font: font);
        });
    _textEditStyleMenuOpen = false;
    if (mounted && _textEditRect != null) _textEditFocus.requestFocus();
  }

  Future<void> _pickInlineTextColor(BuildContext context, Color initial) async {
    if (!_canStyleInlineTextSelection) return;
    _textEditStyleMenuOpen = true;
    _textEditFocus.requestFocus();
    final picked =
        await pickEditingColor(context, _controller, initial: initial);
    _textEditStyleMenuOpen = false;
    if (mounted && _textEditRect != null) _textEditFocus.requestFocus();
    if (picked != null && mounted) _applyInlineTextStyle(color: picked);
  }

  Widget _buildInlineTextStyleChip(Rect editorRect) {
    final s = _chromeScale;
    final current = _currentInlineTextStyle();
    final above = editorRect.top - 54 * s >= 0;
    final width = _geometry.viewSize.width;
    final halfChip = 108 * s;
    final anchor = Offset(
      width <= 2 * halfChip
          ? width / 2
          : editorRect.center.dx.clamp(halfChip, width - halfChip),
      above ? editorRect.top - 10 * s : editorRect.bottom + 10 * s,
    );
    final enabled = _canStyleInlineTextSelection;
    final iconColor = Color(0xFF000000 | (current.color.toARGB32() & 0xFFFFFF));
    return Positioned(
      left: anchor.dx,
      top: anchor.dy,
      child: FractionalTranslation(
        translation: Offset(-0.5, above ? -1 : 0),
        child: Transform.scale(
          scale: s,
          alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
          // pin the editor's focus while a chip button is pressed - on mobile
          // the tap otherwise blurs the field and the focus-loss listener
          // commits/deselects the box before the button's action runs
          child: Listener(
            behavior: HitTestBehavior.deferToChild,
            onPointerDown: (_) => _holdChipFocus(),
            onPointerUp: (_) => _releaseChipFocus(),
            onPointerCancel: (_) => _releaseChipFocus(),
            child: Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            child: Material(
              key: const ValueKey('pdf-inline-text-style-chip'),
              elevation: 3,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Builder(builder: (buttonContext) {
                  return IconButton(
                    key: const ValueKey('pdf-inline-text-font'),
                    icon: const Icon(Icons.font_download_outlined),
                    tooltip: pdfL10n(context).overlayFont,
                    onPressed: enabled
                        ? () => _showInlineTextFontMenu(buttonContext)
                        : null,
                  );
                }),
                IconButton(
                  key: const ValueKey('pdf-inline-text-size-down'),
                  icon: const Icon(Icons.text_decrease),
                  tooltip: pdfL10n(context).overlaySmaller,
                  onPressed: enabled
                      ? () => _applyInlineTextStyle(
                          size: (current.size - 1).clamp(8, 48).toDouble())
                      : null,
                ),
                IconButton(
                  key: const ValueKey('pdf-inline-text-size-up'),
                  icon: const Icon(Icons.text_increase),
                  tooltip: pdfL10n(context).overlayLarger,
                  onPressed: enabled
                      ? () => _applyInlineTextStyle(
                          size: (current.size + 1).clamp(8, 48).toDouble())
                      : null,
                ),
                IconButton(
                  key: const ValueKey('pdf-inline-text-underline'),
                  icon: const Icon(Icons.format_underlined),
                  tooltip: pdfL10n(context).overlayUnderline,
                  isSelected: current.underline,
                  // underline works with or without a selection (whole box)
                  onPressed: _textEditFieldName == null
                      ? _toggleInlineUnderline
                      : null,
                ),
                Builder(builder: (buttonContext) {
                  return IconButton(
                    key: const ValueKey('pdf-inline-text-color'),
                    icon: Icon(Icons.format_color_text, color: iconColor),
                    tooltip: pdfL10n(context).overlayColor,
                    onPressed: enabled
                        ? () async {
                            await _pickInlineTextColor(
                                buttonContext, iconColor);
                          }
                        : null,
                  );
                }),
              ]),
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// The running measurement readout during placement - the formatted
  /// distance/perimeter/area, and the view-space point it should ride.
  /// Null when no measurement tool is mid-placement.
  (String text, Offset anchor)? _measureReadout() {
    final kind = _measureKind;
    if (kind == null) return null;
    switch (kind) {
      case PdfMeasurementKind.distance || PdfMeasurementKind.slope:
        final start = _dragStart, current = _dragCurrent;
        if (start == null || current == null) return null;
        if ((current - start).distance < 1) return null;
        final a = _geometry.toPagePoint(start);
        final b = _geometry.toPagePoint(current);
        final text = kind == PdfMeasurementKind.slope
            ? _controller.measuredSlope(a, b)
            : _controller.measuredDistance(a, b);
        return text == null ? null : (text, current);
      case PdfMeasurementKind.perimeter ||
            PdfMeasurementKind.area ||
            PdfMeasurementKind.angle ||
            PdfMeasurementKind.arc ||
            PdfMeasurementKind.volume:
        final points = _polyPoints;
        if (points == null || points.isEmpty) return null;
        final view = [
          ...points,
          if (_polyHover != null && (_polyHover! - points.last).distance >= 2)
            _polyHover!,
        ];
        final pagePoints = [for (final p in view) _geometry.toPagePoint(p)];
        // volume's depth isn't known until placement finishes, so the live
        // readout shows the enclosed footprint area.
        final text = switch (kind) {
          PdfMeasurementKind.area ||
          PdfMeasurementKind.volume =>
            _controller.measuredArea(pagePoints),
          PdfMeasurementKind.angle => _controller.measuredAngle(pagePoints),
          PdfMeasurementKind.arc => _controller.measuredArc(pagePoints),
          _ => _controller.measuredPerimeter(pagePoints),
        };
        return text == null ? null : (text, view.last);
      default:
        // count/areaCutout have no in-overlay live readout.
        return null;
    }
  }

  /// Tools whose drag shows a stroke-width / opacity readout.
  static const _strokeTools = {
    PdfEditTool.rectangle,
    PdfEditTool.ellipse,
    PdfEditTool.cloudPolygon,
    PdfEditTool.line,
    PdfEditTool.arrow,
    PdfEditTool.polyline,
    PdfEditTool.polygon,
  };

  /// A `"{width} pt · {opacity}%"` readout while a shape/line is being
  /// drawn (the creation pen width and opacity) or a stroked selection is
  /// being resized (its own values) - so they're visible mid-gesture.
  /// Null for measurement tools (their own readout shows) and when nothing
  /// stroke-bearing is mid-drag.
  (String text, Offset anchor)? _styleReadout() {
    if (_measureKind != null) return null;
    double width;
    double opacity;
    Offset anchor;
    if (_resizeHandle != null && _resizeRect != null) {
      final style = _controller.selectedAnnotationStyle;
      if (style?.strokeWidth == null) return null;
      width = style!.strokeWidth!;
      opacity = style.opacity;
      anchor = _resizeRect!.bottomRight;
    } else if (_tool != null && _strokeTools.contains(_tool)) {
      if (_dragStart != null &&
          _dragCurrent != null &&
          (_dragCurrent! - _dragStart!).distance >= 2) {
        anchor = _dragCurrent!;
      } else if (_polyPoints != null && _polyPoints!.isNotEmpty) {
        anchor = _polyHover ?? _polyPoints!.last;
      } else {
        return null;
      }
      width = _controller.preferences.strokeWidth;
      opacity = _controller.preferences.opacity;
    } else {
      return null;
    }
    final w = width == width.roundToDouble()
        ? width.toStringAsFixed(0)
        : width.toStringAsFixed(1);
    return ('$w pt · ${(opacity * 100).round()}%', anchor);
  }

  /// The floating measurement readout chip. Mouse: rides just off the
  /// cursor. Touch/stylus: floats well above the finger so the contact
  /// point isn't occluded (the [_buildSelectionChip]/eyedropper pattern,
  /// keyed on [_lastPointerKind]).
  Widget _buildReadoutChip(String text, Offset anchor,
      {String keyValue = 'pdf-measure-readout'}) {
    final touch = _lastPointerKind == PointerDeviceKind.touch ||
        _lastPointerKind == PointerDeviceKind.stylus;
    final offset = touch ? const Offset(0, -64) : const Offset(16, -36);
    final scale = _chromeScale;
    return Positioned(
      // [anchor] is page-overlay space. Counter-scale both the screen-space
      // offset and the chip itself because the whole overlay is inside the
      // viewer's zoom transform.
      left: anchor.dx + offset.dx * scale,
      top: anchor.dy + offset.dy * scale,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: FractionalTranslation(
          // Keep the translation inside the counter-scale transform: an
          // outside translation would itself be magnified by page zoom.
          translation: touch ? const Offset(-0.5, 0) : Offset.zero,
          child: IgnorePointer(
            child: Material(
              key: ValueKey(keyValue),
              color: const Color(0xE6202124),
              elevation: 3,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A wrapped-text box mirroring a committed free-text appearance -
  /// the live resize preview and the post-commit afterimage share it.
  /// [rotation] spins the box about its center (a rotated annotation's
  /// resting angle, view convention).
  Widget _wrappedTextBox({
    Key? key,
    required Rect rect,
    required String text,
    required PdfTextFont font,
    required double size,
    required Color color,
    required Color? background,
    required double rotation,
    PdfTextAlign? align,
    bool underline = false,
    double lineSpacing = kPdfFreeTextDefaultLineSpacing,
  }) {
    // An embedded/bundled face has no platform family - register its outline
    // bytes so Flutter wraps this preview in the real font (until the async
    // load lands, [_textEditUiFamily] returns null and the fallback face wraps
    // it, still without stretching). Bold/italic are base-14-only variants.
    if (font is PdfEmbeddedFont) _ensureEmbeddedFontPreview(font);
    final isBold = font is PdfStandardFont && font.isBold;
    final isItalic = font is PdfStandardFont && font.isItalic;
    final direction = _flutterTextDirection(text);
    final columnAlign = switch (align) {
      null => AlignmentDirectional.topStart.resolve(direction),
      PdfTextAlign.left => Alignment.topLeft,
      PdfTextAlign.center => Alignment.topCenter,
      PdfTextAlign.right => Alignment.topRight,
    };
    final box = Container(
      key: key,
      color: background,
      padding: EdgeInsets.all(3 * _geometry.scale),
      alignment: columnAlign,
      child: Directionality(
        textDirection: direction,
        child: Text(
          text,
          textAlign:
              align == null ? TextAlign.start : _flutterTextAlign(align),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
          ),
          style: TextStyle(
            color: color,
            fontSize: size * _geometry.scale,
            height: lineSpacing,
            fontFamily: _textEditUiFamily(font),
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            decoration: underline ? TextDecoration.underline : null,
            decorationColor: underline ? color : null,
          ),
        ),
      ),
    );
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child:
            rotation == 0 ? box : Transform.rotate(angle: rotation, child: box),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRasterReady();
    _textEditText.scale = _geometry.scale;
    _textEditText.previewLineHeight = _textEditLineSpacing;
    _textEditText.previewLetterSpacing = _textEditCharSpacing * _geometry.scale;
    _ensureGhost();
    _ensureSourceClean();
    // the afterimage has served once the committed revision's raster is
    // on screen - or is stale once the document moved past that revision
    if (_afterDocument != null &&
        (widget.rasterCurrent ||
            !identical(_afterDocument, _controller.document))) {
      _clearAfterimage();
    }
    if (_polyPoints != null &&
        !_polyTool &&
        _tool != PdfEditTool.cloudPolygon) {
      _polyPoints = null;
      _polyHover = null;
    }
    // re-derive the editor's view rect through the LIVE geometry: a zoom
    // can re-lay-out the page (_layoutZoom) between open and now, so a
    // cached view rect would have drifted across the page content
    if (_textEditPageRect != null) {
      _textEditRect = _geometry.toViewRect(_textEditPageRect!);
    }
    // switching tools mid-edit commits the text, like leaving the ink tool
    if (_textEditRect != null && _tool != _textEditTool) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _textEditRect != null && _tool != _textEditTool) {
          _commitTextEdit();
        }
      });
    }
    final selected = _selectedViewRect;
    final chrome = _selectionChrome;
    final restingRotation = chrome?.$2 ?? 0;
    final moveDelta =
        _resizeHandle == null && _moveStart != null && _moveCurrent != null
            ? _moveCurrent! - _moveStart!
            : Offset.zero;
    // the rest of a multi-selection on this page: chrome boxes without
    // handles, riding along with a move drag
    final allSelected = _selectedViewRects;
    final extraSelected = [
      for (final rect in selected == null
          ? allSelected
          : allSelected.sublist(0, allSelected.length - 1))
        rect.shift(moveDelta)
    ];
    final rotating = _rotateStartAngle != null;
    final dragging =
        _resizeHandle != null || moveDelta != Offset.zero || rotating;
    // When an edit (notably a vector-snapshot paste from ⌘V/the context
    // menu) swaps in a new document, the page raster still shows the old
    // revision until the async re-render lands. If the newly selected
    // annotation's appearance has already been recorded for drag previews,
    // paint that same picture at rest so vector paste feedback is immediate
    // instead of waiting for the full-page raster. Dragging keeps using the
    // normal ghost path, and explicit commit afterimages take precedence.
    final selectedAnnotation = _controller.selectedAnnotation;
    final washRestGhost = selectedAnnotation?.subtype == 'FreeText';
    final _AfterGhost? restGhost = !widget.rasterCurrent &&
            !dragging &&
            _afterGhost == null &&
            _ghost != null &&
            selected != null
        ? (
            picture: _ghost!,
            from: selected,
            to: selected,
            source: washRestGhost ? selected : null,
            sourceClean: washRestGhost ? _sourceCleanPicture : null,
            sourceWash: washRestGhost
                ? Color.alphaBlend(widget.pageColor, const Color(0xFFFFFFFF))
                : null,
            rotation: 0.0,
            localAngle: 0.0,
            flipX: false,
            flipY: false,
          )
        : null;
    final _AfterGhost? afterGhost = _afterGhost != null
        ? (
            picture: _afterGhost!,
            from: _afterGhostFrom!,
            to: _afterGhostTo!,
            source: _afterGhostSourceRect,
            sourceClean: _afterGhostSourceClean,
            sourceWash: _afterGhostSourceRect != null &&
                    _afterGhostSourceClean == null
                ? Color.alphaBlend(widget.pageColor, const Color(0xFFFFFFFF))
                : null,
            rotation: _afterGhostRotation,
            localAngle: _afterGhostLocalAngle,
            flipX: _afterGhostFlipX,
            flipY: _afterGhostFlipY,
          )
        : restGhost;
    // a free-text resize re-wraps at constant font size - preview the
    // wrapping live instead of the ghost's stretched glyphs
    final wrapResize =
        _resizeHandle != null && _resizeRect != null ? _textResizeStyle : null;
    // a Square/Circle resize regenerates at a constant stroke width:
    // preview that (live during the drag, then the frozen afterimage)
    // instead of the ghost, whose line would stretch and snap back
    final shapeResize =
        wrapResize == null && _resizeHandle != null && _resizeRect != null
            ? _shapeResizeStyle(_resizeRect!, _resizeAngle)
            : _afterShapeResize;
    // strokes beyond the pending ink: the committed-ink afterimage (held
    // until the new raster lands) and the signature tool's live preview
    final committedInk = widget.rasterCurrent
        ? null
        : _controller.committedInkOn(widget.pageIndex);
    _InkPaint? signaturePreview;
    if (_signaturePreview != null && _tool == PdfEditTool.signature) {
      final (x, y) = _geometry.toPagePoint(_signaturePreview!);
      final placement = _controller.signaturePlacement(widget.pageIndex, x, y);
      if (placement != null) {
        signaturePreview = (
          strokes: placement.strokes,
          pressures: placement.pressures,
          color: Color(0xFF000000 | placement.color).withValues(alpha: 0.55),
          strokeWidth: placement.strokeWidth * _geometry.scale,
        );
      }
    }
    final extraInk = <_InkPaint>[
      if (committedInk != null)
        (
          strokes: committedInk.strokes,
          pressures: committedInk.pressures,
          color: committedInk.color,
          strokeWidth: committedInk.strokeWidth * _geometry.scale,
        ),
      if (_afterSignature != null) _afterSignature!,
      if (signaturePreview != null) signaturePreview,
      // the eraser's live remainders, then the committed slice held
      // until its raster lands - painted over the fade wash
      ..._eraseSliced.values,
      ...?_afterEraseInk,
    ];
    // a fresh attention flash for this page starts its pulse
    final flash = _controller.pendingFlash;
    if (flash != null &&
        flash.page == widget.pageIndex &&
        flash.sequence != _flashSequence) {
      _flashSequence = flash.sequence;
      _flashRect = _controller.annotationAt(flash.page, flash.slot)?.rect;
      if (_flashRect != null) _flashController.forward(from: 0);
    }
    // warm the eyedropper's raster so the first preview is instant-ish
    if (_controller.isPickingColor) unawaited(_ensureSampler());
    final preview = _controller.isPickingColor ? _pickPosition : null;
    final polyPreview = _polyPoints == null
        ? null
        : [
            ..._polyPoints!,
            if (_polyHover != null &&
                (_polyHover! - _polyPoints!.last).distance >= 2)
              _polyHover!,
          ];
    final vertexHandles = _vertexPoints ?? _selectedVertexPoints;
    final vertexPreview =
        _vertexPoints == null ? null : _linePreviewPath(_vertexPoints!);
    // touch and stylus get the hover/right-click affordances as a
    // floating action chip beside the selection
    final showChip = (_lastPointerKind == PointerDeviceKind.touch ||
            _lastPointerKind == PointerDeviceKind.stylus) &&
        _selectMode &&
        selected != null &&
        !dragging &&
        _moveStart == null &&
        _marqueeStart == null &&
        _textEditRect == null &&
        _pointers.rawPointer == null;
    return Listener(
      // raw events carry what pan callbacks drop: pressure and the
      // device kind (for Apple Pencil palm rejection); pointer-up is
      // also the eyedropper's commit
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // with finger drawing off, touch falls through to the scroll
        // view and only pen-like devices reach the ink recognizers
        supportedDevices: _drawTool && !_controller.preferences.fingerDrawsInk
            ? const {
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              }
            : null,
        // anchor drags at the press point, not where the recognizer won the
        // arena - a shape should start exactly where the pointer went down
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _panStart,
        onPanUpdate: _panUpdate,
        onPanEnd: _panEnd,
        onTapUp: _onTapUp,
        onDoubleTapDown:
            _polyTool || _tool == PdfEditTool.cloudPolygon ||
                    _tool == PdfEditTool.form
                ? _onDoubleTapDown
                : null,
        onDoubleTap:
            _polyTool || _tool == PdfEditTool.cloudPolygon ||
                    _tool == PdfEditTool.form
                ? _onDoubleTap
                : null,
        child: MouseRegion(
          cursor: _cursor,
          onHover: _onHover,
          onExit: (_) {
            if (_pickPosition == null &&
                (_signaturePreview == null || _signatureDrag) &&
                (_eraserCursor == null || _erasePath.isNotEmpty) &&
                _penCursor == null &&
                _countCursor == null &&
                _stampPreview == null &&
                (_rotateCursor == null || _rotateStartAngle != null) &&
                _polyHover == null) {
              return;
            }
            setState(() {
              _pickPosition = null;
              _pickPreview = null;
              if (!_signatureDrag) _signaturePreview = null;
              if (_erasePath.isEmpty) _eraserCursor = null;
              _penCursor = null;
              _countCursor = null;
              _stampPreview = null;
              if (_rotateStartAngle == null) _rotateCursor = null;
              _polyHover = null;
            });
          },
          // touch and stylus long-press opens the context menu (the
          // recognizer claims only when the press point has a menu to
          // offer, so text selection and slow drags keep their gestures)
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _MenuLongPressRecognizer: GestureRecognizerFactoryWithHandlers<
                  _MenuLongPressRecognizer>(
                () => _MenuLongPressRecognizer(debugOwner: this),
                (recognizer) => recognizer
                  ..shouldClaim = _menuLongPressClaims
                  ..onLongPressStart = _onMenuLongPress,
              ),
            },
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _EditingPreviewPainter(
                    theme: PdfViewerTheme.of(context),
                    chromeScale: _chromeScale,
                    tool: _tool,
                    color: _controller.color,
                    strokeWidth: _controller.preferences.strokeWidth * _geometry.scale,
                    geometry: _geometry,
                    // the in-progress stroke is NOT here - it rides its own
                    // RepaintBoundary layer below so each appended point is a
                    // repaint, not a rebuild of this whole painter
                    strokes: _controller.strokesOn(widget.pageIndex),
                    pressures: _controller.strokePressuresOn(widget.pageIndex),
                    dragRect: _dragStart != null && _dragCurrent != null
                        ? Rect.fromPoints(_dragStart!, _dragCurrent!)
                        : null,
                    dragLine: _dragStart != null &&
                            _dragCurrent != null &&
                            (_lineDragTool || _tool == PdfEditTool.callout)
                        ? (_dragStart!, _dragCurrent!)
                        : null,
                    calloutLeader: _calloutLeaderPreview(),
                    dragPath: polyPreview,
                    dragPathFill: (_tool == PdfEditTool.polygon ||
                                _tool == PdfEditTool.cloudPolygon) &&
                            _controller.preferences.shapeFillColor != null
                        ? _controller.preferences.shapeFillColor!.withValues(
                            alpha: _controller.preferences.opacity.clamp(0.0, 1.0))
                        : null,
                    dashed: _controller.dashedStroke,
                    livePath: vertexPreview,
                    selectionRect: _resizeHandle != null
                        ? _resizeRect
                        : chrome?.$1.shift(moveDelta),
                    extraSelectionRects: extraSelected,
                    marqueeRect:
                        _marqueeStart != null && _marqueeCurrent != null
                            ? Rect.fromPoints(_marqueeStart!, _marqueeCurrent!)
                            : null,
                    ghost: wrapResize == null && shapeResize == null
                        ? _ghost
                        : null,
                    shapeResize: shapeResize,
                    ghostFrom: _resizeHandle != null && _resizeAngle != 0
                        ? _resizeFrom
                        : selected,
                    ghostTo: _resizeHandle != null
                        ? _resizeRect
                        : selected?.shift(moveDelta),
                    dragging: dragging,
                    rotation: restingRotation + (rotating ? _rotateDelta : 0),
                    ghostRotation: rotating ? _rotateDelta : 0,
                    ghostLocalAngle: _resizeHandle != null ? _resizeAngle : 0,
                    ghostFlipX: _resizeHandle != null && _resizeFlipX,
                    ghostFlipY: _resizeHandle != null && _resizeFlipY,
                    // free-text resize lift: hide the original box's
                    // footprint with the page rendered without it (or an
                    // opaque-paper wash until that lands). After the commit
                    // the same lift carries on (kept alive as
                    // [_afterTextClean]) so a transparent box's afterimage
                    // shows page content behind it, not an opaque flash.
                    resizeClean: wrapResize != null
                        ? _resizeCleanPicture
                        : _afterTextClean,
                    resizeHideRect:
                        wrapResize != null ? _resizeFrom : _afterTextHideRect,
                    resizeHideAngle:
                        wrapResize != null ? _resizeAngle : _afterTextHideAngle,
                    resizeHideWash: Color.alphaBlend(
                        widget.pageColor, const Color(0xFFFFFFFF)),
                    extraInk: extraInk,
                    fadeRects: [
                      ..._eraseRects.values,
                      ...?_afterEraseRects,
                    ],
                    fadeInk: [
                      ..._eraseFade.values,
                      ...?_afterEraseFade,
                    ],
                    fadeColor: widget.pageColor.withValues(alpha: 0.72),
                    eraserCursor:
                        _tool == PdfEditTool.eraser || _pointers.rawErasing
                            ? _eraserCursor
                            : null,
                    eraserRadius: _controller.preferences.eraserRadius * _geometry.scale,
                    // the pen-preview dot (ink tool) and the rotation glyph
                    // (rotate knob): painted in place of the system cursor
                    penCursor:
                        _inkTool && _activeStroke == null ? _penCursor : null,
                    penOpacity: _controller.preferences.opacity,
                    countPreview:
                        _tool == PdfEditTool.count && _countCursor != null
                            ? _countPreviewAt(_countCursor!)
                            : null,
                    stampPreview: _tool == PdfEditTool.stamp &&
                            _dragStart == null &&
                            _stampPreview != null
                        ? _stampHoverAfterimageAt(_stampPreview!)
                        : null,
                    rotateCursor: _rotateCursor,
                    afterGhost: afterGhost,
                    afterShape: _afterShape,
                    afterStamp: _afterStamp,
                    afterPath: _afterPath,
                    showHandles: selected != null &&
                        _controller.canResizeSelected &&
                        !_selectedLineFamily &&
                        _moveStart == null,
                    showRotateHandle: selected != null &&
                        _controller.canRotateSelected &&
                        _moveStart == null,
                    vertexHandles:
                        _moveStart == null ? vertexHandles : const <Offset>[],
                    elementRect: _selectedElementViewRect,
                    flashRect:
                        _flashController.isAnimating && _flashRect != null
                            ? _geometry.toViewRect(_flashRect!)
                            : null,
                    flashProgress: _flashController.value,
                    redactionRects: _redactionViewRects,
                  ),
                  size: Size.infinite,
                ),
              ),
              // The in-progress pencil/mouse stroke, isolated on its own
              // RepaintBoundary and repainted via _activeStrokeRepaint. While
              // a stroke is live nothing above rebuilds, so only this layer
              // re-rasterizes per appended point - the latency fix.
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ActiveStrokePainter(this),
                    size: Size.infinite,
                  ),
                ),
              ),
              // a free-text resize in flight: the text re-wrapped to the
              // dragged box at its committed size - never the ghost's
              // stretched glyphs. The original box is hidden by the
              // painter's lift layer (the page rendered without it), so
              // this preview is TRANSPARENT save for the box's own fill:
              // the page content behind it shows through, Acrobat-style.
              if (wrapResize != null)
                _wrappedTextBox(
                  key: const ValueKey('pdf-text-resize-preview'),
                  rect: _resizeRect!,
                  text: wrapResize.text,
                  font: wrapResize.font,
                  size: wrapResize.size,
                  color: wrapResize.color,
                  background: wrapResize.fill,
                  rotation: _resizeAngle,
                  align: wrapResize.align,
                  underline: wrapResize.underline,
                  lineSpacing: wrapResize.lineSpacing,
                ),
              // a just-committed text edit, frozen until the page raster
              // catches up (same wash the inline editor painted over old
              // renderings, so nothing shows through meanwhile)
              if (_afterText case final after?)
                _wrappedTextBox(
                  rect: after.rect,
                  text: after.text,
                  font: after.font,
                  size: after.size,
                  color: after.color,
                  background: after.fill ??
                      (after.washed
                          ? widget.pageColor.withValues(alpha: 0.92)
                          : null),
                  rotation: after.rotation,
                  align: after.align,
                  underline: after.underline,
                  lineSpacing: after.lineSpacing,
                ),
              if (preview != null)
                Positioned(
                  left: preview.dx + 14,
                  top: preview.dy - 38,
                  child: IgnorePointer(
                    child: _EyedropperChip(color: _pickPreview),
                  ),
                ),
              if (_textEditRect != null)
                Positioned.fromRect(
                  rect: _textEditRect!.inflate(2),
                  // identity at angle 0; spins the box about its center
                  // onto the resting rotation when editing rotated text
                  child: Transform.rotate(
                    angle: _textEditRotation,
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.escape):
                            _onEscapeTextEdit,
                        const SingleActivator(LogicalKeyboardKey.enter,
                            meta: true): _commitTextEdit,
                        const SingleActivator(LogicalKeyboardKey.enter,
                            control: true): _commitTextEdit,
                        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
                            () => _toggleInlineTextStyle(
                                  italic: false,
                                ),
                        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
                            () => _toggleInlineTextStyle(
                                  italic: false,
                                ),
                        const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
                            () => _toggleInlineTextStyle(
                                  italic: true,
                                ),
                        const SingleActivator(LogicalKeyboardKey.keyI, control: true):
                            () => _toggleInlineTextStyle(
                                  italic: true,
                                ),
                        const SingleActivator(LogicalKeyboardKey.keyU, meta: true):
                            _toggleInlineUnderline,
                        const SingleActivator(LogicalKeyboardKey.keyU, control: true):
                            _toggleInlineUnderline,
                      },
                      child: Container(
                        // the chrome border lives in the inflate(2) gutter
                        // and paints as a FOREGROUND decoration: a regular
                        // decoration border adds itself to the padding, and
                        // any net inset shifts the text when the editor
                        // opens - content must sit exactly on the box
                        padding: const EdgeInsets.all(2),
                        // the box's own fill when it has one; otherwise wash
                        // the paper color over what's underneath: faint for a
                        // fresh box, fully opaque when editing existing text
                        // so the old rendering doesn't ghost through and read
                        // as a misaligned shadow behind the live text
                        color: _textEditFill ??
                            widget.pageColor
                                .withValues(alpha: _textEditExisting ? 1 : 0.3),
                        foregroundDecoration: BoxDecoration(
                          border: Border.all(
                              color: PdfViewerTheme.of(context)
                                      .annotationChromeColor ??
                                  const Color(0xFF1E88E5),
                              width: 1.5 * _chromeScale),
                        ),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _textEditText,
                          builder: (context, value, _) {
                            final direction = _flutterTextDirection(value.text);
                            return Directionality(
                              textDirection: direction,
                              child: TextField(
                                key: ValueKey(_textEditFieldName == null
                                    ? 'pdf-freetext-editor'
                                    : 'pdf-form-text-editor'),
                                controller: _textEditText,
                                focusNode: _textEditFocus,
                                autofocus: true,
                                // single-line form fields edit single-line:
                                // Enter commits instead of inserting a newline
                                maxLines: _textEditFieldName == null ||
                                        _textEditMultiline
                                    ? null
                                    : 1,
                                expands: _textEditFieldName == null ||
                                    _textEditMultiline,
                                onSubmitted: (_) => _commitTextEdit(),
                                textDirection: direction,
                                // free text follows the box's /Q alignment so
                                // the live text sits where it commits; a box
                                // with no explicit /Q (and form fields) stays
                                // direction-aware start-aligned
                                textAlign: _textEditFieldName == null &&
                                        _textEditAlign != null
                                    ? _flutterTextAlign(_textEditAlign!)
                                    : TextAlign.start,
                                textAlignVertical: _textEditFieldName == null ||
                                        _textEditMultiline
                                    ? TextAlignVertical.top
                                    : TextAlignVertical.center,
                                // pin line height to the box's leading so the
                                // preview spacing is font-independent, matching
                                // the committed appearance - changing a run's
                                // font no longer nudges the lines until commit
                                strutStyle: _textEditFieldName == null
                                    ? StrutStyle(
                                        fontSize: _textEditText.maxStyleSize *
                                            _geometry.scale,
                                        height: _textEditLineSpacing,
                                        forceStrutHeight: true,
                                      )
                                    : null,
                                cursorColor: _textEditColor,
                                cursorWidth: 2 * _chromeScale,
                                selectionControls: _ScaledTextSelectionControls(
                                    _chromeScale,
                                    _inlineTextHandleColor(context)),
                                contextMenuBuilder:
                                    (context, editableTextState) {
                                  final menu =
                                      AdaptiveTextSelectionToolbar.editableText(
                                          editableTextState: editableTextState);
                                  if (_chromeScale == 1) return menu;
                                  return Transform.scale(
                                    scale: _chromeScale,
                                    alignment: Alignment.topCenter,
                                    child: menu,
                                  );
                                },
                                // mirrors the committed appearance: same size
                                // in view pixels, same leading/spacing,
                                // matching family, color and underline
                                style: TextStyle(
                                  color: _textEditColor,
                                  fontSize: _textEditSize * _geometry.scale,
                                  height: _textEditLineSpacing,
                                  letterSpacing:
                                      _textEditCharSpacing * _geometry.scale,
                                  fontFamily: _textEditUiFamily(_textEditFont),
                                  fontWeight: _textEditFont.isBold
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontStyle: _textEditFont.isItalic
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  decoration:
                                      _textEditText.defaultStyle.underline
                                          ? TextDecoration.underline
                                          : null,
                                ),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  // PDF free-text appearances put the first
                                  // baseline exactly one ascent below the top
                                  // padding. Flutter splits the extra 1.2
                                  // line-height leading above and below
                                  // editable text, so trim that half-leading
                                  // from the top padding to avoid a small
                                  // edit-time layout jump.
                                  contentPadding: EdgeInsets.fromLTRB(
                                    3 * _geometry.scale,
                                    math.max(
                                      0,
                                      3 * _geometry.scale -
                                          0.1 * _textEditSize * _geometry.scale,
                                    ),
                                    3 * _geometry.scale,
                                    3 * _geometry.scale,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              if (_textEditRect != null &&
                  _textEditFieldName == null &&
                  _controller.hasTouchInput)
                _buildInlineTextStyleChip(_textEditRect!),
              if (showChip) _buildSelectionChip(chrome?.$1 ?? selected),
              if (_measureReadout() case (final text, final anchor))
                _buildReadoutChip(text, anchor),
              if (_styleReadout() case (final text, final anchor))
                _buildReadoutChip(text, anchor, keyValue: 'pdf-style-readout'),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The overlay's context-menu long-press: touch and stylus only, and it
/// only enters the gesture arena when [shouldClaim] says the press point
/// has a menu to offer - otherwise a held finger must stay available to
/// text selection, marquees, and slow move drags.
class _MenuLongPressRecognizer extends LongPressGestureRecognizer {
  _MenuLongPressRecognizer({super.debugOwner})
      : super(supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        });

  bool Function(Offset localPosition)? shouldClaim;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (shouldClaim?.call(event.localPosition) == false) return;
    super.addAllowedPointer(event);
  }
}

/// The eyedropper's floating preview: the color under the pointer and
/// its hex value, riding beside the cursor.
class _EyedropperChip extends StatelessWidget {
  const _EyedropperChip({required this.color});

  /// Null while the page raster is still being built (or off the page).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color ?? Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            color == null
                ? '…'
                : '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ]),
      ),
    );
  }
}

/// Paints page-space ink [strokes] with the committed appearance's
/// Catmull-Rom smoothing and pressure-mapped width. Shared by the heavy
/// preview painter (buffered/committed strokes) and the lightweight
/// [_ActiveStrokePainter] (the single in-progress stroke).
void _paintInkStrokes(
    Canvas canvas,
    PdfPageGeometry geometry,
    List<List<(double, double)>> strokes,
    List<List<double>?> pressures,
    Color color,
    double strokeWidth) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  for (var s = 0; s < strokes.length; s++) {
    final stroke = strokes[s];
    final pressure = s < pressures.length ? pressures[s] : null;
    if (stroke.isEmpty) continue;
    if (stroke.length == 1) {
      final p = geometry.toViewOffset(stroke.single.$1, stroke.single.$2);
      final width = pressure == null
          ? strokeWidth
          : pdfInkStrokeWidth(strokeWidth, pressure.first);
      canvas.drawCircle(p, width / 2, Paint()..color = color);
      continue;
    }
    // the same Catmull-Rom smoothing the committed appearance uses
    final controls = pdfInkCurveControls(stroke);
    if (pressure != null) {
      // matches the committed appearance: a stroked spline segment per
      // point pair at its own pressure-mapped width, round caps as the
      // seams
      final segment = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < stroke.length - 1; i++) {
        final (xa, ya) = stroke[i];
        final ((c1x, c1y), (c2x, c2y)) = controls[i];
        final a = geometry.toViewOffset(xa, ya);
        final c1 = geometry.toViewOffset(c1x, c1y);
        final c2 = geometry.toViewOffset(c2x, c2y);
        final b = geometry.toViewOffset(stroke[i + 1].$1, stroke[i + 1].$2);
        segment.strokeWidth =
            pdfInkStrokeWidth(strokeWidth, (pressure[i] + pressure[i + 1]) / 2);
        canvas.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy),
            segment);
      }
      continue;
    }
    final start = geometry.toViewOffset(stroke.first.$1, stroke.first.$2);
    final path = Path()..moveTo(start.dx, start.dy);
    for (var i = 0; i < stroke.length - 1; i++) {
      final ((c1x, c1y), (c2x, c2y)) = controls[i];
      final c1 = geometry.toViewOffset(c1x, c1y);
      final c2 = geometry.toViewOffset(c2x, c2y);
      final p = geometry.toViewOffset(stroke[i + 1].$1, stroke[i + 1].$2);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// The single in-progress pencil/mouse stroke, on its own RepaintBoundary.
///
/// Reads the live stroke buffers straight off the overlay state and repaints
/// only when [_EditingPageOverlayState._activeStrokeRepaint] ticks - so a
/// pointer-move appends a point and bumps the notifier without rebuilding the
/// overlay or the heavy [_EditingPreviewPainter]. [shouldRepaint] stays false:
/// the repaint Listenable is the sole driver (the start, every point, and the
/// clear on commit/bail all tick it), and the buffers are mutated in place so
/// the painter always sees the current points.
class _ActiveStrokePainter extends CustomPainter {
  _ActiveStrokePainter(this._state)
      : super(repaint: _state._activeStrokeRepaint);

  final _EditingPageOverlayState _state;

  @visibleForTesting
  Offset? get debugPenCursor => _state._penCursor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = _state._activeStroke;
    if (stroke == null || stroke.isEmpty) return;
    final geometry = _state._geometry;
    var display = stroke;
    var pressures = _state._activeStrokePressures;
    // a forward-extrapolated lead so the line keeps up with the pen tip -
    // display only, recomputed each repaint (so the next real sample
    // replaces it) and never folded into the committed stroke
    if (_state.widget.predictStrokes) {
      final lead = pdfPredictStrokeLead(stroke);
      if (lead.isNotEmpty) {
        display = [...stroke, ...lead];
        if (pressures != null) {
          pressures = [...pressures, for (final _ in lead) pressures.last];
        }
      }
    }
    _paintInkStrokes(
      canvas,
      geometry,
      [display],
      [pressures],
      _state._controller.color,
      _state._controller.preferences.strokeWidth * geometry.scale,
    );
    final cursor = _state._penCursor;
    if (cursor != null && _state._inkTool) {
      _paintPenCursor(
        canvas,
        cursor,
        strokeWidth: _state._controller.preferences.strokeWidth * geometry.scale,
        chromeScale: _state._chromeScale,
        color: _state._controller.color,
        opacity: _state._controller.preferences.opacity,
      );
    }
  }

  @override
  bool shouldRepaint(_ActiveStrokePainter oldDelegate) => false;
}

void _paintPenCursor(
  Canvas canvas,
  Offset center, {
  required double strokeWidth,
  required double chromeScale,
  required Color color,
  required double opacity,
}) {
  final r = math.max(strokeWidth / 2, 1.5 * chromeScale);
  canvas.drawCircle(
      center, r + 1.5 * chromeScale, Paint()..color = const Color(0x33000000));
  canvas.drawCircle(
      center, r, Paint()..color = color.withValues(alpha: opacity));
  canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = const Color(0xB3FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * chromeScale);
}

class _EditingPreviewPainter extends CustomPainter {
  _EditingPreviewPainter({
    required this.theme,
    this.chromeScale = 1,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.geometry,
    required this.strokes,
    required this.pressures,
    required this.dragRect,
    required this.dragLine,
    this.calloutLeader,
    required this.dragPath,
    this.dragPathFill,
    required this.dashed,
    required this.livePath,
    required this.selectionRect,
    required this.extraSelectionRects,
    required this.marqueeRect,
    required this.ghost,
    required this.ghostFrom,
    required this.ghostTo,
    this.shapeResize,
    required this.dragging,
    required this.rotation,
    required this.ghostRotation,
    this.ghostLocalAngle = 0,
    this.ghostFlipX = false,
    this.ghostFlipY = false,
    this.resizeClean,
    this.resizeHideRect,
    this.resizeHideAngle = 0,
    this.resizeHideWash = const Color(0xFFFFFFFF),
    required this.extraInk,
    this.fadeRects = const [],
    this.fadeInk = const [],
    this.fadeColor = const Color(0x00000000),
    this.eraserCursor,
    this.eraserRadius = 0,
    this.penCursor,
    this.penOpacity = 1,
    this.countPreview,
    this.stampPreview,
    this.rotateCursor,
    required this.afterGhost,
    required this.afterShape,
    required this.afterStamp,
    required this.afterPath,
    required this.showHandles,
    required this.showRotateHandle,
    required this.vertexHandles,
    required this.elementRect,
    this.flashRect,
    this.flashProgress = 0,
    this.redactionRects = const [],
  });

  /// View-space rects of marked (unburned) /Redact annotations on this
  /// page, drawn with a hatched preview so they read as "to be redacted".
  final List<Rect> redactionRects;

  final PdfEditTool? tool;
  final Color color;
  final double strokeWidth;
  final PdfPageGeometry geometry;
  final List<List<(double, double)>> strokes;

  /// Parallels [strokes]: per-point normalized pressures, or null for a
  /// uniform-width stroke.
  final List<List<double>?> pressures;

  final Rect? dragRect;
  final (Offset, Offset)? dragLine;

  /// A callout leader to paint from its terminus to its base while the box is
  /// being placed/edited (before the annotation exists) or while the terminus
  /// or base handle is being dragged: (terminus, base, color, strokeWidth).
  final (Offset, Offset, Color, double)? calloutLeader;
  final List<Offset>? dragPath;

  /// The interior fill for an in-progress polygon [dragPath], so drawing a
  /// filled polygon previews the fill. Null leaves the path outline-only.
  final Color? dragPathFill;
  final bool dashed;
  final ({
    List<Offset> points,
    PdfEditTool tool,
    Color color,
    Color? fillColor,
    double strokeWidth,
    bool dashed,
  })? livePath;
  final Rect? selectionRect;

  /// The non-primary members of a multi-selection on this page: chrome
  /// boxes without handles.
  final List<Rect> extraSelectionRects;

  /// The select tool's in-flight rubber band.
  final Rect? marqueeRect;

  /// The selected annotation's appearance in page raster space, and its
  /// resting view rect - drawn stretched onto [ghostTo] while
  /// [dragging], so the user sees the move/resize result live.
  final ui.Picture? ghost;
  final Rect? ghostFrom;
  final Rect? ghostTo;

  /// A Square/Circle resize preview (or its committed afterimage) drawn
  /// with a constant stroke width - the shape regenerates rather than
  /// stretching, so the ghost is suppressed in its favour.
  final _ShapeResize? shapeResize;
  final bool dragging;

  /// The chrome's total rotation (view radians, clockwise positive):
  /// the annotation's resting rotation plus a rotate drag's sweep - the
  /// selection box hugs rotated artwork instead of boxing its bounds.
  final double rotation;

  /// A rotate drag's sweep alone: the ghost's appearance already carries
  /// the resting rotation, so only the delta spins it.
  final double ghostRotation;

  /// A rotated selection's resting angle during a resize drag:
  /// [ghostFrom]/[ghostTo] are then local boxes and the ghost scales
  /// along the rotated axes instead of stretching page-axis rects.
  final double ghostLocalAngle;

  /// A resize drag that crossed the 0 point: the ghost mirrors along the
  /// flipped axis (about [ghostTo]'s center / local axes) so the live
  /// preview matches the inverted artwork the commit produces.
  final bool ghostFlipX;
  final bool ghostFlipY;

  /// The free-text resize "lift": the page rendered without the dragged
  /// box ([resizeClean], page raster space at 1 unit = 1 point), clipped
  /// to that box's original footprint [resizeHideRect] (a view rect, spun
  /// by [resizeHideAngle]) so the page content behind it shows through
  /// instead of the original. A null [resizeClean] falls back to an opaque
  /// [resizeHideWash] (blank paper) until the async render lands, so the
  /// original never flashes. Painted before the chrome and the floating
  /// re-wrapped preview, so both sit on top.
  final ui.Picture? resizeClean;
  final Rect? resizeHideRect;
  final double resizeHideAngle;
  final Color resizeHideWash;

  /// Stroke sets beyond the pending ink: committed-ink afterimages and
  /// the signature tool's live preview.
  final List<_InkPaint> extraInk;

  /// Inkless annotations the eraser swipe will delete whole: their view
  /// rects, washed with [fadeColor] (the paper color, mostly opaque) so
  /// they read as going - live during the swipe, and as the afterimage
  /// until the deletion's raster lands.
  final List<Rect> fadeRects;

  /// Sliceable ink the eraser swipe has touched: the original strokes,
  /// washed with [fadeColor] along their own paths (not the bounding
  /// box) so the baked-in ink fades without dimming the page content
  /// around it or spilling off the page.
  final List<_InkPaint> fadeInk;
  final Color fadeColor;

  /// The circle eraser's ring cursor: view position and radius (the
  /// page-space eraser radius scaled into view pixels, so the ring is
  /// exactly the area the eraser removes at any zoom).
  final Offset? eraserCursor;
  final double eraserRadius;

  /// The ink tool's pen-preview cursor: a filled dot in [color] at
  /// [penOpacity], sized to the pen width ([strokeWidth], view pixels),
  /// painted in place of the system cursor so the colour and width that
  /// will be drawn are visible before the stroke starts.
  final Offset? penCursor;
  final double penOpacity;

  /// The count tool's hover preview: the check mark that a click will place,
  /// already clamped to the same page-space rect as the committed annotation.
  final _StampAfterimage? countPreview;

  /// The stamp tool's hover preview: the active custom stamp that a click
  /// will place, already clamped to the same rect as the committed annotation.
  final _StampAfterimage? stampPreview;

  /// The rotate knob's cursor: a small curved-arrow glyph painted here
  /// (Flutter has no built-in rotation cursor, so the system cursor is
  /// hidden over the knob and this tracks the pointer instead).
  final Offset? rotateCursor;

  /// A just-committed move/resize/rotate, kept painted at full strength
  /// until the new revision's raster lands. [source] is the old
  /// on-raster position; when [sourceClean] is ready, that rect is restored
  /// from a clean page render so no duplicate or paper-colored box remains.
  final _AfterGhost? afterGhost;

  /// A just-committed shape's drag preview, same deal.
  final ({
    Rect rect,
    PdfEditTool tool,
    Color color,
    double strokeWidth
  })? afterShape;

  /// A just-committed tap/drag stamp preview, held until the new raster lands.
  final _StampAfterimage? afterStamp;

  /// A just-committed line-family preview, held until the new raster lands.
  final ({
    List<Offset> points,
    PdfEditTool tool,
    Color color,
    Color? fillColor,
    double strokeWidth,
    bool dashed,
  })? afterPath;

  final bool showHandles;
  final bool showRotateHandle;
  final List<Offset>? vertexHandles;

  /// The selected content element's box - orange, to read as "page
  /// content", distinct from the blue annotation chrome.
  final Rect? elementRect;

  /// An attention pulse around [flashRect] (the annotation a sidebar
  /// tile zoomed to), animated by [flashProgress] 0→1: an amber ring
  /// closing in on the rect, fading as it settles.
  final Rect? flashRect;
  final double flashProgress;

  final PdfViewerThemeData theme;

  /// Overlay pixels per intended screen pixel - chrome (selection boxes,
  /// handles, marquee, flash ring) multiplies its sizes by this so it
  /// stays constant-size on screen while the viewer is zoomed in.
  final double chromeScale;

  Color get _chrome => theme.annotationChromeColor ?? const Color(0xFF1E88E5);
  Color get _elementChrome =>
      theme.elementChromeColor ?? const Color(0xFFFB8C00);
  Color get _flash => theme.flashColor ?? const Color(0xFFFFB300);

  /// Paints one set of page-space ink strokes with the committed
  /// appearance's smoothing and pressure mapping.
  void _paintInk(Canvas canvas, List<List<(double, double)>> strokes,
          List<List<double>?> pressures, Color color, double strokeWidth) =>
      _paintInkStrokes(
          canvas, geometry, strokes, pressures, color, strokeWidth);

  void _paintShapePreview(
      Canvas canvas, Rect rect, PdfEditTool? tool, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (tool) {
      case PdfEditTool.ellipse:
        canvas.drawOval(rect, paint);
      case PdfEditTool.cloudPolygon:
        _paintCloudPolygon(
            canvas,
            [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft],
            color,
            null,
            width,
            false);
      case PdfEditTool.freeText || PdfEditTool.stamp || PdfEditTool.form:
        canvas.drawRect(
            rect,
            Paint()
              ..color = color.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1 * chromeScale);
      case PdfEditTool.redact:
        paintRedactionHatch(canvas, rect, chromeScale: chromeScale);
      case PdfEditTool.snapshot || PdfEditTool.signatureBox:
        // a selection marquee: the region grab in a screenshot tool, and the
        // "draw where the signature goes" box in Acrobat/Bluebeam
        canvas.drawRect(rect, Paint()..color = _chrome.withAlpha(0x1A));
        canvas.drawRect(
            rect,
            Paint()
              ..color = _chrome
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1 * chromeScale);
      default:
        canvas.drawRect(rect, paint);
    }
  }

  void _paintCloudPolygon(Canvas canvas, List<Offset> points, Color color,
      Color? fillColor, double width, bool dashed) {
    if (points.length < 3) return;
    final cloud = _cloudPath(points, width);
    if (fillColor != null) {
      // Fill the scalloped outline itself so the interior colour reaches the
      // puffed edges, matching the committed appearance stream.
      canvas.drawPath(
          cloud,
          Paint()
            ..color = fillColor
            ..style = PaintingStyle.fill);
    }
    canvas.drawPath(
        dashed ? _dashPath(cloud, width) : cloud,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  /// Extra bulge past a semicircle so scallops read as overlapping puffs.
  /// Mirrors `_cloudBulgeFactor` in pdf_document's annotation_editor so the
  /// live preview matches the committed appearance stream.
  static const double _cloudBulgeFactor = 1.15;

  /// Fraction of the bulge by which the shared foot between puffs is pulled
  /// inward, deepening the pinched cusp. Mirrors `_cloudNeckInset` in
  /// pdf_document's annotation_editor so the preview matches the committed
  /// appearance.
  static const double _cloudNeckInset = 0.2;

  /// Tangential forward lean of each puff's trailing (end) foot control handle
  /// (fraction of the perpendicular foot handle length) - this is what curls
  /// the scallops into rounder, asymmetric rolled puffs. Mirrors
  /// `_cloudNeckCurl` in pdf_document's annotation_editor so the preview
  /// matches the committed appearance.
  static const double _cloudNeckCurl = 0.75;

  Path _cloudPath(List<Offset> points, double strokeWidth) {
    final path = Path();
    if (points.length < 3) return path;
    final clockwise = _signedArea(points) < 0;
    // The appearance stream uses max(12, sw*4) *page* points; map that arc
    // radius into view space (strokeWidth here is already scaled) so the
    // preview and the saved cloud line up scallop-for-scallop.
    final arc = math.max(12.0 * geometry.scale, strokeWidth * 4.0);
    const k = 0.5522847498307936;
    var first = true;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final delta = b - a;
      final length = delta.distance;
      if (length < 0.01) continue;
      final scallops = math.max(1, (length / (2 * arc)).round());
      final unit = delta / length;
      final normal =
          clockwise ? Offset(-unit.dy, unit.dx) : Offset(unit.dy, -unit.dx);
      final chord = length / scallops;
      final r = chord / 2;
      final bulge = math.min(r, arc) * _cloudBulgeFactor;
      final ca = r * k; // apex control handle, along the edge
      final cf = bulge * k; // foot control handle, perpendicular (outward)
      final inset = bulge * _cloudNeckInset; // pull cusp inward
      final curl = cf * _cloudNeckCurl; // tangential lean that rounds each puff
      for (var j = 0; j < scallops; j++) {
        final t0 = j / scallops;
        final t1 = (j + 1) / scallops;
        // Apex height is measured from the edge (before insetting the feet) so
        // the outward extent matches the committed appearance stream.
        final mid = Offset.lerp(a, b, (t0 + t1) / 2)!;
        final start = Offset.lerp(a, b, t0)! - normal * inset;
        final end = Offset.lerp(a, b, t1)! - normal * inset;
        final apex = mid + normal * bulge;
        if (first) {
          path.moveTo(start.dx, start.dy);
          first = false;
        }
        // Only the trailing (end) foot leans forward (+u); the leading foot
        // stays upright, so each scallop rolls the same way (see annotation
        // editor's _appendCloudPath).
        path.cubicTo(
          start.dx + normal.dx * cf,
          start.dy + normal.dy * cf,
          apex.dx - unit.dx * ca,
          apex.dy - unit.dy * ca,
          apex.dx,
          apex.dy,
        );
        path.cubicTo(
          apex.dx + unit.dx * ca,
          apex.dy + unit.dy * ca,
          end.dx + normal.dx * cf + unit.dx * curl,
          end.dy + normal.dy * cf + unit.dy * curl,
          end.dx,
          end.dy,
        );
      }
    }
    path.close();
    return path;
  }

  double _signedArea(List<Offset> points) {
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    return area / 2;
  }

  void _paintStampAfterimage(Canvas canvas, _StampAfterimage stamp) {
    final rect = stamp.rect;
    if (rect.isEmpty) return;
    final color = stamp.color.withValues(alpha: stamp.opacity);
    final template = stamp.template;
    if (template != null) {
      _paintStampTemplateAfterimage(canvas, rect, template, stamp.opacity);
      return;
    }
    if (stamp.check) {
      final s = math.min(rect.width, rect.height);
      if (s <= 0) return;
      final ox = rect.left + (rect.width - s) / 2;
      final oy = rect.top + (rect.height - s) / 2;
      final path = Path()
        ..moveTo(ox + s * 0.18, oy + s * 0.50)
        ..lineTo(ox + s * 0.42, oy + s * 0.74)
        ..lineTo(ox + s * 0.82, oy + s * 0.26);
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.16
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      return;
    }

    final borderWidth = math.max(0.5, 2 * geometry.scale);
    final pad = 6 * geometry.scale;
    final box = rect.deflate(borderWidth / 2);
    if (box.width > 0 && box.height > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, Radius.circular(4 * geometry.scale)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth);
    }

    final text = stamp.text;
    if (text == null || text.isEmpty) return;
    final availableWidth = math.max(0.0, rect.width - 2 * pad);
    final availableHeight = math.max(0.0, rect.height - 2 * pad);
    if (availableWidth == 0 || availableHeight == 0) return;
    var fontSize = availableHeight * 0.72;
    if (fontSize <= 0) return;

    TextPainter painterFor(double size) => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: color,
              fontFamily: 'Helvetica',
              fontWeight: FontWeight.bold,
              fontSize: size,
              height: 1,
            ),
          ),
          textDirection: _flutterTextDirection(text),
          maxLines: 1,
        )..layout(maxWidth: double.infinity);

    var textPainter = painterFor(fontSize);
    if (textPainter.width > availableWidth && textPainter.width > 0) {
      fontSize *= availableWidth / textPainter.width;
      textPainter = painterFor(fontSize);
    }
    textPainter.paint(
        canvas,
        Offset(rect.left + (rect.width - textPainter.width) / 2,
            rect.top + (rect.height - textPainter.height) / 2));
  }

  void _paintStampTemplateAfterimage(
      Canvas canvas, Rect rect, PdfStampTemplate template, double opacity) {
    if (!template.isValid || rect.isEmpty) return;
    canvas.saveLayer(
        rect,
        Paint()
          ..color = const Color(0xFFFFFFFF)
              .withValues(alpha: opacity.clamp(0.0, 1.0)));
    final sx = rect.width / template.width;
    final sy = rect.height / template.height;
    final strokeScale = math.min(sx, sy);
    for (final component in template.components) {
      if (component.width <= 0 || component.height <= 0) continue;
      final componentRect = Rect.fromLTWH(
        rect.left + component.x * sx,
        rect.top + component.y * sy,
        component.width * sx,
        component.height * sy,
      );
      _paintStampTemplateComponent(
          canvas, component, componentRect, strokeScale);
    }
    canvas.restore();
  }

  void _paintStampTemplateComponent(Canvas canvas,
      PdfStampTemplateComponent component, Rect rect, double strokeScale) {
    final strokeWidth = math.max(0.1, component.strokeWidth * strokeScale);
    switch (component.type) {
      case PdfStampTemplateComponentType.rectangle:
        final shape = rect.deflate(strokeWidth / 2);
        if (shape.isEmpty) return;
        final rrect = RRect.fromRectAndRadius(
            shape, Radius.circular(component.radius * strokeScale));
        if (component.fillColor != null) {
          canvas.drawRRect(
              rrect, Paint()..color = Color(0xFF000000 | component.fillColor!));
        }
        canvas.drawRRect(
            rrect,
            Paint()
              ..color = Color(0xFF000000 | component.color)
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth);
      case PdfStampTemplateComponentType.ellipse:
        final shape = rect.deflate(strokeWidth / 2);
        if (shape.isEmpty) return;
        if (component.fillColor != null) {
          canvas.drawOval(
              shape, Paint()..color = Color(0xFF000000 | component.fillColor!));
        }
        canvas.drawOval(
            shape,
            Paint()
              ..color = Color(0xFF000000 | component.color)
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth);
      case PdfStampTemplateComponentType.text:
        final text = component.text.trim();
        if (text.isEmpty || rect.width <= 0 || rect.height <= 0) return;
        var fontSize =
            (component.fontSize ?? component.height * 0.72) * strokeScale;
        fontSize = math.min(fontSize, rect.height * 0.9);
        if (fontSize <= 0) return;
        TextPainter painterFor(double size) => TextPainter(
              text: TextSpan(
                text: text,
                style: TextStyle(
                  color: Color(0xFF000000 | component.color),
                  fontFamily: _textEditUiFamily(component.font),
                  fontWeight: component.font.isBold
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontStyle: component.font.isItalic
                      ? FontStyle.italic
                      : FontStyle.normal,
                  fontSize: size,
                  height: 1,
                ),
              ),
              textDirection: _flutterTextDirection(text),
              maxLines: 1,
            )..layout(maxWidth: double.infinity);
        var textPainter = painterFor(fontSize);
        if (textPainter.width > rect.width && textPainter.width > 0) {
          fontSize *= rect.width / textPainter.width;
          textPainter = painterFor(fontSize);
        }
        textPainter.paint(
            canvas,
            Offset(rect.left + (rect.width - textPainter.width) / 2,
                rect.top + (rect.height - textPainter.height) / 2));
      case PdfStampTemplateComponentType.image:
        canvas.drawRect(
            rect, Paint()..color = const Color(0xFFE0E0E0).withAlpha(0x99));
        canvas.drawRect(
            rect.deflate(0.5),
            Paint()
              ..color = Color(0xFF000000 | component.color)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.5, strokeScale));
      case PdfStampTemplateComponentType.signature:
        _paintStampTemplateSignature(canvas, component, rect, strokeScale);
    }
  }

  void _paintStampTemplateSignature(Canvas canvas,
      PdfStampTemplateComponent component, Rect rect, double strokeScale) {
    if (component.strokes.isEmpty || rect.width <= 0 || rect.height <= 0) {
      return;
    }
    final baseWidth = math.max(0.1, component.strokeWidth * strokeScale);
    final color = Color(0xFF000000 | component.color);
    for (var i = 0; i < component.strokes.length; i++) {
      final stroke = [
        for (final (x, y) in component.strokes[i])
          Offset(rect.left + x * rect.width, rect.top + y * rect.height),
      ];
      if (stroke.isEmpty) continue;
      final controls =
          pdfInkCurveControls([for (final p in stroke) (p.dx, p.dy)]);
      final pressure =
          i < component.pressures.length ? component.pressures[i] : null;
      if (stroke.length == 1) {
        canvas.drawCircle(
            stroke.single,
            pdfInkStrokeWidth(
                    baseWidth,
                    pressure == null || pressure.length != 1
                        ? 0.5
                        : pressure.first) /
                2,
            Paint()..color = color);
        continue;
      }
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (pressure == null || pressure.length != stroke.length) {
        paint.strokeWidth = baseWidth;
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (var j = 0; j < stroke.length - 1; j++) {
          final ((c1x, c1y), (c2x, c2y)) = controls[j];
          path.cubicTo(c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy);
        }
        canvas.drawPath(path, paint);
        continue;
      }
      for (var j = 0; j < stroke.length - 1; j++) {
        paint.strokeWidth =
            pdfInkStrokeWidth(baseWidth, (pressure[j] + pressure[j + 1]) / 2);
        final ((c1x, c1y), (c2x, c2y)) = controls[j];
        canvas.drawPath(
            Path()
              ..moveTo(stroke[j].dx, stroke[j].dy)
              ..cubicTo(c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy),
            paint);
      }
    }
  }

  /// Draws a Square/Circle at [s.rect] the way the editor regenerates it:
  /// a constant-width stroke inset by half its width (so it stays inside
  /// the rect, matching `_shapeContent`), an optional fill, rotated about
  /// the rect center and dimmed to the appearance's opacity. The
  /// constant width is the whole point - the ghost would stretch it.
  void _paintShapeResize(Canvas canvas, _ShapeResize s) {
    canvas.save();
    if (s.rotation != 0) {
      final c = s.rect.center;
      canvas
        ..translate(c.dx, c.dy)
        ..rotate(s.rotation)
        ..translate(-c.dx, -c.dy);
    }
    final layered = s.opacity < 1;
    if (layered) {
      canvas.saveLayer(s.rect.inflate(s.strokeWidth + 2),
          Paint()..color = Color.fromRGBO(0, 0, 0, s.opacity.clamp(0.0, 1.0)));
    }
    final stroking = s.stroke != null && s.strokeWidth > 0;
    final inset = stroking ? s.strokeWidth / 2 : 0.0;
    final box = s.rect.deflate(inset);
    if (s.fill != null && box.width > 0 && box.height > 0) {
      final paint = Paint()
        ..color = s.fill!
        ..style = PaintingStyle.fill;
      s.ellipse ? canvas.drawOval(box, paint) : canvas.drawRect(box, paint);
    }
    if (stroking && box.width > 0 && box.height > 0) {
      final paint = Paint()
        ..color = s.stroke!
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.strokeWidth;
      if (s.dashPattern == null) {
        s.ellipse ? canvas.drawOval(box, paint) : canvas.drawRect(box, paint);
      } else {
        final path = Path();
        s.ellipse ? path.addOval(box) : path.addRect(box);
        canvas.drawPath(_dashPath(path, s.strokeWidth, s.dashPattern), paint);
      }
    }
    if (layered) canvas.restore();
    canvas.restore();
  }

  void _paintPathPreview(Canvas canvas, List<Offset> points, PdfEditTool? tool,
      Color color, Color? fillColor, double width, bool dashed) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final closed = tool == PdfEditTool.polygon ||
        tool == PdfEditTool.cloudPolygon ||
        tool == PdfEditTool.measureArea;
    if (closed) {
      path.close();
      if (fillColor != null && tool != PdfEditTool.cloudPolygon) {
        canvas.drawPath(
            path,
            Paint()
              ..color = fillColor
              ..style = PaintingStyle.fill);
      }
    }
    if (tool == PdfEditTool.cloudPolygon && points.length >= 3) {
      _paintCloudPolygon(canvas, points, color, fillColor, width, dashed);
    } else {
      // For the cloud tool with fewer than three vertices there is no cloud
      // to draw yet, so this rubber-bands the straight edge instead - placing
      // the first side of a polygon cloud still gives live feedback.
      canvas.drawPath(dashed ? _dashPath(path, width) : path, paint);
    }
    if (tool == PdfEditTool.arrow) {
      final tip = points.last;
      final from = points[points.length - 2];
      final arrow = _arrowHead(tip, from, width);
      canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(arrow.$1.dx, arrow.$1.dy)
            ..lineTo(arrow.$2.dx, arrow.$2.dy)
            ..close(),
          Paint()
            ..color = color
            ..style = PaintingStyle.fill);
    }
    if (tool == PdfEditTool.callout) {
      // the terminus (arrow tip) is the FIRST point; draw the open arrow
      // there, matching the /OpenArrow the committed callout carries
      final tip = points.first;
      final from = points[1];
      final arrow = _arrowHead(tip, from, width);
      canvas.drawPath(
          Path()
            ..moveTo(arrow.$1.dx, arrow.$1.dy)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(arrow.$2.dx, arrow.$2.dy),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
  }

  /// Paints a callout leader from [terminus] to [base] with the open arrow at
  /// the terminus - mirrors the model's `/OpenArrow` so the on-screen preview
  /// matches what the committed annotation draws.
  void _paintCalloutLeader(
      Canvas canvas, Offset terminus, Offset base, Color color, double width) {
    _paintPathPreview(
        canvas, [terminus, base], PdfEditTool.callout, color, null, width,
        false);
  }

  Path _dashPath(Path path, double width, [List<double>? dashPattern]) {
    final out = Path();
    final pattern = dashPattern == null ||
            dashPattern.isEmpty ||
            !dashPattern.any((length) => length > 0)
        ? [math.max(2.0, width * 3), math.max(2.0, width * 2)]
        : [for (final length in dashPattern) math.max(0.01, length)];
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      var index = 0;
      while (distance < metric.length) {
        final next = math.min(distance + pattern[index], metric.length);
        if (draw) out.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next;
        draw = !draw;
        index = (index + 1) % pattern.length;
      }
    }
    return out;
  }

  (Offset, Offset) _arrowHead(Offset tip, Offset from, double width) {
    final delta = from - tip;
    final len = delta.distance;
    if (len == 0) return (tip, tip);
    final unit = delta / len;
    final size = math.max(10.0, width * 5);
    final half = size * 0.38;
    final base = tip + unit * size;
    final perp = Offset(-unit.dy, unit.dx);
    return (base + perp * half, base - perp * half);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // a free-text resize lifts the dragged box off the page: hide its
    // ORIGINAL footprint with the page rendered without it (the content
    // behind shows through) - or, until that async render lands, an opaque
    // paper wash. Drawn first so the chrome and the floating re-wrapped
    // preview paint on top.
    final hideRect = resizeHideRect;
    if (hideRect != null) {
      canvas.save();
      if (resizeHideAngle != 0) {
        canvas.translate(hideRect.center.dx, hideRect.center.dy);
        canvas.rotate(resizeHideAngle);
        canvas.translate(-hideRect.center.dx, -hideRect.center.dy);
      }
      // a hair of inflation swallows the original border's anti-aliased edge
      final clip = hideRect.inflate(1);
      canvas.clipRect(clip);
      final clean = resizeClean;
      if (clean != null) {
        // the clean page shares the ghost's raster space (1 unit = 1
        // point), so scaling by the view scale lands it on the page
        canvas.save();
        canvas.scale(geometry.scale);
        canvas.drawPicture(clean);
        canvas.restore();
      } else {
        canvas.drawRect(clip, Paint()..color = resizeHideWash);
      }
      canvas.restore();
    }

    // the wash goes under every stroke preview: the eraser's sliced
    // remainders (and any other pending ink) paint at full strength
    // over their faded originals. Sliceable ink fades along its own
    // strokes (so only the ink dims, not the page around it); inkless
    // whole-delete annotations fall back to a rect wash, clipped to the
    // page so it can't spill onto the viewer canvas.
    for (final ink in fadeInk) {
      _paintInk(canvas, ink.strokes, ink.pressures, fadeColor, ink.strokeWidth);
    }
    if (fadeRects.isNotEmpty) {
      final wash = Paint()..color = fadeColor;
      final page = Offset.zero & size;
      for (final rect in fadeRects) {
        final clipped = rect.inflate(2).intersect(page);
        if (!clipped.isEmpty) canvas.drawRect(clipped, wash);
      }
    }

    _paintInk(canvas, strokes, pressures, color, strokeWidth);
    for (final ink in extraInk) {
      _paintInk(canvas, ink.strokes, ink.pressures, ink.color, ink.strokeWidth);
    }

    final after = afterShape;
    if (after != null) {
      _paintShapePreview(
          canvas, after.rect, after.tool, after.color, after.strokeWidth);
    }

    final afterStamp = this.afterStamp;
    if (afterStamp != null) {
      _paintStampAfterimage(canvas, afterStamp);
    }

    final afterPath = this.afterPath;
    if (afterPath != null) {
      _paintPathPreview(
          canvas,
          afterPath.points,
          afterPath.tool,
          afterPath.color,
          afterPath.fillColor,
          afterPath.strokeWidth,
          afterPath.dashed);
    }

    final livePath = this.livePath;
    if (livePath != null) {
      _paintPathPreview(canvas, livePath.points, livePath.tool, livePath.color,
          livePath.fillColor, livePath.strokeWidth, livePath.dashed);
    }

    final line = dragLine;
    if (line != null) {
      _paintPathPreview(
          canvas, [line.$1, line.$2], tool, color, null, strokeWidth, dashed);
    } else if (dragPath != null) {
      _paintPathPreview(
          canvas, dragPath!, tool, color, dragPathFill, strokeWidth, dashed);
    } else if (dragRect case final rect?) {
      _paintShapePreview(canvas, rect, tool, color, strokeWidth);
    }

    if (calloutLeader case final leader?) {
      _paintCalloutLeader(canvas, leader.$1, leader.$2, leader.$3, leader.$4);
    }

    for (final rect in redactionRects) {
      paintRedactionHatch(canvas, rect, chromeScale: chromeScale);
    }

    for (final rect in extraSelectionRects) {
      final box = rect.inflate(2 * chromeScale);
      canvas.drawRect(box, Paint()..color = _chrome.withAlpha(0x1A));
      canvas.drawRect(
          box,
          Paint()
            ..color = _chrome
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * chromeScale);
    }

    final marquee = marqueeRect;
    if (marquee != null) {
      canvas.drawRect(marquee, Paint()..color = _chrome.withAlpha(0x14));
      canvas.drawRect(
          marquee,
          Paint()
            ..color = _chrome
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 * chromeScale);
    }

    final committed = afterGhost;
    if (committed != null) {
      final source = committed.source;
      final sourceClean = committed.sourceClean;
      if (source != null && sourceClean != null) {
        canvas.save();
        canvas.clipRect(source.inflate(2));
        canvas.scale(geometry.scale);
        canvas.drawPicture(sourceClean);
        canvas.restore();
      } else if (source != null && committed.sourceWash != null) {
        final page = Offset.zero & size;
        final clipped = source.inflate(2).intersect(page);
        if (!clipped.isEmpty) {
          canvas.drawRect(clipped, Paint()..color = committed.sourceWash!);
        }
      }
      // full strength: this *is* the committed result, standing in for
      // the raster that hasn't landed yet
      paintAnnotationDragPreview(canvas,
          picture: committed.picture,
          from: committed.from,
          to: committed.to,
          scale: geometry.scale,
          rotation: committed.rotation,
          localAngle: committed.localAngle,
          flipX: committed.flipX,
          flipY: committed.flipY,
          opacity: 1);
    }

    final selection = selectionRect;
    final ghost = this.ghost;
    final ghostFrom = this.ghostFrom;
    final ghostTo = this.ghostTo;
    if (dragging && ghostTo != null && ghost != null && ghostFrom != null) {
      paintAnnotationDragPreview(canvas,
          picture: ghost,
          from: ghostFrom,
          to: ghostTo,
          scale: geometry.scale,
          rotation: ghostRotation,
          localAngle: ghostLocalAngle,
          flipX: ghostFlipX,
          flipY: ghostFlipY);
    }
    final shapeResize = this.shapeResize;
    if (shapeResize != null) _paintShapeResize(canvas, shapeResize);
    if (selection != null) {
      canvas.save();
      if (rotation != 0) {
        canvas.translate(selection.center.dx, selection.center.dy);
        canvas.rotate(rotation);
        canvas.translate(-selection.center.dx, -selection.center.dy);
      }
      final box = selection.inflate(2 * chromeScale);
      final stroke = Paint()
        ..color = _chrome
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * chromeScale;
      canvas.drawRect(box, Paint()..color = _chrome.withAlpha(0x1A));
      canvas.drawRect(box, stroke);
      // the knob's connector line first, so the top-center resize handle
      // paints over it instead of being crossed out
      final rotateKnob = showRotateHandle
          ? Offset(box.center.dx,
              box.top - (_rotateHandleDistance - 2) * chromeScale)
          : null;
      if (rotateKnob != null) {
        canvas.drawLine(box.topCenter, rotateKnob, stroke);
      }
      if (showHandles) {
        final fill = Paint()..color = const Color(0xFFFFFFFF);
        for (final handle in _handles) {
          final center = Offset(
            box.center.dx + handle.dx * box.width / 2,
            box.center.dy + handle.dy * box.height / 2,
          );
          final knob = Rect.fromCircle(
              center: center, radius: _handleSize / 2 * chromeScale);
          canvas.drawRect(knob, fill);
          canvas.drawRect(knob, stroke);
        }
      }
      if (rotateKnob != null) {
        canvas.drawCircle(rotateKnob, (_handleSize / 2 + 1) * chromeScale,
            Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawCircle(
            rotateKnob, (_handleSize / 2 + 1) * chromeScale, stroke);
      }
      canvas.restore();
    }
    if (vertexHandles case final handles?) {
      final fill = Paint()..color = const Color(0xFFFFFFFF);
      final stroke = Paint()
        ..color = _chrome
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * chromeScale;
      for (final center in handles) {
        final knob = Rect.fromCircle(
            center: center, radius: _handleSize / 2 * chromeScale);
        canvas.drawRect(knob, fill);
        canvas.drawRect(knob, stroke);
      }
    }

    final element = elementRect;
    if (element != null) {
      final box = element.inflate(2 * chromeScale);
      canvas.drawRect(box, Paint()..color = _elementChrome.withAlpha(0x1A));
      canvas.drawRect(
          box,
          Paint()
            ..color = _elementChrome
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * chromeScale);
    }

    final flash = flashRect;
    if (flash != null) {
      final fade = (1 - flashProgress).clamp(0.0, 1.0);
      // close in over the first third, then hold while fading out
      final settle =
          Curves.easeOutCubic.transform((flashProgress * 3).clamp(0.0, 1.0));
      final ring = RRect.fromRectAndRadius(
          flash.inflate((4 + 26 * (1 - settle)) * chromeScale),
          Radius.circular(6 * chromeScale));
      canvas.drawRRect(
          ring, Paint()..color = _flash.withValues(alpha: 0.20 * fade));
      canvas.drawRRect(
          ring,
          Paint()
            ..color = _flash.withValues(alpha: 0.9 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * chromeScale);
    }

    // the eraser's ring cursor, topmost: page-space radius (it shows
    // exactly what a stamp removes), screen-constant line weight - a
    // light ring over a dark halo so it reads on any page color
    final cursor = eraserCursor;
    if (cursor != null && eraserRadius > 0) {
      canvas.drawCircle(
          cursor, eraserRadius, Paint()..color = const Color(0x14000000));
      canvas.drawCircle(
          cursor,
          eraserRadius,
          Paint()
            ..color = const Color(0x66000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * chromeScale);
      canvas.drawCircle(
          cursor,
          eraserRadius,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * chromeScale);
    }

    // the ink tool's pen-preview dot: the pen colour at its opacity, sized
    // to the stroke width, with a halo + hairline so it reads on any page
    final pen = penCursor;
    if (pen != null) {
      _paintPenCursor(
        canvas,
        pen,
        strokeWidth: strokeWidth,
        chromeScale: chromeScale,
        color: color,
        opacity: penOpacity,
      );
    }

    final count = countPreview;
    if (count != null) {
      _paintStampAfterimage(canvas, count);
    }

    final stamp = stampPreview;
    if (stamp != null) {
      _paintStampAfterimage(canvas, stamp);
    }

    // the rotate knob's cursor: a curved arrow (no system rotation cursor)
    final rotate = rotateCursor;
    if (rotate != null) {
      final rr = 9 * chromeScale;
      // a 290° arc, leaving a gap for the arrowhead at its end
      const start = -math.pi / 2;
      const sweep = 290 * math.pi / 180;
      final box = Rect.fromCircle(center: rotate, radius: rr);
      final halo = Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4 * chromeScale;
      final arc = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2 * chromeScale;
      canvas.drawArc(box, start, sweep, false, halo);
      canvas.drawArc(box, start, sweep, false, arc);
      // arrowhead tangent to the arc end
      final end = start + sweep;
      final tip = rotate + Offset(math.cos(end), math.sin(end)) * rr;
      final tangent = end + math.pi / 2; // clockwise travel
      final wing = 4 * chromeScale;
      for (final a in [tangent + 2.5, tangent - 2.5]) {
        final p = tip + Offset(math.cos(a), math.sin(a)) * wing;
        canvas.drawLine(tip, p, halo);
        canvas.drawLine(tip, p, arc);
      }
    }
  }

  /// Cheap inequality for the extra ink sets: counts plus each set's
  /// first point catch both new sets and a moving signature preview.
  static bool _inkChanged(List<_InkPaint> a, List<_InkPaint> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].strokes.length != b[i].strokes.length ||
          a[i].color != b[i].color ||
          a[i].strokeWidth != b[i].strokeWidth) {
        return true;
      }
      if (a[i].strokes.isNotEmpty &&
          b[i].strokes.isNotEmpty &&
          (a[i].strokes.first.isEmpty != b[i].strokes.first.isEmpty ||
              (a[i].strokes.first.isNotEmpty &&
                  a[i].strokes.first.first != b[i].strokes.first.first))) {
        return true;
      }
    }
    return false;
  }

  @override
  bool shouldRepaint(_EditingPreviewPainter oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.chromeScale != chromeScale ||
      oldDelegate.tool != tool ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      !listEquals(oldDelegate.redactionRects, redactionRects) ||
      oldDelegate.dragRect != dragRect ||
      oldDelegate.calloutLeader != calloutLeader ||
      oldDelegate.dragPathFill != dragPathFill ||
      oldDelegate.selectionRect != selectionRect ||
      !listEquals(oldDelegate.extraSelectionRects, extraSelectionRects) ||
      oldDelegate.marqueeRect != marqueeRect ||
      oldDelegate.ghost != ghost ||
      oldDelegate.ghostFrom != ghostFrom ||
      oldDelegate.ghostTo != ghostTo ||
      oldDelegate.shapeResize != shapeResize ||
      oldDelegate.dragging != dragging ||
      oldDelegate.rotation != rotation ||
      oldDelegate.ghostRotation != ghostRotation ||
      oldDelegate.ghostLocalAngle != ghostLocalAngle ||
      oldDelegate.ghostFlipX != ghostFlipX ||
      oldDelegate.ghostFlipY != ghostFlipY ||
      oldDelegate.resizeClean != resizeClean ||
      oldDelegate.resizeHideRect != resizeHideRect ||
      oldDelegate.resizeHideAngle != resizeHideAngle ||
      oldDelegate.resizeHideWash != resizeHideWash ||
      _inkChanged(oldDelegate.extraInk, extraInk) ||
      !listEquals(oldDelegate.fadeRects, fadeRects) ||
      _inkChanged(oldDelegate.fadeInk, fadeInk) ||
      oldDelegate.fadeColor != fadeColor ||
      oldDelegate.eraserCursor != eraserCursor ||
      oldDelegate.eraserRadius != eraserRadius ||
      oldDelegate.penCursor != penCursor ||
      oldDelegate.penOpacity != penOpacity ||
      oldDelegate.countPreview != countPreview ||
      oldDelegate.stampPreview != stampPreview ||
      oldDelegate.rotateCursor != rotateCursor ||
      oldDelegate.afterGhost != afterGhost ||
      oldDelegate.afterShape != afterShape ||
      oldDelegate.afterStamp != afterStamp ||
      oldDelegate.showHandles != showHandles ||
      oldDelegate.showRotateHandle != showRotateHandle ||
      oldDelegate.elementRect != elementRect ||
      oldDelegate.flashRect != flashRect ||
      oldDelegate.flashProgress != flashProgress ||
      oldDelegate.strokes.length != strokes.length ||
      (strokes.isNotEmpty &&
          oldDelegate.strokes.isNotEmpty &&
          oldDelegate.strokes.last.length != strokes.last.length);
}

/// Paints [picture] - an annotation appearance recorded in page raster
/// space (1 unit = 1 point, y down; see
/// [PdfPageRenderer.renderAnnotationPicture]) - mapped from its resting
/// view rect [from] onto [to], the live preview of a move/resize drag.
/// [scale] is the view's pixels-per-point.
///
/// Drawn at ~75% [opacity] by default: solid enough to judge the
/// result, light enough to read as a preview over the still-rendered
/// original. The post-commit afterimage paints at 1.0 - it *is* the
/// committed result, standing in until the new raster lands.
///
/// [rotation] (view radians, clockwise positive) additionally spins the
/// preview about [to]'s center - the rotate handle's live feedback.
///
/// With [localAngle] (a rotated selection's resting angle), [from] and
/// [to] are *local* boxes: the picture scales by their size ratio along
/// the rotated axes about the box centers, instead of stretching one
/// page-axis rect onto another - a rotated annotation's resize preview
/// must not shear.
/// Paints the hatched "marked for redaction" preview into [rect]: a faint
/// dark wash, a solid border, and diagonal cross-hatch lines, so a marked
/// region is unmistakable before it is burned (after burning the area is a
/// solid fill baked into the page content).
void paintRedactionHatch(Canvas canvas, Rect rect, {double chromeScale = 1}) {
  if (rect.isEmpty) return;
  final s = chromeScale.isFinite && chromeScale > 0 ? chromeScale : 1.0;
  canvas.drawRect(rect, Paint()..color = const Color(0x22000000));
  canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * s);
  canvas.save();
  canvas.clipRect(rect);
  final hatch = Paint()
    ..color = const Color(0x66D32F2F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1 * s;
  final step = 8.0 * s;
  for (var x = rect.left - rect.height; x < rect.right; x += step) {
    canvas.drawLine(
        Offset(x, rect.bottom), Offset(x + rect.height, rect.top), hatch);
  }
  canvas.restore();
}

@visibleForTesting
void paintAnnotationDragPreview(
  Canvas canvas, {
  required ui.Picture picture,
  required Rect from,
  required Rect to,
  required double scale,
  double rotation = 0,
  double localAngle = 0,
  bool flipX = false,
  bool flipY = false,
  double opacity = 0.75,
}) {
  if (from.width <= 0 || from.height <= 0) return;
  final bounds = rotation == 0 && localAngle == 0
      ? to.inflate(4)
      : Rect.fromCircle(
          center: to.center,
          radius: Offset(to.width, to.height).distance / 2 + 4);
  canvas.saveLayer(
      bounds,
      Paint()
        ..color =
            const Color(0xFFFFFFFF).withValues(alpha: opacity.clamp(0.0, 1.0)));
  if (rotation != 0) {
    canvas.translate(to.center.dx, to.center.dy);
    canvas.rotate(rotation);
    canvas.translate(-to.center.dx, -to.center.dy);
  }
  // a flip is a negative scale along the axis; about the box center for
  // the rotated path (the scale already sits there) and about the
  // appropriate edge for the page-axis path so it mirrors within [to]
  final sx = (to.width / from.width) * (flipX ? -1 : 1);
  final sy = (to.height / from.height) * (flipY ? -1 : 1);
  if (localAngle != 0) {
    canvas.translate(to.center.dx, to.center.dy);
    canvas.rotate(localAngle);
    canvas.scale(sx, sy);
    canvas.rotate(-localAngle);
    canvas.translate(-from.center.dx, -from.center.dy);
  } else {
    canvas.translate(flipX ? to.right : to.left, flipY ? to.bottom : to.top);
    canvas.scale(sx, sy);
    canvas.translate(-from.left, -from.top);
  }
  canvas.scale(scale, scale);
  canvas.drawPicture(picture);
  canvas.restore();
}

/// Paints a single-selection move drag's floating ghost ([preview]) into
/// the viewer's list space; [origin] is the dragged page's top-left in
/// that space, translating the preview's overlay-local rects. Lives here
/// so it can reach [paintAnnotationDragPreview] without tripping its
/// `@visibleForTesting` guard from the viewer.
void paintMoveDragPreview(
    Canvas canvas, PdfMoveDragPreview preview, Offset origin) {
  paintAnnotationDragPreview(
    canvas,
    picture: preview.picture,
    from: preview.from.shift(origin),
    to: preview.to.shift(origin),
    scale: preview.scale,
  );
}

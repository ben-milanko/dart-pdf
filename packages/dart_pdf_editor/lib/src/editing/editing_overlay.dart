import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import '../page_geometry.dart';
import '../renderer.dart';
import '../theme.dart';
import 'editing_controller.dart';
import 'stroke_prediction.dart';
import 'text_prompt.dart';

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
    this.onPanViewport,
    this.onPanViewportEnd,
    this.rasterCurrent = true,
    this.zoom = 1,
    this.predictStrokes = true,
    this.formImagePicker,
    this.onShowAnnotationMenu,
    this.onShowFormFieldMenu,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final PdfPageGeometry geometry;
  final PdfTextPrompt textPrompt;

  /// How the form tool asks for a push-button field's image. With none,
  /// tapping a push button does nothing.
  final PdfFormImagePicker? formImagePicker;

  /// The paper color the page is displayed with — the eyedropper's
  /// raster must match what's on screen.
  final Color pageColor;

  /// Whether the page is displayed with its annotations — same
  /// requirement as [pageColor]: the eyedropper samples what's visible.
  final bool showAnnotations;

  /// Pans the viewer by a pointer delta (this overlay's local space).
  /// Lets a drag on empty page area scroll the document even though the
  /// overlay's recognizers won the arena — grab panning and annotation
  /// selection co-existing in the select tool.
  final void Function(Offset delta)? onPanViewport;

  /// A viewport pan ended: hands the gesture's lift-off velocity to the
  /// viewer so a finger fling keeps its momentum (the overlay's pan path
  /// bypasses the list's scroll physics, which would otherwise carry it).
  final void Function(Velocity velocity)? onPanViewportEnd;

  /// Whether the page raster on screen already shows the controller's
  /// current revision. While false (an edit just committed and the
  /// re-render is in flight), the overlay keeps painting the committed
  /// edit's preview — its afterimage — so the edit never blinks out.
  final bool rasterCurrent;

  /// Screen pixels per overlay pixel — the viewer's transform zoom. The
  /// overlay paints inside that transform, so selection chrome (outline,
  /// handles, the rotate knob) divides its sizes and hit radii by this
  /// to stay constant-size on screen at any zoom. Page-content previews
  /// (ink, shapes, the drag ghost) scale with the page on purpose.
  final double zoom;

  /// See [PdfViewer.predictStrokes]. When true the in-progress ink layer
  /// draws a forward-extrapolated lead so the painted line keeps up with
  /// the pen tip.
  final bool predictStrokes;

  /// Opens the annotation context menu at a global position — the
  /// selection action chip's "more" button and the touch long-press,
  /// which give touch input the menu that mice reach by right-clicking.
  /// The viewer supplies its menu (including the host's custom actions);
  /// [pagePoint] anchors a paste from a press on empty page area.
  final void Function(Offset globalPosition, int pageIndex,
      {(double, double)? pagePoint})? onShowAnnotationMenu;

  /// Opens the form-field context menu (rename/convert/delete/flatten)
  /// at a global position — the touch long-press counterpart of
  /// right-clicking a field widget with the form tool armed.
  final void Function(Offset globalPosition, String fieldName)?
      onShowFormFieldMenu;

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

/// A Square/Circle drawn for a resize preview (or its committed
/// afterimage). The editor *regenerates* a shape's appearance at the new
/// rect with a constant stroke width rather than stretching the old one,
/// so a stretched ghost would thicken the line during the drag and snap
/// back on commit — this draws the shape the way the commit will, line
/// width and all. [strokeWidth] is view space; [rotation] view radians.
typedef _ShapeResize = ({
  Rect rect,
  bool ellipse,
  Color? stroke,
  double strokeWidth,
  Color? fill,
  double rotation,
  double opacity,
});

/// Which sides of the selection a resize handle moves: -1 left/top edge,
/// +1 right/bottom edge, 0 leaves that axis alone. (View space, y down.)
typedef _Handle = ({int dx, int dy});

const List<_Handle> _handles = [
  (dx: -1, dy: -1),
  (dx: 0, dy: -1),
  (dx: 1, dy: -1),
  (dx: -1, dy: 0),
  (dx: 1, dy: 0),
  (dx: -1, dy: 1),
  (dx: 0, dy: 1),
  (dx: 1, dy: 1),
];

const double _handleSize = 8;
const double _handleHitRadius = 12;
const double _minSizeView = 12;

/// How far the rotation knob floats above the selection's top edge.
const double _rotateHandleDistance = 22;

/// Rotation drags snap to 45° multiples when within this margin.
const double _rotateSnapRadians = 3 * math.pi / 180;

class _EditingPageOverlayState extends State<EditingPageOverlay>
    with SingleTickerProviderStateMixin {
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
  /// without rebuilding the overlay subtree or the heavy preview painter —
  /// the difference between a per-point widget rebuild and a per-point
  /// repaint, which is what the pen latency was paying for. Every mutation
  /// of [_activeStroke]/[_activeStrokePressures] must call [_bumpActiveStroke]
  /// (the painter's shouldRepaint stays false — this Listenable is the only
  /// thing that drives it, including the clear on commit/bail).
  final ValueNotifier<int> _activeStrokeRepaint = ValueNotifier<int>(0);

  void _bumpActiveStroke() => _activeStrokeRepaint.value++;

  /// The latest normalized pressure of the pointer being tracked, or null
  /// for devices that don't report pressure (finger, mouse).
  double? _pointerPressure;

  // raw-driven drawing: with ink or the eraser armed, stylus pointers
  // (and touch, when fingers draw) skip the gesture arena entirely — a
  // pan recognizer only wins after ~36px of motion, which swallowed the
  // start of every pencil stroke and dropped quick dots as taps. The
  // pointer id claims the gesture; moves append, up commits.
  int? _rawPointer;
  bool _rawErasing = false;

  // raw-driven finger pan: with the ink/eraser tool armed and finger
  // drawing OFF (Apple Pencil mode), a finger must still scroll the
  // document. The list's physics are NeverScrollable while a tool is
  // armed and touch is excluded from the overlay's gesture arena, so a
  // single finger reaches neither — it would do nothing. This raw path
  // pans the viewer instead (the pen keeps drawing via [_rawPointer], so
  // the two never collide). A touch landing during an active pen stroke
  // is a palm and is ignored (gated on `_rawPointer == null`); a second
  // finger bails to the viewer's pinch-zoom recognizer.
  int? _panPointer;
  Offset? _panLast;
  VelocityTracker? _panVelocity;

  /// Concurrent touch pointers on this page. A second finger landing
  /// mid-gesture aborts it (see [_bailActiveGesture]) instead of feeding
  /// both fingers' positions into one stroke.
  final Set<int> _touchPointers = {};

  /// True from a multi-touch bail until every touch pointer lifts —
  /// the remainder of the gesture is dead air.
  bool _gestureBailed = false;

  /// The device kind of the latest pointer down on this page — the
  /// selection action chip only shows for touch and stylus input.
  PointerDeviceKind? _lastPointerKind;

  // circle eraser: the swipe's swept path (page space), the live-sliced
  // remainder per touched /Annots slot (painted over the faded
  // original, so the preview shows exactly what the commit keeps), the
  // original strokes of each touched sliceable annotation (washed over
  // so the baked-in ink fades without obscuring the page content around
  // it — the wash follows the strokes, not the bounding box), inkless
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

  /// The rotate knob's cursor position (hover over the knob, or live
  /// through a rotate drag): Flutter has no rotation cursor, so the
  /// system cursor is hidden here and a small curved-arrow glyph is
  /// painted to track the pointer instead.
  Offset? _rotateCursor;

  /// Erase results kept painted until the new revision's raster lands —
  /// without them the old strokes pop back at full strength for a frame.
  List<Rect>? _afterEraseRects;
  List<_InkPaint>? _afterEraseFade;
  List<_InkPaint>? _afterEraseInk;

  // in-place text editor: open after a free-text drag-out (new) or a
  // tap on the already-selected free text annotation (existing)
  Rect? _textEditRect; // view space; null = closed
  bool _textEditExisting = false;
  PdfEditTool? _textEditTool;
  late final TextEditingController _textEditText = TextEditingController();
  late final FocusNode _textEditFocus = FocusNode()
    ..addListener(_onTextEditFocus);
  PdfStandardFont _textEditFont = PdfStandardFont.helvetica;
  double _textEditSize = 14; // pt
  Color _textEditColor = const Color(0xFF000000);
  Color? _textEditFill; // the box background the commit will paint
  // resting view-space rotation of the box being edited (radians,
  // clockwise positive): nonzero only when editing already-rotated text,
  // so the inline editor and afterimage sit on the artwork instead of
  // snapping back to horizontal
  double _textEditRotation = 0;

  // form-tool text fill: when set, the inline editor commits into this
  // field's /V instead of creating a free-text annotation
  String? _textEditFieldName;
  bool _textEditMultiline = true;

  // select-tool drags. A rotated selection resizes in its local frame:
  // _resizeFrom/_resizeRect are then the chrome's local box (the rect
  // the painter spins by _resizeAngle), not page-axis view rects.
  Offset? _moveStart;
  Offset? _moveCurrent;
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

  // rubber-band selection (mouse drags on empty page area)
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  bool _marqueeAdd = false;

  // touch drags on empty page area pan the viewer instead
  bool _viewportPanning = false;

  // rotate drag: the pointer's start angle about the selection center,
  // the annotation's resting rotation when the drag started, and the
  // current delta (view space, clockwise positive — y is down)
  double? _rotateStartAngle;
  double _rotateResting = 0;
  double _rotateDelta = 0;

  // signature tool: the pointer position the live preview rides (hover
  // for a mouse, press-and-drag for touch), and whether a drag-place is
  // in flight
  Offset? _signaturePreview;
  bool _signatureDrag = false;

  // afterimage of the last commit, painted until the new revision's
  // raster lands ([widget.rasterCurrent]) — without it the preview
  // clears frames before the page re-renders and the edit blinks out
  PdfDocument? _afterDocument;
  ui.Picture? _afterGhost;
  Rect? _afterGhostFrom;
  Rect? _afterGhostTo;
  Rect? _afterGhostSourceRect;
  double _afterGhostRotation = 0;
  double _afterGhostLocalAngle = 0;
  bool _afterGhostFlipX = false;
  bool _afterGhostFlipY = false;
  ({Rect rect, PdfEditTool tool, Color color, double strokeWidth})? _afterShape;
  // a just-committed Square/Circle resize, held (constant stroke width)
  // until the new revision's raster lands — see [_shapeResizeStyle]
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
    PdfStandardFont font,
    double size,
    Color color,
    Color? fill,
    bool washed,
    double rotation,
  })? _afterText;
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
  PdfRect? _flashRect; // page space — view rect derives per build

  void _onFlashTick() => setState(() {});

  void _onFlashStatus(AnimationStatus status) {
    // pulse done: retire the pending flash so the overlay can unmount
    if (status == AnimationStatus.completed) {
      _controller.expireFlash(_flashSequence);
    }
  }

  MouseCursor _cursor = MouseCursor.defer;

  PdfEditingController get _controller => widget.controller;
  PdfPageGeometry get _geometry => widget.geometry;

  /// Overlay pixels per intended screen pixel for chrome metrics — the
  /// inverse of the viewer's transform zoom (see [EditingPageOverlay.zoom]).
  double get _chromeScale {
    final zoom = widget.zoom;
    return zoom.isFinite && zoom > 0 ? 1 / zoom : 1.0;
  }

  /// Null while the eyedropper is armed without a tool, or while a
  /// default-mode (mouse click) selection exists without one.
  PdfEditTool? get _tool => _controller.tool;

  /// Select-tool behavior applies: the tool is armed, or an annotation
  /// was selected in default mode (no tool) by a mouse click — the
  /// selection needs its move/resize/marquee interactions either way.
  bool get _selectMode =>
      _tool == PdfEditTool.select ||
      (_tool == null && _controller.hasAnnotationSelection);

  /// Shift/⌘/Ctrl held — a click toggles membership, a marquee adds.
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

  bool get _drawTool => _tool == PdfEditTool.ink || _tool == PdfEditTool.eraser;

  /// A finger should pan the viewer (not draw): the draw tool is armed
  /// but finger-drawing is off, so touch is reserved for scrolling.
  bool get _fingerPansViewport =>
      _drawTool &&
      !_controller.fingerDrawsInk &&
      widget.onPanViewport != null;
  bool get _polyTool =>
      _tool == PdfEditTool.polyline ||
      _tool == PdfEditTool.polygon ||
      _tool == PdfEditTool.measurePerimeter ||
      _tool == PdfEditTool.measureArea;

  /// A tool placed by dragging a single straight segment (a /Line or a
  /// distance measurement).
  bool get _lineDragTool =>
      _tool == PdfEditTool.line ||
      _tool == PdfEditTool.arrow ||
      _tool == PdfEditTool.measureDistance;

  /// The measurement kind the armed tool creates, or null for a
  /// non-measurement tool.
  PdfMeasurementKind? get _measureKind => switch (_tool) {
        PdfEditTool.measureDistance => PdfMeasurementKind.distance,
        PdfEditTool.measurePerimeter => PdfMeasurementKind.perimeter,
        PdfEditTool.measureArea => PdfMeasurementKind.area,
        _ => null,
      };

  /// Whether a pointer of [kind] draws (or erases) through the raw
  /// event stream instead of the gesture arena. Pan recognizers only
  /// win the arena after ~36px of motion, which swallowed the start of
  /// every pencil stroke and dropped quick dots as taps — so with ink
  /// or the eraser armed, stylus input (and touch, when fingers draw)
  /// starts on pointer-down. Mouse and trackpad keep the arena path:
  /// they have no latency problem and hover/click semantics to honor.
  bool _rawDrives(PointerDeviceKind? kind) {
    if (!_drawTool) return false;
    return switch (kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.touch => _controller.fingerDrawsInk,
      _ => false,
    };
  }

  /// Raw-pointer bookkeeping the pan callbacks can't see: the pressure
  /// stream, stylus detection for palm rejection, multi-touch bail, and
  /// — with ink or the eraser armed — the stroke itself.
  void _onPointerDown(PointerDownEvent event) {
    _pointerPressure = _normalizedPressure(event);
    if (_lastPointerKind != event.kind) {
      // the selection action chip shows for touch/stylus input only
      setState(() => _lastPointerKind = event.kind);
    }
    if (event.kind == PointerDeviceKind.touch) {
      _touchPointers.add(event.pointer);
      if (_touchPointers.length >= 2) {
        // a stylus stroke survives stray touches — that second contact
        // is the palm resting on the screen, not a gesture
        if (_rawPointer != null && !_touchPointers.contains(_rawPointer)) {
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
    if (_gestureBailed) return;
    if (_polyTool) {
      _addPolyPoint(event.localPosition);
      return;
    }
    if (_drawTool &&
        _controller.fingerDrawsInk &&
        (event.kind == PointerDeviceKind.stylus ||
            event.kind == PointerDeviceKind.invertedStylus)) {
      // an Apple Pencil (or other stylus) is in play: from now on the
      // pen draws and fingers scroll, until the user toggles it back
      _controller.fingerDrawsInk = false;
    }
    if (_rawPointer == null && _rawDrives(event.kind)) {
      _rawPointer = event.pointer;
      // a flipped pencil erases even while the ink tool is armed —
      // that's what the flip is for
      _rawErasing = _tool == PdfEditTool.eraser ||
          event.kind == PointerDeviceKind.invertedStylus;
      if (_rawErasing) {
        _eraseAt(event.localPosition);
      } else {
        // hold the auto-commit while this stroke is on the page
        _controller.beginInkStroke();
        final pressure = _pointerPressure;
        // no setState: the active stroke lives on its own repaint layer
        _activeStroke = [_geometry.toPagePoint(event.localPosition)];
        _activeStrokePressures = pressure == null ? null : [pressure];
        _bumpActiveStroke();
      }
    } else if (_panPointer == null &&
        _rawPointer == null &&
        event.kind == PointerDeviceKind.touch &&
        _fingerPansViewport) {
      // pencil mode, single finger, no pen stroke in flight: pan the
      // viewer. A move drives [onPanViewport]; lift hands the velocity
      // to [onPanViewportEnd] for a fling, exactly like a select-mode
      // empty-area touch drag.
      _panPointer = event.pointer;
      _panLast = event.localPosition;
      _panVelocity = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.localPosition);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final pressure = _normalizedPressure(event);
    if (pressure != null) _pointerPressure = pressure;
    if (_controller.isPickingColor) {
      _updatePickPreview(event.localPosition);
      return;
    }
    if (event.pointer == _panPointer) {
      final last = _panLast;
      if (last != null) {
        widget.onPanViewport?.call(event.localPosition - last);
      }
      _panLast = event.localPosition;
      _panVelocity?.addPosition(event.timeStamp, event.localPosition);
      return;
    }
    if (event.pointer != _rawPointer) return;
    if (_rawErasing) {
      _eraseAt(event.localPosition);
    } else if (_activeStroke != null) {
      // hot path: append + repaint the stroke layer only, no rebuild
      _activeStroke!.add(_geometry.toPagePoint(event.localPosition));
      _activeStrokePressures
          ?.add(_pointerPressure ?? _activeStrokePressures!.last);
      _bumpActiveStroke();
    }
  }

  /// Aborts whatever gesture is in flight — a second finger landed, so
  /// the first one wasn't drawing or dragging after all (it's a pinch,
  /// or just a clumsy grip). Nothing commits; the rest of the gesture
  /// is dead air until every touch pointer lifts.
  void _bailActiveGesture() {
    _gestureBailed = true;
    _rawPointer = null;
    _rawErasing = false;
    // a second finger landed: stop panning so the viewer's pinch-zoom
    // recognizer takes both touches (no fling — the gesture isn't a pan)
    _panPointer = null;
    _panLast = null;
    _panVelocity = null;
    setState(() {
      _activeStroke = null;
      _activeStrokePressures = null;
      _resetErase();
      _panErasing = false;
      _dragStart = null;
      _dragCurrent = null;
      _moveStart = null;
      _moveCurrent = null;
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
    _clearResizeClean();
    _bumpActiveStroke();
    // earlier strokes waiting in the buffer get their auto-commit back
    _controller.cancelInkStroke();
  }

  /// Touch bookkeeping and the raw gesture's commit, shared by
  /// pointer-up and pointer-cancel.
  void _endRawPointer(PointerEvent event, {required bool canceled}) {
    if (event.kind == PointerDeviceKind.touch) {
      _touchPointers.remove(event.pointer);
      if (_touchPointers.isEmpty) _gestureBailed = false;
    }
    if (event.pointer == _panPointer) {
      final velocity = canceled
          ? Velocity.zero
          : (_panVelocity?.getVelocity() ?? Velocity.zero);
      _panPointer = null;
      _panLast = null;
      _panVelocity = null;
      if (!canceled) widget.onPanViewportEnd?.call(velocity);
      return;
    }
    if (event.pointer != _rawPointer) return;
    _rawPointer = null;
    final erasing = _rawErasing;
    _rawErasing = false;
    if (erasing) {
      if (canceled) {
        setState(_resetErase);
      } else {
        _commitErase();
      }
      return;
    }
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
  /// usable /InkList can't be sliced — they fade whole and the commit
  /// deletes them.
  void _eraseAt(Offset position) {
    final point = _geometry.toPagePoint(position);
    final radius = _controller.eraserRadius;
    final from = _erasePath.isEmpty ? point : _erasePath.last;
    setState(() {
      _eraserCursor = position;
      _erasePath.add(point);
      final annotations = _controller.pageAt(widget.pageIndex).annotations;
      for (var slot = 0; slot < annotations.length; slot++) {
        final annotation = annotations[slot];
        if (annotation.subtype != 'Ink' || annotation.isHidden) continue;
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
                  pressures:
                      List<List<double>?>.filled(strokes.length, null),
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
  /// page — the one that gets resize/rotate handles (single selection).
  Rect? get _selectedViewRect {
    if (_controller.selectedPage != widget.pageIndex) return null;
    final annotation = _controller.selectedAnnotation;
    return annotation == null ? null : _geometry.toViewRect(annotation.rect);
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
    final subtype = _controller.selectedAnnotation?.subtype;
    return subtype == 'Line' || subtype == 'PolyLine' || subtype == 'Polygon';
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
        return PdfEditTool.polygon;
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

  /// The view-space rotation of [quad]'s bottom edge — the angle the
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
  /// (pre-rotation) rectangle — the painter spins it back into place,
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

  static Offset _rotatePoint(Offset p, Offset center, double angle) {
    final d = p - center;
    final c = math.cos(angle), s = math.sin(angle);
    return center + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// Drops the afterimage (and its ghost picture, which the state owns).
  void _clearAfterimage() {
    _afterGhost?.dispose();
    _afterGhost = null;
    _afterGhostFrom = null;
    _afterGhostTo = null;
    _afterGhostSourceRect = null;
    _afterGhostRotation = 0;
    _afterGhostLocalAngle = 0;
    _afterGhostFlipX = false;
    _afterGhostFlipY = false;
    _afterShape = null;
    _afterShapeResize = null;
    _afterPath = null;
    _afterText = null;
    _afterSignature = null;
    _afterEraseRects = null;
    _afterEraseFade = null;
    _afterEraseInk = null;
    _afterDocument = null;
  }

  /// Runs [commit] and, when it produced a new revision, keeps the
  /// current ghost painted at [to] (spun by [rotation]) as the
  /// afterimage — the move/resize/rotate result stays visible while the
  /// page re-renders. The ghost's ownership transfers to the afterimage;
  /// [_ensureGhost] re-renders a fresh one for the new revision.
  ///
  /// For a rotated selection's resize, [localAngle] is its resting
  /// rotation and [to] the dragged *local* box — the afterimage then
  /// scales along the local axes, exactly like the live preview did.
  ///
  /// [flipX]/[flipY] mirror the afterimage so a resize that inverted the
  /// annotation stays inverted while the page re-renders.
  void _commitWithGhost(VoidCallback commit,
      {Rect? to,
      double rotation = 0,
      double localAngle = 0,
      bool flipX = false,
      bool flipY = false}) {
    final from = localAngle == 0 ? _selectedViewRect : _selectionChrome?.$1;
    final source = _selectedViewRect;
    final ghost = _ghost;
    final before = _controller.document;
    commit();
    if (identical(before, _controller.document)) return;
    if (ghost == null || from == null || to == null) return;
    _clearAfterimage();
    _ghost = null;
    _ghostKey = null;
    _afterGhost = ghost;
    _afterGhostFrom = from;
    _afterGhostTo = to;
    _afterGhostSourceRect = source;
    _afterGhostRotation = rotation;
    _afterGhostLocalAngle = localAngle;
    _afterGhostFlipX = flipX;
    _afterGhostFlipY = flipY;
    _afterDocument = _controller.document;
  }

  /// The selection's text style when a resize commit will RE-WRAP it at
  /// a constant font size — the editor's FreeText regenerate path:
  /// an /AP to replace and a /DA naming a standard font. Null means the
  /// commit stretches the appearance and the ghost previews faithfully.
  ({String text, PdfStandardFont font, double size, Color color, Color? fill})?
      get _textResizeStyle {
    final annotation = _controller.selectedAnnotation;
    if (annotation == null ||
        annotation.subtype != 'FreeText' ||
        annotation.normalAppearance == null) {
      return null;
    }
    final parsed = annotation.freeTextStyle;
    final font =
        parsed == null ? null : PdfStandardFont.tryFromName(parsed.fontName);
    if (parsed == null || font == null) return null;
    return (
      text: annotation.contents ?? '',
      font: font,
      size: parsed.fontSize,
      color: Color(0xFF000000 | parsed.color),
      fill: parsed.fillColor != null
          ? Color(0xFF000000 | parsed.fillColor!)
          : null,
    );
  }

  /// The selected annotation's style when a resize commit will
  /// REGENERATE it (Square/Circle) at a constant stroke width — the
  /// editor's shape regenerate path: an /AP to replace, no cloudy /BE,
  /// no dashed border, and a stroke or fill to draw. [strokeWidth] is in
  /// view pixels (the page-space border width scaled), so the preview
  /// reads at the same weight the commit will, instead of the ghost's
  /// stretched line. Null leaves the drag on the stretch ghost.
  ///
  /// Mirrors `_regenerateResizedAppearance`'s Square/Circle gate exactly,
  /// so the preview never disagrees with the commit.
  _ShapeResize? _shapeResizeStyle(Rect rect, double rotation) {
    final annotation = _controller.selectedAnnotation;
    if (annotation == null ||
        (annotation.subtype != 'Square' && annotation.subtype != 'Circle') ||
        annotation.normalAppearance == null) {
      return null;
    }
    // cloudy and dashed borders fall back to the stretch path in the editor
    if (annotation.dict['BE'] != null || annotation.borderDash != null) {
      return null;
    }
    final width = annotation.borderWidth ?? 1;
    final stroke = width > 0 ? annotation.color : null;
    final fill = annotation.interiorColor;
    if (stroke == null && fill == null) return null;
    return (
      rect: rect,
      ellipse: annotation.subtype == 'Circle',
      stroke: stroke == null ? null : Color(0xFF000000 | stroke),
      strokeWidth: width * _geometry.scale,
      fill: fill == null ? null : Color(0xFF000000 | fill),
      rotation: rotation,
      opacity: annotation.appearanceOpacity,
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
            document.page(widget.pageIndex), annotation)
        .then((picture) {
      if (!mounted || _ghostKey != key) {
        picture?.dispose();
        return;
      }
      setState(() => _ghost = picture);
    }));
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
      // moved under us — a stale clean page would hide the wrong thing
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

  /// Drops the lifted clean-page picture once a resize drag ends.
  void _clearResizeClean() {
    _resizeCleanPicture?.dispose();
    _resizeCleanPicture = null;
    _resizeCleanFor = null;
  }

  @override
  void dispose() {
    if (_textEditRect != null) _controller.setEditingText(false);
    _textEditFocus
      ..removeListener(_onTextEditFocus)
      ..dispose();
    _textEditText.dispose();
    _ghost?.dispose();
    _afterGhost?.dispose();
    _resizeCleanPicture?.dispose();
    _flashController.dispose();
    _activeStrokeRepaint.dispose();
    super.dispose();
  }

  Offset _handleCenter(Rect rect, _Handle handle) => Offset(
        rect.center.dx + handle.dx * rect.width / 2,
        rect.center.dy + handle.dy * rect.height / 2,
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
    for (final handle in _handles) {
      if ((position - _handleCenter(rect, handle)).distance <=
          _handleHitRadius * _chromeScale) {
        return handle;
      }
    }
    return null;
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

  /// The rotate knob's view position: above the chrome box's top edge,
  /// riding the annotation's resting [rotation] about the box center.
  Offset _rotateHandleCenter(Rect rect, double rotation) => _rotatePoint(
        Offset(rect.center.dx, rect.top - _rotateHandleDistance * _chromeScale),
        rect.center,
        rotation,
      );

  /// Resize handles get first claim (the top-center knob sits close),
  /// so this is only consulted after [_handleAt] misses.
  bool _hitsRotateHandle(Rect rect, double rotation, Offset position) =>
      _controller.canRotateSelected &&
      (position - _rotateHandleCenter(rect, rotation)).distance <=
          _handleHitRadius * _chromeScale;

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
    final h = (_controller.fontSize * 1.6 + 8) * scale;
    final size = _geometry.viewSize;
    final left = tap.dx.clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    final top = tap.dy.clamp(0.0, math.max(0.0, size.height - h)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Opens the inline text editor over [viewRect] — empty for a fresh
  /// free-text box, prefilled from the selected annotation when
  /// [existing]. The editor renders with the same font, size, and color
  /// the committed annotation will use.
  void _openTextEditor(Rect viewRect, {required bool existing}) {
    final style = existing ? _controller.selectedTextStyle : null;
    // /DA carries the text color; /C is the box background for free text
    final annotation = existing ? _controller.selectedAnnotation : null;
    final parsed = annotation?.freeTextStyle;
    final annotationColor = parsed?.color ?? annotation?.color;
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
    _textEditText.text = existing ? (_controller.selectedText ?? '') : '';
    setState(() {
      _textEditRect = rect;
      _textEditRotation = rotation;
      _textEditExisting = existing;
      _textEditTool = _tool;
      _textEditFont = style?.font ?? _controller.fontFamily;
      _textEditSize = style?.size ?? _controller.fontSize;
      _textEditColor = annotationColor != null
          ? Color(0xFF000000 | annotationColor)
          : _controller.color;
      _textEditFill = existing
          ? (parsed?.fillColor != null
              ? Color(0xFF000000 | parsed!.fillColor!)
              : null)
          : _controller.textFillColor;
    });
    _controller.setEditingText(true);
    // the field's autofocus is ignored: the creating gesture's
    // pointer-down put primary focus on the viewer's own node, and
    // autofocus only fires into an unfocused scope — claim it so typing
    // lands in the fresh box without clicking into it first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _textEditRect != null) _textEditFocus.requestFocus();
    });
  }

  /// Opens the inline editor over a text field's widget, prefilled with
  /// its value — the form tool's tap-to-fill. The commit goes into the
  /// field's /V instead of creating an annotation.
  void _openFormTextEditor(PdfFormField field, int widgetIndex) {
    final rect = field.widgetRect(widgetIndex);
    if (rect == null) return;
    final tf = RegExp(r'/(\S+)\s+(\d+(?:\.\d+)?)\s+Tf')
        .firstMatch(field.defaultAppearance ?? '');
    final size = double.tryParse(tf?.group(2) ?? '') ?? 0;
    _textEditText.text = field.value ?? '';
    setState(() {
      _textEditRect = _geometry.toViewRect(rect);
      _textEditRotation = 0;
      _textEditExisting = false;
      _textEditTool = _tool;
      _textEditFieldName = field.name;
      _textEditMultiline = field.isMultiline;
      _textEditFont = tf == null
          ? PdfStandardFont.helvetica
          : PdfStandardFont.fromName(tf.group(1)!);
      // an auto-size /DA (0 Tf) edits at a readable default; the
      // committed appearance derives its own size as usual
      _textEditSize = size > 0 ? size : 12;
      _textEditColor = const Color(0xFF000000);
      _textEditFill = null;
    });
    _controller.setEditingText(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _textEditRect != null) _textEditFocus.requestFocus();
    });
  }

  /// Commits the editor's text: a new free-text annotation, the
  /// selected one rewritten, or — for the form tool — the field's new
  /// value. Empty text adds nothing / changes nothing.
  void _commitTextEdit() {
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
      );
      _afterDocument = _controller.document;
      return;
    }
    final text = _textEditText.text.trimRight();
    final existing = _textEditExisting;
    final font = _textEditFont;
    final size = _textEditSize;
    final color = _textEditColor;
    final fill = _textEditFill;
    final rotation = _textEditRotation;
    _closeTextEditor();
    final before = _controller.document;
    if (existing) {
      if (text.isNotEmpty && text != _controller.selectedText) {
        _controller.setSelectedText(text);
      }
    } else if (text.isNotEmpty) {
      _controller.addFreeText(
          widget.pageIndex, _geometry.toPageRect(rect), text);
    }
    if (identical(before, _controller.document)) return;
    // the editor's rendering, frozen until the new revision's raster
    // lands — otherwise the text vanishes for the render's duration
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
    );
    _afterDocument = _controller.document;
  }

  void _cancelTextEdit() => _closeTextEditor();

  void _closeTextEditor() {
    if (_textEditRect == null) return;
    if (mounted) {
      setState(() {
        _textEditRect = null;
        _textEditFieldName = null;
      });
    } else {
      _textEditRect = null;
      _textEditFieldName = null;
    }
    _controller.setEditingText(false);
  }

  /// Losing focus commits — tapping another widget, switching panes.
  /// (Escape cancels first, so by the time the unfocus arrives the
  /// session is already gone and this is a no-op.)
  void _onTextEditFocus() {
    if (!_textEditFocus.hasFocus) _commitTextEdit();
  }

  void _panStart(DragStartDetails details) {
    // raw-driven pointers own their gesture: the pan recognizer still
    // claims the arena (keeping the viewer's pan/zoom from fighting the
    // stroke) but its callbacks must not double-drive it
    if (_gestureBailed || _rawDrives(details.kind)) return;
    final position = details.localPosition;
    if (_textEditRect != null) {
      // a drag outside the open editor commits it, like a tap
      _commitTextEdit();
      return;
    }
    if (_selectMode) {
      _selectPanStart(details);
      return;
    }
    switch (_tool) {
      case null:
        break; // eyedropper only — taps, no drags
      case PdfEditTool.select:
        break; // handled by _selectPanStart above
      case PdfEditTool.eraser:
        // mouse/trackpad erase through the arena like any drag
        _panErasing = true;
        _eraseAt(position);
      case PdfEditTool.ink:
        // hold the auto-commit while this stroke is on the page
        _controller.beginInkStroke();
        final pressure = _pointerPressure;
        // no setState: the active stroke lives on its own repaint layer
        _activeStroke = [_geometry.toPagePoint(position)];
        // the first event decides: a pressure device varies the whole
        // stroke, anything else stays uniform
        _activeStrokePressures = pressure == null ? null : [pressure];
        _bumpActiveStroke();
      case PdfEditTool.rectangle ||
            PdfEditTool.ellipse ||
            PdfEditTool.line ||
            PdfEditTool.arrow ||
            PdfEditTool.measureDistance ||
            PdfEditTool.freeText ||
            PdfEditTool.stamp ||
            PdfEditTool.redact:
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
          return;
        }
        if (_controller.formFieldAt(widget.pageIndex, x, y) == null) {
          setState(() {
            _dragStart = position;
            _dragCurrent = position;
          });
        }
      case PdfEditTool.signature:
        // press-drag-release placement: the preview rides the pointer
        // (touch has no hover), release commits where it landed
        if (_controller.signature != null) {
          setState(() {
            _signatureDrag = true;
            _signaturePreview = position;
          });
        }
      case PdfEditTool.polyline ||
            PdfEditTool.polygon ||
            PdfEditTool.measurePerimeter ||
            PdfEditTool.measureArea:
        break; // taps add vertices; double-tap finishes
      case PdfEditTool.note || PdfEditTool.content:
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
        setState(() {
          _moveStart = position;
          _moveCurrent = position;
          _cursor = SystemMouseCursors.grabbing; // closed hand while dragging
        });
        return;
      }
    }
    final (x, y) = _geometry.toPagePoint(position);
    if (_controller.selectableAnnotationAt(widget.pageIndex, x, y) != null) {
      // grab an unselected annotation: select it and move it in one drag
      _controller.selectAnnotationAt(widget.pageIndex, x, y);
      setState(() {
        _moveStart = position;
        _moveCurrent = position;
        _cursor = SystemMouseCursors.grabbing;
      });
      return;
    }
    final mouseLike = details.kind == null ||
        details.kind == PointerDeviceKind.mouse ||
        details.kind == PointerDeviceKind.trackpad;
    if (mouseLike) {
      setState(() {
        _marqueeStart = position;
        _marqueeCurrent = position;
        _marqueeAdd = _additiveModifier;
      });
    } else if (widget.onPanViewport != null) {
      _viewportPanning = true;
    }
  }

  /// Whether a touch/stylus long-press at [position] would open a
  /// context menu — checked on pointer DOWN (the recognizer only joins
  /// the arena when this is true), so a long-press that has nothing to
  /// offer never steals the gesture from text selection or the viewer.
  bool _menuLongPressClaims(Offset position) {
    if (_gestureBailed) return false;
    final (x, y) = _geometry.toPagePoint(position);
    if (_tool == PdfEditTool.form) {
      return _controller.formFieldAt(widget.pageIndex, x, y) != null &&
          widget.onShowFormFieldMenu != null;
    }
    if (!_selectMode || widget.onShowAnnotationMenu == null) return false;
    return _controller.selectableAnnotationAt(widget.pageIndex, x, y) != null ||
        _controller.hasAnnotationClipboard;
  }

  /// Touch/stylus long-press: the context menu mice reach by
  /// right-clicking. A pressed annotation joins the selection first
  /// (an already-selected one keeps a multi-selection intact); empty
  /// page area opens the paste menu when the clipboard has content.
  void _onMenuLongPress(LongPressStartDetails details) {
    final position = details.localPosition;
    final (x, y) = _geometry.toPagePoint(position);
    if (_tool == PdfEditTool.form) {
      final field = _controller.formFieldAt(widget.pageIndex, x, y);
      if (field == null) return;
      HapticFeedback.selectionClick();
      widget.onShowFormFieldMenu?.call(details.globalPosition, field.$1.name);
      return;
    }
    final hit = _controller.selectableAnnotationAt(widget.pageIndex, x, y);
    if (hit != null) {
      if (!_controller.isAnnotationSelected(widget.pageIndex, hit.$1)) {
        _controller.selectAnnotationAt(widget.pageIndex, x, y);
      }
    } else if (!_controller.hasAnnotationClipboard) {
      return;
    }
    HapticFeedback.selectionClick();
    widget.onShowAnnotationMenu
        ?.call(details.globalPosition, widget.pageIndex, pagePoint: (x, y));
  }

  void _panUpdate(DragUpdateDetails details) {
    if (_gestureBailed || _rawPointer != null) return;
    final position = details.localPosition;
    if (_panErasing) {
      _eraseAt(position);
      return;
    }
    if (_viewportPanning) {
      widget.onPanViewport?.call(details.delta);
      return;
    }
    if (_marqueeStart != null) {
      setState(() => _marqueeCurrent = position);
      return;
    }
    if (_signatureDrag) {
      setState(() => _signaturePreview = position);
      return;
    }
    if (_rotateStartAngle != null) {
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
        final aspectRatio = HardwareKeyboard.instance.isShiftPressed &&
                _resizeFrom!.height > 0
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
      setState(() => _moveCurrent = position);
    } else if (_activeStroke != null) {
      // hot path: append + repaint the stroke layer only, no rebuild
      _activeStroke!.add(_geometry.toPagePoint(position));
      _activeStrokePressures
          ?.add(_pointerPressure ?? _activeStrokePressures!.last);
      _bumpActiveStroke();
    } else if (_dragStart != null) {
      setState(() => _dragCurrent = position);
    }
  }

  void _panEnd(DragEndDetails details) {
    if (_rawPointer != null) return; // the raw pointer-up commits
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
    final resizeRect = _resizeHandle != null ? _resizeRect : null;
    final resizeAngle = _resizeAngle;
    final resizeFlipX = _resizeFlipX;
    final resizeFlipY = _resizeFlipY;
    final vertexPoints = _vertexHandle != null ? _vertexPoints : null;
    final rotating = _rotateStartAngle != null;
    final rotateDelta = _rotateDelta;
    final marquee = _marqueeStart != null && _marqueeCurrent != null
        ? Rect.fromPoints(_marqueeStart!, _marqueeCurrent!)
        : null;
    final marqueeAdd = _marqueeAdd;
    final panned = _viewportPanning;
    final signaturePlace = _signatureDrag ? _signaturePreview : null;
    setState(() {
      _activeStroke = null;
      _activeStrokePressures = null;
      _dragStart = null;
      _dragCurrent = null;
      _moveStart = null;
      _moveCurrent = null;
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
    // the in-flight lift is done; the afterimage covers the commit gap
    _clearResizeClean();
    _bumpActiveStroke();

    if (panned) {
      // momentum: the fling continues in the viewer, which owns the
      // scroll position and zoom window this pan was feeding
      widget.onPanViewportEnd?.call(details.velocity);
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
      // rotation is counterclockwise-positive — hence the sign flip
      _commitWithGhost(
          () => _controller.rotateSelected(-rotateDelta * 180 / math.pi),
          to: _selectedViewRect,
          rotation: rotateDelta);
    } else if (vertexPoints != null) {
      _commitVertexDrag(vertexPoints);
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
        // the commit re-wraps the text at constant size — a stretched
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
            washed: true,
            rotation: resizeAngle,
          );
          _afterDocument = _controller.document;
        }
      } else if (shapeStyle != null) {
        // the commit regenerates the shape at a constant stroke width —
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
      final (x1, y1) = _geometry.toPagePoint(moveCurrent);
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
    final before = _controller.document;
    if (_tool == PdfEditTool.measureDistance) {
      _controller.addMeasurement(widget.pageIndex, PdfMeasurementKind.distance,
          [_geometry.toPagePoint(start), _geometry.toPagePoint(end)]);
    } else {
      _controller.addLine(widget.pageIndex, _geometry.toPagePoint(start),
          _geometry.toPagePoint(end),
          arrow: _tool == PdfEditTool.arrow);
    }
    if (identical(before, _controller.document)) return;
    _clearAfterimage();
    _afterPath = (
      points: [start, end],
      tool: _tool!,
      color: _controller.color
          .withValues(alpha: _controller.opacity.clamp(0.0, 1.0)),
      fillColor: null,
      strokeWidth: _controller.strokeWidth * _geometry.scale,
      dashed: _controller.dashedStroke,
    );
    _afterDocument = _controller.document;
  }

  void _commitVertexDrag(List<Offset> points) {
    final tool = _selectedLineTool;
    if (tool == null) return;
    final style = _controller.selectedAnnotationStyle;
    final annotation = _controller.selectedAnnotation;
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
      fillColor: annotation?.interiorColor == null
          ? null
          : Color(0xFF000000 | annotation!.interiorColor!)
              .withValues(alpha: opacity),
      strokeWidth:
          (style?.strokeWidth ?? _controller.strokeWidth) * _geometry.scale,
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
      fillColor: annotation.interiorColor == null
          ? null
          : Color(0xFF000000 | annotation.interiorColor!)
              .withValues(alpha: opacity),
      strokeWidth:
          (style.strokeWidth ?? _controller.strokeWidth) * _geometry.scale,
      dashed: annotation.borderDash != null,
    );
  }

  void _addPolyPoint(Offset point) {
    setState(() {
      final points = _polyPoints ?? <Offset>[];
      if (points.isEmpty || (point - points.last).distance >= 2) {
        _polyPoints = [...points, point];
      }
      _polyHover = null;
    });
  }

  void _finishPolyPath([Offset? finalPoint]) {
    final existing = _polyPoints;
    if (existing == null) return;
    final points = List<Offset>.of(existing);
    if (finalPoint != null &&
        (points.isEmpty || (finalPoint - points.last).distance >= 2)) {
      points.add(finalPoint);
    }
    final closed =
        _tool == PdfEditTool.polygon || _tool == PdfEditTool.measureArea;
    final minPoints = closed ? 3 : 2;
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
    switch (_measureKind) {
      case PdfMeasurementKind.perimeter:
        _controller.addMeasurement(
            widget.pageIndex, PdfMeasurementKind.perimeter, pagePoints);
      case PdfMeasurementKind.area:
        _controller.addMeasurement(
            widget.pageIndex, PdfMeasurementKind.area, pagePoints);
      case PdfMeasurementKind.distance:
      case null:
        if (_tool == PdfEditTool.polygon) {
          _controller.addPolygon(widget.pageIndex, pagePoints);
        } else {
          _controller.addPolyLine(widget.pageIndex, pagePoints);
        }
    }
    if (identical(before, _controller.document)) return;
    _clearAfterimage();
    setState(() {
      _polyPoints = null;
      _polyHover = null;
    });
    _afterPath = (
      points: simplified,
      tool: _tool!,
      color: _controller.color
          .withValues(alpha: _controller.opacity.clamp(0.0, 1.0)),
      fillColor: null,
      strokeWidth: _controller.strokeWidth * _geometry.scale,
      dashed: _controller.dashedStroke,
    );
    _afterDocument = _controller.document;
  }

  Future<void> _commitRect(Rect viewRect) async {
    final rect = _geometry.toPageRect(viewRect);
    switch (_tool) {
      case PdfEditTool.rectangle || PdfEditTool.ellipse:
        final tool = _tool!;
        final before = _controller.document;
        if (tool == PdfEditTool.rectangle) {
          _controller.addRectangle(widget.pageIndex, rect);
        } else {
          _controller.addEllipse(widget.pageIndex, rect);
        }
        if (identical(before, _controller.document)) return;
        // the drag preview, frozen until the new revision renders
        _clearAfterimage();
        _afterShape = (
          rect: viewRect,
          tool: tool,
          color: _controller.color
              .withValues(alpha: _controller.opacity.clamp(0.0, 1.0)),
          strokeWidth: _controller.strokeWidth * _geometry.scale,
        );
        _afterDocument = _controller.document;
      case PdfEditTool.stamp:
        final stamp = _controller.activeStamp;
        if (stamp != null) {
          _controller.addStamp(widget.pageIndex, rect, stamp.text,
              color: stamp.color);
          return;
        }
        final text = await widget.textPrompt(context,
            title: 'Stamp text', initial: 'APPROVED');
        if (text == null || text.isEmpty) return;
        _controller.addStamp(widget.pageIndex, rect, text);
      case PdfEditTool.form:
        _controller.addFormField(
            _controller.newFormFieldKind, widget.pageIndex, rect);
      case PdfEditTool.redact:
        _controller.addRedaction(widget.pageIndex, rect);
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
        if (bytes != null) _controller.setFormButtonImage(name, bytes);
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
            child: Text(display),
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
              pageColor: pageColor, annotations: annotations)
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
  /// swipe) and picks the eyedropper's previewed color — so both a
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
    if (_gestureBailed) return;
    if (_tool == PdfEditTool.eraser) {
      // a mouse/trackpad click erases what's under it; raw-driven
      // pointers already handled theirs on the way down
      if (!_rawDrives(details.kind)) {
        _eraseAt(details.localPosition);
        _commitErase();
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
    switch (_tool) {
      case null:
        break;
      case PdfEditTool.select:
        break; // handled above
      case PdfEditTool.content:
        _controller.selectElementAt(widget.pageIndex, x, y);
      case PdfEditTool.note:
        final text =
            await widget.textPrompt(context, title: 'Note', multiline: true);
        if (text == null || text.isEmpty) return;
        _controller.addNote(widget.pageIndex, x, y, text);
      case PdfEditTool.signature:
        _placeSignature(details.localPosition);
      case PdfEditTool.freeText:
        // tapping without dragging out a box opens a default-sized one
        _openTextEditor(_defaultPlacementRect(details.localPosition),
            existing: false);
      case PdfEditTool.stamp:
        if (_controller.activeStamp != null) {
          // an active custom stamp drops at its auto-size on tap
          _controller.placeStamp(widget.pageIndex, x, y);
        } else {
          // the classic flow normally drags out a box; a plain tap places
          // a default-sized stamp after prompting for its caption
          final text = await widget.textPrompt(context,
              title: 'Stamp text', initial: 'APPROVED');
          if (text == null || text.isEmpty) return;
          _controller.placeTextStamp(widget.pageIndex, x, y, text);
        }
      case PdfEditTool.form:
        // single tap selects the field for move/resize/menu; double-tap
        // fills it (read mode is the no-tool path to just fill)
        _controller.selectFormWidgetAt(widget.pageIndex, x, y,
            toggle: _additiveModifier);
      default:
        break;
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
    if (!_polyTool) return;
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
        // hovering a selected annotation: the grab hand reads as "drag me"
        cursor = SystemMouseCursors.grab;
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
    } else if (_tool == PdfEditTool.ink) {
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
    } else if (_tool == PdfEditTool.signature) {
      // the live preview rides the mouse; a click commits it
      if (_controller.signature != null &&
          event.localPosition != _signaturePreview) {
        setState(() => _signaturePreview = event.localPosition);
      }
      cursor = SystemMouseCursors.precise;
    } else if (_polyTool) {
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
    if (_tool != PdfEditTool.ink && _penCursor != null) {
      setState(() => _penCursor = null);
    }
    if (cursor != _cursor) setState(() => _cursor = cursor);
  }

  /// The floating action row beside a touch/stylus selection — the
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
                tooltip: 'Delete',
                onPressed: _controller.deleteSelected,
              ),
              if (_controller.canEditSelectedText)
                IconButton(
                  key: const ValueKey('pdf-selection-chip-edit'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit text',
                  onPressed: () {
                    final rect = _selectedViewRect;
                    if (rect != null) _openTextEditor(rect, existing: true);
                  },
                ),
              if (widget.onShowAnnotationMenu != null)
                IconButton(
                  key: const ValueKey('pdf-selection-chip-menu'),
                  icon: const Icon(Icons.more_horiz),
                  tooltip: 'More',
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    widget.onShowAnnotationMenu!(
                        box.localToGlobal(anchor), widget.pageIndex);
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// The running measurement readout during placement — the formatted
  /// distance/perimeter/area, and the view-space point it should ride.
  /// Null when no measurement tool is mid-placement.
  (String text, Offset anchor)? _measureReadout() {
    final kind = _measureKind;
    if (kind == null) return null;
    switch (kind) {
      case PdfMeasurementKind.distance:
        final start = _dragStart, current = _dragCurrent;
        if (start == null || current == null) return null;
        if ((current - start).distance < 1) return null;
        final text = _controller.measuredDistance(
            _geometry.toPagePoint(start), _geometry.toPagePoint(current));
        return text == null ? null : (text, current);
      case PdfMeasurementKind.perimeter || PdfMeasurementKind.area:
        final points = _polyPoints;
        if (points == null || points.isEmpty) return null;
        final view = [
          ...points,
          if (_polyHover != null && (_polyHover! - points.last).distance >= 2)
            _polyHover!,
        ];
        final pagePoints = [for (final p in view) _geometry.toPagePoint(p)];
        final text = kind == PdfMeasurementKind.area
            ? _controller.measuredArea(pagePoints)
            : _controller.measuredPerimeter(pagePoints);
        return text == null ? null : (text, view.last);
    }
  }

  /// The floating measurement readout chip. Mouse: rides just off the
  /// cursor. Touch/stylus: floats well above the finger so the contact
  /// point isn't occluded (the [_buildSelectionChip]/eyedropper pattern,
  /// keyed on [_lastPointerKind]).
  Widget _buildMeasureReadoutChip(String text, Offset anchor) {
    final touch = _lastPointerKind == PointerDeviceKind.touch ||
        _lastPointerKind == PointerDeviceKind.stylus;
    final offset = touch ? const Offset(0, -64) : const Offset(16, -36);
    return Positioned(
      left: anchor.dx + offset.dx,
      top: anchor.dy + offset.dy,
      child: FractionalTranslation(
        translation: touch ? const Offset(-0.5, 0) : Offset.zero,
        child: IgnorePointer(
          child: Material(
            key: const ValueKey('pdf-measure-readout'),
            color: const Color(0xE6202124),
            elevation: 3,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    );
  }

  /// A wrapped-text box mirroring a committed free-text appearance —
  /// the live resize preview and the post-commit afterimage share it.
  /// [rotation] spins the box about its center (a rotated annotation's
  /// resting angle, view convention).
  Widget _wrappedTextBox({
    Key? key,
    required Rect rect,
    required String text,
    required PdfStandardFont font,
    required double size,
    required Color color,
    required Color? background,
    required double rotation,
  }) {
    final box = Container(
      key: key,
      color: background,
      padding: EdgeInsets.all(3 * _geometry.scale),
      alignment: Alignment.topLeft,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: size * _geometry.scale,
          height: 1.2,
          fontFamily: _uiFamily(font),
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

  /// The Flutter font family that visually matches [font] — the same
  /// substitution the renderer uses for non-embedded base-14 fonts.
  static String _uiFamily(PdfStandardFont font) => switch (font) {
        PdfStandardFont.helvetica => 'Helvetica',
        PdfStandardFont.times => 'Times New Roman',
        PdfStandardFont.courier => 'Courier',
      };

  @override
  Widget build(BuildContext context) {
    _ensureGhost();
    // the afterimage has served once the committed revision's raster is
    // on screen — or is stale once the document moved past that revision
    if (_afterDocument != null &&
        (widget.rasterCurrent ||
            !identical(_afterDocument, _controller.document))) {
      _clearAfterimage();
    }
    if (_polyPoints != null && !_polyTool) {
      _polyPoints = null;
      _polyHover = null;
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
    // a free-text resize re-wraps at constant font size — preview the
    // wrapping live instead of the ghost's stretched glyphs
    final wrapResize =
        _resizeHandle != null && _resizeRect != null ? _textResizeStyle : null;
    // a Square/Circle resize regenerates at a constant stroke width:
    // preview that (live during the drag, then the frozen afterimage)
    // instead of the ghost, whose line would stretch and snap back
    final shapeResize = wrapResize == null &&
            _resizeHandle != null &&
            _resizeRect != null
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
      // until its raster lands — painted over the fade wash
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
        _rawPointer == null;
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
        supportedDevices: _drawTool && !_controller.fingerDrawsInk
            ? const {
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              }
            : null,
        // anchor drags at the press point, not where the recognizer won the
        // arena — a shape should start exactly where the pointer went down
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _panStart,
        onPanUpdate: _panUpdate,
        onPanEnd: _panEnd,
        onTapUp: _onTapUp,
        onDoubleTapDown:
            _polyTool || _tool == PdfEditTool.form ? _onDoubleTapDown : null,
        onDoubleTap:
            _polyTool || _tool == PdfEditTool.form ? _onDoubleTap : null,
        child: MouseRegion(
          cursor: _cursor,
          onHover: _onHover,
          onExit: (_) {
            if (_pickPosition == null &&
                (_signaturePreview == null || _signatureDrag) &&
                (_eraserCursor == null || _erasePath.isNotEmpty) &&
                _penCursor == null &&
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
                    strokeWidth: _controller.strokeWidth * _geometry.scale,
                    geometry: _geometry,
                    // the in-progress stroke is NOT here — it rides its own
                    // RepaintBoundary layer below so each appended point is a
                    // repaint, not a rebuild of this whole painter
                    strokes: _controller.strokesOn(widget.pageIndex),
                    pressures: _controller.strokePressuresOn(widget.pageIndex),
                    dragRect: _dragStart != null && _dragCurrent != null
                        ? Rect.fromPoints(_dragStart!, _dragCurrent!)
                        : null,
                    dragLine: _dragStart != null &&
                            _dragCurrent != null &&
                            _lineDragTool
                        ? (_dragStart!, _dragCurrent!)
                        : null,
                    dragPath: polyPreview,
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
                    ghost:
                        wrapResize == null && shapeResize == null ? _ghost : null,
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
                    // opaque-paper wash until that lands)
                    resizeClean: wrapResize != null ? _resizeCleanPicture : null,
                    resizeHideRect: wrapResize != null ? _resizeFrom : null,
                    resizeHideAngle: _resizeAngle,
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
                    eraserCursor: _tool == PdfEditTool.eraser || _rawErasing
                        ? _eraserCursor
                        : null,
                    eraserRadius: _controller.eraserRadius * _geometry.scale,
                    // the pen-preview dot (ink tool) and the rotation glyph
                    // (rotate knob): painted in place of the system cursor
                    penCursor: _tool == PdfEditTool.ink && _activeStroke == null
                        ? _penCursor
                        : null,
                    penOpacity: _controller.opacity,
                    rotateCursor: _rotateCursor,
                    afterGhost: _afterGhost != null
                        ? (
                            picture: _afterGhost!,
                            from: _afterGhostFrom!,
                            to: _afterGhostTo!,
                            source: _afterGhostSourceRect,
                            rotation: _afterGhostRotation,
                            localAngle: _afterGhostLocalAngle,
                            flipX: _afterGhostFlipX,
                            flipY: _afterGhostFlipY,
                          )
                        : null,
                    afterShape: _afterShape,
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
              // re-rasterizes per appended point — the latency fix.
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ActiveStrokePainter(this),
                    size: Size.infinite,
                  ),
                ),
              ),
              // a free-text resize in flight: the text re-wrapped to the
              // dragged box at its committed size — never the ghost's
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
                            _cancelTextEdit,
                        const SingleActivator(LogicalKeyboardKey.enter,
                            meta: true): _commitTextEdit,
                        const SingleActivator(LogicalKeyboardKey.enter,
                            control: true): _commitTextEdit,
                      },
                      child: Container(
                        // the chrome border lives in the inflate(2) gutter
                        // and paints as a FOREGROUND decoration: a regular
                        // decoration border adds itself to the padding, and
                        // any net inset shifts the text when the editor
                        // opens — content must sit exactly on the box
                        padding: const EdgeInsets.all(2),
                        // the box's own fill when it has one; otherwise wash
                        // the paper color over what's underneath: faint for a
                        // fresh box, near-opaque when editing existing text
                        // so the old rendering doesn't show through
                        color: _textEditFill ??
                            widget.pageColor.withValues(
                                alpha: _textEditExisting ? 0.92 : 0.3),
                        foregroundDecoration: BoxDecoration(
                          border: Border.all(
                              color: PdfViewerTheme.of(context)
                                      .annotationChromeColor ??
                                  const Color(0xFF1E88E5),
                              width: 1.5 * _chromeScale),
                        ),
                        child: TextField(
                          key: ValueKey(_textEditFieldName == null
                              ? 'pdf-freetext-editor'
                              : 'pdf-form-text-editor'),
                          controller: _textEditText,
                          focusNode: _textEditFocus,
                          autofocus: true,
                          // single-line form fields edit single-line: Enter
                          // commits instead of inserting a newline
                          maxLines:
                              _textEditFieldName == null || _textEditMultiline
                                  ? null
                                  : 1,
                          expands:
                              _textEditFieldName == null || _textEditMultiline,
                          onSubmitted: (_) => _commitTextEdit(),
                          textAlignVertical:
                              _textEditFieldName == null || _textEditMultiline
                                  ? TextAlignVertical.top
                                  : TextAlignVertical.center,
                          cursorColor: _textEditColor,
                          // mirrors the committed appearance: same size in view
                          // pixels, same 1.2 leading, matching family and color
                          style: TextStyle(
                            color: _textEditColor,
                            fontSize: _textEditSize * _geometry.scale,
                            height: 1.2,
                            fontFamily: _uiFamily(_textEditFont),
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(3 * _geometry.scale),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (showChip) _buildSelectionChip(chrome?.$1 ?? selected),
              if (_measureReadout() case (final text, final anchor))
                _buildMeasureReadoutChip(text, anchor),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The overlay's context-menu long-press: touch and stylus only, and it
/// only enters the gesture arena when [shouldClaim] says the press point
/// has a menu to offer — otherwise a held finger must stay available to
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
        segment.strokeWidth = pdfInkStrokeWidth(
            strokeWidth, (pressure[i] + pressure[i + 1]) / 2);
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
/// only when [_EditingPageOverlayState._activeStrokeRepaint] ticks — so a
/// pointer-move appends a point and bumps the notifier without rebuilding the
/// overlay or the heavy [_EditingPreviewPainter]. [shouldRepaint] stays false:
/// the repaint Listenable is the sole driver (the start, every point, and the
/// clear on commit/bail all tick it), and the buffers are mutated in place so
/// the painter always sees the current points.
class _ActiveStrokePainter extends CustomPainter {
  _ActiveStrokePainter(this._state)
      : super(repaint: _state._activeStrokeRepaint);

  final _EditingPageOverlayState _state;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = _state._activeStroke;
    if (stroke == null || stroke.isEmpty) return;
    final geometry = _state._geometry;
    var display = stroke;
    var pressures = _state._activeStrokePressures;
    // a forward-extrapolated lead so the line keeps up with the pen tip —
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
      _state._controller.strokeWidth * geometry.scale,
    );
  }

  @override
  bool shouldRepaint(_ActiveStrokePainter oldDelegate) => false;
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
    required this.dragPath,
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
    this.rotateCursor,
    required this.afterGhost,
    required this.afterShape,
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
  final List<Offset>? dragPath;
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
  /// resting view rect — drawn stretched onto [ghostTo] while
  /// [dragging], so the user sees the move/resize result live.
  final ui.Picture? ghost;
  final Rect? ghostFrom;
  final Rect? ghostTo;

  /// A Square/Circle resize preview (or its committed afterimage) drawn
  /// with a constant stroke width — the shape regenerates rather than
  /// stretching, so the ghost is suppressed in its favour.
  final _ShapeResize? shapeResize;
  final bool dragging;

  /// The chrome's total rotation (view radians, clockwise positive):
  /// the annotation's resting rotation plus a rotate drag's sweep — the
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
  /// they read as going — live during the swipe, and as the afterimage
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

  /// The rotate knob's cursor: a small curved-arrow glyph painted here
  /// (Flutter has no built-in rotation cursor, so the system cursor is
  /// hidden over the knob and this tracks the pointer instead).
  final Offset? rotateCursor;

  /// A just-committed move/resize/rotate, kept painted at full strength
  /// until the new revision's raster lands. [source] is the old
  /// on-raster position, washed out first so a slow page rerender
  /// doesn't leave a visible duplicate behind the afterimage.
  final ({
    ui.Picture picture,
    Rect from,
    Rect to,
    Rect? source,
    double rotation,
    double localAngle,
    bool flipX,
    bool flipY,
  })? afterGhost;

  /// A just-committed shape's drag preview, same deal.
  final ({
    Rect rect,
    PdfEditTool tool,
    Color color,
    double strokeWidth
  })? afterShape;

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

  /// The selected content element's box — orange, to read as "page
  /// content", distinct from the blue annotation chrome.
  final Rect? elementRect;

  /// An attention pulse around [flashRect] (the annotation a sidebar
  /// tile zoomed to), animated by [flashProgress] 0→1: an amber ring
  /// closing in on the rect, fading as it settles.
  final Rect? flashRect;
  final double flashProgress;

  final PdfViewerThemeData theme;

  /// Overlay pixels per intended screen pixel — chrome (selection boxes,
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
      case PdfEditTool.freeText || PdfEditTool.stamp || PdfEditTool.form:
        canvas.drawRect(
            rect,
            Paint()
              ..color = color.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      case PdfEditTool.redact:
        paintRedactionHatch(canvas, rect);
      default:
        canvas.drawRect(rect, paint);
    }
  }

  /// Draws a Square/Circle at [s.rect] the way the editor regenerates it:
  /// a constant-width stroke inset by half its width (so it stays inside
  /// the rect, matching `_shapeContent`), an optional fill, rotated about
  /// the rect center and dimmed to the appearance's opacity. The
  /// constant width is the whole point — the ghost would stretch it.
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
      canvas.saveLayer(
          s.rect.inflate(s.strokeWidth + 2),
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, s.opacity.clamp(0.0, 1.0)));
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
      s.ellipse ? canvas.drawOval(box, paint) : canvas.drawRect(box, paint);
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
    if (tool == PdfEditTool.polygon || tool == PdfEditTool.measureArea) {
      path.close();
      if (fillColor != null) {
        canvas.drawPath(
            path,
            Paint()
              ..color = fillColor
              ..style = PaintingStyle.fill);
      }
    }
    canvas.drawPath(dashed ? _dashPath(path, width) : path, paint);
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
  }

  Path _dashPath(Path path, double width) {
    final out = Path();
    final pattern = [math.max(2.0, width * 3), math.max(2.0, width * 2)];
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
    // behind shows through) — or, until that async render lands, an opaque
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
          canvas, dragPath!, tool, color, null, strokeWidth, dashed);
    } else if (dragRect case final rect?) {
      _paintShapePreview(canvas, rect, tool, color, strokeWidth);
    }

    for (final rect in redactionRects) {
      paintRedactionHatch(canvas, rect);
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
      if (source != null) {
        canvas.drawRect(
          source.inflate(2),
          Paint()..color = fadeColor.withValues(alpha: 0.92),
        );
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
    // exactly what a stamp removes), screen-constant line weight — a
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
      final r = math.max(strokeWidth / 2, 1.5 * chromeScale);
      canvas.drawCircle(pen, r + 1.5 * chromeScale,
          Paint()..color = const Color(0x33000000));
      canvas.drawCircle(
          pen, r, Paint()..color = color.withValues(alpha: penOpacity));
      canvas.drawCircle(
          pen,
          r,
          Paint()
            ..color = const Color(0xB3FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 * chromeScale);
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
      oldDelegate.rotateCursor != rotateCursor ||
      oldDelegate.afterGhost != afterGhost ||
      oldDelegate.afterShape != afterShape ||
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

/// Paints [picture] — an annotation appearance recorded in page raster
/// space (1 unit = 1 point, y down; see
/// [PdfPageRenderer.renderAnnotationPicture]) — mapped from its resting
/// view rect [from] onto [to], the live preview of a move/resize drag.
/// [scale] is the view's pixels-per-point.
///
/// Drawn at ~75% [opacity] by default: solid enough to judge the
/// result, light enough to read as a preview over the still-rendered
/// original. The post-commit afterimage paints at 1.0 — it *is* the
/// committed result, standing in until the new raster lands.
///
/// [rotation] (view radians, clockwise positive) additionally spins the
/// preview about [to]'s center — the rotate handle's live feedback.
///
/// With [localAngle] (a rotated selection's resting angle), [from] and
/// [to] are *local* boxes: the picture scales by their size ratio along
/// the rotated axes about the box centers, instead of stretching one
/// page-axis rect onto another — a rotated annotation's resize preview
/// must not shear.
/// Paints the hatched "marked for redaction" preview into [rect]: a faint
/// dark wash, a solid border, and diagonal cross-hatch lines, so a marked
/// region is unmistakable before it is burned (after burning the area is a
/// solid fill baked into the page content).
void paintRedactionHatch(Canvas canvas, Rect rect) {
  if (rect.isEmpty) return;
  canvas.drawRect(rect, Paint()..color = const Color(0x22000000));
  canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
  canvas.save();
  canvas.clipRect(rect);
  final hatch = Paint()
    ..color = const Color(0x66D32F2F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  const step = 8.0;
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

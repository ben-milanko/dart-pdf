// The drawing surface of the signature dialog, on its own: pointer and
// stylus capture with pressure, the predicted lead, and trackpad drawing,
// over a controller that holds the strokes, the ink and the pen. Widgets
// only, so a host can put it in its own sheet, page or platform dialog.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart'
    show pdfInkCurveControls, pdfInkStrokeWidth;

import '../l10n/pdf_l10n.dart';
import 'models/ink_signature.dart';
import 'stroke_prediction.dart';

/// The strokes, ink and pen of a [PdfSignaturePad], and its trackpad mode.
///
/// Points are in pad pixels (the pad's own coordinate space, y down);
/// [toSignature] normalizes them into a [PdfInkSignature]. The pad drives
/// [beginStroke]/[addPoint]/[endStroke] from the pointer; a host may drive
/// them too (a replay, a test).
class PdfSignaturePadController extends ChangeNotifier {
  PdfSignaturePadController({
    Color color = const Color(0xFF000000),
    double strokeWidth = PdfInkSignature.defaultStrokeWidth,
  })  : _color = color,
        _strokeWidth = _clampWidth(strokeWidth);

  static double _clampWidth(double width) => width
      .clamp(PdfInkSignature.minStrokeWidth, PdfInkSignature.maxStrokeWidth)
      .toDouble();

  final List<List<Offset>> _strokes = [];
  final List<List<double>?> _pressures = [];
  List<Offset>? _active;
  List<double>? _activePressures;

  /// The finished strokes, in pad pixels.
  List<List<Offset>> get strokes => List.unmodifiable(_strokes);

  /// Per-point pressures (0-1) paralleling [strokes]; null for a stroke
  /// drawn without pressure (mouse, finger).
  List<List<double>?> get pressures => List.unmodifiable(_pressures);

  /// The stroke being drawn, or null between strokes.
  List<Offset>? get activeStroke =>
      _active == null ? null : List.unmodifiable(_active!);

  /// Whether nothing has been drawn (no finished or in-progress stroke).
  bool get isEmpty => _strokes.isEmpty && _active == null;

  Color _color;

  /// The ink. Opaque: the alpha channel is dropped by [toSignature].
  Color get color => _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    notifyListeners();
  }

  double _strokeWidth;

  /// The pen width in points at [PdfInkSignature.referenceWidth] (clamped
  /// to [PdfInkSignature.minStrokeWidth]..[PdfInkSignature.maxStrokeWidth]).
  /// The pad scales it to its own width, so what is drawn there is what
  /// lands on the page.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    final clamped = _clampWidth(value);
    if (clamped == _strokeWidth) return;
    _strokeWidth = clamped;
    notifyListeners();
  }

  /// Starts a stroke at [point]; [pressure] (0-1) or null for none. Ends
  /// any stroke still open.
  void beginStroke(Offset point, {double? pressure}) {
    _commitActive();
    _active = [point];
    _activePressures = pressure == null ? null : [pressure];
    notifyListeners();
  }

  /// Extends the open stroke to [point] (opening one when none is). A
  /// pressure-less sample on a pressure stroke repeats the last pressure.
  void addPoint(Offset point, {double? pressure}) {
    final active = _active;
    if (active == null) {
      beginStroke(point, pressure: pressure);
      return;
    }
    active.add(point);
    final pressures = _activePressures;
    pressures?.add(pressure ?? pressures.last);
    notifyListeners();
  }

  /// Finishes the open stroke, if any.
  void endStroke() {
    if (_commitActive()) notifyListeners();
  }

  bool _commitActive() {
    final stroke = _active;
    if (stroke == null) return false;
    _strokes.add(stroke);
    _pressures.add(_activePressures);
    _active = null;
    _activePressures = null;
    return true;
  }

  /// Wipes every stroke.
  void clear() {
    if (isEmpty) return;
    _strokes.clear();
    _pressures.clear();
    _active = null;
    _activePressures = null;
    notifyListeners();
  }

  /// The drawing as a signature (normalized to its bounding box), or null
  /// when nothing is drawn. An open stroke is included.
  PdfInkSignature? toSignature() => PdfInkSignature.fromPad(
        [..._strokes, if (_active != null) _active!],
        [..._pressures, if (_active != null) _activePressures],
        _color,
        strokeWidth: _strokeWidth,
      );

  // --- trackpad: run by the mounted pad --------------------------------

  _PdfSignaturePadState? _pad;

  bool _trackpadAvailable = false;

  /// Whether the mounted pad's [PdfSignaturePad.trackpad] reported a
  /// trackpad - when [startTrackpad] can do anything.
  bool get trackpadAvailable => _trackpadAvailable;

  /// Whether a trackpad capture is running: the whole trackpad maps onto
  /// the pad, and any key (or the capture's own finish) ends it.
  bool get trackpadActive => _pad?._trackpadActive ?? false;

  /// Starts drawing with a finger on the trackpad. A no-op without a
  /// mounted pad that has a trackpad capture, or while one runs.
  void startTrackpad() => _pad?._startTrackpad();

  /// Ends a running trackpad capture.
  void stopTrackpad() => _pad?._stopTrackpad();

  void _setTrackpadAvailable(bool value) {
    if (value == _trackpadAvailable) return;
    _trackpadAvailable = value;
    notifyListeners();
  }

  void _changed() => notifyListeners();

  @override
  void dispose() {
    _pad = null;
    super.dispose();
  }
}

/// A signature drawing pad: draw with a mouse, finger or stylus (stylus
/// pressure is recorded and drawn as variable width, like the ink tool),
/// or - with a [trackpad] capture and
/// [PdfSignaturePadController.startTrackpad] - with a finger on the
/// trackpad. The strokes, ink and pen live in the [controller].
///
/// The pad draws at the scale a signature is stamped at: its width stands
/// for [PdfInkSignature.referenceWidth] points, so the pen thickness on the
/// pad is the pen thickness on the page. Size it with [size].
///
/// The stock [PdfSignatureDialog] is this pad plus a colour row, a pen
/// slider and Clear/Done; build your own around it for a different look:
///
/// ```dart
/// final pad = PdfSignaturePadController();
/// Column(children: [
///   PdfSignaturePad(controller: pad),
///   ListenableBuilder(
///     listenable: pad,
///     builder: (context, _) => MyButton(
///       onPressed: pad.isEmpty
///           ? null
///           : () => Navigator.pop(context, pad.toSignature()),
///     ),
///   ),
/// ])
/// ```
class PdfSignaturePad extends StatefulWidget {
  const PdfSignaturePad({
    super.key,
    required this.controller,
    this.size = const Size(360, 180),
    this.predictStrokes = true,
    this.trackpad,
    this.paperColor = const Color(0xFFFFFFFF),
    this.borderColor = const Color(0xFF79747E),
    this.activeBorderColor = const Color(0xFF6750A4),
    this.baselineColor = const Color(0x1F000000),
    this.borderRadius = 8,
    this.trackpadHint,
    this.trackpadHintStyle,
  });

  /// The strokes, ink and pen.
  final PdfSignaturePadController controller;

  /// The pad's size in logical pixels.
  final Size size;

  /// Draws a short predicted lead beyond the pen tip on the stroke being
  /// drawn, the same predictive ink the ink tool uses
  /// ([PdfViewer.predictStrokes]). Display only - never in the signature.
  final bool predictStrokes;

  /// The trackpad drawing source (see [PdfTrackpadSignatureCapture]); null
  /// offers none. [PdfSignaturePadController.trackpadAvailable] reports
  /// whether it found a trackpad.
  final PdfTrackpadSignatureCapture? trackpad;

  /// The paper. White by default, like the page the signature lands on.
  final Color paperColor;

  /// The pad's outline, and its outline while a trackpad capture runs.
  final Color borderColor;
  final Color activeBorderColor;

  /// The faint signing line three quarters of the way down.
  final Color baselineColor;

  final double borderRadius;

  /// The hint shown on the pad while a trackpad capture runs; null uses the
  /// localized "press any key when finished" text.
  final String? trackpadHint;

  /// Its style; null uses a small grey over the ambient text style.
  final TextStyle? trackpadHintStyle;

  @override
  State<PdfSignaturePad> createState() => _PdfSignaturePadState();
}

class _PdfSignaturePadState extends State<PdfSignaturePad> {
  double? _pointerPressure;

  StreamSubscription<PdfTrackpadSignatureEvent>? _trackpadCapture;

  /// Takes the keyboard while a capture runs, so any key can finish it.
  final _trackpadFocus = FocusNode(debugLabel: 'pdf-signature-trackpad');

  /// Ends a capture when the app loses focus, so a host that parked the
  /// cursor gets it back.
  AppLifecycleListener? _lifecycle;

  bool get _trackpadActive => _trackpadCapture != null;

  PdfSignaturePadController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
    _watchTrackpad();
  }

  @override
  void didUpdateWidget(PdfSignaturePad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _stopTrackpad();
      _unbind(oldWidget.controller);
      _bind(widget.controller);
    }
    if (!identical(oldWidget.trackpad, widget.trackpad)) {
      _stopTrackpad();
      _watchTrackpad();
    }
  }

  void _bind(PdfSignaturePadController controller) {
    controller._pad = this;
    controller.addListener(_onControllerChanged);
  }

  void _unbind(PdfSignaturePadController controller) {
    controller.removeListener(_onControllerChanged);
    if (identical(controller._pad, this)) {
      controller._pad = null;
      controller._setTrackpadAvailable(false);
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _watchTrackpad() {
    final trackpad = widget.trackpad;
    _lifecycle?.dispose();
    _lifecycle = null;
    _controller._setTrackpadAvailable(false);
    if (trackpad == null) return;
    _lifecycle =
        AppLifecycleListener(onInactive: _stopTrackpad, onHide: _stopTrackpad);
    trackpad.isAvailable().then((available) {
      if (mounted && identical(trackpad, widget.trackpad) && available) {
        _controller._setTrackpadAvailable(true);
      }
    }, onError: (Object _) {});
  }

  void _startTrackpad() {
    final trackpad = widget.trackpad;
    if (trackpad == null || _trackpadActive) return;
    _controller.endStroke();
    setState(() {
      _trackpadCapture = trackpad.capture().listen(
            _onTrackpad,
            onError: (Object _) => _stopTrackpad(),
            onDone: _stopTrackpad,
          );
    });
    _trackpadFocus.requestFocus();
    _controller._changed();
  }

  /// "Press any key when finished"; every other key is swallowed while the
  /// capture runs so none reaches the dialog or the document behind it.
  KeyEventResult _onTrackpadKey(FocusNode node, KeyEvent event) {
    if (!_trackpadActive) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _stopTrackpad();
    return KeyEventResult.handled;
  }

  void _stopTrackpad() {
    final capture = _trackpadCapture;
    if (capture == null) return;
    _trackpadCapture = null;
    capture.cancel();
    if (!mounted) return;
    _controller.endStroke();
    setState(() {});
    _controller._changed();
  }

  /// The whole trackpad surface maps onto the whole pad, like a desktop
  /// trackpad signature: where the finger lands is where the pen lands.
  void _onTrackpad(PdfTrackpadSignatureEvent event) {
    if (!mounted) return;
    final size = widget.size;
    final point = Offset(event.x.clamp(0.0, 1.0) * size.width,
        event.y.clamp(0.0, 1.0) * size.height);
    switch (event.phase) {
      case PdfTrackpadSignaturePhase.down:
        _controller.beginStroke(point);
      case PdfTrackpadSignaturePhase.move:
        _controller.addPoint(point);
      case PdfTrackpadSignaturePhase.up:
        final active = _controller._active;
        if (active != null && (active.isEmpty || active.last != point)) {
          _controller.addPoint(point);
        }
        _controller.endStroke();
      case PdfTrackpadSignaturePhase.finish:
        _stopTrackpad();
    }
  }

  @override
  void dispose() {
    _trackpadCapture?.cancel();
    _trackpadCapture = null;
    _lifecycle?.dispose();
    _trackpadFocus.dispose();
    _unbind(widget.controller);
    super.dispose();
  }

  /// 0–1 within the device's range; null when the device has none
  /// (mouse, finger) - same convention as the ink overlay.
  static double? _normalizedPressure(PointerEvent event) {
    if (event.pressureMax <= event.pressureMin) return null;
    return ((event.pressure - event.pressureMin) /
            (event.pressureMax - event.pressureMin))
        .clamp(0.0, 1.0);
  }

  /// The in-progress stroke with a display-only predicted lead appended
  /// (and its last pressure carried onto the lead), recomputed each build
  /// so the next real sample replaces it - the pad's analogue of the ink
  /// tool's live prediction. Null when no stroke is active.
  ({List<Offset> points, List<double>? pressures})? get _activeDisplay {
    final active = _controller._active;
    if (active == null) return null;
    var pressures = _controller._activePressures;
    if (widget.predictStrokes) {
      final lead = pdfPredictStrokeLead([for (final p in active) (p.dx, p.dy)]);
      if (lead.isNotEmpty) {
        final points = [...active, for (final (x, y) in lead) Offset(x, y)];
        if (pressures != null) {
          pressures = [...pressures, for (final _ in lead) pressures.last];
        }
        return (points: points, pressures: pressures);
      }
    }
    return (points: [...active], pressures: pressures?.toList());
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final activeDisplay = _activeDisplay;
    final radius = BorderRadius.circular(widget.borderRadius);
    final hintStyle = widget.trackpadHintStyle ??
        DefaultTextStyle.of(context)
            .style
            .copyWith(fontSize: 12, color: const Color(0x8A000000));
    Widget pad = Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: widget.paperColor,
        border: _trackpadActive
            ? Border.all(color: widget.activeBorderColor, width: 2)
            : Border.all(color: widget.borderColor),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Listener(
          onPointerDown: (e) => _pointerPressure = _normalizedPressure(e),
          onPointerMove: (e) => _pointerPressure = _normalizedPressure(e),
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (details) => _controller
                .beginStroke(details.localPosition, pressure: _pointerPressure),
            onPanUpdate: (details) => _controller
                .addPoint(details.localPosition, pressure: _pointerPressure),
            onPanEnd: (_) => _controller.endStroke(),
            child: CustomPaint(
              key: const ValueKey('pdf-signature-pad'),
              size: size,
              painter: _SignaturePadPainter(
                strokes: [
                  ..._controller._strokes,
                  if (activeDisplay != null) activeDisplay.points
                ],
                pressures: [
                  ..._controller._pressures,
                  if (activeDisplay != null) activeDisplay.pressures
                ],
                color: _controller.color,
                strokeWidth: _controller.strokeWidth *
                    size.width /
                    PdfInkSignature.referenceWidth,
                baselineColor: widget.baselineColor,
              ),
              child: _trackpadActive
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          widget.trackpadHint ??
                              pdfL10n(context).sigTrackpadHint,
                          key: const ValueKey('pdf-signature-trackpad-hint'),
                          textAlign: TextAlign.center,
                          style: hintStyle,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
    if (widget.trackpad != null) {
      pad = Focus(
        focusNode: _trackpadFocus,
        onKeyEvent: _onTrackpadKey,
        child: pad,
      );
    }
    return pad;
  }
}

class _SignaturePadPainter extends CustomPainter {
  _SignaturePadPainter({
    required this.strokes,
    required this.pressures,
    required this.color,
    required this.strokeWidth,
    required this.baselineColor,
  });

  final List<List<Offset>> strokes;
  final List<List<double>?> pressures;
  final Color color;
  final Color baselineColor;

  /// The pen width in pad pixels - the chosen point width scaled to the
  /// pad, so what is drawn here is what lands on the page.
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = baselineColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(16, size.height * 0.75),
        Offset(size.width - 16, size.height * 0.75), baseline);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final pressure = i < pressures.length ? pressures[i] : null;
      if (stroke.isEmpty) continue;
      // same Catmull-Rom smoothing as the committed ink appearance
      final controls =
          pdfInkCurveControls([for (final p in stroke) (p.dx, p.dy)]);
      if (pressure == null) {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (var j = 0; j + 1 < stroke.length; j++) {
          final ((c1x, c1y), (c2x, c2y)) = controls[j];
          path.cubicTo(c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy);
        }
        canvas.drawPath(path, paint);
      } else {
        // same per-segment width mapping as the committed appearance
        final segment = Paint()
          ..color = color
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        if (stroke.length == 1) {
          canvas.drawCircle(
              stroke.single,
              pdfInkStrokeWidth(strokeWidth, pressure.first) / 2,
              Paint()..color = color);
          continue;
        }
        for (var j = 0; j + 1 < stroke.length; j++) {
          final avg = (pressure[j] + pressure[j + 1]) / 2;
          segment.strokeWidth = pdfInkStrokeWidth(strokeWidth, avg);
          final ((c1x, c1y), (c2x, c2y)) = controls[j];
          canvas.drawPath(
              Path()
                ..moveTo(stroke[j].dx, stroke[j].dy)
                ..cubicTo(
                    c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy),
              segment);
        }
      }
    }
  }

  // the stroke lists are rebuilt every build, so this repaints on every
  // pad rebuild - which is every sample, as before
  @override
  bool shouldRepaint(_SignaturePadPainter old) =>
      old.strokes != strokes ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.baselineColor != baselineColor;
}

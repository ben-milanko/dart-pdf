import 'package:pdf_document/pdf_document.dart'
    show PdfMeasurementKind, PdfRect;

import 'editing_controller.dart';
import 'editing_signature.dart';

/// Which controls the style popup should show for a tool (or an annotation
/// selection) - each context only carries the settings it can actually use,
/// so the tune popup never shows (say) a font picker while a rectangle is
/// armed, or line endings while ink is armed.
///
/// This mirrors, on the tool side, what [PdfEditToolBehavior.styleFields]
/// exposes; the toolbar also builds one directly from a selected
/// annotation's subtype. See [PdfEditToolBehavior].
class PdfToolStyleFields {
  const PdfToolStyleFields({
    this.stroke = false,
    this.strokeColor = false,
    this.opacity = false,
    this.lineType = false,
    this.lineScale = false,
    this.lineEndings = false,
    this.font = false,
    this.boxColors = false,
    this.shapeFill = false,
    this.cornerRadius = false,
    this.eraser = false,
    this.formField = false,
  });

  final bool stroke;

  /// The stroke/outline colour row - shapes (including revision clouds) and
  /// the line family. Distinct from [shapeFill], the interior fill.
  final bool strokeColor;

  final bool opacity;

  /// The rectangle corner-radius slider (rectangle shape only).
  final bool cornerRadius;

  /// The line-type dropdown (solid / dashed / dotted / dash-dot) - shapes
  /// and the line family.
  final bool lineType;

  /// The pattern-scale slider - sizes dash patterns and cloudy scallops
  /// apart from the pen width. Shown alongside [lineType].
  final bool lineScale;
  final bool lineEndings;

  /// Font size + family (free text).
  final bool font;

  /// The text-box fill + border colour rows (free text).
  final bool boxColors;

  /// The shape interior-fill colour row (rectangle / ellipse).
  final bool shapeFill;

  /// Eraser radius - replaces every other control while the eraser is armed.
  final bool eraser;

  /// The form text field style block (font, alignment, auto-size, size,
  /// multiline, colour) - a single text-field widget is selected. Only ever
  /// set from an annotation selection, never a tool.
  final bool formField;

  bool get isEmpty =>
      !stroke &&
      !strokeColor &&
      !opacity &&
      !lineType &&
      !lineScale &&
      !lineEndings &&
      !font &&
      !boxColors &&
      !shapeFill &&
      !cornerRadius &&
      !eraser &&
      !formField;
}

/// One authoritative view of an editing tool's behaviour.
///
/// [PdfEditTool] is a wide enum, and its behaviour used to be smeared across
/// several `switch (tool)` blocks in separate gesture phases (the overlay's
/// pointer handlers), the controller's persisted-style scopes, and the
/// toolbar's per-tool capability booleans. This descriptor owns that
/// per-tool identity in one place: the classification the overlay dispatches
/// on, the style scope the controller persists, the controls the toolbar's
/// tune popup offers, and - for the tools whose commit is a single document
/// mutation - the commit itself, so it can be unit-tested against a
/// [PdfEditingController] without pumping a widget.
///
/// This mirrors [PdfAnnotationBehavior] (pdf_document) on the tool side.
/// Material labels, icons, and dock grouping deliberately stay in the
/// toolbar; this descriptor owns only tool semantics.
///
/// One adapter per tool is registered in [_behaviors]; look one up with
/// [PdfEditToolBehavior.of] or [PdfEditToolBehavior.maybeOf].
abstract class PdfEditToolBehavior {
  const PdfEditToolBehavior();

  /// The enum value this behaviour implements.
  PdfEditTool get tool;

  // ---------------------------------------------------------------------
  // Classification - the predicates the overlay's gesture phases route on.
  // ---------------------------------------------------------------------

  /// Freehand ink family (pen or freehand highlighter): strokes accumulate
  /// in the controller until finished as one Ink annotation.
  bool get isInk => false;

  /// A "draw" tool driven through the raw pointer stream rather than the
  /// gesture arena (ink, freehand highlight, and the eraser).
  bool get isDraw => false;

  /// A tool whose strokes buffer under a held auto-commit (ink / highlight).
  bool get buffersInk => false;

  /// Placed by clicking a running vertex list, finished by a double-tap
  /// (polyline / polygon and the poly-shaped measurements). The cloud tool
  /// is a hybrid and is deliberately *not* included - it rubber-bands a
  /// rectangle by default.
  bool get isPoly => false;

  /// Placed by dragging a single straight segment (a /Line, an arrow, a
  /// distance/slope measurement, or the scale-calibration drag).
  bool get isLineDrag => false;

  /// The measurement kind this tool stamps, or null for a non-measurement
  /// tool.
  PdfMeasurementKind? get measureKind => null;

  /// The number of clicks a fixed-arity poly tool takes before it
  /// auto-finishes - three for the angle and arc takeoffs - or null for an
  /// open-ended poly tool (finished by a double-tap).
  int? get fixedPolyCount => null;

  // ---------------------------------------------------------------------
  // Persisted style scope - what the controller remembers per tool.
  // ---------------------------------------------------------------------

  /// The persisted-style scope key - a stable slot name for the tool's
  /// remembered style, or null for the tools that create nothing styled
  /// (select, content, form, redact, image, snapshot, signatureBox,
  /// calibrate). See [PdfEditingController.preferences].
  String? get styleScopeKey => null;

  /// The style fields this tool remembers - mirrors the controls its toolbar
  /// strip exposes, so a rectangle keeps its fill but not a font, ink keeps
  /// its stroke but not line endings, and so on.
  Set<String> get styleScopeFields => const {};

  /// Initial values seeded into the tool's style scope the first time it is
  /// armed (the freehand highlighter's broad translucent yellow).
  Map<String, Object?> get styleScopeDefaults => const {};

  /// Whether the tool creates annotations that carry a colour the toolbar
  /// can offer - i.e. its scope remembers `color`.
  bool get usesColor => styleScopeFields.contains('color');

  // ---------------------------------------------------------------------
  // Toolbar tune popup.
  // ---------------------------------------------------------------------

  /// Which controls the tune popup shows while this tool is armed.
  PdfToolStyleFields get styleFields => const PdfToolStyleFields();

  // ---------------------------------------------------------------------
  // Commit - a single document mutation, factored out so it can be driven
  // from a unit test (feed a controller + page-space geometry, assert the
  // emitted annotation) rather than a pumped widget. The overlay maps the
  // gesture to page space, calls the matching hook, and keeps the
  // render-side afterimage bookkeeping. Tools whose placement needs a
  // prompt/picker (stamp text, note text, image bytes, calibration length,
  // volume depth) keep that flow in the overlay.
  // ---------------------------------------------------------------------

  /// Commits a rubber-banded box for the shape family (rectangle, ellipse,
  /// cloud). Returns true if it consumed the gesture.
  bool commitShapeRect(PdfEditingController controller, int page, PdfRect rect) =>
      false;

  /// Commits a single straight-segment drag from [start] to [end] (both in
  /// page space) for the line family and the line-shaped measurements.
  /// Returns true if it consumed the gesture.
  bool commitLineDrag(PdfEditingController controller, int page,
          (double, double) start, (double, double) end) =>
      false;

  /// Commits a finished vertex list ([points] in page space) for the poly
  /// family and the poly-shaped measurements. Returns true if it consumed
  /// the gesture; false leaves it to the overlay (the volume tool, which
  /// must prompt for a depth first).
  bool commitPoly(
          PdfEditingController controller, int page, List<(double, double)> points) =>
      false;

  /// The behaviour for [tool].
  static PdfEditToolBehavior of(PdfEditTool tool) => _behaviors[tool]!;

  /// The behaviour for [tool], or null when no tool is armed.
  static PdfEditToolBehavior? maybeOf(PdfEditTool? tool) =>
      tool == null ? null : _behaviors[tool];
}

// ---------------------------------------------------------------------------
// Adapters. Grouped by shape of behaviour; metadata-only tools share
// [_SimpleTool] so each still gets one authoritative row.
// ---------------------------------------------------------------------------

/// A tool whose behaviour is pure metadata (no drag/tap commit lives here -
/// its placement stays in the overlay because it needs a prompt, a picker,
/// or the select/erase interaction).
class _SimpleTool extends PdfEditToolBehavior {
  const _SimpleTool(
    this.tool, {
    this.styleScopeKey,
    this.styleScopeFields = const {},
    this.styleScopeDefaults = const {},
    this.styleFields = const PdfToolStyleFields(),
    this.isInk = false,
    this.isDraw = false,
    this.buffersInk = false,
    this.isLineDrag = false,
  });

  @override
  final PdfEditTool tool;
  @override
  final String? styleScopeKey;
  @override
  final Set<String> styleScopeFields;
  @override
  final Map<String, Object?> styleScopeDefaults;
  @override
  final PdfToolStyleFields styleFields;
  @override
  final bool isInk;
  @override
  final bool isDraw;
  @override
  final bool buffersInk;
  @override
  final bool isLineDrag;
}

/// Rectangle / ellipse / cloud: a drag rubber-bands a box that becomes a
/// /Square, /Circle, or cloudy /Polygon.
class _ShapeTool extends PdfEditToolBehavior {
  const _ShapeTool(this.tool,
      {required this.styleScopeKey,
      required this.styleScopeFields,
      required this.styleFields});

  @override
  final PdfEditTool tool;
  @override
  final String? styleScopeKey;
  @override
  final Set<String> styleScopeFields;
  @override
  final PdfToolStyleFields styleFields;

  @override
  bool commitShapeRect(
      PdfEditingController controller, int page, PdfRect rect) {
    switch (tool) {
      case PdfEditTool.rectangle:
        controller.addRectangle(page, rect);
      case PdfEditTool.ellipse:
        controller.addEllipse(page, rect);
      case PdfEditTool.cloudPolygon:
        controller.addCloudPolygon(page, rect);
      default:
        return false;
    }
    return true;
  }
}

/// Line / arrow: a drag lays down a straight /Line annotation.
class _LineTool extends PdfEditToolBehavior {
  const _LineTool(this.tool,
      {required this.styleScopeKey, required this.styleScopeFields});

  @override
  final PdfEditTool tool;
  @override
  final String? styleScopeKey;
  @override
  final Set<String> styleScopeFields;
  @override
  bool get isLineDrag => true;

  @override
  PdfToolStyleFields get styleFields => PdfToolStyleFields(
        stroke: true,
        strokeColor: true,
        opacity: true,
        lineType: true,
        lineScale: true,
        lineEndings: tool == PdfEditTool.line,
      );

  @override
  bool commitLineDrag(PdfEditingController controller, int page,
      (double, double) start, (double, double) end) {
    controller.addLine(page, start, end, arrow: tool == PdfEditTool.arrow);
    return true;
  }
}

/// Polyline / polygon: a running vertex list becomes an open /PolyLine or a
/// closed /Polygon.
class _PolyTool extends PdfEditToolBehavior {
  const _PolyTool(this.tool,
      {required this.styleScopeKey,
      required this.styleScopeFields,
      required this.styleFields});

  @override
  final PdfEditTool tool;
  @override
  final String? styleScopeKey;
  @override
  final Set<String> styleScopeFields;
  @override
  final PdfToolStyleFields styleFields;
  @override
  bool get isPoly => true;

  @override
  bool commitPoly(PdfEditingController controller, int page,
      List<(double, double)> points) {
    if (tool == PdfEditTool.polygon) {
      controller.addPolygon(page, points);
    } else {
      controller.addPolyLine(page, points);
    }
    return true;
  }
}

/// A line-shaped measurement (distance / slope): a drag stamps a /Line
/// takeoff whose real-world length or inclination is shown live.
class _MeasureLineTool extends PdfEditToolBehavior {
  const _MeasureLineTool(this.tool, this.measureKind);

  @override
  final PdfEditTool tool;
  @override
  final PdfMeasurementKind measureKind;
  @override
  bool get isLineDrag => true;
  @override
  String get styleScopeKey => tool.name;
  @override
  Set<String> get styleScopeFields => const {'color', 'strokeWidth', 'opacity'};
  @override
  PdfToolStyleFields get styleFields => PdfToolStyleFields(
        stroke: true,
        opacity: true,
        font: true,
        // distance/slope draw an open segment, so it carries endings
        lineEndings: true,
      );

  @override
  bool commitLineDrag(PdfEditingController controller, int page,
      (double, double) start, (double, double) end) {
    controller.addMeasurement(page, measureKind, [start, end]);
    return true;
  }
}

/// A poly-shaped measurement (perimeter / area / angle / arc / volume): a
/// running vertex list stamps a /PolyLine or /Polygon takeoff whose live
/// readout is its perimeter, area, interior angle, arc length, or volume.
class _MeasurePolyTool extends PdfEditToolBehavior {
  const _MeasurePolyTool(this.tool, this.measureKind,
      {this.fixedPolyCount, required this.hasEndings});

  @override
  final PdfEditTool tool;
  @override
  final PdfMeasurementKind measureKind;
  @override
  final int? fixedPolyCount;

  /// Whether the running readout draws an open segment (so it carries
  /// endings): perimeter / angle / arc, but not the closed area / volume.
  final bool hasEndings;

  @override
  bool get isPoly => true;
  @override
  String get styleScopeKey => tool.name;
  @override
  Set<String> get styleScopeFields => const {'color', 'strokeWidth', 'opacity'};
  @override
  PdfToolStyleFields get styleFields =>
      PdfToolStyleFields(stroke: true, opacity: true, font: true, lineEndings: hasEndings);

  @override
  bool commitPoly(PdfEditingController controller, int page,
      List<(double, double)> points) {
    // The volume tool needs a depth prompt first, so it defers to the
    // overlay rather than committing here.
    if (measureKind == PdfMeasurementKind.volume) return false;
    controller.addMeasurement(page, measureKind, points);
    return true;
  }
}

const _shapeFields = {
  'color',
  'strokeWidth',
  'opacity',
  'lineStyle',
  'lineScale',
  'shapeFillColor',
};

const _lineFields = {
  'color',
  'strokeWidth',
  'opacity',
  'lineStyle',
  'lineScale',
  'lineStartEnding',
  'lineEndEnding',
};

const _textFields = {
  'color',
  'fontSize',
  'fontFamily',
  'textAlign',
  'opacity',
  'textFillColor',
  'textBorderColor',
  'strokeWidth',
};

const _inkFields = {'color', 'strokeWidth', 'opacity'};

final Map<PdfEditTool, PdfEditToolBehavior> _behaviors = {
  for (final b in <PdfEditToolBehavior>[
    const _SimpleTool(PdfEditTool.select),
    const _SimpleTool(PdfEditTool.ink,
        styleScopeKey: 'ink',
        styleScopeFields: _inkFields,
        isInk: true,
        isDraw: true,
        buffersInk: true,
        styleFields: PdfToolStyleFields(stroke: true, opacity: true)),
    const _SimpleTool(PdfEditTool.highlight,
        styleScopeKey: 'freehandHighlight',
        styleScopeFields: _inkFields,
        styleScopeDefaults: {
          'color': 0xFFFFD100,
          'strokeWidth': 12.0,
          'opacity': 0.45,
        },
        isInk: true,
        isDraw: true,
        buffersInk: true,
        styleFields: PdfToolStyleFields(stroke: true, opacity: true)),
    const _SimpleTool(PdfEditTool.eraser,
        styleScopeKey: 'eraser',
        styleScopeFields: {'eraserRadius'},
        isDraw: true,
        styleFields: PdfToolStyleFields(eraser: true)),
    const _ShapeTool(PdfEditTool.rectangle,
        styleScopeKey: 'rectangle',
        styleScopeFields: {
          'color',
          'strokeWidth',
          'opacity',
          'lineStyle',
          'shapeFillColor',
          'cornerRadius',
        },
        styleFields: PdfToolStyleFields(
          stroke: true,
          strokeColor: true,
          opacity: true,
          lineType: true,
          lineScale: true,
          shapeFill: true,
          cornerRadius: true,
        )),
    const _ShapeTool(PdfEditTool.ellipse,
        styleScopeKey: 'ellipse',
        styleScopeFields: _shapeFields,
        styleFields: PdfToolStyleFields(
          stroke: true,
          strokeColor: true,
          opacity: true,
          lineType: true,
          lineScale: true,
          shapeFill: true,
        )),
    const _ShapeTool(PdfEditTool.cloudPolygon,
        styleScopeKey: 'cloudPolygon',
        styleScopeFields: _shapeFields,
        styleFields: PdfToolStyleFields(
          stroke: true,
          strokeColor: true,
          opacity: true,
          lineType: true,
          lineScale: true,
          shapeFill: true,
        )),
    const _LineTool(PdfEditTool.line,
        styleScopeKey: 'line', styleScopeFields: _lineFields),
    const _LineTool(PdfEditTool.arrow, styleScopeKey: 'arrow', styleScopeFields: {
      'color',
      'strokeWidth',
      'opacity',
      'lineStyle',
      'lineScale',
    }),
    const _PolyTool(PdfEditTool.polyline,
        styleScopeKey: 'polyline',
        styleScopeFields: _lineFields,
        styleFields: PdfToolStyleFields(
          stroke: true,
          strokeColor: true,
          opacity: true,
          lineType: true,
          lineScale: true,
          lineEndings: true,
        )),
    const _PolyTool(PdfEditTool.polygon,
        styleScopeKey: 'polygon',
        styleScopeFields: _shapeFields,
        styleFields: PdfToolStyleFields(
          stroke: true,
          strokeColor: true,
          opacity: true,
          lineType: true,
          lineScale: true,
          shapeFill: true,
        )),
    const _MeasureLineTool(PdfEditTool.measureDistance, PdfMeasurementKind.distance),
    const _MeasureLineTool(PdfEditTool.measureSlope, PdfMeasurementKind.slope),
    const _MeasurePolyTool(
        PdfEditTool.measurePerimeter, PdfMeasurementKind.perimeter,
        hasEndings: true),
    const _MeasurePolyTool(PdfEditTool.measureArea, PdfMeasurementKind.area,
        hasEndings: false),
    const _MeasurePolyTool(PdfEditTool.measureAngle, PdfMeasurementKind.angle,
        fixedPolyCount: 3, hasEndings: true),
    const _MeasurePolyTool(PdfEditTool.measureArc, PdfMeasurementKind.arc,
        fixedPolyCount: 3, hasEndings: true),
    const _MeasurePolyTool(PdfEditTool.measureVolume, PdfMeasurementKind.volume,
        hasEndings: false),
    const _SimpleTool(PdfEditTool.calibrate, isLineDrag: true),
    const _SimpleTool(PdfEditTool.freeText,
        styleScopeKey: 'freeText',
        styleScopeFields: _textFields,
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.callout,
        styleScopeKey: 'callout',
        styleScopeFields: _textFields,
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    // The Insert strip offers one shared tune popup (opacity + font + text-box
    // colours) to every tool it hosts, so each carries the same styleFields
    // even though its persisted scope differs.
    const _SimpleTool(PdfEditTool.note,
        styleScopeKey: 'note',
        styleScopeFields: {'color'},
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.stamp,
        styleScopeKey: 'stamp',
        styleScopeFields: {'color', 'opacity'},
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.count,
        styleScopeKey: 'count',
        styleScopeFields: {'color', 'opacity'},
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    // A stamped signature is ink like any other: it carries the tool's
    // colour and pen width, so the strip offers the colour row and the tune
    // popup the stroke-width slider, and both are remembered per tool.
    const _SimpleTool(PdfEditTool.signature,
        styleScopeKey: 'signature',
        styleScopeFields: {'color', 'strokeWidth'},
        styleScopeDefaults: {
          'strokeWidth': PdfInkSignature.defaultStrokeWidth,
        },
        styleFields: PdfToolStyleFields(
            stroke: true, opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.image,
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.content),
    const _SimpleTool(PdfEditTool.form),
    const _SimpleTool(PdfEditTool.redact),
    const _SimpleTool(PdfEditTool.snapshot),
    const _SimpleTool(PdfEditTool.signatureBox),
    const _SimpleTool(PdfEditTool.link),
  ])
    b.tool: b,
};

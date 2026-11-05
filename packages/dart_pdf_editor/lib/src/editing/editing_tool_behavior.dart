import 'dart:ui' show Color, Offset, Rect;

import 'package:pdf_document/pdf_document.dart'
    show
        PdfMeasurementKind,
        PdfRect,
        PdfStampTemplate,
        pdfResolveStampTemplateText;

import 'editing_controller.dart';
import 'models/ink_signature.dart';

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

/// What a press-and-drag with a tool does on the page. The overlay's drag
/// phase dispatches on this, not on tool identity.
enum PdfToolDrag {
  /// Nothing: the tool works by taps (notes, the count, poly vertices).
  none,

  /// The selection's own drags: move, resize, rotate, reshape, marquee.
  select,

  /// Erases whatever the pointer crosses.
  erase,

  /// A freehand stroke.
  freehand,

  /// Drags out a region - a box, a segment or a callout leader - that
  /// [PdfEditToolBehavior.commitRegion] places.
  region,

  /// The form tool: manipulate a field, or drag out a new one.
  form,

  /// Press-drag-release placement of the saved signature.
  signature,

  /// Grabs a page-content element and moves it.
  content,
}

/// A tap with a tool: [at] is the (grid-snapped) view point, [point] its
/// page-space position, [hit] the unsnapped page point under the pointer,
/// and [additive] whether a selection modifier was held.
typedef PdfToolTap = ({
  Offset at,
  (double, double) point,
  (double, double) hit,
  bool additive,
});

/// The page overlay as a tool's placement sees it: the page it works on,
/// the inline text editor, the prompts and pickers, and the afterimages that
/// keep a commit painted until the page re-renders. View space is the
/// overlay's. Tools commit through this port, so each one's gesture →
/// preview → commit lives in its [PdfEditToolBehavior].
abstract interface class PdfToolHost {
  PdfEditingController get controller;

  /// The page the gesture is on.
  int get page;

  (double, double) toPagePoint(Offset view);
  PdfRect toPageRect(Rect view);

  // the inline text editor
  void openTextBox(Rect box);
  void openCallout(Rect box, Offset terminus);
  void openCloudCallout(Rect region);

  /// A default-sized box with its top-left at [at], nudged onto the page.
  Rect defaultBoxAt(Offset at);

  /// The cloud a tap lays down, centred on [center].
  Rect defaultCloudAt(Offset center);

  /// The box a callout placement drag from [start] to [end] drops.
  Rect calloutBoxFor(Offset start, Offset end);

  // prompts and flows the host owns
  Future<String?> promptNoteText();
  Future<String?> promptStampText();
  Future<void> calibrate(Offset start, Offset end);
  Future<void> measureCustom(Offset start, Offset end);
  Future<void> addImageIn(PdfRect rect);
  Future<void> placeImageAt(double x, double y);
  Future<void> addLinkIn(PdfRect rect);
  Future<void> placeSignatureBox(PdfRect rect);
  Future<void> snapshot(Rect box, PdfRect rect);
  void placeSignatureAt(Offset at);

  // afterimages: each paints the commit the [run] callback makes until the
  // new revision's raster lands (a no-op when nothing was written)
  void holdShape(PdfEditTool tool, Rect box, int before);
  void holdLine(PdfEditTool tool, Offset start, Offset end, int before);
  void holdCheckMark(int before);
  Future<void> stampBox(Rect box,
      {required String? text,
      PdfStampTemplate? template,
      required Color color,
      required void Function() run});

  /// Drops a stamp at [at]: the active custom stamp when [text] is null,
  /// else a text stamp captioned [text].
  Future<void> stampAt(Offset at, {String? text, required void Function() run});
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

  /// Whether Escape disarms this tool before backing out of anything else
  /// (see [PdfEditingMode.escapesFirst]).
  bool get escapesFirst => false;

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
  bool commitShapeRect(
          PdfEditingController controller, int page, PdfRect rect) =>
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
  bool commitPoly(PdfEditingController controller, int page,
          List<(double, double)> points) =>
      false;

  // ---------------------------------------------------------------------
  // Gesture lifecycle - what a press does, and how it commits through the
  // page overlay ([PdfToolHost]).
  // ---------------------------------------------------------------------

  /// What a press-and-drag with this tool does.
  PdfToolDrag get drag => PdfToolDrag.none;

  /// Whether a tap with this tool creates something (the overlay tracks it
  /// as a create interaction).
  bool get tapCreates => false;

  /// Commits a [PdfToolDrag.region] drag from [start] to [end] (view space).
  Future<void> commitRegion(PdfToolHost host, Offset start, Offset end) async {}

  /// Commits a tap.
  Future<void> commitTap(PdfToolHost host, PdfToolTap tap) async {}

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
    this.drag = PdfToolDrag.none,
    this.tapCreates = false,
    this.escapesFirst = false,
    this.region,
    this.tap,
  });

  @override
  final PdfEditTool tool;
  @override
  final PdfToolDrag drag;
  @override
  final bool tapCreates;
  @override
  final bool escapesFirst;

  /// The [commitRegion] of a tool whose region needs only the host.
  final Future<void> Function(PdfToolHost host, Offset start, Offset end)?
      region;

  /// The [commitTap] of a tool whose tap needs only the host.
  final Future<void> Function(PdfToolHost host, PdfToolTap tap)? tap;

  @override
  Future<void> commitRegion(PdfToolHost host, Offset start, Offset end) =>
      region?.call(host, start, end) ?? Future.value();

  @override
  Future<void> commitTap(PdfToolHost host, PdfToolTap tap) =>
      this.tap?.call(host, tap) ?? Future.value();
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
  PdfToolDrag get drag => PdfToolDrag.region;

  @override
  Future<void> commitRegion(PdfToolHost host, Offset start, Offset end) async {
    final box = Rect.fromPoints(start, end);
    if (_isClick(box)) return;
    final before = host.controller.revisionId;
    commitShapeRect(host.controller, host.page, host.toPageRect(box));
    // the drag preview, frozen until the new revision renders
    host.holdShape(tool, box, before);
  }

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
  PdfToolDrag get drag => PdfToolDrag.region;

  @override
  Future<void> commitRegion(PdfToolHost host, Offset start, Offset end) =>
      _commitSegment(this, host, start, end);

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
  PdfToolDrag get drag => PdfToolDrag.region;

  @override
  Future<void> commitRegion(PdfToolHost host, Offset start, Offset end) =>
      _commitSegment(this, host, start, end);

  @override
  bool commitLineDrag(PdfEditingController controller, int page,
      (double, double) start, (double, double) end) {
    controller.addMeasurement(page, measureKind, [start, end]);
    return true;
  }
}

/// The written-value dimension ([PdfEditTool.measureCustom]): a distance
/// drag whose value the user types, so its commit - which needs that
/// prompt - stays in the overlay. A dimension reads with an arrowhead at
/// each end, so those are its scope's defaults, remembered like a line's.
class _MeasureCustomTool extends PdfEditToolBehavior {
  const _MeasureCustomTool();

  @override
  PdfEditTool get tool => PdfEditTool.measureCustom;
  @override
  PdfToolDrag get drag => PdfToolDrag.region;

  /// Asks what the drawn segment measures, then stamps it.
  @override
  Future<void> commitRegion(PdfToolHost host, Offset start, Offset end) async {
    if (_isSegmentClick(start, end)) return;
    await host.measureCustom(start, end);
  }

  @override
  PdfMeasurementKind get measureKind => PdfMeasurementKind.distance;
  @override
  bool get isLineDrag => true;
  @override
  String get styleScopeKey => tool.name;
  @override
  Set<String> get styleScopeFields => const {
        'color',
        'strokeWidth',
        'opacity',
        'lineStartEnding',
        'lineEndEnding',
      };
  @override
  Map<String, Object?> get styleScopeDefaults => const {
        'lineStartEnding': 'closedArrow',
        'lineEndEnding': 'closedArrow',
      };
  @override
  PdfToolStyleFields get styleFields => PdfToolStyleFields(
        stroke: true,
        opacity: true,
        font: true,
        lineEndings: true,
      );
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
  PdfToolStyleFields get styleFields => PdfToolStyleFields(
      stroke: true, opacity: true, font: true, lineEndings: hasEndings);

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
  'textVerticalAlign',
  'opacity',
  'textFillColor',
  'textBorderColor',
  'strokeWidth',
};

const _cloudCalloutFields = {..._textFields, 'lineScale'};

const _inkFields = {'color', 'strokeWidth', 'opacity'};

// ---------------------------------------------------------------------------
// Placement - the region and tap commits of the tools that need only the
// host. Top-level so the const table below can tear them off.
// ---------------------------------------------------------------------------

/// A dragged-out box too small to mean anything: the press was a click.
bool _isClick(Rect box) => box.width < 4 || box.height < 4;

/// A segment drag too short to aim: the press was a click.
bool _isSegmentClick(Offset start, Offset end) => (end - start).distance < 4;

/// The line family and line-shaped measurements: one straight segment.
Future<void> _commitSegment(PdfEditToolBehavior behavior, PdfToolHost host,
    Offset start, Offset end) async {
  if (_isSegmentClick(start, end)) return;
  final before = host.controller.revisionId;
  behavior.commitLineDrag(host.controller, host.page, host.toPagePoint(start),
      host.toPagePoint(end));
  host.holdLine(behavior.tool, start, end, before);
}

Future<void> _calibrateRegion(
    PdfToolHost host, Offset start, Offset end) async {
  if (_isSegmentClick(start, end)) return;
  await host.calibrate(start, end);
}

/// Free text: type into the box just dragged out, instead of a dialog.
Future<void> _textBoxRegion(PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  host.openTextBox(box);
}

/// Tapping without dragging out a box opens a default-sized one.
Future<void> _textBoxTap(PdfToolHost host, PdfToolTap tap) async =>
    host.openTextBox(host.defaultBoxAt(tap.at));

/// The drag draws the leader: press at the terminus, release where the box
/// goes. A too-short drag drops a default-offset box.
Future<void> _calloutRegion(PdfToolHost host, Offset start, Offset end) async =>
    host.openCallout(host.calloutBoxFor(start, end), start);

/// A plain tap makes the tap the terminus and offsets the box.
Future<void> _calloutTap(PdfToolHost host, PdfToolTap tap) async =>
    host.openCallout(host.defaultBoxAt(tap.at + const Offset(28, -28)), tap.at);

/// The drag draws the cloud around the area to mark; the note opens beside
/// it. A too-short drag drops a default-size cloud.
Future<void> _cloudCalloutRegion(
        PdfToolHost host, Offset start, Offset end) async =>
    host.openCloudCallout((end - start).distance < 8
        ? host.defaultCloudAt(start)
        : Rect.fromPoints(start, end));

/// A tap drops a default-size cloud there and opens its note.
Future<void> _cloudCalloutTap(PdfToolHost host, PdfToolTap tap) async =>
    host.openCloudCallout(host.defaultCloudAt(tap.at));

Future<void> _noteTap(PdfToolHost host, PdfToolTap tap) async {
  final text = await host.promptNoteText();
  if (text == null || text.isEmpty) return;
  host.controller.addNote(host.page, tap.point.$1, tap.point.$2, text);
}

/// Each tap drops a check-mark and bumps the running tally.
Future<void> _countTap(PdfToolHost host, PdfToolTap tap) async {
  final before = host.controller.revisionId;
  host.controller.placeCheckMark(host.page, tap.point.$1, tap.point.$2);
  host.holdCheckMark(before);
}

Future<void> _signatureTap(PdfToolHost host, PdfToolTap tap) async =>
    host.placeSignatureAt(tap.at);

/// A dragged-out stamp: the active custom stamp, else a captioned one.
Future<void> _stampRegion(PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  final controller = host.controller;
  final rect = host.toPageRect(box);
  final stamp = controller.activeStamp;
  if (stamp != null) {
    final values = controller.resolvedStampTemplateValues;
    await host.stampBox(box,
        text: pdfResolveStampTemplateText(stamp.text, values),
        template: stamp.template?.resolveText(values),
        color: Color(0xFF000000 | stamp.color),
        run: () => controller.addCustomStamp(host.page, rect, stamp));
    return;
  }
  final text = await host.promptStampText();
  if (text == null || text.isEmpty) return;
  await host.stampBox(box,
      text: text,
      color: controller.color,
      run: () => controller.addStamp(host.page, rect, text));
}

/// An active custom stamp drops at its auto-size on tap; the classic flow
/// places a default-sized stamp after prompting for its caption.
Future<void> _stampTap(PdfToolHost host, PdfToolTap tap) async {
  final controller = host.controller;
  final (x, y) = tap.point;
  if (controller.activeStamp != null) {
    await host.stampAt(tap.at,
        run: () => controller.placeStamp(host.page, x, y));
    return;
  }
  final text = await host.promptStampText();
  if (text == null || text.isEmpty) return;
  await host.stampAt(tap.at,
      text: text, run: () => controller.placeTextStamp(host.page, x, y, text));
}

Future<void> _imageRegion(PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  await host.addImageIn(host.toPageRect(box));
}

Future<void> _imageTap(PdfToolHost host, PdfToolTap tap) =>
    host.placeImageAt(tap.point.$1, tap.point.$2);

Future<void> _formRegion(PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  host.controller.addFormField(
      host.controller.newFormFieldKind, host.page, host.toPageRect(box));
}

/// A single tap selects the field for move/resize/menu; a double-tap fills
/// it (read mode is the no-tool path to just fill).
Future<void> _formTap(PdfToolHost host, PdfToolTap tap) async =>
    host.controller.selectFormWidgetAt(host.page, tap.hit.$1, tap.hit.$2,
        toggle: tap.additive);

Future<void> _contentTap(PdfToolHost host, PdfToolTap tap) async =>
    host.controller.selectElementAt(host.page, tap.hit.$1, tap.hit.$2);

Future<void> _redactRegion(PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  host.controller.addRedaction(host.page, host.toPageRect(box));
}

Future<void> _contentDeleteRegion(
    PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  host.controller.deleteElementsInRect(host.page, host.toPageRect(box));
}

Future<void> _linkRegion(PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  await host.addLinkIn(host.toPageRect(box));
}

Future<void> _signatureBoxRegion(
    PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  await host.placeSignatureBox(host.toPageRect(box));
}

Future<void> _snapshotRegion(PdfToolHost host, Offset start, Offset end) async {
  final box = Rect.fromPoints(start, end);
  if (_isClick(box)) return;
  await host.snapshot(box, host.toPageRect(box));
}

final Map<PdfEditTool, PdfEditToolBehavior> _behaviors = {
  for (final b in <PdfEditToolBehavior>[
    const _SimpleTool(PdfEditTool.select, drag: PdfToolDrag.select),
    const _SimpleTool(PdfEditTool.ink,
        styleScopeKey: 'ink',
        styleScopeFields: _inkFields,
        isInk: true,
        isDraw: true,
        buffersInk: true,
        drag: PdfToolDrag.freehand,
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
        drag: PdfToolDrag.freehand,
        styleFields: PdfToolStyleFields(stroke: true, opacity: true)),
    const _SimpleTool(PdfEditTool.eraser,
        styleScopeKey: 'eraser',
        styleScopeFields: {'eraserRadius'},
        isDraw: true,
        drag: PdfToolDrag.erase,
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
    const _LineTool(PdfEditTool.arrow,
        styleScopeKey: 'arrow',
        styleScopeFields: {
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
    const _MeasureLineTool(
        PdfEditTool.measureDistance, PdfMeasurementKind.distance),
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
    const _MeasureCustomTool(),
    const _SimpleTool(PdfEditTool.calibrate,
        isLineDrag: true, drag: PdfToolDrag.region, region: _calibrateRegion),
    const _SimpleTool(PdfEditTool.freeText,
        drag: PdfToolDrag.region,
        tapCreates: true,
        region: _textBoxRegion,
        tap: _textBoxTap,
        styleScopeKey: 'freeText',
        styleScopeFields: _textFields,
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.callout,
        drag: PdfToolDrag.region,
        tapCreates: true,
        region: _calloutRegion,
        tap: _calloutTap,
        styleScopeKey: 'callout',
        styleScopeFields: _textFields,
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    // its own scope so a cloud callout's look (and scallop size) is
    // remembered apart from the plain callout's
    const _SimpleTool(PdfEditTool.cloudCallout,
        drag: PdfToolDrag.region,
        tapCreates: true,
        region: _cloudCalloutRegion,
        tap: _cloudCalloutTap,
        styleScopeKey: 'cloudCallout',
        styleScopeFields: _cloudCalloutFields,
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    // The Insert strip offers one shared tune popup (opacity + font + text-box
    // colours) to every tool it hosts, so each carries the same styleFields
    // even though its persisted scope differs.
    const _SimpleTool(PdfEditTool.note,
        tapCreates: true,
        tap: _noteTap,
        styleScopeKey: 'note',
        styleScopeFields: {'color'},
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.stamp,
        drag: PdfToolDrag.region,
        tapCreates: true,
        region: _stampRegion,
        tap: _stampTap,
        styleScopeKey: 'stamp',
        styleScopeFields: {'color', 'opacity'},
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.count,
        tapCreates: true,
        tap: _countTap,
        styleScopeKey: 'count',
        styleScopeFields: {'color', 'opacity'},
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    // A stamped signature is ink like any other: it carries the tool's
    // colour and pen width, so the strip offers the colour row and the tune
    // popup the stroke-width slider, and both are remembered per tool.
    const _SimpleTool(PdfEditTool.signature,
        drag: PdfToolDrag.signature,
        tapCreates: true,
        tap: _signatureTap,
        styleScopeKey: 'signature',
        styleScopeFields: {'color', 'strokeWidth'},
        styleScopeDefaults: {
          'strokeWidth': PdfInkSignature.defaultStrokeWidth,
        },
        styleFields: PdfToolStyleFields(
            stroke: true, opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.image,
        drag: PdfToolDrag.region,
        tapCreates: true,
        region: _imageRegion,
        tap: _imageTap,
        styleFields:
            PdfToolStyleFields(opacity: true, font: true, boxColors: true)),
    const _SimpleTool(PdfEditTool.content,
        drag: PdfToolDrag.content, tap: _contentTap),
    const _SimpleTool(PdfEditTool.contentDelete,
        drag: PdfToolDrag.region, region: _contentDeleteRegion),
    const _SimpleTool(PdfEditTool.form,
        drag: PdfToolDrag.form, region: _formRegion, tap: _formTap),
    const _SimpleTool(PdfEditTool.redact,
        drag: PdfToolDrag.region, region: _redactRegion),
    const _SimpleTool(PdfEditTool.snapshot,
        drag: PdfToolDrag.region, region: _snapshotRegion),
    const _SimpleTool(PdfEditTool.signatureBox,
        drag: PdfToolDrag.region,
        region: _signatureBoxRegion,
        escapesFirst: true),
    const _SimpleTool(PdfEditTool.link,
        drag: PdfToolDrag.region, region: _linkRegion),
  ])
    b.tool: b,
};

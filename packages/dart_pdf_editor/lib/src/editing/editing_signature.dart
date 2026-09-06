import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show pdfInkCurveControls, pdfInkStrokeWidth;

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import 'editing_color_picker.dart';
import 'stroke_prediction.dart';

/// A hand-drawn signature, stored device-side and stamped onto pages as
/// an Ink annotation ([PdfEditingController.placeSignature]).
///
/// Strokes are normalized to the drawing's bounding box (0–1, y down,
/// like the pad it was drawn on); [aspect] preserves its proportions and
/// [strokeWidth] the pen it was drawn with.
/// Serializes to JSON so [PdfEditingPreferences] can persist it.
class PdfInkSignature {
  PdfInkSignature({
    required this.strokes,
    required this.pressures,
    required this.color,
    required this.aspect,
    this.strokeWidth = defaultStrokeWidth,
  }) : assert(strokes.length == pressures.length);

  /// The point width a signature is laid out at by default - see
  /// [PdfEditingController.placeSignature]'s `width`.
  ///
  /// [strokeWidth] is quoted at this size; every consumer scales the pen
  /// with the size it actually draws the signature at ([strokeWidthFor]),
  /// so a signature stamped small keeps its proportions.
  static const referenceWidth = 160.0;

  /// The pen a signature carries when it doesn't name one - what
  /// [PdfEditingController.placeSignature] used to hard-code (`width / 60`)
  /// before the pad had a thickness control, so signatures drawn by an
  /// older build still stamp exactly as they did.
  static const defaultStrokeWidth = referenceWidth / 60;

  /// The pen width slider's range in the pad, in points - the same range
  /// the toolbar's stroke-width slider offers.
  static const minStrokeWidth = 0.5;
  static const maxStrokeWidth = 12.0;

  /// Normalizes pad-space [strokes] (logical pixels, y down) to the
  /// drawing's bounding box. Returns null when nothing was drawn.
  /// [strokeWidth] is the pen the pad drew with, in points at
  /// [referenceWidth].
  static PdfInkSignature? fromPad(
    List<List<Offset>> strokes,
    List<List<double>?> pressures,
    Color color, {
    double strokeWidth = defaultStrokeWidth,
  }) {
    final points = strokes.expand((s) => s);
    if (points.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    // a dot or a perfectly straight line still needs a finite box
    final width = (maxX - minX).clamp(1.0, double.infinity);
    final height = (maxY - minY).clamp(1.0, double.infinity);
    return PdfInkSignature(
      strokes: [
        for (final stroke in strokes)
          [
            for (final p in stroke)
              ((p.dx - minX) / width, (p.dy - minY) / height)
          ]
      ],
      pressures: [for (final p in pressures) p?.toList()],
      color: color.toARGB32() & 0xFFFFFF,
      aspect: width / height,
      strokeWidth: strokeWidth,
    );
  }

  /// Normalized points per stroke: 0–1 within the bounding box, y down.
  final List<List<(double, double)>> strokes;

  /// Per-point pressures paralleling [strokes]; null entries are strokes
  /// drawn without pressure (mouse, finger).
  final List<List<double>?> pressures;

  /// RGB ink color.
  final int color;

  /// Bounding-box width / height.
  final double aspect;

  /// Pen width in points, quoted at [referenceWidth]. Scale it with
  /// [strokeWidthFor] to draw the signature at any other size.
  final double strokeWidth;

  /// The pen width to draw this signature with when it is laid out
  /// [width] wide - points for a page, pixels for a raster; only the
  /// ratio to [referenceWidth] matters.
  double strokeWidthFor(double width) => strokeWidth * width / referenceWidth;

  String encode() => jsonEncode({
        'color': color,
        'aspect': aspect,
        'strokeWidth': strokeWidth,
        'strokes': [
          for (final stroke in strokes)
            [
              for (final (x, y) in stroke) ...[x, y]
            ]
        ],
        'pressures': pressures,
      });

  /// Parses [encode]'s output; null for anything malformed.
  static PdfInkSignature? decode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final strokes = [
        for (final flat in map['strokes'] as List)
          [
            for (var i = 0; i + 1 < (flat as List).length; i += 2)
              ((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble())
          ]
      ];
      final pressures = [
        for (final p in map['pressures'] as List)
          p == null ? null : [for (final v in p as List) (v as num).toDouble()]
      ];
      if (strokes.length != pressures.length) return null;
      // written since the pad grew a thickness control; anything older (or
      // nonsensical) falls back to the pen those signatures were stamped with
      final width = (map['strokeWidth'] as num?)?.toDouble();
      return PdfInkSignature(
        strokes: strokes,
        pressures: pressures,
        color: map['color'] as int,
        aspect: (map['aspect'] as num).toDouble(),
        strokeWidth: width != null && width.isFinite && width > 0
            ? width
            : defaultStrokeWidth,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A named signature in the device-side signature library.
///
/// [id] remains stable when the entry is renamed or redrawn, which lets the
/// active choice survive both operations and app restarts.
class PdfSavedSignature {
  const PdfSavedSignature({
    required this.id,
    required this.name,
    required this.signature,
  });

  factory PdfSavedSignature.create({
    required String name,
    required PdfInkSignature signature,
  }) =>
      PdfSavedSignature(
        id: _nextSignatureId(),
        name: name,
        signature: signature,
      );

  final String id;
  final String name;
  final PdfInkSignature signature;

  PdfSavedSignature copyWith({String? name, PdfInkSignature? signature}) =>
      PdfSavedSignature(
        id: id,
        name: name ?? this.name,
        signature: signature ?? this.signature,
      );

  String encode() => jsonEncode({
        'v': 1,
        'id': id,
        'name': name,
        'signature': jsonDecode(signature.encode()),
      });

  static PdfSavedSignature? decode(String source) {
    try {
      final map = jsonDecode(source);
      if (map is! Map<String, dynamic> || map['v'] != 1) return null;
      final id = map['id'];
      final name = map['name'];
      final signature = map['signature'];
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          name.trim().isEmpty ||
          signature is! Map) {
        return null;
      }
      final decoded = PdfInkSignature.decode(jsonEncode(signature));
      if (decoded == null) return null;
      return PdfSavedSignature(id: id, name: name, signature: decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfSavedSignature && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

int _signatureIdCounter = 0;

String _nextSignatureId() {
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final sequence = (_signatureIdCounter++).toRadixString(36);
  return 'signature-$micros-$sequence';
}

/// Opens a full colour picker over the signature pad, seeded with the
/// pad's current ink; resolves to the chosen colour or null when
/// dismissed. The stock chrome wires this to `pickEditingColor` so the
/// pad's picker offers the same recents and document colours as every
/// other colour in the editor.
typedef PdfSignatureColorPicker = Future<Color?> Function(
    BuildContext context, Color initial);

/// Opens the saved-signature picker. Callbacks keep storage and controller
/// policy with the caller while this widget owns the list-management UI.
Future<void> showPdfSignatureLibrary(
  BuildContext context, {
  required List<PdfSavedSignature> signatures,
  required String? activeId,
  required Future<PdfSavedSignature?> Function(BuildContext context) onAdd,
  required Future<PdfSavedSignature?> Function(
          BuildContext context, PdfSavedSignature signature)
      onRename,
  required Future<PdfSavedSignature?> Function(
          BuildContext context, PdfSavedSignature signature)
      onRedraw,
  required void Function(PdfSavedSignature signature) onSelect,
  required void Function(PdfSavedSignature signature) onDelete,
}) =>
    showPdfDialog<void>(
      context: context,
      builder: (context) => PdfSignatureLibraryDialog(
        signatures: signatures,
        activeId: activeId,
        onAdd: onAdd,
        onRename: onRename,
        onRedraw: onRedraw,
        onSelect: onSelect,
        onDelete: onDelete,
      ),
    );

/// Standard picker for adding, choosing, renaming, redrawing, and deleting
/// handwritten signatures.
class PdfSignatureLibraryDialog extends StatefulWidget {
  const PdfSignatureLibraryDialog({
    super.key,
    required this.signatures,
    required this.activeId,
    required this.onAdd,
    required this.onRename,
    required this.onRedraw,
    required this.onSelect,
    required this.onDelete,
  });

  final List<PdfSavedSignature> signatures;
  final String? activeId;
  final Future<PdfSavedSignature?> Function(BuildContext context) onAdd;
  final Future<PdfSavedSignature?> Function(
      BuildContext context, PdfSavedSignature signature) onRename;
  final Future<PdfSavedSignature?> Function(
      BuildContext context, PdfSavedSignature signature) onRedraw;
  final void Function(PdfSavedSignature signature) onSelect;
  final void Function(PdfSavedSignature signature) onDelete;

  @override
  State<PdfSignatureLibraryDialog> createState() =>
      _PdfSignatureLibraryDialogState();
}

class _PdfSignatureLibraryDialogState extends State<PdfSignatureLibraryDialog> {
  late final List<PdfSavedSignature> _signatures = [...widget.signatures];
  late String? _activeId = widget.activeId;

  Future<void> _add() async {
    final added = await widget.onAdd(context);
    if (added == null || !mounted) return;
    setState(() {
      _signatures.add(added);
      _activeId = added.id;
    });
  }

  Future<void> _replace(
    PdfSavedSignature signature,
    Future<PdfSavedSignature?> Function(
            BuildContext context, PdfSavedSignature signature)
        action,
  ) async {
    final replacement = await action(context, signature);
    if (replacement == null || !mounted) return;
    final index = _signatures.indexWhere((entry) => entry.id == signature.id);
    if (index == -1) return;
    setState(() => _signatures[index] = replacement);
  }

  void _select(PdfSavedSignature signature) {
    widget.onSelect(signature);
    setState(() => _activeId = signature.id);
  }

  void _delete(PdfSavedSignature signature) {
    widget.onDelete(signature);
    setState(() {
      _signatures.removeWhere((entry) => entry.id == signature.id);
      if (_activeId == signature.id) {
        _activeId = _signatures.isEmpty ? null : _signatures.first.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pdfL10n(context).sigTitle),
      content: SizedBox(
        width: 390,
        child: _signatures.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(pdfL10n(context).signatureLibraryEmpty),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 430),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _signatures.length,
                  itemBuilder: (context, index) {
                    final signature = _signatures[index];
                    return ListTile(
                      key: ValueKey('pdf-signature-library-item-$index'),
                      selected: signature.id == _activeId,
                      leading: SizedBox(
                        width: 88,
                        height: 40,
                        child:
                            PdfSignaturePreview(signature: signature.signature),
                      ),
                      title: Text(signature.name),
                      onTap: () => _select(signature),
                      trailing: PopupMenuButton<String>(
                        key: ValueKey('pdf-signature-library-menu-$index'),
                        onSelected: (action) {
                          switch (action) {
                            case 'rename':
                              _replace(signature, widget.onRename);
                            case 'redraw':
                              _replace(signature, widget.onRedraw);
                            case 'delete':
                              _delete(signature);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                              value: 'rename',
                              child: Text(pdfL10n(context).rename)),
                          PopupMenuItem(
                              value: 'redraw',
                              child: Text(pdfL10n(context).tbDrawNewSignature)),
                          PopupMenuItem(
                              value: 'delete',
                              child: Text(pdfL10n(context).delete)),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('pdf-signature-library-add'),
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: Text(pdfL10n(context).tbDrawNewSignature),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).close),
        ),
      ],
    );
  }
}

/// Small ink preview used by the signature library.
class PdfSignaturePreview extends StatelessWidget {
  const PdfSignaturePreview({super.key, required this.signature});

  final PdfInkSignature signature;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PdfSignaturePreviewPainter(
          signature,
          Theme.of(context).colorScheme.outlineVariant,
        ),
      );
}

class _PdfSignaturePreviewPainter extends CustomPainter {
  const _PdfSignaturePreviewPainter(this.signature, this.borderColor);

  final PdfInkSignature signature;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke;
    final bounds = Offset.zero & size;
    canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.deflate(0.5), const Radius.circular(5)),
        background);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.deflate(0.5), const Radius.circular(5)),
        border);
    final aspect = signature.aspect > 0 ? signature.aspect : 2.0;
    final available = bounds.deflate(5);
    var width = available.width;
    var height = width / aspect;
    if (height > available.height) {
      height = available.height;
      width = height * aspect;
    }
    final left = (size.width - width) / 2;
    final top = (size.height - height) / 2;
    final ink = Paint()
      ..color = Color(0xFF000000 | signature.color)
      ..strokeWidth = signature.strokeWidthFor(width).clamp(0.8, 4.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in signature.strokes) {
      if (stroke.isEmpty) continue;
      final points = [
        for (final (x, y) in stroke) Offset(left + x * width, top + y * height),
      ];
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      final controls = pdfInkCurveControls([
        for (final point in points) (point.dx, point.dy),
      ]);
      for (var i = 0; i < controls.length; i++) {
        final (c1, c2) = controls[i];
        final end = points[i + 1];
        path.cubicTo(c1.$1, c1.$2, c2.$1, c2.$2, end.dx, end.dy);
      }
      if (points.length == 1) path.lineTo(points.first.dx, points.first.dy);
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_PdfSignaturePreviewPainter oldDelegate) =>
      oldDelegate.signature != signature ||
      oldDelegate.borderColor != borderColor;
}

/// Shows the signature pad dialog; resolves to the drawn signature, or
/// null on cancel. [predictStrokes] forward-extrapolates the in-progress
/// stroke to mask input latency, exactly like the ink tool (see
/// [PdfViewer.predictStrokes]); display only, never committed.
///
/// [initialColor] and [initialStrokeWidth] seed the pad's ink and pen so
/// it reopens on the style the last signature was drawn with, and
/// [pickColor] supplies the "any colour" picker behind the pad's custom
/// swatch (defaulting to a plain [showPdfColorPicker]).
Future<PdfInkSignature?> showPdfSignatureDialog(
  BuildContext context, {
  bool predictStrokes = true,
  Color? initialColor,
  double initialStrokeWidth = PdfInkSignature.defaultStrokeWidth,
  PdfSignatureColorPicker? pickColor,
}) =>
    showPdfDialog<PdfInkSignature>(
      context: context,
      builder: (context) => PdfSignatureDialog(
        predictStrokes: predictStrokes,
        initialColor: initialColor,
        initialStrokeWidth: initialStrokeWidth,
        pickColor: pickColor,
      ),
    );

/// A dialog with a drawing pad for capturing a signature: draw with
/// mouse, finger, or stylus (pressure is recorded and rendered as
/// variable width, like the ink tool), pick an ink color - one of the
/// three pen presets or any colour at all, through the picker behind the
/// custom swatch - set the pen thickness, clear, done.
///
/// The pad draws at the scale the signature is stamped at
/// ([PdfInkSignature.referenceWidth]), so the pen thickness on the pad is
/// the pen thickness on the page.
class PdfSignatureDialog extends StatefulWidget {
  const PdfSignatureDialog({
    super.key,
    this.predictStrokes = true,
    this.initialColor,
    this.initialStrokeWidth = PdfInkSignature.defaultStrokeWidth,
    this.pickColor,
  });

  /// Forward-extrapolates a short speculative lead beyond the pen tip on
  /// the in-progress stroke, the same predictive ink the ink tool uses
  /// ([PdfViewer.predictStrokes]). Display only - the lead is redrawn each
  /// frame and never enters the captured signature.
  final bool predictStrokes;

  /// The ink the pad opens on; null starts on the first pen preset.
  final Color? initialColor;

  /// The pen width the pad opens on, in points at
  /// [PdfInkSignature.referenceWidth] (clamped to the slider's range).
  final double initialStrokeWidth;

  /// Opens the "any colour" picker for the pad's custom swatch. Null
  /// falls back to [showPdfColorPicker] with no recents wired.
  final PdfSignatureColorPicker? pickColor;

  @override
  State<PdfSignatureDialog> createState() => _PdfSignatureDialogState();
}

class _PdfSignatureDialogState extends State<PdfSignatureDialog> {
  static const _inks = [
    Color(0xFF000000),
    Color(0xFF1A3E8C),
    Color(0xFFB71C1C)
  ];

  static const _padWidth = 360.0;
  static const _padHeight = 180.0;

  /// Pad pixels per point: the pad is as wide as a signature stamped at
  /// [PdfInkSignature.referenceWidth], so a pen drawn here is the pen that
  /// lands on the page.
  static const _padScale = _padWidth / PdfInkSignature.referenceWidth;

  final List<List<Offset>> _strokes = [];
  final List<List<double>?> _pressures = [];
  List<Offset>? _active;
  List<double>? _activePressures;
  double? _pointerPressure;
  late Color _ink = widget.initialColor ?? _inks.first;
  late double _strokeWidth = widget.initialStrokeWidth
      .clamp(PdfInkSignature.minStrokeWidth, PdfInkSignature.maxStrokeWidth);

  bool get _isEmpty => _strokes.isEmpty && _active == null;

  static String _hexOf(Color color) =>
      (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  /// Opens the full picker so the signature can be drawn in any colour at
  /// all, not just the three pen presets.
  Future<void> _pickInk() async {
    final pick = widget.pickColor ??
        (BuildContext context, Color initial) =>
            showPdfColorPicker(context, initial: initial);
    final picked = await pick(context, _ink);
    if (picked == null || !mounted) return;
    setState(() => _ink = Color(0xFF000000 | (picked.toARGB32() & 0xFFFFFF)));
  }

  /// 0–1 within the device's range; null when the device has none
  /// (mouse, finger) - same convention as the ink overlay.
  static double? _normalizedPressure(PointerEvent event) {
    if (event.pressureMax <= event.pressureMin) return null;
    return ((event.pressure - event.pressureMin) /
            (event.pressureMax - event.pressureMin))
        .clamp(0.0, 1.0);
  }

  void _panStart(DragStartDetails details) {
    final pressure = _pointerPressure;
    setState(() {
      _active = [details.localPosition];
      _activePressures = pressure == null ? null : [pressure];
    });
  }

  void _panUpdate(DragUpdateDetails details) {
    setState(() {
      _active!.add(details.localPosition);
      _activePressures?.add(_pointerPressure ?? _activePressures!.last);
    });
  }

  void _panEnd(DragEndDetails details) {
    final stroke = _active;
    if (stroke == null) return;
    setState(() {
      _strokes.add(stroke);
      _pressures.add(_activePressures);
      _active = null;
      _activePressures = null;
    });
  }

  /// The in-progress stroke with a display-only predicted lead appended
  /// (and its last pressure carried onto the lead), recomputed each build
  /// so the next real sample replaces it - the pad's analogue of the ink
  /// tool's live prediction. Null when no stroke is active.
  ({List<Offset> points, List<double>? pressures})? get _activeDisplay {
    final active = _active;
    if (active == null) return null;
    var pressures = _activePressures;
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
    return (points: active, pressures: pressures);
  }

  @override
  Widget build(BuildContext context) {
    final activeDisplay = _activeDisplay;
    return AlertDialog(
      title: Text(pdfL10n(context).sigTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _padWidth,
            height: _padHeight,
            decoration: BoxDecoration(
              // the pad is always paper-white, like the page the
              // signature will land on - only its border follows the theme
              color: Colors.white,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Listener(
                onPointerDown: (e) => _pointerPressure = _normalizedPressure(e),
                onPointerMove: (e) => _pointerPressure = _normalizedPressure(e),
                child: GestureDetector(
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: _panStart,
                  onPanUpdate: _panUpdate,
                  onPanEnd: _panEnd,
                  child: CustomPaint(
                    key: const ValueKey('pdf-signature-pad'),
                    size: const Size(_padWidth, _padHeight),
                    painter: _SignaturePadPainter(
                      strokes: [
                        ..._strokes,
                        if (activeDisplay != null) activeDisplay.points
                      ],
                      pressures: [
                        ..._pressures,
                        if (activeDisplay != null) activeDisplay.pressures
                      ],
                      color: _ink,
                      strokeWidth: _strokeWidth * _padScale,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (final ink in _inks)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _InkSwatch(
                  key: ValueKey('pdf-signature-ink-${_hexOf(ink)}'),
                  color: ink,
                  selected: _ink == ink,
                  onTap: () => setState(() => _ink = ink),
                ),
              ),
            // any colour at all, through the full picker
            _InkSwatch(
              key: const ValueKey('pdf-signature-custom-ink'),
              color: _ink,
              selected: !_inks.contains(_ink),
              tooltip: pdfL10n(context).colorPickColor,
              icon: Icons.colorize,
              onTap: _pickInk,
            ),
            const Spacer(),
            TextButton(
              onPressed: _isEmpty
                  ? null
                  : () => setState(() {
                        _strokes.clear();
                        _pressures.clear();
                        _active = null;
                        _activePressures = null;
                      }),
              child: Text(pdfL10n(context).clear),
            ),
          ]),
          Row(children: [
            Text(pdfL10n(context).tbStrokeWidthLabel),
            Expanded(
              child: Slider(
                key: const ValueKey('pdf-signature-stroke-width'),
                value: _strokeWidth,
                min: PdfInkSignature.minStrokeWidth,
                max: PdfInkSignature.maxStrokeWidth,
                onChanged: (value) => setState(() => _strokeWidth = value),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${_strokeWidth.toStringAsFixed(1)} pt',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).cancel),
        ),
        FilledButton(
          onPressed: _isEmpty
              ? null
              : () => Navigator.of(context).pop(PdfInkSignature.fromPad(
                  _strokes, _pressures, _ink,
                  strokeWidth: _strokeWidth)),
          child: Text(pdfL10n(context).done),
        ),
      ],
    );
  }
}

/// One round ink well in the pad's colour row - a preset pen, or (with an
/// [icon]) the custom swatch that opens the full picker.
class _InkSwatch extends StatelessWidget {
  const _InkSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tooltip,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final swatch = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 3 : 1,
          ),
        ),
        child: icon == null
            ? null
            : Icon(
                icon,
                size: 13,
                // the icon rides on the ink itself, so pick the side of
                // the swatch it can actually be read against
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
      ),
    );
    return tooltip == null ? swatch : Tooltip(message: tooltip!, child: swatch);
  }
}

class _SignaturePadPainter extends CustomPainter {
  _SignaturePadPainter({
    required this.strokes,
    required this.pressures,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final List<List<double>?> pressures;
  final Color color;

  /// The pen width in pad pixels - the chosen point width scaled to the
  /// pad, so what is drawn here is what lands on the page.
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = Colors.black12
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

  @override
  bool shouldRepaint(_SignaturePadPainter old) =>
      old.strokes != strokes ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

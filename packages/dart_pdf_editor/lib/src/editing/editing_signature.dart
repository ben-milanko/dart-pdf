import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart' show pdfInkCurveControls;

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import 'editing_color_picker.dart';
import 'models/ink_signature.dart';
import 'signature_pad.dart';
import '../design/editor_presenter.dart';

export 'models/ink_signature.dart'
    show
        PdfInkSignature,
        PdfSavedSignature,
        PdfSignatureColorPicker,
        PdfTrackpadSignatureCapture,
        PdfTrackpadSignatureEvent,
        PdfTrackpadSignaturePhase;

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
    pdfPresentDialog<void>(
      context,
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
        PdfDialogSubmit.action(
            onSubmit: () => Navigator.of(context).pop(),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(pdfL10n(context).close),
            )),
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
/// swatch (defaulting to a plain [showPdfColorPicker]). [trackpad] offers
/// drawing on the trackpad (defaulting to
/// [PdfTrackpadSignatureCapture.platform]).
Future<PdfInkSignature?> showPdfSignatureDialog(
  BuildContext context, {
  bool predictStrokes = true,
  Color? initialColor,
  double initialStrokeWidth = PdfInkSignature.defaultStrokeWidth,
  PdfSignatureColorPicker? pickColor,
  PdfTrackpadSignatureCapture? trackpad,
}) =>
    pdfPresentDialog<PdfInkSignature>(
      context,
      builder: (context) => PdfSignatureDialog(
        predictStrokes: predictStrokes,
        initialColor: initialColor,
        initialStrokeWidth: initialStrokeWidth,
        pickColor: pickColor,
        trackpad: trackpad ?? PdfTrackpadSignatureCapture.platform,
      ),
    );

/// A dialog with a drawing pad for capturing a signature: draw with
/// mouse, finger, or stylus (pressure is recorded and rendered as
/// variable width, like the ink tool), pick an ink color - one of the
/// three pen presets or any colour at all, through the picker behind the
/// custom swatch - set the pen thickness, clear, done. With a [trackpad]
/// capture it can also be drawn with a finger on the trackpad.
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
    this.trackpad,
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

  /// Offers a "Use trackpad" mode that draws with a finger on the
  /// trackpad (see [PdfTrackpadSignatureCapture]); null hides it. Unlike
  /// [showPdfSignatureDialog] this does not fall back to
  /// [PdfTrackpadSignatureCapture.platform].
  final PdfTrackpadSignatureCapture? trackpad;

  @override
  State<PdfSignatureDialog> createState() => _PdfSignatureDialogState();
}

class _PdfSignatureDialogState extends State<PdfSignatureDialog> {
  static const _inks = [
    Color(0xFF000000),
    Color(0xFF1A3E8C),
    Color(0xFFB71C1C)
  ];

  late final _pad = PdfSignaturePadController(
    color: widget.initialColor ?? _inks.first,
    strokeWidth: widget.initialStrokeWidth,
  )..addListener(_onPadChanged);

  void _onPadChanged() {
    if (mounted) setState(() {});
  }

  static String _hexOf(Color color) =>
      (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  /// Opens the full picker so the signature can be drawn in any colour at
  /// all, not just the three pen presets.
  Future<void> _pickInk() async {
    final pick = widget.pickColor ??
        (BuildContext context, Color initial) =>
            pdfPresentColor(context, PdfColorRequest(initial: initial));
    final picked = await pick(context, _pad.color);
    if (picked == null || !mounted) return;
    _pad.color = Color(0xFF000000 | (picked.toARGB32() & 0xFFFFFF));
  }

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = _pad.color;
    final trackpadActive = _pad.trackpadActive;
    final dialog = AlertDialog(
      title: Text(pdfL10n(context).sigTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PdfSignaturePad(
            controller: _pad,
            predictStrokes: widget.predictStrokes,
            trackpad: widget.trackpad,
            // the pad is always paper-white, like the page the signature
            // will land on - only its border follows the theme
            borderColor: scheme.outline,
            activeBorderColor: scheme.primary,
            trackpadHintStyle: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (final preset in _inks)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _InkSwatch(
                  key: ValueKey('pdf-signature-ink-${_hexOf(preset)}'),
                  color: preset,
                  selected: ink == preset,
                  onTap: () => _pad.color = preset,
                ),
              ),
            // any colour at all, through the full picker
            _InkSwatch(
              key: const ValueKey('pdf-signature-custom-ink'),
              color: ink,
              selected: !_inks.contains(ink),
              tooltip: pdfL10n(context).colorPickColor,
              icon: Icons.colorize,
              onTap: _pickInk,
            ),
            const Spacer(),
            if (_pad.trackpadAvailable)
              TextButton.icon(
                key: const ValueKey('pdf-signature-trackpad'),
                onPressed: trackpadActive ? null : _pad.startTrackpad,
                icon: const Icon(Icons.touch_app_outlined, size: 18),
                label: Text(pdfL10n(context).sigUseTrackpad),
              ),
            TextButton(
              onPressed: _pad.isEmpty ? null : _pad.clear,
              child: Text(pdfL10n(context).clear),
            ),
          ]),
          Row(children: [
            Text(pdfL10n(context).tbStrokeWidthLabel),
            Expanded(
              child: Slider(
                key: const ValueKey('pdf-signature-stroke-width'),
                value: _pad.strokeWidth,
                min: PdfInkSignature.minStrokeWidth,
                max: PdfInkSignature.maxStrokeWidth,
                onChanged: (value) => _pad.strokeWidth = value,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${_pad.strokeWidth.toStringAsFixed(1)} pt',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('pdf-signature-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: _pad.isEmpty ? null : _accept,
            child: FilledButton(
              key: const ValueKey('pdf-signature-done'),
              onPressed: _pad.isEmpty ? null : _accept,
              child: Text(pdfL10n(context).done),
            )),
      ],
    );
    if (widget.trackpad == null) return dialog;
    // clicks mean nothing mid-capture: with tap-to-click a quick dab on the
    // trackpad is also a click, and it must not press a button
    return AbsorbPointer(absorbing: trackpadActive, child: dialog);
  }

  void _accept() {
    _pad.endStroke();
    Navigator.of(context).pop(_pad.toSignature());
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

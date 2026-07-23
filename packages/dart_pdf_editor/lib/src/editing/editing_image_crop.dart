import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'handle_layout.dart';

/// The interactive crop rectangle drawn over a selected image stamp while
/// [PdfEditingController.isCroppingImage].
///
/// It is deliberately self-contained - its own [GestureDetector] absorbs every
/// pointer over the page so it never entangles the main editing overlay's
/// gesture machine. Drag a handle to resize the crop, drag the interior to
/// move it, both clamped to [bounds] (the image's full on-screen rectangle).
/// The area of the image outside the crop is dimmed; a rule-of-thirds grid and
/// eight handles mark the crop. Confirm (✓) and cancel (✕) chips float below
/// the rectangle.
///
/// The crop is tracked internally as fractions of [bounds] so it survives a
/// zoom or scroll (which changes [bounds]) mid-crop, and reported back out in
/// view space through [onChanged].
class PdfImageCropOverlay extends StatefulWidget {
  const PdfImageCropOverlay({
    super.key,
    required this.bounds,
    required this.initialCrop,
    required this.chromeScale,
    required this.accentColor,
    required this.onChanged,
    required this.onCommit,
    required this.onCancel,
  });

  /// The image's full rectangle in view space - the crop cannot grow past it.
  final Rect bounds;

  /// The crop rectangle to start from, in view space (defaults to [bounds]).
  final Rect initialCrop;

  /// View-pixels-per-logical for chrome, so handles stay a constant on-screen
  /// size as the page zooms (`1 / zoom`).
  final double chromeScale;

  /// The selection-chrome accent (border + handle stroke).
  final Color accentColor;

  /// Fires as the crop rectangle changes, in view space.
  final ValueChanged<Rect> onChanged;

  /// Fires when the user confirms the crop.
  final VoidCallback onCommit;

  /// Fires when the user abandons the crop.
  final VoidCallback onCancel;

  @override
  State<PdfImageCropOverlay> createState() => _PdfImageCropOverlayState();
}

class _PdfImageCropOverlayState extends State<PdfImageCropOverlay> {
  // The crop as fractions of `bounds`, left/top/right/bottom in [0, 1].
  late double _fl, _ft, _fr, _fb;

  SelectionHandle? _handle;
  bool _moving = false;
  Offset? _dragStart;
  // Fractions captured at drag start.
  late double _sl, _st, _sr, _sb;

  static const double _handleSize = 10;
  static const double _minSpanPx = 16;

  @override
  void initState() {
    super.initState();
    _seedFractions();
  }

  @override
  void didUpdateWidget(PdfImageCropOverlay old) {
    super.didUpdateWidget(old);
    // Re-seed only when the incoming crop identity changes and no drag is in
    // flight (the overlay is authoritative while dragging).
    if (_handle == null &&
        !_moving &&
        old.initialCrop != widget.initialCrop) {
      _seedFractions();
    }
  }

  void _seedFractions() {
    final b = widget.bounds;
    if (b.width <= 0 || b.height <= 0) {
      _fl = 0;
      _ft = 0;
      _fr = 1;
      _fb = 1;
      return;
    }
    final c = widget.initialCrop;
    _fl = ((c.left - b.left) / b.width).clamp(0.0, 1.0);
    _ft = ((c.top - b.top) / b.height).clamp(0.0, 1.0);
    _fr = ((c.right - b.left) / b.width).clamp(0.0, 1.0);
    _fb = ((c.bottom - b.top) / b.height).clamp(0.0, 1.0);
    if (_fr <= _fl) _fr = 1;
    if (_fb <= _ft) _fb = 1;
  }

  Rect get _cropRect {
    final b = widget.bounds;
    return Rect.fromLTRB(
      b.left + _fl * b.width,
      b.top + _ft * b.height,
      b.left + _fr * b.width,
      b.top + _fb * b.height,
    );
  }

  double get _minFracX =>
      widget.bounds.width <= 0 ? 0.1 : _minSpanPx / widget.bounds.width;
  double get _minFracY =>
      widget.bounds.height <= 0 ? 0.1 : _minSpanPx / widget.bounds.height;

  void _onPanStart(DragStartDetails details) {
    final layout = HandleLayout(
      rect: _cropRect,
      chromeScale: widget.chromeScale,
    );
    _dragStart = details.localPosition;
    _sl = _fl;
    _st = _ft;
    _sr = _fr;
    _sb = _fb;
    _handle = layout.handleAt(details.localPosition);
    _moving = _handle == null && _cropRect.contains(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart == null) return;
    final b = widget.bounds;
    if (b.width <= 0 || b.height <= 0) return;
    final d = details.localPosition - _dragStart!;
    final dfx = d.dx / b.width;
    final dfy = d.dy / b.height;
    if (_handle case final handle?) {
      var l = _sl, t = _st, r = _sr, bt = _sb;
      if (handle.dx == -1) l = (_sl + dfx).clamp(0.0, r - _minFracX);
      if (handle.dx == 1) r = (_sr + dfx).clamp(l + _minFracX, 1.0);
      if (handle.dy == -1) t = (_st + dfy).clamp(0.0, bt - _minFracY);
      if (handle.dy == 1) bt = (_sb + dfy).clamp(t + _minFracY, 1.0);
      _apply(l, t, r, bt);
    } else if (_moving) {
      final w = _sr - _sl, h = _sb - _st;
      final l = (_sl + dfx).clamp(0.0, 1.0 - w);
      final t = (_st + dfy).clamp(0.0, 1.0 - h);
      _apply(l, t, l + w, t + h);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _handle = null;
    _moving = false;
    _dragStart = null;
  }

  void _apply(double l, double t, double r, double bt) {
    if (l == _fl && t == _ft && r == _fr && bt == _fb) return;
    setState(() {
      _fl = l;
      _ft = t;
      _fr = r;
      _fb = bt;
    });
    widget.onChanged(_cropRect);
  }

  @override
  Widget build(BuildContext context) {
    final crop = _cropRect;
    // Confirm/cancel chips ride just below the crop, nudged back inside the
    // image when the crop hugs the bottom edge.
    final chipY = (crop.bottom + 10 * widget.chromeScale)
        .clamp(widget.bounds.top, widget.bounds.bottom - 4);
    final chipCenter = crop.center.dx
        .clamp(widget.bounds.left + 44, widget.bounds.right - 44);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // start the drag at the press point (not where the recognizer won
            // the arena) so a handle grab hit-tests against the down position
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _CropPainter(
                bounds: widget.bounds,
                crop: crop,
                accent: widget.accentColor,
                chromeScale: widget.chromeScale,
                handleSize: _handleSize,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        Positioned(
          left: chipCenter - 44,
          top: chipY,
          child: _CropActions(
            accent: widget.accentColor,
            onCommit: widget.onCommit,
            onCancel: widget.onCancel,
          ),
        ),
      ],
    );
  }
}

/// The confirm/cancel chip pair floating beside the crop rectangle.
class _CropActions extends StatelessWidget {
  const _CropActions({
    required this.accent,
    required this.onCommit,
    required this.onCancel,
  });

  final Color accent;
  final VoidCallback onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CropActionButton(
          key: const ValueKey('pdf-crop-cancel'),
          icon: Icons.close,
          tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
          background: Colors.white,
          foreground: Colors.black87,
          onPressed: onCancel,
        ),
        const SizedBox(width: 8),
        _CropActionButton(
          key: const ValueKey('pdf-crop-confirm'),
          icon: Icons.check,
          tooltip: MaterialLocalizations.of(context).okButtonLabel,
          background: accent,
          foreground: Colors.white,
          onPressed: onCommit,
        ),
      ],
    );
  }
}

class _CropActionButton extends StatelessWidget {
  const _CropActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // The crop chips sit over the viewer's SelectableRegion and the editing
    // overlay's gesture stack, which can win a plain tap's arena. A raw
    // pointer-up listener fires regardless of the arena, so the button always
    // responds; the InkWell stays for hover/press feedback. onPressed
    // (commit/cancel) is idempotent, so a redundant fire is harmless.
    return Listener(
      onPointerUp: (_) => onPressed(),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Semantics(
            button: true,
            label: tooltip,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 20, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.bounds,
    required this.crop,
    required this.accent,
    required this.chromeScale,
    required this.handleSize,
  });

  final Rect bounds;
  final Rect crop;
  final Color accent;
  final double chromeScale;
  final double handleSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Dim the image outside the crop (even-odd: image minus crop).
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(bounds),
      Path()..addRect(crop),
    );
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.45));

    // Rule-of-thirds grid inside the crop.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 0.75 * chromeScale;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }

    // Crop border.
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * chromeScale
        ..color = accent,
    );

    // Eight handles.
    final layout = HandleLayout(rect: crop, chromeScale: chromeScale);
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * chromeScale
      ..color = accent;
    final r = handleSize / 2 * chromeScale;
    for (final handle in selectionHandles) {
      final c = layout.handleCenter(handle);
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.bounds != bounds ||
      old.crop != crop ||
      old.accent != accent ||
      old.chromeScale != chromeScale;
}

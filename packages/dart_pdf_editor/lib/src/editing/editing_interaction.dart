import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../page_geometry.dart';

/// A single-selection move drag's floating preview.
///
/// A page overlay reports this to the viewer so the artwork can paint above
/// neighbouring pages during a cross-page drag.
class PdfMoveDragPreview {
  const PdfMoveDragPreview({
    required this.pageIndex,
    required this.picture,
    required this.from,
    required this.to,
    required this.scale,
  });

  final int pageIndex;
  final ui.Picture picture;
  final Rect from;
  final Rect to;

  /// Page-raster to view scale ([PdfPageGeometry.scale]).
  final double scale;
}

typedef PdfMoveDragPreviewCallback = void Function(PdfMoveDragPreview? preview);

/// The viewer-owned services an editing interaction may request.
///
/// Recognizers and preview painters stay internal to the page overlay. This
/// object is the one outer seam for viewport movement, cross-page resolution,
/// menus, and focus handoff; hosts can replace any service independently.
class PdfEditingInteractionHost {
  const PdfEditingInteractionHost({
    this.panViewport,
    this.endViewportPan,
    this.edgeAutoScroll,
    this.showAnnotationMenu,
    this.showFormFieldMenu,
    this.resolvePagePoint,
    this.moveDragPreview,
    this.textEditClosed,
  });

  final void Function(Offset delta)? panViewport;
  final void Function(Velocity velocity)? endViewportPan;
  final Offset Function(Offset globalPosition)? edgeAutoScroll;
  final void Function(Offset globalPosition, int pageIndex,
      {(double, double)? pagePoint})? showAnnotationMenu;
  final void Function(Offset globalPosition, String fieldName,
      {int? widgetIndex})? showFormFieldMenu;
  final (int, double, double)? Function(Offset globalPosition)?
      resolvePagePoint;
  final PdfMoveDragPreviewCallback? moveDragPreview;
  final VoidCallback? textEditClosed;
}

/// The gesture intent currently owned by an editing page.
enum PdfEditingInteractionIntent {
  none,
  ink,
  erase,
  create,
  move,
  resize,
  rotate,
  reshape,
  marquee,
  viewportPan,
  signature,
  text,
}

/// Lifecycle of the current interaction.
enum PdfEditingInteractionPhase { idle, active, awaitingRaster }

/// Last externally relevant effect produced by a transition.
enum PdfEditingInteractionEffect {
  none,
  completed,
  committed,
  canceled,
  rasterReady,
}

/// Immutable diagnostic view of [PdfEditingInteractionSession].
class PdfEditingInteractionState {
  const PdfEditingInteractionState({
    required this.intent,
    required this.phase,
    required this.effect,
    required this.pageIndex,
    required this.pointerKind,
    required this.sampleCount,
    required this.transition,
  });

  final PdfEditingInteractionIntent intent;
  final PdfEditingInteractionPhase phase;
  final PdfEditingInteractionEffect effect;
  final int? pageIndex;
  final PointerDeviceKind? pointerKind;

  /// Pointer/auto-scroll preview samples observed since [transition].
  final int sampleCount;

  /// Monotonic transition sequence. Pointer samples do not increment it.
  final int transition;
}

/// Stable event → state/effect surface for editing gestures.
///
/// Listeners are notified only when an interaction starts, ends, commits, is
/// canceled, or hands its afterimage to a current raster. [sample] is the
/// latency-critical pointer path: it mutates one integer, allocates nothing,
/// and deliberately does not notify or rebuild widgets.
class PdfEditingInteractionSession extends ChangeNotifier {
  PdfEditingInteractionIntent _intent = PdfEditingInteractionIntent.none;
  PdfEditingInteractionPhase _phase = PdfEditingInteractionPhase.idle;
  PdfEditingInteractionEffect _effect = PdfEditingInteractionEffect.none;
  int? _pageIndex;
  PointerDeviceKind? _pointerKind;
  int _sampleCount = 0;
  int _transition = 0;

  PdfEditingInteractionState get state => PdfEditingInteractionState(
        intent: _intent,
        phase: _phase,
        effect: _effect,
        pageIndex: _pageIndex,
        pointerKind: _pointerKind,
        sampleCount: _sampleCount,
        transition: _transition,
      );

  bool get isActive => _phase == PdfEditingInteractionPhase.active;

  void begin(PdfEditingInteractionIntent intent,
      {required int pageIndex, PointerDeviceKind? pointerKind}) {
    if (intent == PdfEditingInteractionIntent.none) return;
    _intent = intent;
    _phase = PdfEditingInteractionPhase.active;
    _effect = PdfEditingInteractionEffect.none;
    _pageIndex = pageIndex;
    _pointerKind = pointerKind;
    _sampleCount = 0;
    _emitTransition();
  }

  /// Records one preview sample without allocating or notifying listeners.
  void sample() {
    if (_phase == PdfEditingInteractionPhase.active) _sampleCount++;
  }

  void complete() => _finish(PdfEditingInteractionEffect.completed, false);

  void commit({bool awaitingRaster = true}) =>
      _finish(PdfEditingInteractionEffect.committed, awaitingRaster);

  void cancel() => _finish(PdfEditingInteractionEffect.canceled, false);

  /// Marks the committed revision's raster current, retiring its afterimage.
  void rasterReady() {
    if (_phase != PdfEditingInteractionPhase.awaitingRaster) return;
    _phase = PdfEditingInteractionPhase.idle;
    _effect = PdfEditingInteractionEffect.rasterReady;
    _emitTransition();
  }

  void _finish(PdfEditingInteractionEffect effect, bool awaitingRaster) {
    if (_phase != PdfEditingInteractionPhase.active) return;
    _phase = awaitingRaster
        ? PdfEditingInteractionPhase.awaitingRaster
        : PdfEditingInteractionPhase.idle;
    _effect = effect;
    _emitTransition();
  }

  void _emitTransition() {
    _transition++;
    notifyListeners();
  }
}

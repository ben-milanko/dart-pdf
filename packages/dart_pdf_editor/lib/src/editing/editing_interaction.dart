import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../page_geometry.dart';
import 'editing_controller.dart';

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

/// What a context menu request acts on - resolved by the viewer before the
/// gesture is handed to the host, so the host never has to re-run a hit test.
enum PdfContextMenuTarget {
  /// Page text. The word under the cursor is selected (a click inside an
  /// existing selection keeps it), and [PdfContextMenuRequest.selectedText]
  /// carries it. Also the outcome on a blank page area with nothing to
  /// paste - the case the stock text menu handles.
  text,

  /// A selectable annotation, named by [PdfContextMenuRequest.annotation]
  /// (and [PdfContextMenuRequest.slot] when the viewer resolved it through
  /// an editing session). It is part of the selection by the time the host
  /// is called.
  annotation,

  /// A locked annotation. It cannot be selected - the stock menu offers
  /// only Unlock here - but it is still named by
  /// [PdfContextMenuRequest.annotation] / [PdfContextMenuRequest.slot].
  lockedAnnotation,

  /// An AcroForm widget. It is the editing session's form selection by the
  /// time the host is called; the widget itself is reachable through
  /// [PdfContextMenuRequest.controller], so [PdfContextMenuRequest.slot] and
  /// [PdfContextMenuRequest.annotation] stay null.
  formWidget,

  /// Empty page area with annotation clipboard content - where the stock
  /// menu would have offered Paste.
  emptyPage,
}

/// A context menu the host is asked to render, with everything the viewer
/// already resolved about the gesture.
///
/// Delivered to [PdfViewer.onContextMenuRequested], which fires only when
/// [PdfViewer.contextMenuEnabled] is false: with the default menu disabled,
/// the viewer prepares the same selection context the stock menu would have
/// had, then hands the gesture to the host instead of opening a menu itself.
/// The host typically wraps this in `showMenu<_T>(context, position: ...)`
/// anchored at [globalPosition], and branches on [target]:
///
/// ```dart
/// onContextMenuRequested: (request) {
///   switch (request.target) {
///     case PdfContextMenuTarget.text:
///       // request.selectedText is the word under the cursor
///     case PdfContextMenuTarget.annotation:
///       // request.annotation.subtype names the kind
///     case PdfContextMenuTarget.lockedAnnotation:
///       // offer Unlock
///     case PdfContextMenuTarget.formWidget:
///     case PdfContextMenuTarget.emptyPage:
///   }
/// }
/// ```
///
/// Because the target is resolved for it, a host does not need a
/// [PdfEditingController] of its own - which is what makes this work inside
/// the drop-in `PdfReader`, whose session is private.
class PdfContextMenuRequest {
  const PdfContextMenuRequest({
    required this.globalPosition,
    required this.pageIndex,
    required this.pagePoint,
    required this.target,
    this.controller,
    this.slot,
    this.annotation,
    this.selectedText = '',
  });

  /// Where the gesture landed, in global Flutter coordinates - anchor the
  /// menu here.
  final Offset globalPosition;

  /// The page the gesture landed on.
  final int pageIndex;

  /// Where the gesture landed, in page coordinates (points).
  final (double, double) pagePoint;

  /// What the gesture landed on.
  final PdfContextMenuTarget target;

  /// The editing session behind the viewer, when there is one - the
  /// editing session, or the reader's standalone form-fill controller.
  /// Null in a plain reader with neither.
  final PdfEditingController? controller;

  /// The /Annots slot of [annotation], when the viewer resolved the hit
  /// through an editing session. Null in a reader without one, and for
  /// targets that are not an annotation.
  final int? slot;

  /// The annotation under the gesture, for [PdfContextMenuTarget.annotation]
  /// and [PdfContextMenuTarget.lockedAnnotation]. Null otherwise.
  final PdfAnnotation? annotation;

  /// The page text selected when the request was made. Non-empty for
  /// [PdfContextMenuTarget.text] whenever there was a word to select.
  final String selectedText;
}

/// Fires when the host wants to render its own context menu in place of the
/// stock annotation/text menu. See [PdfContextMenuRequest].
typedef PdfContextMenuHost = void Function(PdfContextMenuRequest request);

/// The page overlay's channel back to the viewer's [PdfContextMenuHost]: the
/// overlay resolved the annotation itself, the viewer adds the selection and
/// controller and builds the [PdfContextMenuRequest].
typedef PdfContextMenuRelay = void Function(
  Offset globalPosition,
  int pageIndex, {
  required (double, double) pagePoint,
  required PdfContextMenuTarget target,
  int? slot,
  PdfAnnotation? annotation,
});

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
    this.requestContextMenu,
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
  final PdfContextMenuRelay? requestContextMenu;
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
